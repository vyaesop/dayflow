import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/models.dart';

final homeOverviewProvider = FutureProvider.autoDispose<HomeOverview>((ref) async {
  final json = await ApiClient.instance.get('/home/overview');
  return HomeOverview.fromJson(json);
});

final workspacesProvider = FutureProvider.autoDispose<List<WorkspaceSummary>>((ref) async {
  final list = await ApiClient.instance.getList('/workspaces');
  return list.map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>)).toList();
});

/// Favorite toggle for board tiles in the Home lists. Board-screen favoriting
/// goes through BoardController so it can update the open board optimistically.
Future<bool> toggleBoardFavorite(String boardId) async {
  final json = await ApiClient.instance.post('/boards/$boardId/favorite');
  return json['isFavorite'] as bool? ?? false;
}
