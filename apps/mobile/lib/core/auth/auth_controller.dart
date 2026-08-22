import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../realtime/realtime_client.dart';
import 'auth_repository.dart';

sealed class AuthState {
  const AuthState();
}

/// Session restore still in flight — splash stays up.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.me, {this.isFirstRun = false});

  final Me me;

  /// True right after signup — routes through the notifications/confetti steps.
  final bool isFirstRun;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ApiClient.instance));

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    ApiClient.instance.onSessionExpired = () => state = const SignedOut();
    _restore();
    return const AuthUnknown();
  }

  Future<void> _restore() async {
    final me = await ref.read(authRepositoryProvider).restoreSession();
    state = me != null ? SignedIn(me) : const SignedOut();
  }

  void signedIn(Me me, {bool isFirstRun = false}) {
    state = SignedIn(me, isFirstRun: isFirstRun);
  }

  /// Clears the first-run flag once the post-signup tour finishes.
  void completeFirstRun() {
    final current = state;
    if (current is SignedIn) state = SignedIn(current.me);
  }

  void updateMe(Me me) {
    final current = state;
    state = SignedIn(me, isFirstRun: current is SignedIn && current.isFirstRun);
  }

  Future<void> switchAccount(String accountId) async {
    final me = await ref.read(authRepositoryProvider).switchAccount(accountId);
    // The realtime connection is scoped to the account in its token.
    RealtimeClient.instance.reset();
    state = SignedIn(me);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    RealtimeClient.instance.reset();
    state = const SignedOut();
  }
}
