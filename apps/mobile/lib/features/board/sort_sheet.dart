import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import 'columns_sheet.dart' show columnTypeIcon;
import 'view_engine.dart';

/// A sortable field: `name`, `created_at`, `updated_at`, `serial` or a column.
class SortField {
  const SortField({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;
}

/// Name, Created, Updated, Item ID, then the board's item columns.
List<SortField> sortableFields(BoardDetail board) => [
      const SortField(id: 'name', label: 'Name', icon: Icons.title_rounded),
      const SortField(id: 'created_at', label: 'Created', icon: Icons.history_rounded),
      const SortField(id: 'updated_at', label: 'Updated', icon: Icons.update_rounded),
      const SortField(id: 'serial', label: 'Item ID', icon: Icons.tag_rounded),
      for (final column in board.itemColumns)
        SortField(id: column.id, label: column.title, icon: columnTypeIcon(column.type)),
    ];

String sortFieldLabel(BoardDetail board, String field) =>
    sortableFields(board).where((f) => f.id == field).firstOrNull?.label ?? 'Deleted column';

/// Ordered sort rules: pick a field, flip the direction, add, remove, drag to
/// reorder. Returns the new list (possibly empty) or null when dismissed.
Future<List<SortRule>?> showSortSheet(
  BuildContext context, {
  required BoardDetail board,
  required List<SortRule> initial,
}) {
  return showModalBottomSheet<List<SortRule>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) =>
          _SortSheet(board: board, initial: initial, scrollController: scrollController),
    ),
  );
}

class _SortSheet extends StatefulWidget {
  const _SortSheet({required this.board, required this.initial, required this.scrollController});

  final BoardDetail board;
  final List<SortRule> initial;
  final ScrollController scrollController;

  @override
  State<_SortSheet> createState() => _SortSheetState();
}

class _SortSheetState extends State<_SortSheet> {
  late List<SortRule> _rules = [...widget.initial];
  late final List<SortField> _fields = sortableFields(widget.board);

  Future<void> _pickField(int index) async {
    final used = {for (final (i, r) in _rules.indexed) if (i != index) r.field};
    final picked = await showModalBottomSheet<SortField>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (draggableContext, scrollController) => ListView(
          controller: scrollController,
          children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('Sort by', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final field in _fields)
              ListTile(
                leading: Icon(field.icon, size: 20, color: DfColors.primary),
                title: Text(field.label),
                enabled: !used.contains(field.id),
                trailing: _rules[index].field == field.id
                    ? const Icon(Icons.check_rounded, color: DfColors.primary)
                    : null,
                onTap: () => Navigator.pop(sheetContext, field),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      final next = [..._rules];
      next[index] = next[index].copyWith(field: picked.id);
      _rules = next;
    });
  }

  void _add() {
    final used = _rules.map((r) => r.field).toSet();
    final field = _fields.where((f) => !used.contains(f.id)).firstOrNull;
    if (field == null) return;
    setState(() => _rules = [..._rules, SortRule(field: field.id)]);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Sort', style: text.titleLarge)),
          if (_rules.isNotEmpty)
            TextButton(onPressed: () => setState(() => _rules = []), child: const Text('Clear')),
        ]),
      ),
      if (_rules.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Items sort by the first rule, then ties by the next.', style: text.labelSmall),
          ),
        ),
      Expanded(
        child: _rules.isEmpty
            ? Center(
                child: Text(
                  'Items follow the board order. Add a rule to sort them.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            : ReorderableListView.builder(
                scrollController: widget.scrollController,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
                itemCount: _rules.length,
                onReorderItem: (oldIndex, newIndex) => setState(() {
                  final next = [..._rules];
                  final moved = next.removeAt(oldIndex);
                  next.insert(newIndex, moved);
                  _rules = next;
                }),
                itemBuilder: (context, i) {
                  final rule = _rules[i];
                  return Container(
                    key: ValueKey('${rule.field}:$i'),
                    margin: const EdgeInsets.only(bottom: DfSpacing.xs),
                    padding: const EdgeInsets.fromLTRB(DfSpacing.xs, DfSpacing.xxs, DfSpacing.xxs, DfSpacing.xxs),
                    decoration: BoxDecoration(
                      color: isDark ? DfColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(DfRadius.md),
                      border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
                    ),
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(DfSpacing.xs),
                          child: Icon(Icons.drag_handle_rounded, color: DfColors.textTertiary),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickField(i),
                          borderRadius: BorderRadius.circular(DfRadius.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: DfSpacing.xs),
                            child: Text(
                              sortFieldLabel(widget.board, rule.field),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          final next = [..._rules];
                          next[i] = rule.copyWith(direction: rule.isDescending ? 'asc' : 'desc');
                          _rules = next;
                        }),
                        icon: Icon(
                          rule.isDescending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 16,
                        ),
                        label: Text(rule.isDescending ? 'Desc' : 'Asc'),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.textTertiary),
                        tooltip: 'Remove',
                        onPressed: () => setState(() => _rules = [..._rules]..removeAt(i)),
                      ),
                    ]),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _rules.length < _fields.length ? _add : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(_rules.isEmpty ? 'Add sort' : 'Add another'),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.md),
        child: DfButton(label: 'Apply', onPressed: () => Navigator.pop(context, _rules)),
      ),
    ]);
  }
}
