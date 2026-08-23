import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/keys.g.dart';
import '../../../i18n/translations_provider.dart';
import '../../library/data/formatting.dart';
import '../data/smart_draft.dart';
import '../data/smart_model.dart';

/// One rule: `<field> <op> <value>`, rendered from what the field and operator actually allow.
///
/// Every choice offered here comes out of `smart_model.dart`. That is what makes an unsendable
/// rule unbuildable rather than merely rejected: the operator menu holds only the operators the
/// field accepts, and the value widget is chosen by the kind the pair implies, so there is no
/// state the editor can be put into that the Hub would refuse.
class RuleEditor extends ConsumerStatefulWidget {
  const RuleEditor({
    required this.draft,
    required this.index,
    required this.condition,
    super.key,
  });

  final SmartDraft draft;
  final int index;
  final SmartCondition condition;

  @override
  ConsumerState<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<RuleEditor> {
  late final TextEditingController _value;
  late final TextEditingController _upper;

  /// A separate box for the next entry in a value LIST, so the chips above it stay put while
  /// somebody types the third artist.
  final _extra = TextEditingController();

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: _displayValue(widget.condition));
    _upper = TextEditingController(text: widget.condition.value2 ?? '');
  }

  @override
  void didUpdateWidget(RuleEditor old) {
    super.didUpdateWidget(old);
    // Only when the KIND changed. Rewriting the box on every notification would fight the cursor
    // of the person typing into it — the draft is the source of truth for the model, not for the
    // caret.
    final before = valueKindOf(old.condition.field, old.condition.op);
    final now = valueKindOf(widget.condition.field, widget.condition.op);
    if (before != now) {
      _value.text = _displayValue(widget.condition);
      _upper.text = widget.condition.value2 ?? '';
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _upper.dispose();
    _extra.dispose();
    super.dispose();
  }

  String _displayValue(SmartCondition c) =>
      valueKindOf(c.field, c.op) == ValueKind.duration
      ? msToClock(c.value)
      : c.value;

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final c = widget.condition;
    final draft = widget.draft;
    final index = widget.index;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SmartField>(
                    initialValue: c.field,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t(PlaylistsKeys.smartRuleField),
                    ),
                    items: [
                      for (final group in fieldGroups) ...[
                        for (final field in group.fields)
                          DropdownMenuItem(
                            value: field,
                            child: Text(t(smartFieldKey(field))),
                          ),
                      ],
                    ],
                    onChanged: (field) =>
                        field == null ? null : draft.setRuleField(index, field),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: t(PlaylistsKeys.smartRemoveRule),
                  onPressed: () => draft.removeRuleAt(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButtonFormField<SmartOp>(
                // Keyed by FIELD: a form field keeps its own selection, so without this the menu
                // would still be showing the previous field's operator after a retarget picked a
                // different default.
                key: ValueKey(c.field),
                initialValue: c.op,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.smartRuleOperator),
                ),
                // Only the operators this field accepts. Nothing filters a wider list down; the
                // wider list is never built.
                items: [
                  for (final op in opsFor(c.field))
                    DropdownMenuItem(value: op, child: Text(t(smartOpKey(op)))),
                ],
                onChanged: (op) =>
                    op == null ? null : draft.setRuleOp(index, op),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _valueField(context, t, c),
            ),
            if (isRange(c.op)) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _upperField(context, t, c),
              ),
            ],
            if (supportsPeriod(c.field)) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PeriodPicker(
                  label: t(PlaylistsKeys.smartPeriodLabel),
                  value: c.period,
                  allowAllTime: true,
                  onChanged: (period) => draft.setRulePeriod(index, period),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _valueField(BuildContext context, Translate t, SmartCondition c) {
    final draft = widget.draft;
    final index = widget.index;

    switch (valueKindOf(c.field, c.op)) {
      case ValueKind.boolean:
        final positive = c.value != 'false';
        final yes = c.field == SmartField.explicit
            ? PlaylistsKeys.smartBoolExplicitTrue
            : PlaylistsKeys.smartBoolLikedTrue;
        final no = c.field == SmartField.explicit
            ? PlaylistsKeys.smartBoolExplicitFalse
            : PlaylistsKeys.smartBoolLikedFalse;
        return SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(t(yes))),
            ButtonSegment(value: false, label: Text(t(no))),
          ],
          selected: {positive},
          onSelectionChanged: (selection) =>
              draft.setRuleValue(index, '${selection.first}'),
        );

      case ValueKind.variant:
        return DropdownButtonFormField<String>(
          key: ValueKey('variant:${c.field}'),
          initialValue: versionTypes.contains(c.value)
              ? c.value
              : versionTypes.first,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: t(smartFieldKey(SmartField.versionType)),
          ),
          items: [
            for (final variant in versionTypes)
              DropdownMenuItem(
                value: variant,
                child: Text(smartVariantLabel(variant, t)),
              ),
          ],
          onChanged: (value) =>
              value == null ? null : draft.setRuleValue(index, value),
        );

      case ValueKind.date:
        return _DateField(
          label: t(smartOpKey(c.op)),
          value: c.value,
          onChanged: (value) => draft.setRuleValue(index, value),
        );

      case ValueKind.days:
        return TextField(
          controller: _value,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: t(PlaylistsKeys.smartValuePlaceholder),
            suffixText: t(PlaylistsKeys.smartUnitDays),
          ),
          onChanged: (value) => draft.setRuleValue(index, value),
        );

      case ValueKind.count:
      case ValueKind.year:
        return TextField(
          controller: _value,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: t(PlaylistsKeys.smartValuePlaceholder),
          ),
          onChanged: (value) => draft.setRuleValue(index, value),
        );

      case ValueKind.duration:
        // Shown as `m:ss` and stored as milliseconds. A half-typed "3:" parses to the empty
        // string, which the save path drops as an unfinished rule rather than sending as
        // "longer than nothing".
        return TextField(
          controller: _value,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: t(PlaylistsKeys.smartValuePlaceholder),
            hintText: '3:30',
          ),
          onChanged: (value) => draft.setRuleValue(index, clockToMs(value)),
        );

      case ValueKind.text:
        return supportsValueList(c.field)
            ? _valueList(context, t, c)
            : TextField(
                controller: _value,
                decoration: InputDecoration(
                  labelText: t(PlaylistsKeys.smartValuePlaceholder),
                ),
                onChanged: (value) => draft.setRuleValue(index, value),
              );
    }
  }

  /// A text rule with several values, matched as OR: "artist is A, B or C".
  ///
  /// One rule about one field, rather than the three-row `match any` it used to take — which then
  /// could not be ANDed with anything else.
  Widget _valueList(BuildContext context, Translate t, SmartCondition c) {
    final values = valuesOf(c);
    final hintKey = smartValueHintKey(c.field);

    void commit(List<String> next) => widget.draft.setRuleValues(widget.index, [
      for (final value in next)
        if (value.trim().isNotEmpty) value.trim(),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (values.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final value in values)
                InputChip(
                  label: Text(value),
                  onDeleted: () =>
                      commit([...values]..removeWhere((v) => v == value)),
                  deleteButtonTooltipMessage: t(
                    PlaylistsKeys.smartValueListRemove,
                    {'name': value},
                  ),
                ),
            ],
          ),
        TextField(
          controller: _extra,
          decoration: InputDecoration(
            labelText: values.isEmpty
                ? t(PlaylistsKeys.smartValuePlaceholder)
                : t(PlaylistsKeys.smartValueListAddMore),
            hintText: hintKey == null ? null : t(hintKey),
          ),
          textInputAction: TextInputAction.done,
          // Committed on submit rather than on every keystroke: a chip that appears letter by
          // letter is not a chip, and the first value has to be able to stand alone.
          onSubmitted: (typed) {
            if (typed.trim().isEmpty) return;
            commit([...values, typed]);
            _extra.clear();
          },
          onChanged: (typed) {
            if (values.isEmpty) widget.draft.setRuleValue(widget.index, typed);
          },
        ),
      ],
    );
  }

  Widget _upperField(BuildContext context, Translate t, SmartCondition c) {
    final kind = valueKindOf(c.field, c.op);
    if (kind == ValueKind.date) {
      return _DateField(
        label: t(PlaylistsKeys.smartValueUpper),
        value: c.value2 ?? '',
        onChanged: (value) =>
            widget.draft.setRuleUpperValue(widget.index, value),
      );
    }
    return TextField(
      controller: _upper,
      keyboardType: kind == ValueKind.duration
          ? TextInputType.datetime
          : TextInputType.number,
      inputFormatters: kind == ValueKind.duration
          ? null
          : [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: t(PlaylistsKeys.smartValueUpper)),
      onChanged: (value) => widget.draft.setRuleUpperValue(
        widget.index,
        kind == ValueKind.duration ? clockToMs(value) : value,
      ),
    );
  }
}

