import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/models/models.dart';

final memberDirectoryProvider = FutureProvider.autoDispose<MemberDirectory>((ref) async {
  return MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
});

/// Account members shaped for people pickers. Assignment is account-scoped, so
/// this — not the board's own member list — is what cells offer.
final assignableMembersProvider = FutureProvider.autoDispose<List<BoardMember>>((ref) async {
  final directory = await ref.watch(memberDirectoryProvider.future);
  return directory.members.map((m) => m.toBoardMember()).toList();
});

final membersRepositoryProvider = Provider<MembersRepository>((ref) => MembersRepository(ApiClient.instance));

class MembersRepository {
  MembersRepository(this._api);

  final ApiClient _api;

  Future<PendingInvite> invite({required String email, required String role}) async {
    final json = await _api.post('/invitations', body: {'email': email, 'role': role});
    return PendingInvite.fromJson(json);
  }

  Future<void> revokeInvite(String invitationId) => _api.delete('/invitations/$invitationId');

  Future<({String accountId, String accountName, String role})> accept(String token) async {
    final json = await _api.post('/invitations/accept', body: {'token': token});
    return (
      accountId: json['accountId'] as String,
      accountName: json['accountName'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
    );
  }

  Future<void> changeRole({required String userId, required String role}) =>
      _api.patch('/members/$userId', body: {'role': role});

  Future<void> remove(String userId) => _api.delete('/members/$userId');
}
