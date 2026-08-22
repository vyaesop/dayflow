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

  Future<AppFile> uploadFile({
    required List<int> bytes,
    required String filename,
    String? itemId,
    String? updateId,
  }) async =>
      AppFile.fromJson(await _api.postMultipart('/files', bytes: bytes, filename: filename, fields: {
        'itemId': ?itemId,
        'updateId': ?updateId,
      }));

  Future<void> deleteFile(String fileId) => _api.delete('/files/$fileId');
}
