import 'dart:convert';
import 'dart:io';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

class _ImportSection extends ConsumerWidget {
  const _ImportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final jobs = ref.watch(importJobsProvider);
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
        // Starting an import uploads the export file as `application/octet-stream`, and this
        // client speaks JSON bodies only — see `ImportEndpoints` in `chordia_api`, which models
        // the read half for exactly this reason. Until the transport grows a byte-body path, the
        // phone shows progress for jobs rather than pretending it can start one.
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
