import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'cell_editors.dart';

const _labelColors = ['amber', 'green', 'red', 'blue', 'purple', 'pink', 'teal', 'indigo', 'grey'];

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

/// Edits the labels of a status column or the options of a dropdown/tags column.
/// Returns the new `settings` map, or null if cancelled.
Future<Map<String, dynamic>?> editColumnSettings(BuildContext context, BoardColumn column) {
  final isStatus = column.type == 'status';
  final raw = isStatus
      ? column.statusLabels.map((l) => _Choice(id: l.id, label: l.label, color: l.color, isDone: l.isDone)).toList()
      : (column.settings['options'] as List<dynamic>? ?? const [])
          .map((o) => o as Map<String, dynamic>)
          .map((o) => _Choice(
                id: o['id'] as String,
                label: o['label'] as String? ?? '',
                color: o['color'] as String? ?? 'grey',
              ))
          .toList();

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ColumnSettingsSheet(column: column, initial: raw, isStatus: isStatus),
  );
}

class _ColumnSettingsSheet extends StatefulWidget {
  const _ColumnSettingsSheet({required this.column, required this.initial, required this.isStatus});

  final BoardColumn column;
  final List<_Choice> initial;
  final bool isStatus;

  @override
  State<_ColumnSettingsSheet> createState() => _ColumnSettingsSheetState();
}

class _ColumnSettingsSheetState extends State<_ColumnSettingsSheet> {
  late final List<_Choice> _choices = [...widget.initial];

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
      title: widget.isStatus ? 'New label' : 'New option',
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
    final cleaned = _choices.where((c) => c.label.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) {
      showDfToast(context, 'Keep at least one entry', icon: Icons.info_outline_rounded);
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      if (widget.isStatus)
        'labels': cleaned.map((c) => c.toStatusJson()).toList()
      else
        'options': cleaned.map((c) => c.toOptionJson()).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: DfSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.isStatus ? '${widget.column.title} labels' : '${widget.column.title} options',
              style: text.titleMedium,
            ),
          ),
          if (widget.isStatus)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Items on a "done" label count as complete.',
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: DfSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final choice in _choices)
                  Padding(
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
                      if (widget.isStatus)
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
                  ),
              ],
            ),
          ),
          const SizedBox(height: DfSpacing.xs),
          DfButton(
            label: widget.isStatus ? 'Add label' : 'Add option',
            variant: DfButtonVariant.tonal,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: _add,
          ),
          const SizedBox(height: DfSpacing.xs),
          DfButton(label: 'Save', onPressed: _save),
        ]),
      ),
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
