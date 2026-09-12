import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/models.dart';

final itemRepositoryProvider = Provider<ItemRepository>((ref) => ItemRepository(ApiClient.instance));

/// Updates, interactions, and attachments on items.
class ItemRepository {
  ItemRepository(this._api);

  final ApiClient _api;

  Future<ItemDetail> fetch(String itemId) async =>
      ItemDetail.fromJson(await _api.get('/items/$itemId'));

  Future<ItemUpdate> postUpdate({required String itemId, required String body, String? parentId}) async =>
      ItemUpdate.fromJson(await _api.post('/items/$itemId/updates', body: {
        'body': body,
        'parentId': ?parentId,
      }));

  Future<void> editUpdate(String updateId, String body) => _api.patch('/updates/$updateId', body: {'body': body});

  Future<void> deleteUpdate(String updateId) => _api.delete('/updates/$updateId');

  Future<({bool liked, int likesCount})> toggleLike(String updateId) async {
    final json = await _api.post('/updates/$updateId/like');
    return (liked: json['liked'] as bool? ?? false, likesCount: json['likesCount'] as int? ?? 0);
  }

  /// Toggles one emoji reaction; returns the update's full reaction list.
  Future<List<Reaction>> toggleReaction(String updateId, String emoji) async {
    final json = await _api.post('/updates/$updateId/reactions', body: {'emoji': emoji});
    return (json['reactions'] as List<dynamic>? ?? const [])
        .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------------- board discussion

  Future<List<ItemUpdate>> boardUpdates(String boardId) async {
    final list = await _api.getList('/boards/$boardId/updates');
    return list.map((u) => ItemUpdate.fromJson(u as Map<String, dynamic>)).toList();
  }

  Future<ItemUpdate> postBoardUpdate({required String boardId, required String body, String? parentId}) async =>
      ItemUpdate.fromJson(await _api.post('/boards/$boardId/updates', body: {
        'body': body,
        'parentId': ?parentId,
      }));

  Future<bool> toggleBookmark(String updateId) async {
    final json = await _api.post('/updates/$updateId/bookmark');
    return json['bookmarked'] as bool? ?? false;
  }

  Future<List<FeedEntry>> feed({String? boardId, bool bookmarkedOnly = false}) async {
    final list = await _api.getList('/updates/feed', query: {
      'boardId': ?boardId,
      if (bookmarkedOnly) 'bookmarked': 'true',
    });
    return list.map((e) => FeedEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  // -------------------------------------------------------------------- files

  Future<List<AppFile>> filesForItem(String itemId) async {
    final list = await _api.getList('/items/$itemId/files');
    return list.map((f) => AppFile.fromJson(f as Map<String, dynamic>)).toList();
  }

  /// Uploads a file to an item, an update, or (with [columnId]) a Files column cell.
  Future<AppFile> uploadFile({
    required List<int> bytes,
    required String filename,
    String? itemId,
    String? updateId,
    String? columnId,
  }) async =>
      AppFile.fromJson(await _api.postMultipart('/files', bytes: bytes, filename: filename, fields: {
        'itemId': ?itemId,
        'updateId': ?updateId,
        'columnId': ?columnId,
      }));

  Future<void> deleteFile(String fileId) => _api.delete('/files/$fileId');
}