/// A `YYYY-MM-DD` value, chosen from the platform date picker rather than typed.
///
/// Typing a date on a phone keyboard produces "2024-2-1" as often as not, and the Hub parses this
/// field strictly — so the box is read-only and the picker is the only way in.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value);
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: parsed ?? now,
            firstDate: DateTime(1900),
            lastDate: DateTime(now.year + 5),
          );
          if (picked != null) onChanged(_iso(picked));
        },
        child: Row(
          children: [
            Expanded(child: Text(value.isEmpty ? '—' : value)),
            const Icon(Icons.calendar_today_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A window of listening history: all time, a rolling stretch of days, this month, or this year.
///
/// Calendar and rolling windows are separate on the wire because they answer different questions
/// and are served from different tables — so they are separate here too, rather than being flattened
/// into a day count that would quietly turn "in 2025" into "the last 365 days".
class PeriodPicker extends ConsumerWidget {
  const PeriodPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowAllTime = false,
    super.key,
  });

  final String label;
  final SmartPeriod? value;
  final ValueChanged<SmartPeriod?> onChanged;

  /// Whether "all time" (no window at all) is one of the choices. It is for a rule — `my_plays`
  /// with no window means all time — and is not for the SORT, which is only offered on the one
  /// sort that requires a window.
  final bool allowAllTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final now = DateTime.now();
    final options = <_PeriodOption>[
      if (allowAllTime)
        _PeriodOption('all', t(PlaylistsKeys.smartPeriodAll), null),
      for (final days in const [7, 30, 90, 365])
        _PeriodOption(
          'rolling:$days',
          t(PlaylistsKeys.smartPeriodRolling, {'count': days}),
          SmartPeriodRolling(days: days),
        ),
      _PeriodOption(
        'month',
        t(PlaylistsKeys.smartPeriodMonth, {'month': monthKey(now)}),
        SmartPeriodMonth(month: monthKey(now)),
      ),
      _PeriodOption(
        'year',
        t(PlaylistsKeys.smartPeriodYear, {'year': now.year}),
        SmartPeriodYear(year: now.year),
      ),
    ];

    final current = _keyOf(value);
    return DropdownButtonFormField<String>(
      initialValue: options.any((o) => o.key == current)
          ? current
          : options.first.key,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option.key, child: Text(option.label)),
      ],
      onChanged: (key) {
        if (key == null) return;
        onChanged(options.firstWhere((o) => o.key == key).period);
      },
    );
  }

  static String _keyOf(SmartPeriod? period) => switch (period) {
    null => 'all',
    SmartPeriodRolling(:final days) => 'rolling:$days',
    SmartPeriodMonth() => 'month',
    SmartPeriodYear() => 'year',
  };
}

class _PeriodOption {
  const _PeriodOption(this.key, this.label, this.period);

  final String key;
  final String label;
  final SmartPeriod? period;
}
