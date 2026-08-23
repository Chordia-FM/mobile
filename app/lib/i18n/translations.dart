import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/message_format.dart';

/// Loaded catalogs for one locale, with its fallback chain already merged in.
///
/// Keys are `namespace:dotted.path`, matching the web client so the same catalogs serve both.
/// Regional catalogs (`en-GB`, `pt-BR`) ship only the strings they override, so a lookup falls
/// through to the base language and finally to `en`, which is the complete source.
class Translations {
  Translations._(this.locale, this._entries);

  /// The locale actually resolved, which may be a fallback of the one requested.
  final String locale;
  final Map<String, String> _entries;
  final Map<String, MessageFormat> _formats = {};

  static const fallbackLocale = 'en';
  static const _assetRoot = 'assets/i18n';

  static List<String>? _available;

  /// Locales the app ships catalogs for, as BCP-47 tags.
  static Future<List<String>> availableLocales(AssetBundle bundle) async {
    await _loadManifest(bundle);
    return _available!;
  }

  static Future<void> _loadManifest(AssetBundle bundle) async {
    if (_available != null) return;
    final raw = await bundle.loadString('$_assetRoot/manifest.json');
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    _available = (manifest['locales'] as List).cast<String>();
  }

  /// Builds the lookup chain for [requested]: itself, its base language, then `en`.
  ///
  /// Case is normalised because a tag can arrive as `en-gb` from a system locale while the catalog
  /// directory is `en-GB`.
  static List<String> resolveChain(String requested, List<String> available) {
    final byLower = {for (final l in available) l.toLowerCase(): l};
    final chain = <String>[];

    void add(String? tag) {
      if (tag == null) return;
      final match = byLower[tag.toLowerCase()];
      if (match != null && !chain.contains(match)) chain.add(match);
    }

    final cleaned = requested.trim().replaceAll('_', '-');
    add(cleaned);
    final dash = cleaned.indexOf('-');
    if (dash > 0) add(cleaned.substring(0, dash));
    add(fallbackLocale);
    return chain;
  }

  static Future<Translations> load(
    String requested, {
    AssetBundle? bundle,
  }) async {
    final b = bundle ?? rootBundle;
    await _loadManifest(b);
    final chain = resolveChain(requested, _available!);

    // Walk the chain from least to most specific so more specific entries overwrite.
    final entries = <String, String>{};
    for (final locale in chain.reversed) {
      final raw = await b.loadString('$_assetRoot/$locale.json');
      final bundle = jsonDecode(raw) as Map<String, dynamic>;
      for (final ns in bundle.entries) {
        _flatten(ns.value as Map<String, dynamic>, ns.key, '', entries);
      }
    }

    return Translations._(chain.first, entries);
  }

  static void _flatten(
    Map<String, dynamic> map,
    String namespace,
    String prefix,
    Map<String, String> out,
  ) {
    for (final entry in map.entries) {
      final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        _flatten(value, namespace, path, out);
      } else if (value is String) {
        out['$namespace:$path'] = value;
      }
    }
  }

  /// Whether a key exists in this locale's merged catalogs.
  bool has(String key) => _entries.containsKey(key);

  /// Looks up [key] and applies ICU formatting when the string takes arguments.
  ///
  /// A missing key returns the key itself. That is deliberately ugly: it shows up immediately in
  /// review and in screenshots, where a silent empty string would not.
  String call(String key, [Map<String, Object?> args = const {}]) {
    final pattern = _entries[key];
    if (pattern == null) return key;
    // Most strings are literals; parsing them as ICU would cost for nothing, and an apostrophe in
    // ordinary prose ("d'écoute") is ICU quoting syntax that would silently eat characters.
    if (args.isEmpty && !pattern.contains('{')) return pattern;

    final format = _formats.putIfAbsent(
      key,
      () => MessageFormat(pattern, locale: locale),
    );
    try {
      // A null argument has no ICU representation; dropping it renders the placeholder rather
      // than throwing, which is the better failure for a missing optional value.
      final resolved = <String, Object>{
        for (final e in args.entries)
          if (e.value != null) e.key: e.value!,
      };
      return format.format(resolved);
    } on Object {
      // A malformed pattern must not take a screen down with it.
      return pattern;
    }
  }
}
