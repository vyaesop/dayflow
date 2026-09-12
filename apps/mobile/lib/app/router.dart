import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../features/auth/account_picker_screen.dart';
import '../features/auth/create_account_screen.dart';
import '../features/auth/email_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/password_login_screen.dart';
import '../features/activity/board_activity_screen.dart';
import '../features/archive/archive_screen.dart';
import '../features/board/board_discussion_screen.dart';
import '../features/board/board_screen.dart';
import '../features/board/calendar_screen.dart';
import '../features/board/create_board_screen.dart';
import '../features/board/dashboard_screen.dart';
import '../features/board/kanban_screen.dart';
import '../features/feed/update_feed_screen.dart';
import '../features/home/home_screen.dart';
import '../features/invite/invite_accept_screen.dart';
import '../features/invite/invite_providers.dart';
import '../features/item/item_detail_screen.dart';
import '../features/members/members_screen.dart';
import '../features/more/more_screen.dart';
import '../features/mywork/my_work_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/done_screen.dart';
import '../features/onboarding/notifications_screen.dart';
import '../features/onboarding/onboarding_wizard_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/support/support_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/welcome/welcome_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Bridges Riverpod auth (and pending-invite) state into go_router's refresh
/// mechanism.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen<AuthState>(authControllerProvider, (previous, next) => notifyListeners());
    _ref.listen<String?>(pendingInviteProvider, (previous, next) => notifyListeners());
  }

  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.matchedLocation;
      final inAuthFlow = path.startsWith('/auth') || path == '/welcome' || path.startsWith('/onboarding');

      // An invite deep link can land before a session exists: stash the token
      // (it also survives restarts) so the accept screen runs after sign-in.
      if (path.startsWith('/invite/')) {
        final token = state.pathParameters['token'] ?? '';
        if (token.isNotEmpty) ref.read(pendingInviteProvider.notifier).set(token);
      }
      final pendingInvite = ref.read(pendingInviteProvider);

      return switch (auth) {
        // Session restore in flight — hold on the splash.
        AuthUnknown() => path == '/splash' ? null : '/splash',
        // Signed out: allow the welcome + auth + onboarding screens only.
        SignedOut() => inAuthFlow ? null : '/welcome',
        // Fresh signup routes through the notification ask + confetti.
        SignedIn(isFirstRun: true) =>
          path.startsWith('/onboarding/') ? null : '/onboarding/notifications',
        // A stashed invite takes priority the moment a session exists.
        SignedIn() when pendingInvite != null && !path.startsWith('/invite/') => '/invite/$pendingInvite',
        // Established session: keep out of the auth flow.
        SignedIn() => inAuthFlow || path == '/splash' ? '/home' : null,
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(
        path: '/auth/email',
        builder: (context, state) => EmailScreen(isSignup: state.uri.queryParameters['mode'] != 'login'),
      ),
      GoRoute(path: '/auth/otp', builder: (context, state) => const OtpScreen()),
      GoRoute(path: '/auth/password', builder: (context, state) => const PasswordLoginScreen()),
      GoRoute(path: '/auth/create', builder: (context, state) => const CreateAccountScreen()),
      GoRoute(path: '/auth/accounts', builder: (context, state) => const AccountPickerScreen()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingWizardScreen()),
      GoRoute(
        path: '/onboarding/notifications',
        builder: (context, state) => const NotificationsAskScreen(),
      ),
      GoRoute(path: '/onboarding/done', builder: (context, state) => const OnboardingDoneScreen()),

      // Full-screen routes, pushed above the tab shell.
      GoRoute(
        path: '/boards/:id/kanban',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => KanbanScreen(
          boardId: state.pathParameters['id']!,
          viewId: state.uri.queryParameters['viewId'],
        ),
      ),
      GoRoute(
        path: '/boards/:id/calendar',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => CalendarScreen(
          boardId: state.pathParameters['id']!,
          viewId: state.uri.queryParameters['viewId'],
        ),
      ),
      GoRoute(
        path: '/boards/:id/dashboard',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DashboardScreen(
          boardId: state.pathParameters['id']!,
          viewId: state.uri.queryParameters['viewId'],
        ),
      ),
      GoRoute(
        path: '/boards/:id/activity',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => BoardActivityScreen(boardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/boards/:id/discussion',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => BoardDiscussionScreen(boardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/archive',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ArchiveScreen(
          boardId: state.uri.queryParameters['boardId'],
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0,
        ),
      ),
      GoRoute(
        path: '/invite/:token',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => InviteAcceptScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: '/feed',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const UpdateFeedScreen(),
      ),
      GoRoute(
        path: '/boards/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => BoardScreen(boardId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/items/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/boards-new',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const CreateBoardScreen(),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/members',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const MembersScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SettingsScreen(),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/my-work', builder: (context, state) => const MyWorkScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notifications', builder: (context, state) => const NotificationsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (context, state) => const MoreScreen()),
          ]),
        ],
      ),
    ],
  );
});
