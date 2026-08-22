// Copies the shared locale catalogs into the app's assets and generates compile-checked key
// constants from the `en` catalog.
//
// The catalogs live in the sibling `i18n` repo, which is the single source Crowdin writes to. They
// are COPIED and committed rather than referenced, so a build never depends on a sibling checkout
// being present — and so CI can regenerate and diff, which is what catches a catalog change that
// nobody synced.
//
//   dart tool/sync_i18n.dart                 # sync from ../i18n
//   dart tool/sync_i18n.dart --check         # fail if the committed copy is stale
//   dart tool/sync_i18n.dart --source <dir>  # explicit locales/ parent

import 'dart:convert';
import 'dart:io';

const _assetDir = 'app/assets/i18n';
const _keysFile = 'app/lib/i18n/keys.g.dart';

void main(List<String> args) {
  final check = args.contains('--check');
  final sourceIdx = args.indexOf('--source');
  final sourceRoot = sourceIdx >= 0 && sourceIdx + 1 < args.length
      ? args[sourceIdx + 1]
      : '../i18n';

  final localesDir = Directory('$sourceRoot/locales');
  if (!localesDir.existsSync()) {
    stderr.writeln(
      'No catalogs at ${localesDir.path}.\n'
      'Check out the i18n repo beside this one, or pass --source <path to the i18n repo>.',
    );
    exit(2);
  }

  final locales =
      localesDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .where((n) => !n.startsWith('.'))
          .toList()
        ..sort();

  if (!locales.contains('en')) {
    stderr.writeln('The `en` catalog is the source of truth and is missing.');
    exit(2);
  }

  final written = <String, String>{};
  final namespacesByLocale = <String, List<String>>{};

  for (final locale in locales) {
    final files =
        Directory('${localesDir.path}/$locale')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final namespaces = <String>[];
    final bundled = <String, dynamic>{};
    for (final file in files) {
      final ns = file.uri.pathSegments.last.replaceAll('.json', '');
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        stderr.writeln('${file.path} is not a JSON object.');
        exit(2);
      }
      _assertNested(decoded, '$locale/$ns');
      namespaces.add(ns);
      bundled[ns] = decoded;
    }
    // One file per locale, not one per namespace: Flutter's asset declaration does not recurse
    // into subdirectories, and this makes loading a locale a single read instead of eighteen.
    written['$_assetDir/$locale.json'] = jsonEncode(bundled);
    namespacesByLocale[locale] = namespaces;
  }

  written['$_assetDir/manifest.json'] = jsonEncode({
    'locales': locales,
    'namespaces': namespacesByLocale,
  });

  // The generated keys are committed and CI gates on `dart format`, so the generator has to emit
  // exactly what the formatter would — including in --check mode, or every run would look stale.
  written[_keysFile] = _formatDart(_generateKeys(localesDir.path));

  var stale = <String>[];
  for (final entry in written.entries) {
    final file = File(entry.key);
    final current = file.existsSync() ? file.readAsStringSync() : null;
    if (current == entry.value) continue;
    stale.add(entry.key);
    if (!check) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  // A locale removed upstream must disappear here too, or the app keeps offering a language whose
  // catalog no longer exists. This also sweeps the per-namespace layout an earlier version wrote.
  final assetRoot = Directory(_assetDir);
  if (assetRoot.existsSync()) {
    for (final entity in assetRoot.listSync()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final keep =
          entity is File &&
          (name == 'manifest.json' ||
              locales.contains(name.replaceAll('.json', '')));
      if (keep) continue;
      stale.add('${entity.path} (no longer generated)');
      if (!check) entity.deleteSync(recursive: true);
    }
  }

  if (check && stale.isNotEmpty) {
    stderr.writeln(
      'Locale assets are out of date. Run: dart tool/sync_i18n.dart',
    );
    for (final s in stale) {
      stderr.writeln('  $s');
    }
    exit(1);
  }

  stdout.writeln(
    check
        ? 'Locale assets are up to date (${locales.length} locales).'
        : 'Synced ${locales.length} locales'
              '${stale.isEmpty ? " (no changes)" : ", ${stale.length} file(s) updated"}.',
  );
}

