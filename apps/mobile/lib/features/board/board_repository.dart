import '../../core/api/api_client.dart';
import '../../core/models/models.dart';

/// Every board mutation the client can perform.
class BoardRepository {
  BoardRepository(this._api);

  final ApiClient _api;

  Future<BoardDetail> fetch(String boardId) async =>
      BoardDetail.fromJson(await _api.get('/boards/$boardId'));

  Future<void> recordVisit(String boardId) => _api.post('/boards/$boardId/visit');

  Future<bool> toggleFavorite(String boardId) async {
    final json = await _api.post('/boards/$boardId/favorite');
    return json['isFavorite'] as bool? ?? false;
  }

  // ------------------------------------------------------------------- boards

  Future<List<BoardTemplate>> templates() async {
    final list = await _api.getList('/templates');
    return list.map((t) => BoardTemplate.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<void> deleteTemplate(String templateId) => _api.delete('/templates/$templateId');

  Future<String> createBoard({
    required String name,
    String? workspaceId,
    String? template,
    String? description,
    String? type,
  }) async {
    final json = await _api.post('/boards', body: {
      'name': name,
      'workspaceId': ?workspaceId,
      'template': ?template,
      'description': ?description,
      'type': ?type,
    });
    return json['id'] as String;
  }

  Future<void> renameBoard(String boardId, String name) => _api.patch('/boards/$boardId', body: {'name': name});

  Future<void> updateBoardDescription(String boardId, String description) =>
      _api.patch('/boards/$boardId', body: {'description': description});

  /// Changing visibility takes a board owner or an account admin.
  Future<void> setBoardType(String boardId, String type) => _api.patch('/boards/$boardId', body: {'type': type});

  /// Archive keeps the board (restorable, indefinitely).
  Future<void> archiveBoard(String boardId) => _api.post('/boards/$boardId/archive');

  /// Trash purges after 30 days unless restored.
  Future<void> trashBoard(String boardId) => _api.delete('/boards/$boardId');

  Future<void> restoreBoard(String boardId) => _api.post('/boards/$boardId/restore');

  Future<void> deleteBoardPermanently(String boardId) => _api.delete('/boards/$boardId/permanent');

  /// Returns the new board's id.
  Future<String> duplicateBoard(String boardId, {String? name, required String mode, String? workspaceId}) async {
    final json = await _api.post('/boards/$boardId/duplicate', body: {
      'name': ?name,
      'mode': mode,
      'workspaceId': ?workspaceId,
    });
    return json['id'] as String;
  }

  Future<BoardTemplate> saveAsTemplate(
    String boardId, {
    required String name,
    String? description,
    required bool includeItems,
  }) async =>
      BoardTemplate.fromJson(await _api.post('/boards/$boardId/save-as-template', body: {
        'name': name,
        'description': ?description,
        'includeItems': includeItems,
      }));

  // -------------------------------------------------------------------- views

  Future<List<BoardView>> views(String boardId) async {
    final list = await _api.getList('/boards/$boardId/views');
    return list.map((v) => BoardView.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<BoardView> createView(
    String boardId, {
    required String type,
    required String name,
    Map<String, dynamic>? config,
    bool? isDefault,
  }) async =>
      BoardView.fromJson(await _api.post('/boards/$boardId/views', body: {
        'type': type,
        'name': name,
        'config': ?config,
        'isDefault': ?isDefault,
      }));

  Future<BoardView> updateView(String viewId, {String? name, Map<String, dynamic>? config, bool? isDefault}) async =>
      BoardView.fromJson(await _api.patch('/views/$viewId', body: {
        'name': ?name,
        'config': ?config,
        'isDefault': ?isDefault,
      }));

  Future<void> moveView({required String viewId, String? afterViewId}) =>
      _api.post('/views/$viewId/move', body: {'afterViewId': afterViewId});

  Future<BoardView> duplicateView(String viewId) async =>
      BoardView.fromJson(await _api.post('/views/$viewId/duplicate'));

  Future<void> deleteView(String viewId) => _api.delete('/views/$viewId');

  // ------------------------------------------------------------ board members

  Future<BoardMemberList> boardMembers(String boardId) async =>
      BoardMemberList.fromJson(await _api.get('/boards/$boardId/members'));

  Future<BoardMemberList> addBoardMember({
    required String boardId,
    required String userId,
    String role = 'member',
  }) async {
    final json = await _api.post('/boards/$boardId/members', body: {'userId': userId, 'role': role});
    return BoardMemberList.fromJson(json);
  }

  Future<BoardMemberList> changeBoardMemberRole({
    required String boardId,
    required String userId,
    required String role,
  }) async {
    final json = await _api.patch('/boards/$boardId/members/$userId', body: {'role': role});
    return BoardMemberList.fromJson(json);
  }

  Future<BoardMemberList> removeBoardMember({required String boardId, required String userId}) async {
    final json = await _api.delete('/boards/$boardId/members/$userId');
    return BoardMemberList.fromJson(json);
  }

  Future<WorkspaceSummary> createWorkspace(String name) async {
    final json = await _api.post('/workspaces', body: {'name': name});
    return WorkspaceSummary.fromJson(json);
  }

  // -------------------------------------------------------------------- items

  Future<BoardItem> createItem({
    required String boardId,
    required String groupId,
    required String name,
    String? afterItemId,
    bool atTop = false,
  }) async {
    final json = await _api.post('/boards/$boardId/items', body: {
      'groupId': groupId,
      'name': name,
      // Omitted entirely means "append"; explicit null means "put it first".
      if (atTop || afterItemId != null) 'afterItemId': afterItemId,
    });
    return BoardItem.fromJson(json);
  }

  Future<BoardItem> createSubitem({required String parentItemId, required String name}) async =>
      BoardItem.fromJson(await _api.post('/items/$parentItemId/subitems', body: {'name': name}));

  Future<void> renameItem(String itemId, String name) => _api.patch('/items/$itemId', body: {'name': name});

  Future<void> moveItem({required String itemId, String? groupId, String? afterItemId}) =>
      _api.post('/items/$itemId/move', body: {'groupId': ?groupId, 'afterItemId': afterItemId});

  Future<BoardItem> duplicateItem(String itemId) async =>
      BoardItem.fromJson(await _api.post('/items/$itemId/duplicate'));

  /// Archive keeps the item (restorable, indefinitely).
  Future<void> archiveItem(String itemId) => _api.post('/items/$itemId/archive');

  /// Trash purges after 30 days unless restored.
  Future<void> trashItem(String itemId) => _api.delete('/items/$itemId');

  Future<BoardItem> restoreItem(String itemId) async => BoardItem.fromJson(await _api.post('/items/$itemId/restore'));

  Future<void> deleteItemPermanently(String itemId) => _api.delete('/items/$itemId/permanent');

  /// Sets or clears one cell. `value == null` clears it.
  Future<Map<String, dynamic>?> setCellValue({
    required String itemId,
    required String columnId,
    required Map<String, dynamic>? value,
  }) async {
    final json = await _api.put('/items/$itemId/columns/$columnId', body: {'value': value});
    return json['value'] as Map<String, dynamic>?;
  }

  /// One transactional action over many items; returns how many were affected.
  Future<int> batch({
    required String boardId,
    required List<String> itemIds,
    required String action,
    String? groupId,
    String? columnId,
    Map<String, dynamic>? value,
  }) async {
    final json = await _api.post('/boards/$boardId/items/batch', body: {
      'itemIds': itemIds,
      'action': action,
      'groupId': ?groupId,
      'columnId': ?columnId,
      if (action == 'set_cell') 'value': value,
    });
    return json['affected'] as int? ?? 0;
  }

  Future<MovePreview> movePreview({required String itemId, required String boardId}) async =>
      MovePreview.fromJson(await _api.get('/items/$itemId/move-preview', query: {'boardId': boardId}));

  Future<void> moveToBoard({required String itemId, required String boardId, required String groupId}) =>
      _api.post('/items/$itemId/move-to-board', body: {'boardId': boardId, 'groupId': groupId});

  // ------------------------------------------------------------------- groups

  Future<BoardGroup> createGroup({required String boardId, required String title, String? color}) async {
    final json = await _api.post('/boards/$boardId/groups', body: {'title': title, 'color': ?color});
    return BoardGroup.fromJson(json);
  }

  Future<void> updateGroup(String groupId, {String? title, String? color, bool? collapsed}) =>
      _api.patch('/groups/$groupId', body: {'title': ?title, 'color': ?color, 'collapsed': ?collapsed});

  Future<void> deleteGroup(String groupId) => _api.delete('/groups/$groupId');

  Future<void> moveGroup({required String groupId, String? afterGroupId}) =>
      _api.post('/groups/$groupId/move', body: {'afterGroupId': afterGroupId});

  // ------------------------------------------------------------------ columns

  Future<BoardColumn> createColumn({
    required String boardId,
    required String type,
    required String title,
    String scope = 'items',
    Map<String, dynamic>? settings,
  }) async {
    final json = await _api.post('/boards/$boardId/columns', body: {
      'type': type,
      'title': title,
      'scope': scope,
      'settings': ?settings,
    });
    return BoardColumn.fromJson(json);
  }

  Future<void> updateColumn(String columnId, {String? title, Map<String, dynamic>? settings, int? width}) =>
      _api.patch('/columns/$columnId', body: {'title': ?title, 'settings': ?settings, 'width': ?width});

  Future<void> moveColumn({required String columnId, String? afterColumnId}) =>
      _api.post('/columns/$columnId/move', body: {'afterColumnId': afterColumnId});

  Future<void> deleteColumn(String columnId) => _api.delete('/columns/$columnId');

  // ---------------------------------------------------------- archive & trash

  Future<ArchiveListing> archive({String? boardId}) async =>
      ArchiveListing.fromJson(await _api.get('/archive', query: {'boardId': ?boardId}));

  Future<ArchiveListing> trash({String? boardId}) async =>
      ArchiveListing.fromJson(await _api.get('/trash', query: {'boardId': ?boardId}));

  // ----------------------------------------------------------------- activity

  Future<ActivityPage> activity(
    String boardId, {
    String? event,
    String? actorId,
    String? itemId,
    String? cursor,
    int limit = 50,
  }) async =>
      ActivityPage.fromJson(await _api.get('/boards/$boardId/activity', query: {
        'event': ?event,
        'actorId': ?actorId,
        'itemId': ?itemId,
        'cursor': ?cursor,
        'limit': limit,
      }));

  Future<void> undoActivity(String entryId) => _api.post('/activity/$entryId/undo');

  /// CSV of the board; pass a view to export only what it shows.
  Future<String> exportCsv(String boardId, {String? viewId}) =>
      _api.getText('/boards/$boardId/export.csv${viewId != null ? '?viewId=$viewId' : ''}');
}
