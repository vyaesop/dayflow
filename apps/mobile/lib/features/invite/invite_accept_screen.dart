import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_logo.dart';
import '../members/members_providers.dart';
import 'invite_providers.dart';

/// Landing screen for an invite deep link (`dayflow:///invite/<token>`).
///
/// Only reachable signed-in (the router stashes the token and routes through
/// auth first otherwise). Accepts the invitation, switches into the new
/// account, and hands off to Home.
class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  String? _joinedAccountName;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _accept();
  }

  Future<void> _accept() async {
    // Whatever happens, this token is spent from the app's point of view.
    ref.read(pendingInviteProvider.notifier).clear();
    try {
      final result = await ref.read(membersRepositoryProvider).accept(widget.token);
      await ref.read(authControllerProvider.notifier).switchAccount(result.accountId);
      ref.invalidate(memberDirectoryProvider);
      if (mounted) {
        setState(() {
          _joinedAccountName = result.accountName;
          _busy = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const DfLogoMark(size: 56),
                const SizedBox(height: DfSpacing.lg),
                if (_busy) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: DfSpacing.md),
                  Text('Joining the team…', style: text.titleMedium),
                ] else if (_error != null) ...[
                  const Icon(Icons.error_outline_rounded, size: 40, color: DfColors.danger),
                  const SizedBox(height: DfSpacing.sm),
                  Text('This invitation could not be used', style: text.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: DfSpacing.xxs),
                  Text(_error!, style: text.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: DfSpacing.lg),
                  DfButton(label: 'Go to Home', onPressed: () => context.go('/home')),
                ] else ...[
                  const Icon(Icons.check_circle_rounded, size: 40, color: DfColors.primary),
                  const SizedBox(height: DfSpacing.sm),
                  Text(
                    _joinedAccountName == null || _joinedAccountName!.isEmpty
                        ? 'You joined the team!'
                        : 'Welcome to $_joinedAccountName!',
                    style: text.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: DfSpacing.xxs),
                  Text('You are all set — the team\'s boards are waiting.',
                      style: text.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: DfSpacing.lg),
                  DfButton(label: 'Take me there', onPressed: () => context.go('/home')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