/// i18next resolves `.` as a key separator, so a flat-dotted catalog renders raw keys to users.
/// Agents and hand edits have produced flat catalogs before; fail loudly rather than ship one.
void _assertNested(Map<String, dynamic> map, String where) {
  void walk(Map<String, dynamic> m, String path) {
    for (final entry in m.entries) {
      if (entry.key.contains('.')) {
        stderr.writeln(
          'Flat-dotted key "${entry.key}" in $where$path. Catalogs must be nested objects.',
        );
        exit(2);
      }
      final v = entry.value;
      if (v is Map<String, dynamic>) walk(v, '$path.${entry.key}');
    }
  }

  walk(map, '');
}

String _generateKeys(String localesPath) {
  final enDir = Directory('$localesPath/en');
  final files =
      enDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final buffer = StringBuffer()
    ..writeln('// GENERATED BY tool/sync_i18n.dart — DO NOT EDIT.')
    ..writeln('//')
    ..writeln(
      '// Every translatable string in the app goes through one of these constants, so a',
    )
    ..writeln(
      '// key deleted or renamed upstream becomes a compile error instead of a raw key',
    )
    ..writeln('// rendered to a user.')
    ..writeln();

  for (final file in files) {
    final ns = file.uri.pathSegments.last.replaceAll('.json', '');
    final catalog = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final flat = <String, String>{};
    void walk(Map<String, dynamic> map, List<String> path) {
      for (final entry in map.entries) {
        final next = [...path, entry.key];
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          walk(value, next);
        } else {
          flat[_identifier(next)] = next.join('.');
        }
      }
    }

    walk(catalog, const []);

    final seen = <String, String>{};
    for (final entry in flat.entries) {
      final clash = seen[entry.key];
      if (clash != null) {
        stderr.writeln(
          'Key collision in "$ns": "$clash" and "${entry.value}" both mangle to '
          '"${entry.key}". Rename one of them upstream.',
        );
        exit(2);
      }
      seen[entry.key] = entry.value;
    }

    buffer
      ..writeln('/// Keys for the `$ns` namespace.')
      ..writeln('abstract final class ${_className(ns)}Keys {');
    final sorted = flat.keys.toList()..sort();
    for (final id in sorted) {
      buffer.writeln("  static const $id = '$ns:${flat[id]}';");
    }
    buffer
      ..writeln('}')
      ..writeln();
  }

  return buffer.toString();
}

/// Runs `dart format` over generated source, via a temp file since the formatter is file-based.
String _formatDart(String source) {
  final tmp = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}chordia_keys_$pid.dart',
  )..writeAsStringSync(source);
  try {
    final result = Process.runSync('dart', [
      'format',
      tmp.path,
    ], runInShell: true);
    if (result.exitCode != 0) {
      stderr.writeln(
        'dart format failed on the generated keys:\n${result.stderr}',
      );
      exit(2);
    }
    return tmp.readAsStringSync();
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

/// `controls.play` -> `controlsPlay`; leading digits and Dart keywords get a prefix.
String _identifier(List<String> path) {
  final parts = <String>[];
  for (var i = 0; i < path.length; i++) {
    final segment = path[i].replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    for (final piece in segment.split('_').where((p) => p.isNotEmpty)) {
      parts.add(parts.isEmpty ? _lowerFirst(piece) : _upperFirst(piece));
    }
  }
  var id = parts.join();
  if (id.isEmpty) id = 'key';
  if (RegExp(r'^[0-9]').hasMatch(id)) id = 'k$id';
  if (_dartKeywords.contains(id)) id = '${id}Key';
  return id;
}

String _className(String ns) => ns
    .split(RegExp(r'[^A-Za-z0-9]+'))
    .where((p) => p.isNotEmpty)
    .map(_upperFirst)
    .join();

String _upperFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

const _dartKeywords = {
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
  'dynamic',
  'implements',
  'import',
  'library',
  'part',
  'show',
  'static',
};
