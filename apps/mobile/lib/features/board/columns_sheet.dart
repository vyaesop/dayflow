import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'board_controller.dart';
import 'cell_editors.dart';
import 'column_settings_sheet.dart';
import 'view_engine.dart';

/// One entry of the "Add column" picker.
class ColumnTypeEntry {
  const ColumnTypeEntry({required this.type, required this.label, required this.icon, this.section});

  final String type;
  final String label;
  final IconData icon;

  /// Set on the read-only "Board info" types.
  final String? section;
}

/// Column types in the order the contract's picker lists them (§1).
const columnTypeCatalog = <ColumnTypeEntry>[
  ColumnTypeEntry(type: 'status', label: 'Status', icon: Icons.donut_large_rounded),
  ColumnTypeEntry(type: 'people', label: 'People', icon: Icons.person_outline_rounded),
  ColumnTypeEntry(type: 'date', label: 'Date', icon: Icons.event_rounded),
  ColumnTypeEntry(type: 'timeline', label: 'Timeline', icon: Icons.date_range_rounded),
  ColumnTypeEntry(type: 'text', label: 'Text', icon: Icons.notes_rounded),
  ColumnTypeEntry(type: 'long_text', label: 'Long text', icon: Icons.subject_rounded),
  ColumnTypeEntry(type: 'number', label: 'Number', icon: Icons.numbers_rounded),
  ColumnTypeEntry(type: 'checkbox', label: 'Checkbox', icon: Icons.check_box_outlined),
  ColumnTypeEntry(type: 'dropdown', label: 'Dropdown', icon: Icons.arrow_drop_down_circle_outlined),
  ColumnTypeEntry(type: 'tags', label: 'Tags', icon: Icons.sell_outlined),
  ColumnTypeEntry(type: 'link', label: 'Link', icon: Icons.link_rounded),
  ColumnTypeEntry(type: 'email', label: 'Email', icon: Icons.alternate_email_rounded),
  ColumnTypeEntry(type: 'phone', label: 'Phone', icon: Icons.phone_outlined),
  ColumnTypeEntry(type: 'location', label: 'Location', icon: Icons.place_outlined),
  ColumnTypeEntry(type: 'files', label: 'Files', icon: Icons.attach_file_rounded),
  ColumnTypeEntry(type: 'rating', label: 'Rating', icon: Icons.star_border_rounded),
  ColumnTypeEntry(type: 'vote', label: 'Vote', icon: Icons.thumb_up_alt_outlined),
  ColumnTypeEntry(type: 'item_id', label: 'Item ID', icon: Icons.tag_rounded, section: 'Board info'),
  ColumnTypeEntry(type: 'creation_log', label: 'Creation log', icon: Icons.history_rounded, section: 'Board info'),
  ColumnTypeEntry(type: 'last_updated', label: 'Last updated', icon: Icons.update_rounded, section: 'Board info'),
  ColumnTypeEntry(type: 'auto_number', label: 'Auto number', icon: Icons.format_list_numbered_rounded, section: 'Board info'),
];

IconData columnTypeIcon(String type) =>
    columnTypeCatalog.where((t) => t.type == type).firstOrNull?.icon ?? Icons.view_column_outlined;

String columnTypeLabel(String type) =>
    columnTypeCatalog.where((t) => t.type == type).firstOrNull?.label ?? type.replaceAll('_', ' ');

/// Type picker followed by a name prompt. Returns null when dismissed.
Future<({String type, String title})?> showAddColumnSheet(BuildContext context, {String scope = 'items'}) async {
  final picked = await showModalBottomSheet<ColumnTypeEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) => ListView(
        controller: scrollController,
        children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(
              scope == 'subitems' ? 'Add a subitem column' : 'Add a column',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final (index, entry) in columnTypeCatalog.indexed) ...[
            if (entry.section != null && (index == 0 || columnTypeCatalog[index - 1].section != entry.section))
              Padding(
                padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.sm, DfSpacing.md, DfSpacing.xxs),
                child: Text(entry.section!.toUpperCase(), style: Theme.of(sheetContext).textTheme.labelSmall),
              ),
            ListTile(
              leading: Icon(entry.icon, color: DfColors.primary),
              title: Text(entry.label),
              subtitle: entry.section != null ? const Text('Read-only, filled in automatically') : null,
              onTap: () => Navigator.pop(sheetContext, entry),
            ),
          ],
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return null;

  final title = await promptForText(context, title: 'Column name', initial: picked.label);
  if (title == null || title.isEmpty) return null;
  return (type: picked.type, title: title);
}

