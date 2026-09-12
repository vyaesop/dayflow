import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'board_controller.dart';
import 'view_engine.dart';

/// Kanban board: lanes are the labels of a status column (or the options of
/// a dropdown column). Dragging a card between lanes writes that value.
///
/// With a [viewId] the saved view's filters apply and its `laneColumnId`
/// picks the lane column; changing the column is written back to the view.
class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({super.key, required this.boardId, this.viewId});

  final String boardId;
  final String? viewId;

  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  String? _laneColumnId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardControllerProvider(widget.boardId));
    final controller = ref.read(boardControllerProvider(widget.boardId).notifier);
    final auth = ref.watch(authControllerProvider);
    final meUserId = auth is SignedIn ? auth.me.id : null;
    final text = Theme.of(context).textTheme;

    final board = state.value;
    final view = board?.views.where((v) => v.id == widget.viewId).firstOrNull;
    final config = view == null ? const ViewConfig.empty() : ViewConfig.fromJson(view.config);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        centerTitle: false,
        titleSpacing: 0,
        title: state.maybeWhen(
          data: (board) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${view?.name ?? 'Kanban'} · ${board.itemCount} items', style: text.labelSmall),
            ],
          ),
          orElse: () => const Text('Kanban'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_rows_outlined),
            tooltip: 'Table view',
            onPressed: () => context.pushReplacement('/boards/${widget.boardId}'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
              const SizedBox(height: DfSpacing.md),
              DfButton(
                label: 'Try again',
                variant: DfButtonVariant.tonal,
                expand: false,
                onPressed: () => ref.invalidate(boardControllerProvider(widget.boardId)),
              ),
            ]),
          ),
        ),
        data: (board) {
          final laneColumns = board.itemColumns.where((c) => c.type == 'status' || c.type == 'dropdown').toList();
          if (laneColumns.isEmpty) {
            return _NoStatusColumn(boardId: widget.boardId);
          }

          final wantedId = _laneColumnId ?? config.laneColumnId;
          final laneColumn = laneColumns.firstWhere(
            (c) => c.id == wantedId,
            orElse: () => laneColumns.firstWhere((c) => c.type == 'status', orElse: () => laneColumns.first),
          );

          // Subitems ride inside their parents and never become cards.
          final groups = applyView(board, config, ViewContext.forBoard(board, meUserId: meUserId));
          final items = [for (final group in groups) ...group.items];

          return Column(children: [
            if (laneColumns.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
                child: Row(children: [
                  Text('Lanes by', style: text.labelMedium),
                  const SizedBox(width: DfSpacing.xs),
                  DropdownButton<String>(
                    value: laneColumn.id,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final column in laneColumns)
                        DropdownMenuItem(value: column.id, child: Text(column.title)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _laneColumnId = value);
                      if (view != null && board.canEdit) {
                        _persist(controller, view, config.copyWith(laneColumnId: () => value));
                      }
                    },
                  ),
                  if (config.hasFilters) ...[
                    const Spacer(),
                    Text('Filtered by view', style: text.labelSmall),
                  ],
                ]),
              ),
            Expanded(
              child: _Lanes(board: board, laneColumn: laneColumn, items: items, controller: controller),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _persist(BoardController controller, BoardView view, ViewConfig config) async {
    try {
      await controller.updateViewConfig(view.id, config.toJson());
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
}

/// One lane of a status or dropdown column.
typedef _LaneChoice = ({String id, String label, String color});

List<_LaneChoice> _choicesOf(BoardColumn column) => column.type == 'status'
    ? [for (final l in column.statusLabels) (id: l.id, label: l.label, color: l.color)]
    : [
        for (final o in column.options)
          (id: o['id'] as String, label: o['label']?.toString() ?? '', color: o['color']?.toString() ?? 'blue'),
      ];

String? _laneOf(BoardItem item, BoardColumn column) {
  final cell = item.values[column.id];
  if (cell is! Map<String, dynamic>) return null;
  if (column.type == 'status') return cell['labelId'] as String?;
  final ids = cell['optionIds'];
  return ids is List && ids.isNotEmpty ? ids.first?.toString() : null;
}

class _Lanes extends StatelessWidget {
  const _Lanes({required this.board, required this.laneColumn, required this.items, required this.controller});

  final BoardDetail board;
  final BoardColumn laneColumn;
  final List<BoardItem> items;
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    final choices = _choicesOf(laneColumn);

    List<BoardItem> itemsFor(String? id) => items.where((item) => _laneOf(item, laneColumn) == id).toList();

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
      children: [
        // An explicit "unset" lane so items without a value stay reachable.
        _Lane(
          title: 'No ${laneColumn.title.toLowerCase()}',
          colorToken: 'grey',
          items: itemsFor(null),
          board: board,
          onAccept: (item) => _setLane(context, item, null),
        ),
        for (final choice in choices)
          _Lane(
            title: choice.label,
            colorToken: choice.color,
            items: itemsFor(choice.id),
            board: board,
            onAccept: (item) => _setLane(context, item, choice.id),
          ),
      ],
    );
  }

  Future<void> _setLane(BuildContext context, BoardItem item, String? id) async {
    if (!board.canEdit) {
      showDfToast(context, 'You can only view this board', icon: Icons.info_outline_rounded);
      return;
    }
    final value = id == null
        ? null
        : laneColumn.type == 'status'
            ? {'labelId': id}
            : {'optionIds': [id]};
    try {
      await controller.setCell(itemId: item.id, columnId: laneColumn.id, value: value);
    } on ApiException catch (e) {
      if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
}

class _Lane extends StatelessWidget {
  const _Lane({
    required this.title,
    required this.colorToken,
    required this.items,
    required this.board,
    required this.onAccept,
  });

  final String title;
  final String colorToken;
  final List<BoardItem> items;
  final BoardDetail board;
  final ValueChanged<BoardItem> onAccept;

  @override
  Widget build(BuildContext context) {
    final color = DfColors.token(colorToken);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DragTarget<BoardItem>(
      onWillAcceptWithDetails: (details) => !items.any((i) => i.id == details.data.id),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Container(
          width: 260,
          margin: const EdgeInsets.symmetric(horizontal: DfSpacing.xxs),
          decoration: BoxDecoration(
            color: highlighted
                ? color.withValues(alpha: 0.12)
                : (isDark ? DfColors.surfaceDark : DfColors.surfaceAlt),
            borderRadius: BorderRadius.circular(DfRadius.md),
            border: Border.all(
              color: highlighted ? color : (isDark ? DfColors.borderDark : DfColors.border),
              width: highlighted ? 1.6 : 1,
            ),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.sm),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: DfSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('${items.length}', style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        highlighted ? 'Drop here' : 'Empty',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
                      children: [
                        for (final item in items) _KanbanCard(item: item, board: board, accent: color),
                        const SizedBox(height: DfSpacing.sm),
                      ],
                    ),
            ),
          ]),
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.item, required this.board, required this.accent});

  final BoardItem item;
  final BoardDetail board;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final card = _CardBody(item: item, board: board, accent: accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: LongPressDraggable<BoardItem>(
        data: item,
        maxSimultaneousDrags: board.canEdit ? 1 : 0,
        feedback: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(DfRadius.sm),
          child: SizedBox(width: 240, child: card),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: InkWell(
          onTap: () => context.push('/items/${item.id}'),
          borderRadius: BorderRadius.circular(DfRadius.sm),
          child: card,
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.item, required this.board, required this.accent});

  final BoardItem item;
  final BoardDetail board;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;

    // People assigned through the first people column, for a compact face row.
    final peopleColumn = board.itemColumns.where((c) => c.type == 'people').firstOrNull;
    final assigned = peopleColumn == null
        ? const <String>[]
        : (((item.values[peopleColumn.id] as Map<String, dynamic>?)?['userIds'] as List<dynamic>?) ?? const [])
            .cast<String>();
    final subitems = item.subitems.length;

    return Container(
      padding: const EdgeInsets.all(DfSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : Colors.white,
        borderRadius: BorderRadius.circular(DfRadius.sm),
        border: Border(left: BorderSide(color: accent, width: 3)),
        boxShadow: isDark ? null : DfShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
        if (assigned.isNotEmpty || item.updatesCount > 0 || subitems > 0) ...[
          const SizedBox(height: DfSpacing.xs),
          Row(children: [
            for (final id in assigned.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: DfAvatar(
                  name: board.members.where((m) => m.userId == id).firstOrNull?.fullName ?? '?',
                  seed: id,
                  size: 20,
                ),
              ),
            const Spacer(),
            if (subitems > 0) ...[
              const Icon(Icons.subdirectory_arrow_right_rounded, size: 12, color: DfColors.textTertiary),
              const SizedBox(width: 2),
              Text('${item.subitemsDone(board.columns)}/$subitems', style: text.labelSmall),
              const SizedBox(width: DfSpacing.xs),
            ],
            if (item.updatesCount > 0) ...[
              const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: DfColors.textTertiary),
              const SizedBox(width: 2),
              Text('${item.updatesCount}', style: text.labelSmall),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _NoStatusColumn extends StatelessWidget {
  const _NoStatusColumn({required this.boardId});

  final String boardId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.view_kanban_outlined, size: 34, color: DfColors.textTertiary),
          const SizedBox(height: DfSpacing.sm),
          Text('No status column', style: text.titleMedium),
          const SizedBox(height: DfSpacing.xxs),
          Text(
            'Kanban lanes come from a status or dropdown column.\nAdd one on the table view to use this.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: DfSpacing.md),
          DfButton(
            label: 'Back to table',
            variant: DfButtonVariant.tonal,
            expand: false,
            onPressed: () => context.pushReplacement('/boards/$boardId'),
          ),
        ]),
      ),
    );
  }
}
