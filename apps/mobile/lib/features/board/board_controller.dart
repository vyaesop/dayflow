import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/realtime/realtime_client.dart';
import 'board_repository.dart';

final boardRepositoryProvider = Provider<BoardRepository>((ref) => BoardRepository(ApiClient.instance));

/// Link state of the realtime connection, for "live vs. auto-refresh" UI.
final realtimeStatusProvider = Provider<ValueNotifier<RealtimeStatus>>(
  (ref) => RealtimeClient.instance.status,
);

final templatesProvider = FutureProvider.autoDispose<List<BoardTemplate>>(
  (ref) => ref.read(boardRepositoryProvider).templates(),
);

/// The saved view a board screen is showing; null falls back to the default view.
final activeViewIdProvider = StateProvider.autoDispose.family<String?, String>((ref, boardId) => null);

/// Board state with optimistic editing: every mutation updates the local copy
/// first, then reconciles with the server and rolls back on failure.
final boardControllerProvider =
    AsyncNotifierProvider.autoDispose.family<BoardController, BoardDetail, String>(BoardController.new);

class BoardController extends AutoDisposeFamilyAsyncNotifier<BoardDetail, String> {
  BoardRepository get _repo => ref.read(boardRepositoryProvider);
  StreamSubscription<BoardEvent>? _live;
  Timer? _poll;
  bool _wasDegraded = false;

  /// How often the board re-reads itself while the realtime link is down.
  static const pollInterval = Duration(seconds: 25);

  @override
  Future<BoardDetail> build(String boardId) async {
    // Visit tracking is best-effort and must not fail the load.
    _repo.recordVisit(boardId).ignore();

    // Live updates from other people editing the same board. The server never
    // echoes our own changes back, so these are always someone else's.
    RealtimeClient.instance.subscribe(boardId);
    _live = RealtimeClient.instance.events
        .where((event) => event.boardId == boardId)
        .listen(_applyRemoteEvent);

    // When the socket cannot connect (serverless host, flaky network), fall
    // back to periodic refetching so the board still converges.
    RealtimeClient.instance.status.addListener(_onLinkChange);
    _onLinkChange();

    ref.onDispose(() {
      RealtimeClient.instance.status.removeListener(_onLinkChange);
      _poll?.cancel();
      _live?.cancel();
      RealtimeClient.instance.unsubscribe(boardId);
    });

    return _repo.fetch(boardId);
  }

  void _onLinkChange() {
    final status = RealtimeClient.instance.status.value;
    if (status == RealtimeStatus.connected) {
      _poll?.cancel();
      _poll = null;
      // Catch up on anything that happened while events could not reach us.
      if (_wasDegraded) unawaited(_refetch());
      _wasDegraded = false;
    } else if (status == RealtimeStatus.offline && _poll == null) {
      _wasDegraded = true;
      _poll = Timer.periodic(pollInterval, (_) => unawaited(_refetch()));
    }
  }

