import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import '../../widgets/cover_art.dart';
import '../library/data/formatting.dart';
import '../library/data/library_providers.dart';
import '../library/data/rules_summary.dart';
import '../library/widgets/library_states.dart';
import 'data/playlists_providers.dart';
import 'data/smart_draft.dart';
import 'data/smart_model.dart';
import 'widgets/rule_editor.dart';

/// Opens the rule builder, and answers with the playlist's id once it is saved.
///
/// One screen for both cases: creating a smart playlist IS writing its rules, so a create flow
/// that stopped at a name would only be a detour on the way here.
Future<String?> openSmartRules(
  BuildContext context, {
  String? seedName,
  SmartSource? existing,
}) => Navigator.of(context).push<String>(
  MaterialPageRoute<String>(
    builder: (_) => SmartRulesScreen(seedName: seedName, existing: existing),
  ),
);

class SmartRulesScreen extends ConsumerStatefulWidget {
  const SmartRulesScreen({super.key, this.seedName, this.existing});

  final String? seedName;

  /// Null when this is a playlist that does not exist yet.
  final SmartSource? existing;

  @override
  ConsumerState<SmartRulesScreen> createState() => _SmartRulesScreenState();
}

class _SmartRulesScreenState extends ConsumerState<SmartRulesScreen> {
  SmartDraft? _draft;
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.seedName ?? '',
  );
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final api = ref.read(smartPlaylistsApiProvider);
    if (api == null) return;
    final draft = SmartDraft(
      api: api,
      onFailure: _report,
      existing: widget.existing,
    )..addListener(_onChanged);
    draft.setName(_name.text);
    _draft = draft;
    // Straight away rather than on the first edit: an existing playlist should show what its rules
    // match before anything is touched, so a change can be read against something.
    draft.refreshPreview();
  }

  @override
  void dispose() {
    _draft
      ?..removeListener(_onChanged)
      ..dispose();
    _name.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _report(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          describeError(error, ref.read(translationsProvider).call),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final draft = _draft;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            widget.existing == null
                ? PlaylistsKeys.smartNewTitle
                : PlaylistsKeys.smartEditTitle,
          ),
        ),
        actions: [
          TextButton(
            onPressed: draft == null || !draft.canSave || _saving
                ? null
                : _save,
            child: Text(t(CommonKeys.actionsSave)),
          ),
        ],
      ),
      body: draft == null
          ? EmptyNote(message: t(ErrorsKeys.failedToLoad))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _nameField(t),
                if (widget.existing == null && draft.rows.isEmpty)
                  _presets(t, draft),
                _matchRow(t, draft),
                for (var i = 0; i < draft.rows.length; i++)
                  RuleEditor(
                    // Keyed by the row's own id, not by its index: removing the second of four
                    // rules must not make the third inherit the second's text controllers.
                    key: ValueKey(draft.rows[i].id),
                    draft: draft,
                    index: i,
                    condition: draft.rows[i].condition,
                  ),
                if (draft.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      t(PlaylistsKeys.smartNoRules),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: OutlinedButton.icon(
                    onPressed: () => _addRule(draft),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t(PlaylistsKeys.smartAddRule)),
                  ),
                ),
                const Divider(),
                _sortSection(t, draft),
                const Divider(),
                _scheduleSection(t, draft),
                const Divider(),
                _previewSection(t, draft),
              ],
            ),
    );
  }

  Widget _nameField(Translate t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: TextField(
      controller: _name,
      decoration: InputDecoration(
        labelText: t(PlaylistsKeys.smartNamePlaceholder),
      ),
      onChanged: (value) => _draft?.setName(value),
    ),
  );

  /// Starting points, offered only on a blank new playlist.
  ///
  /// They vanish the moment there is a rule, because past that point they would not be a starting
  /// point — they would be a button that silently throws away what somebody has written.
  Widget _presets(Translate t, SmartDraft draft) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          t(PlaylistsKeys.smartPresetsTitle),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: smartPresets.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final preset = smartPresets[index];
            return ActionChip(
              label: Text(t(preset.labelKey)),
              tooltip: t(preset.descriptionKey),
              onPressed: () {
                draft.applyPreset(
                  preset,
                  DateTime.now(),
                  (args) => t(preset.nameKey, args),
                );
                _name.text = draft.name;
              },
            );
          },
        ),
      ),
    ],
  );

  Widget _matchRow(Translate t, SmartDraft draft) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Row(
      children: [
        Text(t(PlaylistsKeys.smartMatch)),
        const SizedBox(width: 12),
        SegmentedButton<SmartMatch>(
          segments: [
            ButtonSegment(
              value: SmartMatch.all,
              label: Text(t(PlaylistsKeys.smartMatchModeAll)),
            ),
            ButtonSegment(
              value: SmartMatch.any,
              label: Text(t(PlaylistsKeys.smartMatchModeAny)),
            ),
          ],
          selected: {draft.matchMode},
          onSelectionChanged: (selection) =>
              draft.setMatchMode(selection.first),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            t(PlaylistsKeys.smartOfTheseRules),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );

  Widget _sortSection(Translate t, SmartDraft draft) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<SmartSort>(
          initialValue: draft.sort,
          isExpanded: true,
          decoration: InputDecoration(labelText: t(PlaylistsKeys.smartSortBy)),
          items: [
            for (final sort in smartSorts)
              DropdownMenuItem(value: sort, child: Text(t(smartSortKey(sort)))),
          ],
          onChanged: (sort) => sort == null ? null : draft.setSort(sort),
        ),
        const SizedBox(height: 12),
        // Random has no direction to have, and offering one would be a control that does nothing.
        if (draft.sort != SmartSort.random)
          SegmentedButton<SmartSortDir>(
            segments: [
              ButtonSegment(
                value: SmartSortDir.asc,
                label: Text(t(PlaylistsKeys.smartDirAsc)),
              ),
              ButtonSegment(
                value: SmartSortDir.desc,
                label: Text(t(PlaylistsKeys.smartDirDesc)),
              ),
            ],
            selected: {draft.sortDir ?? SmartSortDir.asc},
            onSelectionChanged: (selection) =>
                draft.setSortDir(selection.first),
          ),
        if (sortUsesPeriod(draft.sort)) ...[
          const SizedBox(height: 12),
          PeriodPicker(
            label: t(PlaylistsKeys.smartPeriodLabel),
            value: draft.sortPeriod,
            onChanged: (period) =>
                period == null ? null : draft.setSortPeriod(period),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          initialValue: draft.limit?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t(PlaylistsKeys.smartLimit)),
          // Blank means "no limit of mine", which the Hub reads as its own default. Sending 0
          // would mean a playlist of nothing.
          onChanged: (value) => draft.setLimit(int.tryParse(value.trim())),
        ),
      ],
    ),
  );

  Widget _scheduleSection(Translate t, SmartDraft draft) {
    final options = <int>[0, 60, 60 * 6, 60 * 24, 60 * 24 * 7];
    final current = draft.refreshIntervalMinutes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: options.contains(current) ? current : options.first,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t(PlaylistsKeys.smartRefreshScheduleLabel),
            ),
            items: [
              for (final minutes in options)
                DropdownMenuItem(
                  value: minutes,
                  child: Text(smartRefreshLabel(minutes, t)),
                ),
            ],
            onChanged: draft.setRefreshIntervalMinutes,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.refreshOnComplete,
            title: Text(t(PlaylistsKeys.smartRefreshOnCompleteLabel)),
            subtitle: Text(t(PlaylistsKeys.smartRefreshOnCompleteHint)),
            onChanged: (value) => draft.setRefreshOnComplete(value: value),
          ),
        ],
      ),
    );
  }

  /// What the rules match right now, without saving them.
  ///
  /// The count ignores the limit deliberately, so the panel can say "two thousand match, you asked
  /// for the first hundred" rather than reporting a hundred and hiding the fact that the rule is
  /// far wider than intended.
  Widget _previewSection(Translate t, SmartDraft draft) {
    final preview = draft.preview;
    final theme = Theme.of(context);
    final limit = draft.limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                t(PlaylistsKeys.smartPreviewTitle),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 12),
              if (draft.previewing)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        if (draft.previewError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(t(PlaylistsKeys.smartPreviewUnavailable)),
          )
        else if (preview == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(t(PlaylistsKeys.smartPreviewEmpty)),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              t(
                (preview.countCapped ?? false)
                    ? PlaylistsKeys.smartPreviewCountCapped
                    : PlaylistsKeys.smartPreviewCount,
                {'count': preview.count},
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (limit != null && limit > 0 && preview.count > limit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                t(PlaylistsKeys.smartPreviewLimited, {'count': limit}),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final track in preview.sample)
            ListRow(
              leading: CoverArt(sha256: artHashOf(track.coverUrl), size: 40),
              title: Text(track.title),
              subtitle: Text(track.artist),
            ),
        ],
      ],
    );
  }

  Future<void> _addRule(SmartDraft draft) async {
    final t = ref.read(translationsProvider).call;
    final field = await showModalBottomSheet<SmartField>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in fieldGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  t(group.labelKey),
                  style: Theme.of(sheetContext).textTheme.labelLarge,
                ),
              ),
              for (final field in group.fields)
                ListRow(
                  title: Text(t(smartFieldKey(field))),
                  onTap: () => Navigator.of(sheetContext).pop(field),
                ),
            ],
          ],
        ),
      ),
    );
    if (field != null) draft.addRule(field);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    final id = await draft.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;

    ref
      ..invalidate(smartPlaylistsProvider)
      ..invalidate(smartPlaylistProvider(id));
    final t = ref.read(translationsProvider).call;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            draft.isNew
                ? PlaylistsKeys.smartCreated
                : PlaylistsKeys.smartUpdated,
          ),
        ),
      ),
    );
    Navigator.of(context).pop(id);
  }
}
