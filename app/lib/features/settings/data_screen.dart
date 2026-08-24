import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/foundation.dart' show Uint8List, immutable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart' show hubClientProvider;
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'data/settings_values.dart';
import 'widgets/settings_list.dart';

/// Everything that leaves the account, and everything that has been brought into it.
class DataScreen extends ConsumerWidget {
  const DataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return SettingsScaffold(
      title: t(SettingsKeys.dataTitle),
      onRefresh: () async => ref.invalidate(importJobsProvider),
      children: const [_ExportSection(), _ImportSection()],
    );
  }
}

class _ExportSection extends ConsumerStatefulWidget {
  const _ExportSection();

  @override
  ConsumerState<_ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<_ExportSection> {
  bool _busy = false;

  /// Downloads the export and hands it to the system share sheet.
  ///
  /// A share sheet rather than a download: a phone has no visible downloads folder to put a file
  /// in and no browser to have put it there, so the only useful thing to do with a portability
  /// dump is let its owner choose where it goes — Files, a cloud drive, an email to themselves.
  Future<void> _export() async {
    final api = ref.read(dataApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      final document = await api.exportAccount();
      // Written to the cache directory rather than kept in memory: the share sheet takes a file,
      // and an OS storage sweep is welcome to take this copy back once it has been shared.
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}chordia-export.json',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(document),
      );
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: t(SettingsKeys.dataExportSubject),
        ),
      );
      if (!mounted) return;
      showSettingsMessage(context, t(SettingsKeys.dataExportReady));
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    return SettingsSection(
      title: t(SettingsKeys.dataTitle),
      description: t(SettingsKeys.dataBody),
      children: [
        SettingsDisclosureRow(
          icon: Icons.download_rounded,
          label: t(
            _busy ? CommonKeys.statesLoading : SettingsKeys.dataExportMyData,
          ),
          onTap: _busy ? null : _export,
        ),
      ],
    );
  }
}

/// One listening-history export the account holder chose off their device.
@immutable
class PickedImport {
  const PickedImport({required this.bytes, this.contentType});

  final Uint8List bytes;

  /// What the picker says the bytes are, when it says anything. A hint only — the Hub sniffs the
  /// content and a stated format that contradicts it is refused — but passing it along keeps a
  /// `.csv` that happens to parse as something else honest.
  final String? contentType;
}

/// Picks one export file, or null when the sheet was dismissed without choosing.
///
/// A function type rather than a class for the reason `data/image_picking.dart` gives: the test
/// binding answers every platform channel with an error, so a real picker call inside a widget
/// test would fail on the channel rather than on anything under test.
typedef PickImportFile = Future<PickedImport?> Function();

/// How an export file gets off this device.
///
/// **Null in this build, and that is the whole of what is still missing.** `image_picker` is the
/// only picker in the tree and it opens the photo library; a Spotify `.json` or a Last.fm `.csv`
/// needs a DOCUMENT picker, which means a new package in `app/pubspec.yaml`
/// (`file_picker`, or `file_selector` with its Android and iOS implementations) and a dozen lines
/// implementing this typedef against it. Everything on this side of that line is finished: the
/// transport, the endpoint, the size check, the source selector and the job list are all wired and
/// tested, and the row below appears the moment this provider answers with a picker.
///
/// Until then the screen says the import has to be started in a browser rather than offering a
/// button that opens nothing.
final importFilePickerProvider = Provider<PickImportFile?>((ref) => null);

/// Uploads an export and starts the job, or null when there is no hub session to upload to.
typedef StartImport =
    Future<void> Function(Uint8List bytes, ImportSource? source);

/// The one call this screen makes that `DataApi` does not carry.
///
/// `POST /v1/me/imports` sends the file as its body, so it goes through the byte transport rather
/// than the JSON one every other settings call uses. Declared here rather than widened into
/// `DataApi` because this is its only caller, and a test overrides THIS instead.
final importStarterProvider = Provider<StartImport?>((ref) {
  final hub = ref.watch(hubClientProvider);
  if (hub == null) return null;
  return (bytes, source) => hub.startImport(bytes, source: source);
});

class _ImportSection extends ConsumerStatefulWidget {
  const _ImportSection();

  @override
  ConsumerState<_ImportSection> createState() => _ImportSectionState();
}

class _ImportSectionState extends ConsumerState<_ImportSection> {
  /// Null is `auto` — the Hub detects the format from the content either way, and a stated source
  /// only ever narrows. It is the default for that reason: naming the wrong one is a 400, while
  /// naming none is never wrong.
  ImportSource? _source;
  bool _busy = false;