  /// Folds a server-pushed event into local state.
  ///
  /// Events carry only what changed, so anything we cannot apply confidently
  /// (an item arriving for an unknown group, a reorder we have no positions
  /// for) falls back to a refetch rather than guessing.
  void _applyRemoteEvent(BoardEvent event) {
    final board = _board;
    if (board == null) return;

    switch (event.type) {
      case 'item.created':
        final json = event.item;
        final groupId = event.groupId;
        if (json == null || groupId == null) return;
        final incoming = BoardItem.fromJson(json);
        // Ignore a duplicate we already hold (e.g. after a refetch raced us).
        if (board.findItem(incoming.id) != null) return;
        if (incoming.parentItemId != null) {
          final parent = board.findItem(incoming.parentItemId!);
          if (parent == null) {
            unawaited(_refetch());
            return;
          }
          state = AsyncData(board.withItem(
            incoming.parentItemId!,
            (p) => p.copyWith(subitems: [...p.subitems, incoming]),
          ));
          return;
        }
        if (!board.groups.any((g) => g.id == groupId)) {
          unawaited(_refetch());
          return;
        }
        state = AsyncData(board.copyWith(groups: [
          for (final g in board.groups)
            if (g.id == groupId) g.copyWith(items: [...g.items, incoming]) else g,
        ]));

      case 'item.updated':
        final itemId = event.itemId;
        final patch = event.patch;
        if (itemId == null || patch == null || board.findItem(itemId) == null) return;
        state = AsyncData(board.withItem(
          itemId,
          (item) => item.copyWith(
            name: patch['name'] as String?,
            updatedAt: patch['updatedAt'] != null ? DateTime.tryParse(patch['updatedAt'] as String) : null,
            updatedByUserId: patch['updatedByUserId'] as String?,
          ),
        ));

      case 'item.deleted':
        final itemId = event.itemId;
        if (itemId == null) return;
        state = AsyncData(board.withoutItem(itemId));

      case 'cell.changed':
        final itemId = event.itemId;
        final columnId = event.columnId;
        if (itemId == null || columnId == null || !event.hasValue) return;
        if (board.findItem(itemId) == null) return;
        state = AsyncData(board.withItem(itemId, (item) => item.withCell(columnId, event.value)));

      case 'group.created':
        final json = event.group;
        if (json == null) return;
        final incoming = BoardGroup.fromJson(json);
        if (board.groups.any((g) => g.id == incoming.id)) return;
        state = AsyncData(board.copyWith(groups: [...board.groups, incoming]));

      case 'group.updated':
        final groupId = event.groupId;
        final patch = event.patch;
        if (groupId == null || patch == null) return;
        final group = board.groups.where((g) => g.id == groupId).firstOrNull;
        if (group == null) return;
        state = AsyncData(board.withGroup(group.copyWith(
          title: patch['title'] as String?,
          color: patch['color'] as String?,
          // Collapse is a per-viewer preference; don't let someone else fold
          // up the board under us.
        )));

      case 'group.deleted':
        final groupId = event.groupId;
        if (groupId == null) return;
        state = AsyncData(board.copyWith(groups: board.groups.where((g) => g.id != groupId).toList()));

      case 'column.created':
        final json = event.column;
        if (json == null) return;
        final incoming = BoardColumn.fromJson(json);
        if (board.columns.any((c) => c.id == incoming.id)) return;
        state = AsyncData(board.copyWith(columns: [...board.columns, incoming]));

      case 'column.deleted':
        final columnId = event.columnId;
        if (columnId == null) return;
        state = AsyncData(board.copyWith(
          columns: board.columns.where((c) => c.id != columnId).toList(),
          groups: [
            for (final g in board.groups)
              g.copyWith(items: [
                for (final i in g.items)
                  i.withCell(columnId, null).copyWith(
                    subitems: [for (final s in i.subitems) s.withCell(columnId, null)],
                  ),
              ]),
          ],
        ));

      // Moves, column/board metadata, view and batch changes need positions
      // and settings we don't receive, so re-read the board.
      case 'item.moved':
      case 'column.updated':
      case 'column.moved':
      case 'views.changed':
      case 'board.updated':
        unawaited(_refetch());
    }
  }

  Future<void> _refetch() async {
    try {
      state = AsyncData(await _repo.fetch(arg));
    } on ApiException {
      // A failed background refetch leaves the last good state in place.
    }
  }

  BoardDetail? get _board => state.value;

