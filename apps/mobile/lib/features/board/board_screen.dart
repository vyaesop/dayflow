import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/realtime/realtime_client.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../home/home_providers.dart';
import '../item/item_repository.dart';
import '../members/members_providers.dart';
import 'batch_bar.dart';
import 'board_actions.dart';
import 'board_controller.dart';
import 'board_filters.dart';
import 'board_members_sheet.dart';
import 'cell_editors.dart';
import 'columns_sheet.dart';
import 'conditional_colors_sheet.dart';
import 'create_board_screen.dart' show boardTypeOptions;
import 'filter_builder_sheet.dart';
import 'sort_sheet.dart';
import 'subitem_rows.dart';
import 'summary_footer.dart';
import 'view_engine.dart';
import 'view_sheets.dart';

const _groupColors = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];

/// Placeholder id of a row whose create request is still in flight.
const pendingItemId = '__pending__';

// ------------------------------------------------------------------ actions

/// The board mutations the table body needs. `BoardController` satisfies it
/// through [ControllerTableActions]; tests pass a fake.
abstract class BoardTableActions {
  Future<void> addItem({required String groupId, required String name});
  Future<BoardItem?> addSubitem({required String parentItemId, required String name});
  Future<void> renameItem(String itemId, String name);
  Future<void> duplicateItem(String itemId);
  Future<void> archiveItem(String itemId);
  Future<void> trashItem(String itemId);
  Future<void> moveItem({required String itemId, required String groupId, String? afterItemId});
  Future<void> setCell({required String itemId, required String columnId, required Map<String, dynamic>? value});
  Future<void> addGroup(String title);
  Future<void> renameGroup(String groupId, String title);
  Future<void> recolorGroup(String groupId, String color);
  Future<void> deleteGroup(String groupId);
  Future<void> toggleCollapsed(String groupId);
  Future<void> refresh();
}

class ControllerTableActions implements BoardTableActions {
  const ControllerTableActions(this.controller);

  final BoardController controller;

  @override
  Future<void> addItem({required String groupId, required String name}) =>
      controller.addItem(groupId: groupId, name: name);
  @override
  Future<BoardItem?> addSubitem({required String parentItemId, required String name}) =>
      controller.addSubitem(parentItemId: parentItemId, name: name);
  @override
  Future<void> renameItem(String itemId, String name) => controller.renameItem(itemId, name);
  @override
  Future<void> duplicateItem(String itemId) => controller.duplicateItem(itemId);
  @override
  Future<void> archiveItem(String itemId) => controller.archiveItem(itemId);
  @override
  Future<void> trashItem(String itemId) => controller.trashItem(itemId);
  @override
  Future<void> moveItem({required String itemId, required String groupId, String? afterItemId}) =>
      controller.moveItem(itemId: itemId, groupId: groupId, afterItemId: afterItemId);
  @override
  Future<void> setCell({required String itemId, required String columnId, required Map<String, dynamic>? value}) =>
      controller.setCell(itemId: itemId, columnId: columnId, value: value);
  @override
  Future<void> addGroup(String title) => controller.addGroup(title);
  @override
  Future<void> renameGroup(String groupId, String title) => controller.renameGroup(groupId, title);
  @override
  Future<void> recolorGroup(String groupId, String color) => controller.recolorGroup(groupId, color);
  @override
  Future<void> deleteGroup(String groupId) => controller.deleteGroup(groupId);
  @override
  Future<void> toggleCollapsed(String groupId) => controller.toggleCollapsed(groupId);
  @override
  Future<void> refresh() => controller.refresh();
}

/// Ids of the top-level items the table currently shows (saved view + quick
/// filters applied), in display order. Used by "Select all".
List<String> visibleItemIds(BoardDetail board, ViewConfig config, BoardFilter quickFilter, {String? meUserId}) {
  final groups = applyView(
    board,
    config,
    ViewContext.forBoard(board, meUserId: meUserId),
    extraFilter: quickFilter.isActive ? (item) => quickFilter.matches(item, board.columns) : null,
  );
  return [
    for (final g in groups)
      for (final i in g.items)
        if (i.id != pendingItemId) i.id,
  ];
}

// ------------------------------------------------------------------- screen