  /// Picks an export and starts importing it.
  ///
  /// The size is checked before the socket opens: an extended Spotify history runs to tens of
  /// megabytes, and pushing one over a mobile uplink only to be told 413 wastes the whole upload
  /// when splitting the export would have worked.
  Future<void> _import(PickImportFile pick, StartImport start) async {
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      final file = await pick();
      if (file == null) return;
      if (file.bytes.length > ImportEndpoints.maxUploadBytes) {
        if (mounted) {
          showSettingsMessage(context, t(SettingsKeys.importTooLarge));
        }
        return;
      }
      await start(file.bytes, _source);
      // The upload answers with a job that has counted nothing yet, so what the reader needs to
      // see next is the list, with the new row on it and its progress ticking.
      ref.invalidate(importJobsProvider);
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final jobs = ref.watch(importJobsProvider);
    final pick = ref.watch(importFilePickerProvider);
    final start = ref.watch(importStarterProvider);
    final entitlements = ref.watch(myProfileProvider).value?.entitlements;
    // A Hub with no payment provider unlocks everything, and its users must never meet a lock.
    // An absent block is a Hub older than the field, which is the same answer.
    final locked =
        entitlements != null &&
        entitlements.billingEnabled != false &&
        !(entitlements.features ?? const <Feature>[]).contains(
          Feature.historyImport,
        );

    return SettingsSection(
      title: t(SettingsKeys.importTitle),
      description: t(SettingsKeys.importBody),
      children: [
        // The web wraps this whole block in `PlanGate feature="history_import"`
        // (`ImportSection.tsx:63`), whose whole argument is that hiding a paid feature means
        // nobody discovers it. The phone was showing the job list with nothing saying the feature
        // is paid at all, so a free account read "No imports yet" as a bug rather than a plan.
        if (locked) SettingsNote(t(BillingKeys.featuresHistoryImportLocked)),
        if (!locked && pick != null && start != null) ...[
          // Product names, deliberately untranslated — the web makes the same call
          // (`ImportSection.tsx:37-39`).
          SettingsChoiceRow<String>(
            label: t(SettingsKeys.importSourceAuto),
            value: _source?.wire ?? '',
            options: [
              ('', t(SettingsKeys.importSourceAuto)),
              (ImportSource.spotify.wire, 'Spotify'),
              (ImportSource.lastfm.wire, 'Last.fm'),
            ],
            onChanged: _busy
                ? null
                : (wire) =>
                      setState(() => _source = ImportSource.tryFromWire(wire)),
          ),
          SettingsDisclosureRow(
            icon: Icons.upload_file_rounded,
            label: t(
              _busy
                  ? SettingsKeys.importUploading
                  : SettingsKeys.importChooseFile,
            ),
            onTap: _busy ? null : () => _import(pick, start),
          ),
          SettingsNote(t(SettingsKeys.importHint)),
        ] else
          // No document picker in this build; see [importFilePickerProvider].
          SettingsNote(t(SettingsKeys.importStartInBrowser)),
        SettingsBody<List<ImportJob>>(
          value: jobs,
          onRetry: () => ref.invalidate(importJobsProvider),
          builder: (context, rows) => rows.isEmpty
              ? ListRow(gutter: 0, title: Text(t(SettingsKeys.importEmpty)))
              : Column(
                  children: [for (final job in rows) _ImportRow(job: job)],
                ),
        ),
      ],
    );
  }
}

class _ImportRow extends ConsumerWidget {
  const _ImportRow({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final started = DateFormat.yMMMd(
      locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(job.createdAt));
    final running =
        job.status == ImportJobStatus.running ||
        job.status == ImportJobStatus.pending;

    return ListRow(
      gutter: 0,
      title: Text('${job.source.wire} · $started'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t(importStatusLabel(job.status))),
          if (running)
            Text(
              t(SettingsKeys.importProgress, {
                'processed': job.importedRows + job.duplicateRows,
                'total': job.totalRows,
              }),
            ),
          if (job.status == ImportJobStatus.done)
            Text(
              t(SettingsKeys.importSummary, {
                'imported': job.importedRows,
                'matched': job.matchedRows,
                'duplicates': job.duplicateRows,
                'skipped': job.skippedRows,
              }),
            ),
          if (job.status == ImportJobStatus.failed)
            Text(
              t(importErrorKey(job.error)),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      // `total_rows` is 0 until parsing finishes, which is exactly when an indeterminate bar is
      // the truthful one — a 0% bar claims progress nobody has measured yet.
      trailing: running
          ? SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: job.totalRows == 0
                    ? null
                    : (job.importedRows + job.duplicateRows) / job.totalRows,
              ),
            )
          : null,
    );
  }
}