  /// Runs [mutate] locally, then [call] against the server, restoring the
  /// previous state and rethrowing if the server rejects it.
  Future<T?> _optimistic<T>({
    required BoardDetail Function(BoardDetail) mutate,
    required Future<T> Function() call,
    void Function(T result)? reconcile,
  }) async {
    final previous = _board;
    if (previous == null) return null;

    state = AsyncData(mutate(previous));
    try {
      final result = await call();
      reconcile?.call(result);
      return result;
    } on ApiException {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> refresh() async {
    final board = _board;
    if (board == null) return;
    state = AsyncData(await _repo.fetch(board.id));
  }

  // -------------------------------------------------------------------- items

  /// Appends an item to a group. The temporary row is replaced by the server's.
  Future<void> addItem({required String groupId, required String name}) async {
    final board = _board;
    if (board == null) return;

    const tempId = '__pending__';
    final temp = BoardItem(id: tempId, name: name, position: double.maxFinite, updatesCount: 0, values: const {});

    state = AsyncData(board.copyWith(groups: [
      for (final g in board.groups)
        if (g.id == groupId) g.copyWith(items: [...g.items, temp]) else g,
    ]));

    try {
      final created = await _repo.createItem(boardId: board.id, groupId: groupId, name: name);
      final current = _board;
      if (current == null) return;
      state = AsyncData(current.copyWith(groups: [
        for (final g in current.groups)
          if (g.id == groupId)
            g.copyWith(items: [
              for (final i in g.items) if (i.id == tempId) created else i,
            ])
          else
            g,
      ]));
    } on ApiException {
      final current = _board;
      if (current != null) {
        state = AsyncData(current.copyWith(groups: [
          for (final g in current.groups)
            g.copyWith(items: g.items.where((i) => i.id != tempId).toList()),
        ]));
      }
      rethrow;
    }
  }

  /// Adds a subitem under [parentItemId]. The board's subitem columns may be
  /// created server-side on first use, so the board is re-read afterwards.
  Future<BoardItem?> addSubitem({required String parentItemId, required String name}) async {
    final board = _board;
    if (board == null) return null;
    final created = await _repo.createSubitem(parentItemId: parentItemId, name: name);
    final current = _board;
    if (current == null) return created;
    state = AsyncData(current.withItem(parentItemId, (p) => p.copyWith(subitems: [...p.subitems, created])));
    if (current.subitemColumns.isEmpty) await _refetch();
    return created;
  }

  Future<void> renameItem(String itemId, String name) => _optimistic(
        mutate: (board) => board.withItem(itemId, (item) => item.copyWith(name: name)),
        call: () => _repo.renameItem(itemId, name),
      );

  /// Archive: hidden from the board, kept indefinitely, restorable.
  Future<void> archiveItem(String itemId) => _optimistic(
        mutate: (board) => board.withoutItem(itemId),
        call: () => _repo.archiveItem(itemId),
      );

  /// Trash: hidden, purged after 30 days unless restored.
  Future<void> trashItem(String itemId) => _optimistic(
        mutate: (board) => board.withoutItem(itemId),
        call: () => _repo.trashItem(itemId),
      );

  Future<void> duplicateItem(String itemId) async {
    final board = _board;
    if (board == null) return;
    final copy = await _repo.duplicateItem(itemId);

    final current = _board;
    if (current == null) return;
    if (copy.parentItemId != null) {
      state = AsyncData(current.withItem(
        copy.parentItemId!,
        (p) => p.copyWith(subitems: _insertAfter(p.subitems, itemId, copy)),
      ));
      return;
    }
    state = AsyncData(current.copyWith(groups: [
      for (final g in current.groups)
        if (g.items.any((i) => i.id == itemId))
          g.copyWith(items: _insertAfter(g.items, itemId, copy))
        else
          g,
    ]));
  }

  /// Moves an item to [groupId], positioned after [afterItemId] (null = top).
  Future<void> moveItem({
    required String itemId,
    required String groupId,
    String? afterItemId,
  }) async {
    final board = _board;
    if (board == null) return;
    final moving = board.findItem(itemId);
    if (moving == null) return;

    List<BoardGroup> reorder(BoardDetail source) {
      return [
        for (final g in source.groups)
          if (g.id == groupId)
            g.copyWith(items: _placeAfter(g.items.where((i) => i.id != itemId).toList(), afterItemId, moving))
          else
            g.copyWith(items: g.items.where((i) => i.id != itemId).toList()),
      ];
    }

    await _optimistic(
      mutate: (source) => source.copyWith(groups: reorder(source)),
      call: () => _repo.moveItem(itemId: itemId, groupId: groupId, afterItemId: afterItemId),
    );
  }

  /// Reorders a subitem among its siblings (null = first).
  Future<void> moveSubitem({required String parentItemId, required String itemId, String? afterItemId}) async {
    final board = _board;
    if (board == null) return;
    final moving = board.findItem(itemId);
    if (moving == null) return;
    await _optimistic(
      mutate: (source) => source.withItem(
        parentItemId,
        (p) => p.copyWith(subitems: _placeAfter(p.subitems.where((s) => s.id != itemId).toList(), afterItemId, moving)),
      ),
      call: () => _repo.moveItem(itemId: itemId, afterItemId: afterItemId),
    );
  }

  Future<void> setCell({
    required String itemId,
    required String columnId,
    required Map<String, dynamic>? value,
  }) async {
    await _optimistic<Map<String, dynamic>?>(
      mutate: (board) => board.withItem(itemId, (item) => item.withCell(columnId, value)),
      call: () => _repo.setCellValue(itemId: itemId, columnId: columnId, value: value),
      // The server canonicalises values (dropping empties, de-duplicating);
      // adopt its version so the UI matches what was stored.
      reconcile: (stored) {
        final current = _board;
        if (current == null) return;
        state = AsyncData(current.withItem(itemId, (item) => item.withCell(columnId, stored)));
      },
    );
  }

  /// Applies one action to many items in a single request, then re-reads the
  /// board (the server emits a single batch event rather than per-item ones).
  Future<int> batch({
    required List<String> itemIds,
    required String action,
    String? groupId,
    String? columnId,
    Map<String, dynamic>? value,
  }) async {
    final board = _board;
    if (board == null) return 0;
    final affected = await _repo.batch(
      boardId: board.id,
      itemIds: itemIds,
      action: action,
      groupId: groupId,
      columnId: columnId,
      value: value,
    );
    await _refetch();
    return affected;
  }

  // ------------------------------------------------------------------- groups

  Future<void> addGroup(String title) async {
    final board = _board;
    if (board == null) return;
    final created = await _repo.createGroup(boardId: board.id, title: title);
    final current = _board;
    if (current == null) return;
    state = AsyncData(current.copyWith(groups: [...current.groups, created]));
  }

  Future<void> renameGroup(String groupId, String title) => _optimistic(
        mutate: (board) => board.withGroup(
          board.groups.firstWhere((g) => g.id == groupId).copyWith(title: title),
        ),
        call: () => _repo.updateGroup(groupId, title: title),
      );

  Future<void> recolorGroup(String groupId, String color) => _optimistic(
        mutate: (board) => board.withGroup(
          board.groups.firstWhere((g) => g.id == groupId).copyWith(color: color),
        ),
        call: () => _repo.updateGroup(groupId, color: color),
      );

  Future<void> deleteGroup(String groupId) => _optimistic(
        mutate: (board) => board.copyWith(groups: board.groups.where((g) => g.id != groupId).toList()),
        call: () => _repo.deleteGroup(groupId),
      );

  /// Reorders a group (null = first).
  Future<void> moveGroup({required String groupId, String? afterGroupId}) async {
    final board = _board;
    if (board == null) return;
    final moving = board.groups.where((g) => g.id == groupId).firstOrNull;
    if (moving == null) return;
    await _optimistic(
      mutate: (source) {
        final rest = source.groups.where((g) => g.id != groupId).toList();
        final index = afterGroupId == null ? 0 : rest.indexWhere((g) => g.id == afterGroupId) + 1;
        rest.insert(index.clamp(0, rest.length), moving);
        return source.copyWith(groups: rest);
      },
      call: () => _repo.moveGroup(groupId: groupId, afterGroupId: afterGroupId),
    );
  }

  /// Collapse state is per-user UI sugar; it is persisted but never blocks.
  Future<void> toggleCollapsed(String groupId) async {
    final board = _board;
    if (board == null) return;
    final group = board.groups.firstWhere((g) => g.id == groupId);
    final collapsed = !group.collapsed;
    state = AsyncData(board.withGroup(group.copyWith(collapsed: collapsed)));
    try {
      await _repo.updateGroup(groupId, collapsed: collapsed);
    } on ApiException {
      // Leave the local state as-is; the next fetch reconciles.
    }
  }

  // ------------------------------------------------------------------ columns

  Future<void> addColumn({
    required String type,
    required String title,
    String scope = 'items',
    Map<String, dynamic>? settings,
  }) async {
    final board = _board;
    if (board == null) return;
    final created = await _repo.createColumn(
      boardId: board.id,
      type: type,
      title: title,
      scope: scope,
      settings: settings,
    );
    final current = _board;
    if (current == null) return;
    state = AsyncData(current.copyWith(columns: [...current.columns, created]));
  }

  Future<void> deleteColumn(String columnId) => _optimistic(
        mutate: (board) => board.copyWith(
          columns: board.columns.where((c) => c.id != columnId).toList(),
          groups: [
            for (final g in board.groups)
              g.copyWith(items: [
                for (final i in g.items)
                  i.withCell(columnId, null).copyWith(
                    subitems: [for (final s in i.subitems) s.withCell(columnId, null)],
                  ),
              ]),
          ],
        ),
        call: () => _repo.deleteColumn(columnId),
      );

  /// Replaces a column's settings (choices, unit, summary mode, ...).
  /// Cell values referencing a removed choice simply stop rendering, so a
  /// refetch keeps the board honest.
  Future<void> updateColumnSettings(String columnId, Map<String, dynamic> settings) async {
    final board = _board;
    if (board == null) return;
    await _repo.updateColumn(columnId, settings: settings);
    await _refetch();
  }

  Future<void> renameColumn(String columnId, String title) => _optimistic(
        mutate: (board) => board.copyWith(columns: [
          for (final c in board.columns) if (c.id == columnId) c.copyWith(title: title) else c,
        ]),
        call: () => _repo.updateColumn(columnId, title: title),
      );

  /// Reorders a column within its scope (null = first).
  Future<void> moveColumn({required String columnId, String? afterColumnId}) async {
    final board = _board;
    if (board == null) return;
    final moving = board.columns.where((c) => c.id == columnId).firstOrNull;
    if (moving == null) return;
    await _optimistic(
      mutate: (source) {
        final sameScope = source.columns.where((c) => c.scope == moving.scope && c.id != columnId).toList();
        final others = source.columns.where((c) => c.scope != moving.scope).toList();
        final index = afterColumnId == null ? 0 : sameScope.indexWhere((c) => c.id == afterColumnId) + 1;
        sameScope.insert(index.clamp(0, sameScope.length), moving);
        return source.copyWith(columns: moving.scope == 'items' ? [...sameScope, ...others] : [...others, ...sameScope]);
      },
      call: () => _repo.moveColumn(columnId: columnId, afterColumnId: afterColumnId),
    );
  }

  // -------------------------------------------------------------------- views

  Future<BoardView?> createView({
    required String type,
    required String name,
    Map<String, dynamic>? config,
    bool? isDefault,
  }) async {
    final board = _board;
    if (board == null) return null;
    final created = await _repo.createView(board.id, type: type, name: name, config: config, isDefault: isDefault);
    final current = _board;
    if (current == null) return created;
    state = AsyncData(current.copyWith(views: [
      for (final v in current.views) if (created.isDefault) v.copyWith(isDefault: false) else v,
      created,
    ]));
    return created;
  }

  /// Saves a view's config (filters, sort, hidden columns, colors) optimistically.
  Future<void> updateViewConfig(String viewId, Map<String, dynamic> config) => _optimistic<BoardView>(
        mutate: (board) => board.copyWith(views: [
          for (final v in board.views) if (v.id == viewId) v.copyWith(config: config) else v,
        ]),
        call: () => _repo.updateView(viewId, config: config),
        reconcile: (stored) {
          final current = _board;
          if (current == null) return;
          state = AsyncData(current.copyWith(views: [
            for (final v in current.views) if (v.id == viewId) stored else v,
          ]));
        },
      );

  Future<void> renameView(String viewId, String name) => _optimistic(
        mutate: (board) => board.copyWith(views: [
          for (final v in board.views) if (v.id == viewId) v.copyWith(name: name) else v,
        ]),
        call: () => _repo.updateView(viewId, name: name),
      );

  Future<void> setDefaultView(String viewId) => _optimistic(
        mutate: (board) => board.copyWith(views: [
          for (final v in board.views) v.copyWith(isDefault: v.id == viewId),
        ]),
        call: () => _repo.updateView(viewId, isDefault: true),
      );

  Future<BoardView?> duplicateView(String viewId) async {
    final board = _board;
    if (board == null) return null;
    final copy = await _repo.duplicateView(viewId);
    final current = _board;
    if (current == null) return copy;
    final index = current.views.indexWhere((v) => v.id == viewId);
    final next = [...current.views];
    next.insert(index == -1 ? next.length : index + 1, copy);
    state = AsyncData(current.copyWith(views: next));
    return copy;
  }

  Future<void> deleteView(String viewId) async {
    await _optimistic(
      mutate: (board) {
        final remaining = board.views.where((v) => v.id != viewId).toList();
        final wasDefault = board.views.any((v) => v.id == viewId && v.isDefault);
        return board.copyWith(views: [
          for (final (i, v) in remaining.indexed) if (wasDefault && i == 0) v.copyWith(isDefault: true) else v,
        ]);
      },
      call: () => _repo.deleteView(viewId),
    );
  }

  Future<void> moveView({required String viewId, String? afterViewId}) async {
    final board = _board;
    if (board == null) return;
    final moving = board.views.where((v) => v.id == viewId).firstOrNull;
    if (moving == null) return;
    await _optimistic(
      mutate: (source) {
        final rest = source.views.where((v) => v.id != viewId).toList();
        final index = afterViewId == null ? 0 : rest.indexWhere((v) => v.id == afterViewId) + 1;
        rest.insert(index.clamp(0, rest.length), moving);
        return source.copyWith(views: rest);
      },
      call: () => _repo.moveView(viewId: viewId, afterViewId: afterViewId),
    );
  }

  // -------------------------------------------------------------------- board

  Future<void> renameBoard(String name) => _optimistic(
        mutate: (board) => board.copyWith(name: name),
        call: () => _repo.renameBoard(_board!.id, name),
      );

  Future<void> toggleFavorite() async {
    final board = _board;
    if (board == null) return;
    state = AsyncData(board.copyWith(isFavorite: !board.isFavorite));
    try {
      final stored = await _repo.toggleFavorite(board.id);
      final current = _board;
      if (current != null) state = AsyncData(current.copyWith(isFavorite: stored));
    } on ApiException {
      state = AsyncData(board);
      rethrow;
    }
  }
}

List<BoardItem> _insertAfter(List<BoardItem> items, String afterId, BoardItem inserted) {
  final index = items.indexWhere((i) => i.id == afterId);
  final next = [...items];
  next.insert(index == -1 ? next.length : index + 1, inserted);
  return next;
}

/// Places [item] after [afterId], or at the head when [afterId] is null.
List<BoardItem> _placeAfter(List<BoardItem> items, String? afterId, BoardItem item) {
  if (afterId == null) return [item, ...items];
  return _insertAfter(items, afterId, item);
}
