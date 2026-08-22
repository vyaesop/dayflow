import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/realtime/realtime_client.dart';
import 'board_repository.dart';

final boardRepositoryProvider = Provider<BoardRepository>((ref) => BoardRepository(ApiClient.instance));

final templatesProvider = FutureProvider.autoDispose<List<BoardTemplate>>(
  (ref) => ref.read(boardRepositoryProvider).templates(),
);

/// Board state with optimistic editing: every mutation updates the local copy
/// first, then reconciles with the server and rolls back on failure.
final boardControllerProvider =
    AsyncNotifierProvider.autoDispose.family<BoardController, BoardDetail, String>(BoardController.new);

class BoardController extends AutoDisposeFamilyAsyncNotifier<BoardDetail, String> {
  BoardRepository get _repo => ref.read(boardRepositoryProvider);
  StreamSubscription<BoardEvent>? _live;

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
    ref.onDispose(() {
      _live?.cancel();
      RealtimeClient.instance.unsubscribe(boardId);
    });

    return _repo.fetch(boardId);
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
        final name = event.patch?['name'] as String?;
        if (itemId == null || name == null) return;
        state = AsyncData(board.withItem(itemId, (item) => item.copyWith(name: name)));

      case 'item.deleted':
        final itemId = event.itemId;
        if (itemId == null) return;
        state = AsyncData(board.copyWith(groups: [
          for (final g in board.groups) g.copyWith(items: g.items.where((i) => i.id != itemId).toList()),
        ]));

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
              g.copyWith(items: [for (final i in g.items) i.withCell(columnId, null)]),
          ],
        ));

      // Moves and column/board metadata changes need positions and settings we
      // don't receive, so re-read the board.
      case 'item.moved':
      case 'column.updated':
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

  Future<void> renameItem(String itemId, String name) => _optimistic(
        mutate: (board) => board.withItem(itemId, (item) => item.copyWith(name: name)),
        call: () => _repo.renameItem(itemId, name),
      );

  Future<void> archiveItem(String itemId) => _optimistic(
        mutate: (board) => board.copyWith(groups: [
          for (final g in board.groups) g.copyWith(items: g.items.where((i) => i.id != itemId).toList()),
        ]),
        call: () => _repo.archiveItem(itemId),
      );

  Future<void> duplicateItem(String itemId) async {
    final board = _board;
    if (board == null) return;
    final copy = await _repo.duplicateItem(itemId);

    final current = _board;
    if (current == null) return;
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

  Future<void> addColumn({required String type, required String title}) async {
    final board = _board;
    if (board == null) return;
    final created = await _repo.createColumn(boardId: board.id, type: type, title: title);
    final current = _board;
    if (current == null) return;
    state = AsyncData(current.copyWith(columns: [...current.columns, created]));
  }

  Future<void> deleteColumn(String columnId) => _optimistic(
        mutate: (board) => board.copyWith(
          columns: board.columns.where((c) => c.id != columnId).toList(),
          groups: [
            for (final g in board.groups)
              g.copyWith(items: [for (final i in g.items) i.withCell(columnId, null)]),
          ],
        ),
        call: () => _repo.deleteColumn(columnId),
      );

  /// Replaces a column's choice set (status labels, dropdown/tags options).
  /// Cell values referencing a removed id are left untouched server-side and
  /// simply stop rendering, so a refetch keeps the board honest.
  Future<void> updateColumnSettings(String columnId, Map<String, dynamic> settings) async {
    final board = _board;
    if (board == null) return;
    await _repo.updateColumn(columnId, settings: settings);
    await _refetch();
  }

  Future<void> renameColumn(String columnId, String title) => _optimistic(
        mutate: (board) => board.copyWith(columns: [
          for (final c in board.columns)
            if (c.id == columnId)
              BoardColumn(id: c.id, type: c.type, title: title, settings: c.settings, position: c.position)
            else
              c,
        ]),
        call: () => _repo.updateColumn(columnId, title: title),
      );

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