/// Editable board: groups, items, and typed cells, shown through a saved view.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  final _quickFind = TextEditingController();
  bool _showQuickFind = false;

  /// Non-null while rows are being selected for a batch action.
  Set<String>? _selected;
  bool _batchBusy = false;

  String get boardId => widget.boardId;

  @override
  void dispose() {
    _quickFind.dispose();
    super.dispose();
  }

  ViewConfig _config(BoardDetail board) {
    final working = ref.read(workingViewConfigProvider(boardId));
    if (working != null) return working;
    final view = resolveActiveView(board, ref.read(activeViewIdProvider(boardId)));
    return view == null ? const ViewConfig.empty() : ViewConfig.fromJson(view.config);
  }

  void _setWorking(ViewConfig config) => ref.read(workingViewConfigProvider(boardId).notifier).state = config;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardControllerProvider(boardId));
    final controller = ref.read(boardControllerProvider(boardId).notifier);
    final filter = ref.watch(boardFilterProvider(boardId));
    final activeViewId = ref.watch(activeViewIdProvider(boardId));
    final working = ref.watch(workingViewConfigProvider(boardId));
    final auth = ref.watch(authControllerProvider);
    final meUserId = auth is SignedIn ? auth.me.id : null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selecting = _selected != null;

    final board = state.value;
    final view = board == null ? null : resolveActiveView(board, activeViewId);
    final stored = view == null ? const ViewConfig.empty() : ViewConfig.fromJson(view.config);
    final config = working ?? stored;
    final dirty = working != null && !viewConfigsEqual(working, stored);
    final ruleCount = config.filters?.rules.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cancel selection',
                onPressed: () => setState(() => _selected = null),
              )
            : BackButton(onPressed: () => context.pop()),
        centerTitle: false,
        titleSpacing: 0,
        title: selecting
            ? Text('${_selected!.length} selected')
            : state.maybeWhen(
                data: (board) => GestureDetector(
                  onTap: board.canEdit ? () => _renameBoard(context, controller, board) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        if (board.type != 'main') ...[
                          Icon(
                            board.type == 'private' ? Icons.lock_outline_rounded : Icons.link_rounded,
                            size: 11,
                            color: DfColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            '${view?.name ?? board.workspaceName} · ${board.itemCount} items',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                orElse: () => const Text('Board'),
              ),
        actions: [
          if (selecting && board != null)
            TextButton(
              onPressed: () => setState(
                () => _selected = visibleItemIds(board, config, filter, meUserId: meUserId).toSet(),
              ),
              child: const Text('Select all'),
            )
          else
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
                IconButton(
                  icon: Icon(viewTypeIcon(view?.type ?? 'table')),
                  tooltip: 'Views',
                  onPressed: () => showViewSwitcherSheet(
                    context,
                    ref,
                    board: board,
                    activeViewId: activeViewId,
                    currentConfig: config,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) => _onBoardAction(context, action, board, controller, view, config),
                  itemBuilder: (context) => _boardMenuItems(board),
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
          // Degraded-link notice: the board still converges via polling, but
          // people should know edits from others arrive on a delay.
          ValueListenableBuilder(
            valueListenable: ref.watch(realtimeStatusProvider),
            builder: (context, status, _) => status == RealtimeStatus.offline
                ? Container(
                    width: double.infinity,
                    color: DfColors.accentAmber.withValues(alpha: 0.15),
                    padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xxs),
                    child: Row(children: [
                      const Icon(Icons.sync_rounded, size: 14, color: DfColors.textSecondary),
                      const SizedBox(width: DfSpacing.xxs),
                      Expanded(
                        child: Text(
                          'Live sync unavailable — refreshing every ${BoardController.pollInterval.inSeconds}s',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ]),
                  )
                : const SizedBox.shrink(),
          ),
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
                          ref.read(boardFilterProvider(boardId).notifier).state = filter.copyWith(query: '');
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
                  final members = await _assignable(board);
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
              // Saved-view filters, with a rule-count badge.
              IconButton(
                icon: Badge(
                  isLabelVisible: ruleCount > 0,
                  label: Text('$ruleCount'),
                  child: Icon(
                    Icons.filter_list_rounded,
                    color: ruleCount > 0 ? DfColors.primary : DfColors.textSecondary,
                  ),
                ),
                tooltip: 'Filters',
                onPressed: () => _editFilters(context, board, config),
              ),
            ]),
          ),
          if (config.hasSort || dirty)
            Padding(
              padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.xxs),
              child: Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xxs, children: [
                if (config.hasSort)
                  _Pill(
                    icon: Icons.swap_vert_rounded,
                    label: 'Sorted',
                    onTap: () => _editSort(context, board, config),
                  ),
                if (dirty)
                  _UnsavedPill(
                    canSave: board.canEdit && view != null,
                    onSave: () => _guard(context, () async {
                      await controller.updateViewConfig(view!.id, config.toJson());
                      ref.read(workingViewConfigProvider(boardId).notifier).state = null;
                      if (context.mounted) showDfToast(context, 'View saved');
                    }),
                    onDiscard: () => ref.read(workingViewConfigProvider(boardId).notifier).state = null,
                  ),
              ]),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: BoardTableBody(
                board: board,
                actions: ControllerTableActions(controller),
                config: config,
                quickFilter: filter,
                meUserId: meUserId,
                selectedIds: _selected,
                onToggleSelected: (id) => setState(() {
                  final next = {..._selected ?? const <String>{}};
                  if (!next.remove(id)) next.add(id);
                  _selected = next;
                }),
              ),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: selecting && board != null
          ? BatchBar(
              count: _selected!.length,
              busy: _batchBusy,
              onSetStatus: board.itemColumns.any((c) => c.type == 'status')
                  ? () => _batchSetStatus(context, board, controller)
                  : null,
              onAssign: board.itemColumns.any((c) => c.type == 'people')
                  ? () => _batchAssign(context, board, controller)
                  : null,
              onMoveToGroup: () => _batchMove(context, board, controller),
              onDuplicate: () => _runBatch(context, controller, action: 'duplicate'),
              onArchive: () async {
                final confirmed = await _confirm(
                  context,
                  title: 'Archive ${_selected!.length} item(s)?',
                  message: 'They disappear from the board and can be restored from Archived items.',
                  confirmLabel: 'Archive',
                );
                if (confirmed && context.mounted) await _runBatch(context, controller, action: 'archive');
              },
              onDelete: () async {
                final confirmed = await _confirm(
                  context,
                  title: 'Delete ${_selected!.length} item(s)?',
                  message: 'They move to the trash and are deleted for good after 30 days.',
                  destructive: true,
                );
                if (confirmed && context.mounted) await _runBatch(context, controller, action: 'trash');
              },
            )
          : null,
    );
  }

  Future<List<BoardMember>> _assignable(BoardDetail board) =>
      ref.read(assignableMembersProvider.future).catchError((Object _) => board.members);

  // -------------------------------------------------------------- board menu

  List<PopupMenuEntry<String>> _boardMenuItems(BoardDetail board) => [
        if (board.canEdit) ...[
          const PopupMenuItem(value: 'group', child: Text('Add group')),
          const PopupMenuItem(value: 'column', child: Text('Add column')),
        ],
        const PopupMenuItem(value: 'columns', child: Text('Columns')),
        const PopupMenuItem(value: 'views', child: Text('Views')),
        const PopupMenuItem(value: 'sort', child: Text('Sort')),
        const PopupMenuItem(value: 'filters', child: Text('Filters')),
        const PopupMenuItem(value: 'colors', child: Text('Conditional colors')),
        if (board.canEdit) const PopupMenuItem(value: 'select', child: Text('Select items')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'members', child: Text('Board members')),
        const PopupMenuItem(value: 'discussion', child: Text('Board discussion')),
        const PopupMenuItem(value: 'activity', child: Text('Activity log')),
        const PopupMenuItem(value: 'archived', child: Text('Archived items')),
        const PopupMenuDivider(),
        if (board.canEdit) const PopupMenuItem(value: 'rename', child: Text('Rename board')),
        if (board.canManage) const PopupMenuItem(value: 'type', child: Text('Change board type')),
        if (board.canEdit) ...[
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate board')),
          const PopupMenuItem(value: 'template', child: Text('Save as template')),
        ],
        const PopupMenuItem(value: 'info', child: Text('Board info')),
        const PopupMenuItem(value: 'export', child: Text('Export to CSV')),
        if (board.canEdit) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'archive', child: Text('Archive board')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete board', style: TextStyle(color: DfColors.danger)),
          ),
        ],
      ];

  Future<void> _onBoardAction(
    BuildContext context,
    String action,
    BoardDetail board,
    BoardController controller,
    BoardView? view,
    ViewConfig config,
  ) async {
    switch (action) {
      case 'group':
        await _addGroup(context, controller);
      case 'column':
        final picked = await showAddColumnSheet(context);
        if (picked == null || !context.mounted) return;
        await _guard(context, () => controller.addColumn(type: picked.type, title: picked.title));
      case 'columns':
        await showColumnsSheet(context, boardId: boardId, config: config, onConfigChanged: _setWorking);
      case 'views':
        await showViewSwitcherSheet(
          context,
          ref,
          board: board,
          activeViewId: ref.read(activeViewIdProvider(boardId)),
          currentConfig: config,
        );
      case 'sort':
        await _editSort(context, board, config);
      case 'filters':
        await _editFilters(context, board, config);
      case 'colors':
        final members = await _assignable(board);
        if (!context.mounted) return;
        final rules = await showConditionalColorsSheet(
          context,
          board: board,
          members: members,
          initial: config.conditionalColors,
        );
        if (rules == null) return;
        _setWorking(_config(board).copyWith(conditionalColors: rules));
      case 'select':
        setState(() => _selected = {});
      case 'members':
        await showBoardMembersSheet(context, ref, boardId: boardId);
      case 'discussion':
        await context.push('/boards/$boardId/discussion');
      case 'activity':
        await context.push('/boards/$boardId/activity');
      case 'archived':
        await context.push('/archive?boardId=$boardId');
      case 'rename':
        await _renameBoard(context, controller, board);
      case 'type':
        await _changeBoardType(context, board);
      case 'duplicate':
        await showDuplicateBoardSheet(context, ref, board);
      case 'template':
        await showSaveAsTemplateSheet(context, ref, board);
      case 'info':
        await _showBoardInfo(context, board);
      case 'export':
        await _exportCsv(context, board, view);
      case 'archive':
        await _archiveBoard(context, board);
      case 'delete':
        await _deleteBoard(context, board);
    }
  }

  Future<void> _editFilters(BuildContext context, BoardDetail board, ViewConfig config) async {
    final members = await _assignable(board);
    if (!context.mounted) return;
    final group = await showFilterBuilderSheet(context, board: board, members: members, initial: config.filters);
    if (group == null) return;
    _setWorking(_config(board).copyWith(filters: () => group.isEmpty ? null : group));
  }

  Future<void> _editSort(BuildContext context, BoardDetail board, ViewConfig config) async {
    final rules = await showSortSheet(context, board: board, initial: config.sort);
    if (rules == null) return;
    _setWorking(_config(board).copyWith(sort: rules));
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
              '${board.groups.length} groups · ${board.itemCount} items · ${board.itemColumns.length} columns'
              '${board.subitemColumns.isEmpty ? '' : ' · ${board.subitemColumns.length} subitem columns'}'
              ' · ${board.views.length} view${board.views.length == 1 ? '' : 's'}',
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

  Future<void> _exportCsv(BuildContext context, BoardDetail board, BoardView? view) async {
    await _guard(context, () async {
      final csv = await ref.read(boardRepositoryProvider).exportCsv(board.id, viewId: view?.id);
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
      message: 'The board disappears from lists. Its data is kept and it can be restored any time.',
      confirmLabel: 'Archive',
    );
    if (!confirmed || !context.mounted) return;
    await _guard(context, () async {
      await ref.read(boardRepositoryProvider).archiveBoard(board.id);
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
      if (context.mounted) context.pop();
    });
  }

  Future<void> _deleteBoard(BuildContext context, BoardDetail board) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete "${board.name}"?',
      message: 'The board and its ${board.itemCount} items move to the trash and are deleted for good after 30 days.',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _guard(context, () async {
      await ref.read(boardRepositoryProvider).trashBoard(board.id);
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
      if (context.mounted) context.pop();
    });
  }

  Future<void> _renameBoard(BuildContext context, BoardController controller, BoardDetail board) async {
    final name = await promptForText(context, title: 'Rename board', initial: board.name);
    if (name == null || name.isEmpty || name == board.name || !context.mounted) return;
    await _guard(context, () => controller.renameBoard(name));
  }

  Future<void> _changeBoardType(BuildContext context, BoardDetail board) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text('Board type', style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final option in boardTypeOptions)
            ListTile(
              leading: Icon(option.icon, size: 20, color: DfColors.primary),
              title: Text(option.label),
              subtitle: Text(option.description),
              trailing: board.type == option.key ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
              onTap: () => Navigator.pop(sheetContext, option.key),
            ),
        ]),
      ),
    );
    if (picked == null || picked == board.type || !context.mounted) return;

    await _guard(context, () async {
      await ref.read(boardRepositoryProvider).setBoardType(board.id, picked);
      await ref.read(boardControllerProvider(board.id).notifier).refresh();
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
      if (context.mounted) {
        showDfToast(
          context,
          picked == 'main'
              ? 'Board is now visible to everyone in the account'
              : 'Board is now ${picked == 'private' ? 'private' : 'shareable'} — members only',
        );
      }
    });
  }

  Future<void> _addGroup(BuildContext context, BoardController controller) async {
    final title = await promptForText(context, title: 'New group', hint: 'Group name');
    if (title == null || title.isEmpty || !context.mounted) return;
    await _guard(context, () => controller.addGroup(title));
  }

  // ------------------------------------------------------------------- batch

  Future<void> _batchSetStatus(BuildContext context, BoardDetail board, BoardController controller) async {
    final column = await pickColumn(
      context,
      board.itemColumns.where((c) => c.type == 'status').toList(),
      title: 'Which status column?',
    );
    if (column == null || !context.mounted) return;
    final labelId = await showStatusLabelPicker(context, column);
    if (labelId == null || !context.mounted) return;
    await _runBatch(context, controller, action: 'set_cell', columnId: column.id, value: {'labelId': labelId});
  }

  Future<void> _batchAssign(BuildContext context, BoardDetail board, BoardController controller) async {
    final column = board.itemColumns.where((c) => c.type == 'people').firstOrNull;
    if (column == null) return;
    final members = await _assignable(board);
    if (!context.mounted) return;
    final picked = await showPeoplePicker(context, members: members, title: column.title);
    if (picked == null || !context.mounted) return;
    await _runBatch(
      context,
      controller,
      action: 'set_cell',
      columnId: column.id,
      value: picked.isEmpty ? null : {'userIds': picked},
    );
  }

  Future<void> _batchMove(BuildContext context, BoardDetail board, BoardController controller) async {
    final target = await _pickGroup(context, board);
    if (target == null || !context.mounted) return;
    await _runBatch(context, controller, action: 'move', groupId: target);
  }

  Future<void> _runBatch(
    BuildContext context,
    BoardController controller, {
    required String action,
    String? groupId,
    String? columnId,
    Map<String, dynamic>? value,
  }) async {
    final ids = _selected?.toList() ?? const [];
    if (ids.isEmpty) return;
    setState(() => _batchBusy = true);
    await _guard(context, () async {
      final affected = await controller.batch(
        itemIds: ids,
        action: action,
        groupId: groupId,
        columnId: columnId,
        value: value,
      );
      if (context.mounted) showDfToast(context, '$affected item${affected == 1 ? '' : 's'} updated');
    });
    if (mounted) {
      setState(() {
        _batchBusy = false;
        _selected = null;
      });
    }
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DfRadius.pill),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
        decoration: BoxDecoration(
          color: isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle,
          borderRadius: BorderRadius.circular(DfRadius.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: DfColors.primary), const SizedBox(width: 4)],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: DfColors.primary)),
        ]),
      ),
    );
  }
}

