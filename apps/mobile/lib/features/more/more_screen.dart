import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import '../members/members_providers.dart';

/// "More" tab — profile header, shortcuts, sign out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('More'), centerTitle: false, titleSpacing: DfSpacing.md),
      body: ListView(
        padding: const EdgeInsets.all(DfSpacing.md),
        children: [
          if (me != null)
            DfCard(
              child: Row(children: [
                DfAvatar(name: me.fullName, seed: me.id, imageUrl: me.avatarUrl, size: 48),
                const SizedBox(width: DfSpacing.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me.fullName, style: text.titleMedium),
                    Text(me.email, style: text.bodySmall),
                    const SizedBox(height: DfSpacing.xxs),
                    Text('${me.account.name} · ${me.account.role}', style: text.labelSmall),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: DfSpacing.md),
          _MoreTile(
            icon: Icons.dynamic_feed_rounded,
            label: 'Update Feed',
            onTap: () => context.push('/feed'),
          ),
          _MoreTile(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: () => context.push('/search'),
          ),
          _MoreTile(
            icon: Icons.dashboard_customize_outlined,
            label: 'New board',
            onTap: () => context.push('/boards-new'),
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push('/settings'),
          ),
          _MoreTile(
            icon: Icons.people_outline_rounded,
            label: 'Members & invitations',
            onTap: () => context.push('/members'),
          ),
          _MoreTile(
            icon: Icons.mail_outline_rounded,
            label: 'Accept an invitation',
            onTap: () => _showAcceptInvite(context, ref),
          ),
          _MoreTile(
            icon: Icons.help_outline_rounded,
            label: 'Help & feedback',
            onTap: () => showDfToast(context, 'Support center coming soon', icon: Icons.help_outline_rounded),
          ),
          const SizedBox(height: DfSpacing.md),
          DfButton(
            label: 'Log out',
            variant: DfButtonVariant.danger,
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
    );
  }
}

/// Accepts an invitation by pasting its link or token.
///
/// Deep links (`dayflow://invite/<token>`) are not registered yet, so pasting
/// is the way in; the token is extracted from a full link or used verbatim.
void _showAcceptInvite(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Accept an invitation', style: Theme.of(dialogContext).textTheme.titleMedium),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Paste the invitation link you were sent.',
          style: Theme.of(dialogContext).textTheme.bodySmall,
        ),
        const SizedBox(height: DfSpacing.sm),
        DfTextField(controller: controller, hint: 'dayflow://invite/…', autofocus: true),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final raw = controller.text.trim();
            final token = raw.contains('/') ? raw.split('/').last : raw;
            Navigator.pop(dialogContext);
            if (token.isEmpty) return;
            try {
              final result = await ref.read(membersRepositoryProvider).accept(token);
              final me = await ref.read(authRepositoryProvider).fetchMe();
              ref.read(authControllerProvider.notifier).updateMe(me);
              if (context.mounted) {
                showDfToast(context, 'You joined ${result.accountName} as ${result.role}');
              }
            } on ApiException catch (e) {
              if (context.mounted) {
                showDfToast(context, e.message, icon: Icons.error_outline_rounded);
              }
            }
          },
          child: const Text('Join'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, size: 22, color: DfColors.textSecondary),
          const SizedBox(width: DfSpacing.sm),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          const Icon(Icons.chevron_right_rounded, color: DfColors.textTertiary),
        ]),
      ),
    );
  }
}

