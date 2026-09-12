import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import 'filter_builder_sheet.dart';
import 'view_engine.dart';

/// Conditional colour rules: the same field / operator / value editors as
/// the filter builder plus a colour swatch and a Cell/Row toggle. Returns the
/// new list (possibly empty) or null when dismissed.
Future<List<ConditionalColor>?> showConditionalColorsSheet(
  BuildContext context, {
  required BoardDetail board,
  required List<BoardMember> members,
  required List<ConditionalColor> initial,
}) {
  return showModalBottomSheet<List<ConditionalColor>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) => _ConditionalColorsSheet(
        board: board,
        members: members,
        initial: initial,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ConditionalColorsSheet extends StatefulWidget {
  const _ConditionalColorsSheet({
    required this.board,
    required this.members,
    required this.initial,
    required this.scrollController,
  });

  final BoardDetail board;
  final List<BoardMember> members;
  final List<ConditionalColor> initial;
  final ScrollController scrollController;

  @override
  State<_ConditionalColorsSheet> createState() => _ConditionalColorsSheetState();
}

class _ConditionalColorsSheetState extends State<_ConditionalColorsSheet> {
  late List<ConditionalColor> _rules = [...widget.initial];
  late final List<RuleField> _fields = filterableFields(widget.board);

  void _replace(int index, ConditionalColor rule) => setState(() {
        final next = [..._rules];
        next[index] = rule;
        _rules = next;
      });

  void _add() {
    final seed = newFilterRule(_fields);
    final usedColors = _rules.map((r) => r.color).toSet();
    final color = viewColorPalette.where((c) => !usedColors.contains(c)).firstOrNull ?? viewColorPalette.first;
    setState(() => _rules = [
          ..._rules,
          ConditionalColor(id: seed.id, field: seed.field, operator: seed.operator, color: color),
        ]);
  }

  Future<void> _pickColor(int index) async {
    final current = _rules[index].color;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Color', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: DfSpacing.md),
            Wrap(spacing: DfSpacing.sm, runSpacing: DfSpacing.sm, children: [
              for (final token in viewColorPalette)
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
                    child: token == current ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    _replace(index, _rules[index].copyWith(color: picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Conditional colors', style: text.titleLarge)),
          if (_rules.isNotEmpty)
            TextButton(onPressed: () => setState(() => _rules = []), child: const Text('Clear all')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('The first matching rule wins. Row rules tint the whole item.', style: text.labelSmall),
        ),
      ),
      Expanded(
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
          children: [
            if (_rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DfSpacing.lg),
                child: Text(
                  'No colour rules yet. Highlight cells or rows that match a condition.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            for (final (index, rule) in _rules.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RuleEditorRow(
                    prefix: 'If',
                    rule: rule.asRule,
                    board: widget.board,
                    members: widget.members,
                    fields: _fields,
                    onChanged: (next) => _replace(
                      index,
                      rule.copyWith(field: next.field, operator: next.operator, value: () => next.value),
                    ),
                    onDelete: () => setState(() => _rules = [..._rules]..removeAt(index)),
                    trailing: InkWell(
                      onTap: () => _pickColor(index),
                      borderRadius: BorderRadius.circular(DfRadius.pill),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
                        decoration: BoxDecoration(
                          color: DfColors.token(rule.color).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(DfRadius.pill),
                          border: Border.all(color: DfColors.token(rule.color)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: DfColors.token(rule.color), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(rule.color, style: text.labelMedium),
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(DfSpacing.sm, DfSpacing.xxs, 0, 0),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 'cell', label: Text('Cell')),
                        ButtonSegment(value: 'row', label: Text('Row')),
                      ],
                      selected: {rule.applyTo},
                      onSelectionChanged: (selection) => _replace(index, rule.copyWith(applyTo: selection.first)),
                    ),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(_rules.isEmpty ? 'Add rule' : 'Add another rule'),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: DfButton(label: 'Apply', onPressed: () => Navigator.pop(context, _rules)),
      ),
    ]);
  }
}