/// Columns sheet: reorder (board-level, via `moveColumn`), show/hide (view
/// level, via [onConfigChanged]), rename, settings, delete, add — for item
/// columns and, in a second segment, subitem columns.
Future<void> showColumnsSheet(
  BuildContext context, {
  required String boardId,
  required ViewConfig config,
  required ValueChanged<ViewConfig> onConfigChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) => _ColumnsSheet(
        boardId: boardId,
        initial: config,
        onConfigChanged: onConfigChanged,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ColumnsSheet extends ConsumerStatefulWidget {
  const _ColumnsSheet({
    required this.boardId,
    required this.initial,
    required this.onConfigChanged,
    required this.scrollController,
  });

  final String boardId;
  final ViewConfig initial;
  final ValueChanged<ViewConfig> onConfigChanged;
  final ScrollController scrollController;

  @override
  ConsumerState<_ColumnsSheet> createState() => _ColumnsSheetState();
}

class _ColumnsSheetState extends ConsumerState<_ColumnsSheet> {
  late ViewConfig _config = widget.initial;
  String _scope = 'items';

  BoardController get _controller => ref.read(boardControllerProvider(widget.boardId).notifier);

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  void _setHidden(String columnId, bool hidden) {
    final next = [..._config.hiddenColumnIds.where((id) => id != columnId), if (hidden) columnId];
    setState(() => _config = _config.copyWith(hiddenColumnIds: next));
    widget.onConfigChanged(_config);
  }

  Future<void> _reorder(List<BoardColumn> columns, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final remaining = [...columns]..removeAt(oldIndex);
    final moved = columns[oldIndex];
    final afterColumnId = newIndex == 0 ? null : remaining[newIndex - 1].id;
    await _guard(() => _controller.moveColumn(columnId: moved.id, afterColumnId: afterColumnId));
  }

  Future<void> _rename(BoardColumn column) async {
    final title = await promptForText(context, title: 'Rename column', initial: column.title);
    if (title == null || title.isEmpty || title == column.title) return;
    await _guard(() => _controller.renameColumn(column.id, title));
  }

  Future<void> _settings(BoardColumn column) async {
    final settings = await editColumnSettings(context, column);
    if (settings == null) return;
    await _guard(() => _controller.updateColumnSettings(column.id, settings));
  }

  Future<void> _delete(BoardColumn column) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${column.title}"?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          'Its values are removed from every ${column.isSubitemColumn ? 'subitem' : 'item'} on this board.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: DfColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => _controller.deleteColumn(column.id));
  }

  Future<void> _add() async {
    final picked = await showAddColumnSheet(context, scope: _scope);
    if (picked == null) return;
    await _guard(() => _controller.addColumn(type: picked.type, title: picked.title, scope: _scope));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final board = ref.watch(boardControllerProvider(widget.boardId)).value;
    if (board == null) return const Center(child: CircularProgressIndicator());

    final columns = _scope == 'subitems' ? board.subitemColumns : board.itemColumns;
    final hidden = _config.hiddenColumnIds.toSet();
    final canEdit = board.canEdit;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Columns', style: text.titleLarge)),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: DfColors.primary),
              tooltip: 'Add column',
              onPressed: _add,
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'items', label: Text('Item columns')),
            ButtonSegment(value: 'subitems', label: Text('Subitem columns')),
          ],
          selected: {_scope},
          onSelectionChanged: (selection) => setState(() => _scope = selection.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xs, DfSpacing.md, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            canEdit
                ? 'Drag to reorder the board. The eye only changes this view.'
                : 'The eye only changes this view.',
            style: text.labelSmall,
          ),
        ),
      ),
      Expanded(
        child: columns.isEmpty
            ? Center(
                child: Text(
                  _scope == 'subitems'
                      ? 'No subitem columns yet — they appear with the first subitem.'
                      : 'No columns yet.',
                  style: text.bodySmall,
                ),
              )
            : ReorderableListView.builder(
                scrollController: widget.scrollController,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(vertical: DfSpacing.xs),
                itemCount: columns.length,
                onReorderItem: canEdit ? (oldIndex, newIndex) => _reorder(columns, oldIndex, newIndex) : (_, _) {},
                itemBuilder: (context, i) {
                  final column = columns[i];
                  final isHidden = hidden.contains(column.id);
                  return ListTile(
                    key: ValueKey(column.id),
                    leading: canEdit
                        ? ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle_rounded, color: DfColors.textTertiary),
                          )
                        : Icon(columnTypeIcon(column.type), color: DfColors.primary, size: 20),
                    title: Text(
                      column.title,
                      style: isHidden ? text.bodyMedium?.copyWith(color: DfColors.textTertiary) : null,
                    ),
                    subtitle: Text(columnTypeLabel(column.type)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: Icon(
                          isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: isHidden ? DfColors.textTertiary : DfColors.textSecondary,
                        ),
                        tooltip: isHidden ? 'Show in this view' : 'Hide in this view',
                        onPressed: () => _setHidden(column.id, !isHidden),
                      ),
                      if (canEdit)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: (action) => switch (action) {
                            'rename' => _rename(column),
                            'settings' => _settings(column),
                            'delete' => _delete(column),
                            _ => null,
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'settings', child: Text('Settings')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: DfColors.danger)),
                            ),
                          ],
                        ),
                    ]),
                  );
                },
              ),
      ),
      if (canEdit)
        Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: DfButton(
            label: _scope == 'subitems' ? 'Add subitem column' : 'Add column',
            variant: DfButtonVariant.tonal,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: _add,
          ),
        ),
    ]);
  }
}
