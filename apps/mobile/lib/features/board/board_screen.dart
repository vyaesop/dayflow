import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../home/home_providers.dart';
import '../members/members_providers.dart';
import 'board_controller.dart';
import 'board_filters.dart';
import 'cell_editors.dart';
import 'column_settings_sheet.dart';

const _groupColors = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];

const _columnTypes = <({String type, String label, IconData icon})>[
  (type: 'status', label: 'Status', icon: Icons.donut_large_rounded),
  (type: 'people', label: 'People', icon: Icons.person_outline_rounded),
  (type: 'date', label: 'Date', icon: Icons.event_rounded),
  (type: 'text', label: 'Text', icon: Icons.notes_rounded),
  (type: 'number', label: 'Number', icon: Icons.numbers_rounded),
  (type: 'checkbox', label: 'Checkbox', icon: Icons.check_box_outlined),
  (type: 'link', label: 'Link', icon: Icons.link_rounded),
  (type: 'timeline', label: 'Timeline', icon: Icons.date_range_rounded),
];

/// Editable board: groups, items, and typed cells.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final _quickFind = TextEditingController();
  bool _showQuickFind = false;

  String get boardId => widget.boardId;

  @override
  void dispose() {
    _quickFind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardControllerProvider(boardId));
    final controller = ref.read(boardControllerProvider(boardId).notifier);
    final filter = ref.watch(boardFilterProvider(boardId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        centerTitle: false,
        titleSpacing: 0,
        title: state.maybeWhen(
          data: (board) => GestureDetector(
            onTap: () => _renameBoard(context, controller, board),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${board.workspaceName} · ${board.itemCount} items',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          orElse: () => const Text('Board'),
        ),
        actions: [
          ...state.maybeWhen(
            data: (board) => [
              IconButton(
                icon: Icon(
                  board.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: board.isFavorite ? DfColors.accentAmber : null,
                ),
                tooltip: board.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () => _guard(context, () async {
                  await controller.toggleFavorite();
                  ref.invalidate(homeOverviewProvider);
                  ref.invalidate(workspacesProvider);
                }),
              ),
              // View switcher: Table (here) / Kanban / Calendar.
              PopupMenuButton<String>(
                icon: const Icon(Icons.grid_view_outlined),
                tooltip: 'Change view',
                onSelected: (view) => switch (view) {
                  'kanban' => context.push('/boards/$boardId/kanban'),
                  'calendar' => context.push('/boards/$boardId/calendar'),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'table',
                    enabled: false,
                    child: Row(children: [
                      Icon(Icons.table_rows_outlined, size: 18, color: DfColors.primary),
                      SizedBox(width: 8),
                      Text('Main Table'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'kanban',
                    child: Row(children: [
                      Icon(Icons.view_kanban_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Kanban'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'calendar',
                    child: Row(children: [
                      Icon(Icons.calendar_month_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Calendar'),
                    ]),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) => switch (action) {
                  'group' => _addGroup(context, controller),
                  'column' => _addColumn(context, controller),
                  'columns' => _manageColumns(context, controller, board),
                  'rename' => _renameBoard(context, controller, board),
                  'info' => _showBoardInfo(context, board),
                  'export' => _exportCsv(context, board),
                  'archive' => _archiveBoard(context, board),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'group', child: Text('Add group')),
                  PopupMenuItem(value: 'column', child: Text('Add column')),
                  PopupMenuItem(value: 'columns', child: Text('Manage columns')),
                  PopupMenuItem(value: 'rename', child: Text('Rename board')),
                  PopupMenuItem(value: 'info', child: Text('Board info')),
                  PopupMenuItem(value: 'export', child: Text('Export to CSV')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive board', style: TextStyle(color: DfColors.danger)),
                  ),
                ],
              ),
            ],
            orElse: () => const <Widget>[],
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _BoardError(
          message: '$error',
          onRetry: () => ref.invalidate(boardControllerProvider(boardId)),
        ),
        data: (board) => Column(children: [
          // Quick find + filter bar, as on the design's table view.
          Container(
            padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xxs, DfSpacing.xs, DfSpacing.xxs),
            child: Row(children: [
              Expanded(
                child: AnimatedContainer(
                  duration: DfMotion.productiveLong,
                  curve: DfMotion.transition,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(DfRadius.pill),
                    border: Border.all(
                      color: _showQuickFind || filter.query.isNotEmpty
                          ? DfColors.primary
                          : (isDark ? DfColors.borderDark : DfColors.border),
                    ),
                  ),
                  child: Row(children: [
                    const SizedBox(width: DfSpacing.sm),
                    const Icon(Icons.search_rounded, size: 18, color: DfColors.textTertiary),
                    const SizedBox(width: DfSpacing.xs),
                    Expanded(
                      child: TextField(
                        controller: _quickFind,
                        onTap: () => setState(() => _showQuickFind = true),
                        onChanged: (value) => ref.read(boardFilterProvider(boardId).notifier).state =
                            filter.copyWith(query: value.trim()),
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          hintText: 'Quick find',
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (filter.query.isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          _quickFind.clear();
                          ref.read(boardFilterProvider(boardId).notifier).state =
                              filter.copyWith(query: '');
                        },
                      ),
                  ]),
                ),
              ),
              IconButton(
                icon: Icon(
                  filter.personId != null || filter.statusLabelId != null
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                  color: filter.personId != null || filter.statusLabelId != null
                      ? DfColors.primary
                      : DfColors.textSecondary,
                ),
                tooltip: 'Quick filters',
                onPressed: () async {
                  final members = await ref
                      .read(assignableMembersProvider.future)
                      .catchError((Object _) => board.members);
                  if (!context.mounted) return;
                  await showBoardFilterSheet(
                    context: context,
                    ref: ref,
                    boardId: boardId,
                    board: board,
                    members: members,
                  );
                },
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: _BoardBody(board: board, controller: controller, filter: filter),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showBoardInfo(BuildContext context, BoardDetail board) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(board.name, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: DfSpacing.xxs),
            if (board.description != null && board.description!.isNotEmpty) ...[
              Text(board.description!, style: Theme.of(sheetContext).textTheme.bodyMedium),
              const SizedBox(height: DfSpacing.sm),
            ],
            Text(
              '${board.workspaceName} · ${board.type} board\n'
              '${board.groups.length} groups · ${board.itemCount} items · ${board.columns.length} columns',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            if (board.members.isNotEmpty) ...[
              const SizedBox(height: DfSpacing.sm),
              Row(children: [
                for (final member in board.members.take(8))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: DfAvatar(
                      name: member.fullName,
                      seed: member.userId,
                      imageUrl: member.avatarUrl,
                      size: 28,
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: DfSpacing.sm),
          ]),
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, BoardDetail board) async {
    await _guard(context, () async {
      final csv = await ApiClient.instance.getText('/boards/${board.id}/export.csv');
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        showDfToast(context, 'CSV copied to clipboard (${csv.split('\n').length - 1} rows)');
      }
    });
  }

  Future<void> _archiveBoard(BuildContext context, BoardDetail board) async {
    final confirmed = await _confirm(
      context,
      title: 'Archive "${board.name}"?',
      message: 'The board disappears from lists. Its data is kept.',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _guard(context, () async {
      await ref.read(boardRepositoryProvider).archiveBoard(board.id);
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
      if (context.mounted) context.pop();
    });
  }

  Future<void> _renameBoard(BuildContext context, BoardController controller, BoardDetail board) async {
    final name = await promptForText(context, title: 'Rename board', initial: board.name);
    if (name == null || name == board.name || !context.mounted) return;
    await _guard(context, () => controller.renameBoard(name));
  }

  Future<void> _addGroup(BuildContext context, BoardController controller) async {
    final title = await promptForText(context, title: 'New group', hint: 'Group name');
    if (title == null || title.isEmpty || !context.mounted) return;
    await _guard(context, () => controller.addGroup(title));
  }

  Future<void> _addColumn(BuildContext context, BoardController controller) async {
    final picked = await showModalBottomSheet<({String type, String label, IconData icon})>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('Add a column', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final type in _columnTypes)
              ListTile(
                leading: Icon(type.icon, color: DfColors.primary),
                title: Text(type.label),
                onTap: () => Navigator.pop(sheetContext, type),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    final title = await promptForText(context, title: 'Column name', initial: picked.label);
    if (title == null || title.isEmpty || !context.mounted) return;
    await _guard(context, () => controller.addColumn(type: picked.type, title: title));
  }

  /// Rename columns, edit their choices, or remove them.
  Future<void> _manageColumns(BuildContext context, BoardController controller, BoardDetail board) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: DfSpacing.sm),
          children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('Columns', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final column in board.columns)
              ListTile(
                leading: Icon(
                  _columnTypes.where((t) => t.type == column.type).firstOrNull?.icon ?? Icons.view_column_outlined,
                  color: DfColors.primary,
                  size: 20,
                ),
                title: Text(column.title),
                subtitle: Text(column.type),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (column.type == 'status' || column.type == 'dropdown' || column.type == 'tags')
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      tooltip: 'Edit choices',
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final settings = await editColumnSettings(context, column);
                        if (settings == null || !context.mounted) return;
                        await _guard(
                          context,
                          () => controller.updateColumnSettings(column.id, settings),
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Rename',
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      final title = await promptForText(
                        context,
                        title: 'Rename column',
                        initial: column.title,
                      );
                      if (title == null || title.isEmpty || !context.mounted) return;
                      await _guard(context, () => controller.renameColumn(column.id, title));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: DfColors.danger),
                    tooltip: 'Delete column',
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      final confirmed = await _confirm(
                        context,
                        title: 'Delete "${column.title}"?',
                        message: 'Its values are removed from every item on this board.',
                        destructive: true,
                      );
                      if (!confirmed || !context.mounted) return;
                      await _guard(context, () => controller.deleteColumn(column.id));
                    },
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Runs [action], surfacing an API failure as a toast instead of a red screen.
Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (e) {
    if (context.mounted) {
      showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
}

class _BoardBody extends StatelessWidget {
  const _BoardBody({required this.board, required this.controller, required this.filter});

  final BoardDetail board;
  final BoardController controller;
  final BoardFilter filter;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (board.description != null && board.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xs, DfSpacing.md, DfSpacing.sm),
            child: Text(board.description!, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (board.members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.md),
            child: Row(children: [
              for (final member in board.members.take(6))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: DfAvatar(
                    name: member.fullName,
                    seed: member.userId,
                    imageUrl: member.avatarUrl,
                    size: 28,
                  ),
                ),
              if (board.members.length > 6)
                Text('+${board.members.length - 6}', style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        for (final group in board.groups)
          _GroupSection(board: board, group: group, controller: controller, filter: filter),
        Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: DfButton(
            label: 'Add group',
            variant: DfButtonVariant.tonal,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: () async {
              final title = await promptForText(context, title: 'New group', hint: 'Group name');
              if (title == null || title.isEmpty || !context.mounted) return;
              await _guard(context, () => controller.addGroup(title));
            },
          ),
        ),
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.board,
    required this.group,
    required this.controller,
    required this.filter,
  });

  final BoardDetail board;
  final BoardGroup group;
  final BoardController controller;
  final BoardFilter filter;

  @override
  Widget build(BuildContext context) {
    final color = DfColors.token(group.color);
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final done = group.doneCount(board.columns);

    // Quick Find / quick filters narrow what each group shows. A group whose
    // items are all filtered away collapses to nothing while a filter is on.
    final visibleItems =
        filter.isActive ? group.items.where((i) => filter.matches(i, board.columns)).toList() : group.items;
    if (filter.isActive && visibleItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Group header.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm),
          child: Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: AnimatedRotation(
                turns: group.collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(Icons.expand_more_rounded, color: color, size: 22),
              ),
              tooltip: group.collapsed ? 'Expand' : 'Collapse',
              onPressed: () => controller.toggleCollapsed(group.id),
            ),
            Flexible(
              child: GestureDetector(
                onTap: () async {
                  final title = await promptForText(context, title: 'Rename group', initial: group.title);
                  if (title == null || title.isEmpty || !context.mounted) return;
                  await _guard(context, () => controller.renameGroup(group.id, title));
                },
                child: Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: color),
                ),
              ),
            ),
            const SizedBox(width: DfSpacing.xs),
            Text(
              group.items.isEmpty ? '0' : '$done/${group.items.length}',
              style: text.labelSmall,
            ),
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
              onSelected: (action) async {
                switch (action) {
                  case 'rename':
                    final title = await promptForText(context, title: 'Rename group', initial: group.title);
                    if (title == null || title.isEmpty || !context.mounted) return;
                    await _guard(context, () => controller.renameGroup(group.id, title));
                  case 'color':
                    final picked = await _pickColor(context, group.color);
                    if (picked == null || !context.mounted) return;
                    await _guard(context, () => controller.recolorGroup(group.id, picked));
                  case 'delete':
                    final confirmed = await _confirm(
                      context,
                      title: 'Delete "${group.title}"?',
                      message: group.items.isEmpty
                          ? 'The group will be removed.'
                          : 'This deletes the group and its ${group.items.length} item(s).',
                      destructive: true,
                    );
                    if (!confirmed || !context.mounted) return;
                    await _guard(context, () => controller.deleteGroup(group.id));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'color', child: Text('Change color')),
                PopupMenuItem(value: 'delete', child: Text('Delete group')),
              ],
            ),
          ]),
        ),
        // AnimatedSize makes collapse/expand sweep instead of snap, with the
        // Vibe enter curve.
        AnimatedSize(
          duration: DfMotion.expressiveShort,
          curve: DfMotion.enter,
          alignment: Alignment.topCenter,
          child: group.collapsed
              ? const SizedBox(width: double.infinity)
              : Container(
            margin: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
            decoration: BoxDecoration(
              color: isDark ? DfColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(DfRadius.md),
              border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
            ),
            child: Column(children: [
              // Nested inside the page's ListView, so it must not scroll itself;
              // default drag handles are off in favour of an explicit grip.
              // Reordering is disabled while a filter narrows the list — the
              // visible indices would not match the server's order.
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: visibleItems.length,
                onReorderItem: filter.isActive
                    ? (oldIndex, newIndex) {}
                    : (oldIndex, newIndex) => _reorder(context, group, oldIndex, newIndex),
                itemBuilder: (context, i) => _ItemRow(
                  key: ValueKey(visibleItems[i].id),
                  board: board,
                  group: group,
                  item: visibleItems[i],
                  accent: color,
                  controller: controller,
                  dragIndex: i,
                ),
              ),
              if (group.items.isNotEmpty) const Divider(height: 1),
              _AddItemRow(groupId: group.id, controller: controller),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Translates a list reorder into the API's "place after this item" model.
  ///
  /// `onReorderItem` already gives `newIndex` as the destination in the list
  /// with the dragged row removed, so no off-by-one adjustment is needed.
  Future<void> _reorder(BuildContext context, BoardGroup group, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final remaining = [...group.items]..removeAt(oldIndex);
    final moved = group.items[oldIndex];
    final afterItemId = newIndex == 0 ? null : remaining[newIndex - 1].id;

    await _guard(
      context,
      () => controller.moveItem(itemId: moved.id, groupId: group.id, afterItemId: afterItemId),
    );
  }

  Future<String?> _pickColor(BuildContext context, String current) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Group color', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: DfSpacing.md),
            Wrap(
              spacing: DfSpacing.sm,
              runSpacing: DfSpacing.sm,
              children: [
                for (final token in _groupColors)
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
          ]),
        ),
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    super.key,
    required this.board,
    required this.group,
    required this.item,
    required this.accent,
    required this.controller,
    required this.dragIndex,
  });

  final BoardDetail board;
  final BoardGroup group;
  final BoardItem item;
  final Color accent;
  final BoardController controller;

  /// Position in the reorderable list, needed by the drag handle.
  final int dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isPending = item.id == '__pending__';

    return Opacity(
      opacity: isPending ? 0.5 : 1,
      child: Column(children: [
        if (dragIndex > 0) const Divider(height: 1),
        InkWell(
          onTap: isPending ? null : () => context.push('/items/${item.id}'),
          onLongPress: isPending ? null : () => _showItemMenu(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.sm),
            child: Row(children: [
              _accentBar(),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                  const SizedBox(height: DfSpacing.xxs),
                  // Every column gets a tappable cell; unset ones show a subtle "+".
                  Wrap(spacing: DfSpacing.xxs, runSpacing: DfSpacing.xxs, children: [
                    for (final column in board.columns)
                      _Cell(
                        column: column,
                        item: item,
                        members: board.members,
                        enabled: !isPending,
                        onEdit: () => _editCell(context, ref, column),
                      ),
                  ]),
                ]),
              ),
              if (item.updatesCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: DfSpacing.xs),
                  child: Row(children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: DfColors.textTertiary),
                    const SizedBox(width: 2),
                    Text('${item.updatesCount}', style: text.labelSmall),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// The group-coloured bar doubles as the drag grip, so the rest of the row
  /// keeps its tap and long-press gestures.
  Widget _accentBar() {
    final bar = Container(
      width: 3,
      height: 36,
      margin: const EdgeInsets.only(right: DfSpacing.xs),
      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
    );
    if (item.id == '__pending__') return bar;
    return ReorderableDragStartListener(index: dragIndex, child: bar);
  }

  Future<void> _editCell(BuildContext context, WidgetRef ref, BoardColumn column) async {
    // Assignment is account-scoped, so the picker offers account members rather
    // than only those explicitly added to this board.
    final assignable = await ref.read(assignableMembersProvider.future).catchError(
          (Object _) => board.members,
        );
    if (!context.mounted) return;

    final result = await editCell(
      context: context,
      column: column,
      item: item,
      members: assignable,
    );
    if (!result.changed || !context.mounted) return;
    await _guard(
      context,
      () => controller.setCell(itemId: item.id, columnId: column.id, value: result.value),
    );
  }

  void _showItemMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text('Open item'),
            onTap: () {
              Navigator.pop(sheetContext);
              context.push('/items/${item.id}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await promptForText(context, title: 'Rename item', initial: item.name);
              if (name == null || name.isEmpty || !context.mounted) return;
              await _guard(context, () => controller.renameItem(item.id, name));
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Duplicate'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _guard(context, () => controller.duplicateItem(item.id));
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Move to group'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final target = await _pickGroup(context, board, exclude: group.id);
              if (target == null || !context.mounted) return;
              await _guard(
                context,
                () => controller.moveItem(itemId: item.id, groupId: target),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: DfColors.danger),
            title: const Text('Delete', style: TextStyle(color: DfColors.danger)),
            onTap: () async {
              Navigator.pop(sheetContext);
              final confirmed = await _confirm(
                context,
                title: 'Delete "${item.name}"?',
                message: 'The item will be removed from this board.',
                destructive: true,
              );
              if (!confirmed || !context.mounted) return;
              await _guard(context, () => controller.archiveItem(item.id));
            },
          ),
        ]),
      ),
    );
  }
}

Future<String?> _pickGroup(BuildContext context, BoardDetail board, {String? exclude}) {
  final options = board.groups.where((g) => g.id != exclude).toList();
  if (options.isEmpty) {
    showDfToast(context, 'There is no other group to move to', icon: Icons.info_outline_rounded);
    return Future.value(null);
  }
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text('Move to', style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final group in options)
            ListTile(
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: DfColors.token(group.color),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Text(group.title),
              onTap: () => Navigator.pop(sheetContext, group.id),
            ),
        ],
      ),
    ),
  );
}

/// One cell: shows the value chip, or a placeholder that opens the editor.
///
/// Status chips replay a small celebration when their label changes — a pop
/// with the Vibe emphasize curve, plus a shimmer sweep when the new label
/// counts as done (echoing Vibe's LabelCelebrationAnimation).
class _Cell extends StatelessWidget {
  const _Cell({
    required this.column,
    required this.item,
    required this.members,
    required this.enabled,
    required this.onEdit,
  });

  final BoardColumn column;
  final BoardItem item;
  final List<BoardMember> members;
  final bool enabled;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    var chip = cellChip(context, column, item, members);

    if (chip != null && column.type == 'status') {
      final cell = item.values[column.id];
      final labelId = cell is Map<String, dynamic> ? cell['labelId'] as String? : null;
      final isDone = column.statusLabels.any((l) => l.id == labelId && l.isDone);
      chip = Animate(
        // Re-keying restarts the effects each time the label changes.
        key: ValueKey('${column.id}:$labelId'),
        effects: [
          ScaleEffect(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: DfMotion.expressiveShort,
            curve: DfMotion.emphasize,
          ),
          if (isDone)
            ShimmerEffect(
              delay: DfMotion.productiveMedium,
              duration: DfMotion.expressiveLong,
              color: Colors.white.withValues(alpha: 0.6),
            ),
        ],
        child: chip,
      );
    }

    return InkWell(
      onTap: enabled ? onEdit : null,
      borderRadius: BorderRadius.circular(6),
      child: chip ??
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? DfColors.borderDark
                    : DfColors.border,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, size: 12, color: DfColors.textTertiary),
              const SizedBox(width: 2),
              Text(column.title, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
    );
  }
}

/// Inline "+ Add item" row at the bottom of each group.
class _AddItemRow extends StatefulWidget {
  const _AddItemRow({required this.groupId, required this.controller});

  final String groupId;
  final BoardController controller;

  @override
  State<_AddItemRow> createState() => _AddItemRowState();
}

class _AddItemRowState extends State<_AddItemRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool keepOpen}) async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    _controller.clear();
    await _guard(context, () => widget.controller.addItem(groupId: widget.groupId, name: name));
    if (!mounted) return;
    if (keepOpen) {
      _focus.requestFocus();
    } else {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return InkWell(
        onTap: () {
          setState(() => _editing = true);
          _focus.requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
          child: Row(children: [
            const Icon(Icons.add_rounded, size: 18, color: DfColors.textTertiary),
            const SizedBox(width: DfSpacing.xs),
            Text('Add item', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xxs),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              hintText: 'Item name',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
            ),
            // Enter keeps the row open so several items can be typed in a row.
            onSubmitted: (_) => _submit(keepOpen: true),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.check_rounded, color: DfColors.success),
          tooltip: 'Add',
          onPressed: () => _submit(keepOpen: false),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: DfColors.textTertiary),
          tooltip: 'Cancel',
          onPressed: () {
            _controller.clear();
            setState(() => _editing = false);
          },
        ),
      ]),
    );
  }
}

class _BoardError extends StatelessWidget {
  const _BoardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
          const SizedBox(height: DfSpacing.sm),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: DfSpacing.md),
          DfButton(label: 'Try again', variant: DfButtonVariant.tonal, expand: false, onPressed: onRetry),
        ]),
      ),
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title, style: Theme.of(dialogContext).textTheme.titleMedium),
      content: Text(message, style: Theme.of(dialogContext).textTheme.bodyMedium),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            destructive ? 'Delete' : 'Confirm',
            style: TextStyle(color: destructive ? DfColors.danger : DfColors.primary),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
