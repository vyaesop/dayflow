import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import 'cell_editors.dart';

const _labelColors = ['amber', 'green', 'red', 'blue', 'purple', 'pink', 'teal', 'indigo', 'grey'];

/// Column types whose footer summary can be switched off.
const _footerSummaryTypes = {'status', 'checkbox', 'people', 'date', 'timeline'};

const _numberSummaryModes = ['sum', 'avg', 'min', 'max', 'count', 'none'];

/// Applies [changes] on top of [base]: keys set to null are removed.
Map<String, dynamic> mergeColumnSettings(Map<String, dynamic> base, Map<String, dynamic> changes) {
  final merged = <String, dynamic>{...base};
  changes.forEach((key, value) {
    if (value == null) {
      merged.remove(key);
    } else {
      merged[key] = value;
    }
  });
  return merged;
}

/// Editable copy of one status label / dropdown option.
class _Choice {
  _Choice({required this.id, required this.label, required this.color, this.isDone = false});

  final String id;
  String label;
  String color;
  bool isDone;

  Map<String, dynamic> toStatusJson() => {'id': id, 'label': label, 'color': color, 'isDone': isDone};
  Map<String, dynamic> toOptionJson() => {'id': id, 'label': label, 'color': color};
}

/// Edits a column's settings: description for every type, type-specific
/// options (number formatting, rating max, footer summary) and, for status /
/// dropdown / tags columns, the labels or options list.
///
/// Returns the full merged `settings` map ready to PATCH, or null if cancelled.
Future<Map<String, dynamic>?> editColumnSettings(BuildContext context, BoardColumn column) async {
  final isStatus = column.type == 'status';
  final hasChoices = isStatus || column.type == 'dropdown' || column.type == 'tags';
  final raw = !hasChoices
      ? const <_Choice>[]
      : isStatus
          ? column.statusLabels
              .map((l) => _Choice(id: l.id, label: l.label, color: l.color, isDone: l.isDone))
              .toList()
          : column.options
              .map((o) => _Choice(
                    id: o['id'] as String,
                    label: o['label'] as String? ?? '',
                    color: o['color'] as String? ?? 'grey',
                  ))
              .toList();

  final changes = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ColumnSettingsSheet(column: column, initial: raw),
  );
  if (changes == null) return null;
  return mergeColumnSettings(column.settings, changes);
}

class _ColumnSettingsSheet extends StatefulWidget {
  const _ColumnSettingsSheet({required this.column, required this.initial});

  final BoardColumn column;
  final List<_Choice> initial;

  @override
  State<_ColumnSettingsSheet> createState() => _ColumnSettingsSheetState();
}

class _ColumnSettingsSheetState extends State<_ColumnSettingsSheet> {
  BoardColumn get column => widget.column;
  bool get isStatus => column.type == 'status';
  bool get hasChoices => isStatus || column.type == 'dropdown' || column.type == 'tags';

  late final List<_Choice> _choices = [...widget.initial];

  late final TextEditingController _description = TextEditingController(text: column.description ?? '');
  late final TextEditingController _unit = TextEditingController(text: column.settings['unit'] as String? ?? '');
  late String _unitPosition = column.settings['unitPosition'] == 'prefix' ? 'prefix' : 'suffix';
  late int? _decimals = _readDecimals(column.settings['decimals']);
  late String _numberSummary =
      _numberSummaryModes.contains(column.summaryMode) ? column.summaryMode! : 'sum';
  late int _ratingMax = column.ratingMax;
  late bool _showFooterSummary = column.summaryMode != 'none';

  static int? _readDecimals(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toInt();
    return value >= 0 && value <= 6 ? value : null;
  }

  @override
  void dispose() {
    _description.dispose();
    _unit.dispose();
    super.dispose();
  }

