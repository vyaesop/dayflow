import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';

final memberDirectoryProvider = FutureProvider.autoDispose<MemberDirectory>((ref) async {
  return MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
});

/// Account members shaped for people pickers. Assignment is account-scoped, so
/// this — not the board's own member list — is what cells offer. Deactivated
/// members are left out: they cannot sign in, so nothing should be assigned to them.
final assignableMembersProvider = FutureProvider.autoDispose<List<BoardMember>>((ref) async {
  final directory = await ref.watch(memberDirectoryProvider.future);
  return directory.members.where((m) => m.status == 'active').map((m) => m.toBoardMember()).toList();
});

/// Whether the signed-in user may manage the directory (account admins only).
/// A provider rather than an inline check so screens can be tested without a
/// live session.
final canManageMembersProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth is SignedIn && auth.me.account.role == 'admin';
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

  /// Keeps the member's history but blocks sign-in to this account.
  Future<void> deactivate(String userId) => _api.post('/members/$userId/deactivate');

  Future<void> reactivate(String userId) => _api.post('/members/$userId/reactivate');
}
