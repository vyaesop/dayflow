import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/token_store.dart';

/// Invite token captured from a deep link (`dayflow:///invite/<token>`).
///
/// A link can arrive before the user has a session; the token is stashed here
/// (and in secure storage, surviving a restart) so the router can route to the
/// accept screen once sign-in completes.
final pendingInviteProvider = NotifierProvider<PendingInviteNotifier, String?>(PendingInviteNotifier.new);

class PendingInviteNotifier extends Notifier<String?> {
  @override
  String? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final stored = await TokenStore.instance.readPendingInvite();
    if (stored != null && state == null) state = stored;
  }

  void set(String token) {
    if (state == token) return;
    state = token;
    TokenStore.instance.savePendingInvite(token);
  }

  void clear() {
    state = null;
    TokenStore.instance.clearPendingInvite();
  }
}
