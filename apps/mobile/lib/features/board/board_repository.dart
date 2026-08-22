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

  Future<String> createBoard({
    required String name,
    String? workspaceId,
    String? template,
    String? description,
  }) async {
    final json = await _api.post('/boards', body: {
      'name': name,
      'workspaceId': ?workspaceId,
      'template': ?template,
      'description': ?description,
    });
    return json['id'] as String;
  }

  Future<void> renameBoard(String boardId, String name) => _api.patch('/boards/$boardId', body: {'name': name});

  Future<void> archiveBoard(String boardId) => _api.delete('/boards/$boardId');

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

  Future<void> renameItem(String itemId, String name) => _api.patch('/items/$itemId', body: {'name': name});

  Future<void> moveItem({required String itemId, String? groupId, String? afterItemId}) =>
      _api.post('/items/$itemId/move', body: {'groupId': ?groupId, 'afterItemId': afterItemId});

  Future<BoardItem> duplicateItem(String itemId) async =>
      BoardItem.fromJson(await _api.post('/items/$itemId/duplicate'));

  Future<void> archiveItem(String itemId) => _api.delete('/items/$itemId');

  /// Sets or clears one cell. `value == null` clears it.
  Future<Map<String, dynamic>?> setCellValue({
    required String itemId,
    required String columnId,
    required Map<String, dynamic>? value,
  }) async {
    final json = await _api.put('/items/$itemId/columns/$columnId', body: {'value': value});
    return json['value'] as Map<String, dynamic>?;
  }

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
  }) async {
    final json = await _api.post('/boards/$boardId/columns', body: {'type': type, 'title': title});
    return BoardColumn.fromJson(json);
  }

  Future<void> updateColumn(String columnId, {String? title, Map<String, dynamic>? settings}) =>
      _api.patch('/columns/$columnId', body: {'title': ?title, 'settings': ?settings});

  Future<void> deleteColumn(String columnId) => _api.delete('/columns/$columnId');
}
