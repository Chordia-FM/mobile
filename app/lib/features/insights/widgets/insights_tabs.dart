import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../reports/charts_report.dart';
import '../reports/discovery_report.dart';
import '../reports/history_report.dart';
import '../reports/overview_report.dart';
import '../reports/records_report.dart';
import '../reports/social_report.dart';
import 'insights_primitives.dart';

/// The report a listener's page is showing.
enum InsightsTab {
  overview,
  charts,
  records,
  discovery,
  history,

  /// Friends and taste compatibility.
  ///
  /// Measured against the **viewer**, so it appears only on their own page — showing it under
  /// somebody else's name would label the viewer's friend feed as that person's.
  social;

  String label(String Function(String, [Map<String, Object?>]) t) =>
      t(switch (this) {
        InsightsTab.overview => InsightsKeys.tabsOverview,
        InsightsTab.charts => InsightsKeys.tabsCharts,
        InsightsTab.records => InsightsKeys.tabsRecords,
        InsightsTab.discovery => InsightsKeys.tabsDiscovery,
        InsightsTab.history => InsightsKeys.tabsHistory,
        InsightsTab.social => InsightsKeys.tabsSocial,
      });
}

/// The tab strip, the period selector, and whichever report is selected.
///
/// One widget serving both the viewer's own insights and a profile, so the two cannot drift into
/// different tab sets or different windows. It is a `Column`, not a scroll view: it lives inside
/// the page's single scroll, which is what keeps a long history list from fighting the page for
/// the reader's gesture.
class InsightsTabView extends ConsumerStatefulWidget {
  const InsightsTabView({
    required this.handle,
    required this.own,
    super.key,
    this.shareHandle,
  });

  /// Whose reports, or null for the signed-in listener's own.
  final String? handle;

  /// Whether this page belongs to the viewer. Gates the Social tab and picks the catalogs' copy.
  final bool own;

  /// Handle to stamp on a shared Wrapped card; null hides the share button.
  final String? shareHandle;

  @override
  ConsumerState<InsightsTabView> createState() => _InsightsTabViewState();
}

class _InsightsTabViewState extends ConsumerState<InsightsTabView> {
  InsightsTab _tab = InsightsTab.overview;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final tabs = [
      for (final tab in InsightsTab.values)
        if (tab != InsightsTab.social || widget.own) tab,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final tab in tabs)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: ChoiceChip(
                    label: Text(tab.label(t)),
                    selected: tab == _tab,
                    onSelected: (_) => setState(() => _tab = tab),
                  ),
                ),
            ],
          ),
        ),
        // The Social tab is live data rather than a window, so offering a period selector over it
        // would be a control that changes nothing.
        if (_tab != InsightsTab.social) const PeriodSelector(),
        switch (_tab) {
          InsightsTab.overview => OverviewReport(
            handle: widget.handle,
            shareHandle: widget.shareHandle,
          ),
          InsightsTab.charts => ChartsReport(
            handle: widget.handle,
            own: widget.own,
          ),
          InsightsTab.records => RecordsReport(
            handle: widget.handle,
            own: widget.own,
          ),
          InsightsTab.discovery => DiscoveryReport(
            handle: widget.handle,
            own: widget.own,
          ),
          InsightsTab.history => HistoryReport(
            handle: widget.handle,
            own: widget.own,
          ),
          InsightsTab.social => const SocialReport(),
        },
      ],
    );
  }
}