  /// Slug from the label, kept unique — ids are referenced by stored cell
  /// values, so existing entries keep theirs.
  String _idFor(String label) {
    final base = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    var candidate = base.isEmpty ? 'option' : base;
    var n = 2;
    while (_choices.any((c) => c.id == candidate)) {
      candidate = '${base.isEmpty ? 'option' : base}_$n';
      n++;
    }
    return candidate;
  }

  Future<void> _add() async {
    final label = await promptForText(
      context,
      title: isStatus ? 'New label' : 'New option',
      hint: 'Name',
    );
    if (label == null || label.isEmpty) return;
    setState(() => _choices.add(_Choice(id: _idFor(label), label: label, color: _nextColor())));
  }

  String _nextColor() => _labelColors[_choices.length % _labelColors.length];

  Future<void> _rename(_Choice choice) async {
    final label = await promptForText(context, title: 'Rename', initial: choice.label);
    if (label == null || label.isEmpty) return;
    setState(() => choice.label = label);
  }

  void _save() {
    final changes = <String, dynamic>{};

    final description = _description.text.trim();
    if (description.length > 500) {
      showDfToast(context, 'Keep the description under 500 characters', icon: Icons.info_outline_rounded);
      return;
    }
    changes['description'] = description.isEmpty ? null : description;

    switch (column.type) {
      case 'number':
        final unit = _unit.text.trim();
        if (unit.length > 12) {
          showDfToast(context, 'Keep the unit under 12 characters', icon: Icons.info_outline_rounded);
          return;
        }
        changes['unit'] = unit.isEmpty ? null : unit;
        changes['unitPosition'] = unit.isEmpty ? null : _unitPosition;
        changes['decimals'] = _decimals;
        changes['summary'] = _numberSummary;
      case 'rating':
        changes['max'] = _ratingMax;
      default:
        if (_footerSummaryTypes.contains(column.type)) {
          changes['summary'] = _showFooterSummary ? null : 'none';
        }
    }

    if (hasChoices) {
      final cleaned = _choices.where((c) => c.label.trim().isNotEmpty).toList();
      if (cleaned.isEmpty) {
        showDfToast(context, 'Keep at least one entry', icon: Icons.info_outline_rounded);
        return;
      }
      if (isStatus) {
        changes['labels'] = cleaned.map((c) => c.toStatusJson()).toList();
      } else {
        changes['options'] = cleaned.map((c) => c.toOptionJson()).toList();
      }
    }

    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          DfSpacing.md,
          DfSpacing.md,
          DfSpacing.md,
          DfSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: DfSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${column.title} settings', style: text.titleMedium),
          ),
          const SizedBox(height: DfSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _SectionLabel('Settings'),
                DfTextField(
                  controller: _description,
                  label: 'Description',
                  hint: 'What goes in this column?',
                  textInputAction: TextInputAction.done,
                ),
                ..._typeSettings(text),
                if (hasChoices) ...[
                  const SizedBox(height: DfSpacing.md),
                  _SectionLabel(isStatus ? 'Labels' : 'Options'),
                  if (isStatus)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                      child: Text('Items on a "done" label count as complete.', style: text.bodySmall),
                    ),
                  for (final choice in _choices) _choiceRow(choice, text),
                  const SizedBox(height: DfSpacing.xs),
                  DfButton(
                    label: isStatus ? 'Add label' : 'Add option',
                    variant: DfButtonVariant.tonal,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    onPressed: _add,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: DfSpacing.sm),
          DfButton(label: 'Save', onPressed: _save),
        ]),
      ),
    );
  }

  List<Widget> _typeSettings(TextTheme text) {
    switch (column.type) {
      case 'number':
        return [
          const SizedBox(height: DfSpacing.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: 110,
              child: DfTextField(controller: _unit, label: 'Unit', hint: r'$, kg, h'),
            ),
            const SizedBox(width: DfSpacing.sm),
            Expanded(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'prefix', label: Text('Prefix')),
                  ButtonSegment(value: 'suffix', label: Text('Suffix')),
                ],
                selected: {_unitPosition},
                onSelectionChanged: (s) => setState(() => _unitPosition = s.first),
              ),
            ),
          ]),
          const SizedBox(height: DfSpacing.sm),
          DropdownButtonFormField<int>(
            initialValue: _decimals ?? -1,
            decoration: const InputDecoration(labelText: 'Decimals'),
            items: [
              const DropdownMenuItem(value: -1, child: Text('Auto')),
              for (var d = 0; d <= 6; d++) DropdownMenuItem(value: d, child: Text('$d')),
            ],
            onChanged: (v) => setState(() => _decimals = v == null || v < 0 ? null : v),
          ),
          const SizedBox(height: DfSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _numberSummary,
            decoration: const InputDecoration(labelText: 'Summary'),
            items: [
              for (final mode in _numberSummaryModes)
                DropdownMenuItem(value: mode, child: Text(_summaryLabel(mode))),
            ],
            onChanged: (v) => setState(() => _numberSummary = v ?? 'sum'),
          ),
        ];

      case 'rating':
        return [
          const SizedBox(height: DfSpacing.sm),
          DropdownButtonFormField<int>(
            initialValue: _ratingMax,
            decoration: const InputDecoration(labelText: 'Max stars'),
            items: [for (var n = 1; n <= 10; n++) DropdownMenuItem(value: n, child: Text('$n'))],
            onChanged: (v) => setState(() => _ratingMax = v ?? 5),
          ),
        ];

      default:
        if (!_footerSummaryTypes.contains(column.type)) return const [];
        return [
          const SizedBox(height: DfSpacing.xs),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show summary in footer'),
            subtitle: Text(_footerHint(column.type), style: text.bodySmall),
            value: _showFooterSummary,
            onChanged: (v) => setState(() => _showFooterSummary = v),
          ),
        ];
    }
  }

  static String _summaryLabel(String mode) => switch (mode) {
        'sum' => 'Sum',
        'avg' => 'Average',
        'min' => 'Minimum',
        'max' => 'Maximum',
        'count' => 'Count',
        _ => 'None',
      };

  static String _footerHint(String type) => switch (type) {
        'status' => 'Distribution of labels under each group',
        'checkbox' => 'Checked out of total, e.g. 3/8',
        'people' => 'Number of distinct assignees',
        'date' => 'Earliest to latest date',
        'timeline' => 'Earliest start to latest end',
        _ => '',
      };

  Widget _choiceRow(_Choice choice, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: Row(children: [
        GestureDetector(
          onTap: () async {
            final picked = await _pickColor(context, choice.color);
            if (picked != null) setState(() => choice.color = picked);
          },
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: DfColors.token(choice.color),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: DfSpacing.xs),
        Expanded(
          child: GestureDetector(
            onTap: () => _rename(choice),
            child: Text(choice.label, style: text.bodyMedium),
          ),
        ),
        if (isStatus)
          Tooltip(
            message: 'Counts as done',
            child: Checkbox(
              value: choice.isDone,
              onChanged: (value) => setState(() => choice.isDone = value ?? false),
            ),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.textTertiary),
          tooltip: 'Remove',
          onPressed: () => setState(() => _choices.remove(choice)),
        ),
      ]),
    );
  }

  Future<String?> _pickColor(BuildContext context, String current) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Wrap(
            spacing: DfSpacing.sm,
            runSpacing: DfSpacing.sm,
            children: [
              for (final token in _labelColors)
                GestureDetector(
                  onTap: () => Navigator.pop(sheetContext, token),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: DfColors.token(token),
                      borderRadius: BorderRadius.circular(DfRadius.sm),
                      border: token == current ? Border.all(color: DfColors.textPrimary, width: 2.5) : null,
                    ),
                    child: token == current
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: DfColors.textTertiary, letterSpacing: 0.6),
      ),
    );
  }
}