class _UnsavedPill extends StatelessWidget {
  const _UnsavedPill({required this.canSave, required this.onSave, required this.onDiscard});

  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelSmall;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: DfSpacing.xs),
      decoration: BoxDecoration(
        color: DfColors.accentAmber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(DfRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Unsaved changes', style: text),
        const SizedBox(width: DfSpacing.xxs),
        if (canSave)
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onSave,
            child: Text('Save to view', style: text?.copyWith(color: DfColors.primary)),
          ),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onDiscard,
          child: Text('Discard', style: text),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- table body

/// The table itself: groups → rows → chips, with a saved view applied. Pure
/// of Riverpod state beyond what rows read lazily when editing, so tests can
/// pump it with a fixture board and a fake [BoardTableActions].
class BoardTableBody extends StatefulWidget {
  const BoardTableBody({
    super.key,
    required this.board,
    required this.actions,
    required this.config,
    required this.quickFilter,
    this.meUserId,
    this.selectedIds,
    this.onToggleSelected,
    this.now,
  });

  final BoardDetail board;
  final BoardTableActions actions;
  final ViewConfig config;
  final BoardFilter quickFilter;
  final String? meUserId;

  /// Non-null while in selection mode.
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggleSelected;

  /// Injected clock for date filters in tests.
  final DateTime? now;

  @override
  State<BoardTableBody> createState() => _BoardTableBodyState();
}

class _BoardTableBodyState extends State<BoardTableBody> {
  final _expanded = <String>{};

  void _toggleExpanded(String itemId) => setState(() {
        if (!_expanded.remove(itemId)) _expanded.add(itemId);
      });

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final config = widget.config;
    final quick = widget.quickFilter;
    final ctx = ViewContext.forBoard(board, meUserId: widget.meUserId, now: widget.now);
    final groups = applyView(
      board,
      config,
      ctx,
      extraFilter: quick.isActive ? (item) => quick.matches(item, board.columns) : null,
    );
    final columns = visibleColumns(board.itemColumns, config);
    final autoNumbers = autoNumberIndex(board);
    final filtersActive = config.hasFilters || quick.isActive;
    final canReorder = !filtersActive && !config.hasSort && board.canEdit && widget.selectedIds == null;
    final originals = {for (final g in board.groups) g.id: g};

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
        for (final group in groups)
          if (!(filtersActive && group.items.isEmpty))
            _GroupSection(
              board: board,
              group: originals[group.id] ?? group,
              visibleItems: group.items,
              columns: columns,
              config: config,
              ctx: ctx,
              autoNumbers: autoNumbers,
              actions: widget.actions,
              canReorder: canReorder,
              meUserId: widget.meUserId,
              expanded: _expanded,
              onToggleExpanded: _toggleExpanded,
              selectedIds: widget.selectedIds,
              onToggleSelected: widget.onToggleSelected,
            ),
        if (board.canEdit && widget.selectedIds == null)
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: DfButton(
              label: 'Add group',
              variant: DfButtonVariant.tonal,
              icon: const Icon(Icons.add_rounded, size: 20),
              onPressed: () async {
                final title = await promptForText(context, title: 'New group', hint: 'Group name');
                if (title == null || title.isEmpty || !context.mounted) return;
                await _guard(context, () => widget.actions.addGroup(title));
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
    required this.visibleItems,
    required this.columns,
    required this.config,
    required this.ctx,
    required this.autoNumbers,
    required this.actions,
    required this.canReorder,
    required this.meUserId,
    required this.expanded,
    required this.onToggleExpanded,
    required this.selectedIds,
    required this.onToggleSelected,
  });

  final BoardDetail board;

  /// The unfiltered group (for the header counter and reorder maths).
  final BoardGroup group;

  /// Items after the view's filters/sort and the quick filters.
  final List<BoardItem> visibleItems;
  final List<BoardColumn> columns;
  final ViewConfig config;
  final ViewContext ctx;
  final Map<String, int> autoNumbers;
  final BoardTableActions actions;
  final bool canReorder;
  final String? meUserId;
  final Set<String> expanded;
  final ValueChanged<String> onToggleExpanded;
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final color = DfColors.token(group.color);
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final done = group.doneCount(board.columns);
    final canEdit = board.canEdit;

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
              onPressed: () => actions.toggleCollapsed(group.id),
            ),
            Flexible(
              child: GestureDetector(
                onTap: canEdit
                    ? () async {
                        final title = await promptForText(context, title: 'Rename group', initial: group.title);
                        if (title == null || title.isEmpty || !context.mounted) return;
                        await _guard(context, () => actions.renameGroup(group.id, title));
                      }
                    : null,
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
              group.items.isEmpty
                  ? '0'
                  : visibleItems.length == group.items.length
                      ? '$done/${group.items.length}'
                      : '${visibleItems.length} of ${group.items.length}',
              style: text.labelSmall,
            ),
            const Spacer(),
            if (canEdit)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                onSelected: (action) async {
                  switch (action) {
                    case 'rename':
                      final title = await promptForText(context, title: 'Rename group', initial: group.title);
                      if (title == null || title.isEmpty || !context.mounted) return;
                      await _guard(context, () => actions.renameGroup(group.id, title));
                    case 'color':
                      final picked = await _pickColor(context, group.color);
                      if (picked == null || !context.mounted) return;
                      await _guard(context, () => actions.recolorGroup(group.id, picked));
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
                      await _guard(context, () => actions.deleteGroup(group.id));
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
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: isDark ? DfColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(DfRadius.md),
                    border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
                  ),
                  child: Column(children: [
                    // Nested inside the page's ListView, so it must not scroll itself;
                    // default drag handles are off in favour of an explicit grip.
                    // Reordering is disabled while a filter or sort changes the
                    // visible order — the indices would not match the server's.
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: visibleItems.length,
                      onReorderItem: canReorder
                          ? (oldIndex, newIndex) => _reorder(context, oldIndex, newIndex)
                          : (oldIndex, newIndex) {},
                      itemBuilder: (context, i) {
                        final item = visibleItems[i];
                        return _ItemRow(
                          key: ValueKey(item.id),
                          board: board,
                          group: group,
                          item: item,
                          columns: columns,
                          config: config,
                          ctx: ctx,
                          autoNumber: autoNumbers[item.id],
                          accent: color,
                          actions: actions,
                          dragIndex: i,
                          canDrag: canReorder,
                          meUserId: meUserId,
                          expanded: expanded.contains(item.id),
                          onToggleExpanded: () => onToggleExpanded(item.id),
                          selected: selectedIds?.contains(item.id),
                          onToggleSelected: onToggleSelected == null ? null : () => onToggleSelected!(item.id),
                        );
                      },
                    ),
                    if (visibleItems.isNotEmpty) SummaryFooter(columns: columns, items: visibleItems),
                    if (canEdit && selectedIds == null) ...[
                      if (group.items.isNotEmpty) const Divider(height: 1),
                      _AddItemRow(groupId: group.id, actions: actions),
                    ],
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
  /// Only reachable when the visible list equals the group's list.
  Future<void> _reorder(BuildContext context, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final remaining = [...visibleItems]..removeAt(oldIndex);
    final moved = visibleItems[oldIndex];
    final afterItemId = newIndex == 0 ? null : remaining[newIndex - 1].id;

    await _guard(
      context,
      () => actions.moveItem(itemId: moved.id, groupId: group.id, afterItemId: afterItemId),
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
                      child: token == current ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
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
    required this.columns,
    required this.config,
    required this.ctx,
    required this.autoNumber,
    required this.accent,
    required this.actions,
    required this.dragIndex,
    required this.canDrag,
    required this.meUserId,
    required this.expanded,
    required this.onToggleExpanded,
    required this.selected,
    required this.onToggleSelected,
  });

  final BoardDetail board;
  final BoardGroup group;
  final BoardItem item;
  final List<BoardColumn> columns;
  final ViewConfig config;
  final ViewContext ctx;
  final int? autoNumber;
  final Color accent;
  final BoardTableActions actions;

  /// Position in the reorderable list, needed by the drag handle.
  final int dragIndex;
  final bool canDrag;
  final String? meUserId;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Null when not in selection mode.
  final bool? selected;
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isPending = item.id == pendingItemId;
    final selecting = selected != null;
    final canEdit = board.canEdit && !isPending;
    final rowColor = rowColorFor(item, config, board.columns, ctx);
    final subitemCount = item.subitems.length;

    return Opacity(
      opacity: isPending ? 0.5 : 1,
      child: Column(children: [
        if (dragIndex > 0) const Divider(height: 1),
        Container(
          key: rowColor == null ? null : ValueKey('row-tint:${item.id}'),
          color: rowColor == null
              ? (selected == true ? DfColors.primary.withValues(alpha: 0.08) : null)
              : DfColors.token(rowColor).withValues(alpha: 0.12),
          child: InkWell(
            onTap: isPending
                ? null
                : selecting
                    ? onToggleSelected
                    : () => context.push('/items/${item.id}'),
            onLongPress: isPending || selecting || !board.canEdit ? null : () => _showItemMenu(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.sm),
              child: Row(children: [
                if (selecting)
                  Padding(
                    padding: const EdgeInsets.only(right: DfSpacing.xxs),
                    child: Checkbox(
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: isPending ? null : (_) => onToggleSelected?.call(),
                    ),
                  )
                else
                  _accentBar(),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                    const SizedBox(height: DfSpacing.xxs),
                    // Every visible column gets a tappable cell; unset ones show a subtle "+".
                    Wrap(spacing: DfSpacing.xxs, runSpacing: DfSpacing.xxs, children: [
                      if (subitemCount > 0)
                        SubitemToggleChip(
                          count: subitemCount,
                          done: item.subitemsDone(board.columns),
                          expanded: expanded,
                          onTap: onToggleExpanded,
                        ),
                      for (final column in columns)
                        DfCellChip(
                          column: column,
                          item: item,
                          members: board.members,
                          enabled: canEdit && !selecting,
                          autoNumber: autoNumber,
                          tint: cellColorFor(item, column, config, board.columns, ctx),
                          onEdit: () => _editCell(context, ref, column, item),
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
        ),
        if (expanded && !isPending)
          SubitemRows(
            parent: item,
            columns: board.subitemColumns,
            members: board.members,
            accent: accent,
            canEdit: board.canEdit && !selecting,
            onEditCell: (sub, column) => _editCell(context, ref, column, sub),
            onOpen: (sub) => context.push('/items/${sub.id}'),
            onMenu: (sub) => _showSubitemMenu(context, sub),
            onAdd: board.canEdit && !selecting ? () => _addSubitem(context) : null,
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
    if (!canDrag || item.id == pendingItemId) return bar;
    return ReorderableDragStartListener(index: dragIndex, child: bar);
  }

  Future<void> _editCell(BuildContext context, WidgetRef ref, BoardColumn column, BoardItem target) async {
    // Assignment is account-scoped, so the picker offers account members rather
    // than only those explicitly added to this board.
    final assignable = await ref.read(assignableMembersProvider.future).catchError((Object _) => board.members);
    if (!context.mounted) return;

    final result = await editCell(
      context: context,
      column: column,
      item: target,
      members: assignable,
      meUserId: meUserId,
      files: ref.read(itemRepositoryProvider),
    );
    if (!context.mounted) return;
    if (result.changed) {
      await _guard(
        context,
        () => actions.setCell(itemId: target.id, columnId: column.id, value: result.value),
      );
    }
    if (result.refresh && context.mounted) await _guard(context, actions.refresh);
  }

  Future<void> _addSubitem(BuildContext context) async {
    final name = await promptForText(context, title: 'New subitem', hint: 'Subitem name');
    if (name == null || name.isEmpty || !context.mounted) return;
    await _guard(context, () async {
      await actions.addSubitem(parentItemId: item.id, name: name);
    });
    if (!expanded) onToggleExpanded();
  }

  void _showItemMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ListView(shrinkWrap: true, children: [
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
            await _guard(context, () => actions.renameItem(item.id, name));
          },
        ),
        ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Duplicate'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _guard(context, () => actions.duplicateItem(item.id));
          },
        ),
        ListTile(
          leading: const Icon(Icons.subdirectory_arrow_right_rounded),
          title: const Text('Add subitem'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _addSubitem(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_move_outlined),
          title: const Text('Move to group'),
          onTap: () async {
            Navigator.pop(sheetContext);
            final target = await _pickGroup(context, board, exclude: group.id);
            if (target == null || !context.mounted) return;
            await _guard(context, () => actions.moveItem(itemId: item.id, groupId: target));
          },
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz_rounded),
          title: const Text('Move to board'),
          onTap: () async {
            Navigator.pop(sheetContext);
            final moved = await showMoveItemToBoardFlow(context, ref, item: item, board: board);
            if (moved && context.mounted) await _guard(context, actions.refresh);
          },
        ),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archive'),
          subtitle: const Text('Hidden from the board, restorable any time'),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _guard(context, () => actions.archiveItem(item.id));
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
              message: 'It moves to the trash and is deleted for good after 30 days.'
                  '${item.subitems.isEmpty ? '' : ' Its ${item.subitems.length} subitem(s) go with it.'}',
              destructive: true,
            );
            if (!confirmed || !context.mounted) return;
            await _guard(context, () => actions.trashItem(item.id));
          },
        ),
      ]),
    );
  }

  void _showSubitemMenu(BuildContext context, BoardItem sub) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(
              sub.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final name = await promptForText(context, title: 'Rename subitem', initial: sub.name);
              if (name == null || name.isEmpty || !context.mounted) return;
              await _guard(context, () => actions.renameItem(sub.id, name));
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Duplicate'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _guard(context, () => actions.duplicateItem(sub.id));
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archive'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _guard(context, () => actions.archiveItem(sub.id));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: DfColors.danger),
            title: const Text('Delete', style: TextStyle(color: DfColors.danger)),
            onTap: () async {
              Navigator.pop(sheetContext);
              final confirmed = await _confirm(
                context,
                title: 'Delete "${sub.name}"?',
                message: 'It moves to the trash and is deleted for good after 30 days.',
                destructive: true,
              );
              if (!confirmed || !context.mounted) return;
              await _guard(context, () => actions.trashItem(sub.id));
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

/// Inline "+ Add item" row at the bottom of each group.
class _AddItemRow extends StatefulWidget {
  const _AddItemRow({required this.groupId, required this.actions});

  final String groupId;
  final BoardTableActions actions;

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
    await _guard(context, () => widget.actions.addItem(groupId: widget.groupId, name: name));
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
  String? confirmLabel,
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
            confirmLabel ?? (destructive ? 'Delete' : 'Confirm'),
            style: TextStyle(color: destructive ? DfColors.danger : DfColors.primary),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
