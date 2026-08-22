import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import 'members_providers.dart';

const _roles = <({String key, String label, String blurb})>[
  (key: 'admin', label: 'Admin', blurb: 'Full access, can manage members'),
  (key: 'member', label: 'Member', blurb: 'Can create and edit boards'),
  (key: 'viewer', label: 'Viewer', blurb: 'Read-only access'),
];

/// Account members and pending invitations.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberDirectoryProvider);
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth is SignedIn && auth.me.account.role == 'admin';
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_rounded),
              tooltip: 'Invite',
              onPressed: () => _showInviteSheet(context, ref),
            ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
              const SizedBox(height: DfSpacing.sm),
              Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
              const SizedBox(height: DfSpacing.md),
              DfButton(
                label: 'Try again',
                variant: DfButtonVariant.tonal,
                expand: false,
                onPressed: () => ref.invalidate(memberDirectoryProvider),
              ),
            ]),
          ),
        ),
        data: (directory) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(memberDirectoryProvider);
            await ref.read(memberDirectoryProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(DfSpacing.md),
            children: [
              Text('${directory.members.length} member(s)', style: text.labelMedium),
              const SizedBox(height: DfSpacing.xs),
              for (final member in directory.members)
                _MemberTile(member: member, canManage: isAdmin),
              if (directory.invitations.isNotEmpty) ...[
                const SizedBox(height: DfSpacing.md),
                Text('Pending invitations', style: text.labelMedium),
                const SizedBox(height: DfSpacing.xs),
                for (final invite in directory.invitations) _InviteTile(invite: invite),
              ],
              if (isAdmin) ...[
                const SizedBox(height: DfSpacing.md),
                DfButton(
                  label: 'Invite teammates',
                  variant: DfButtonVariant.tonal,
                  icon: const Icon(Icons.person_add_alt_rounded, size: 20),
                  onPressed: () => _showInviteSheet(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: const _InviteSheet(),
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet();

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _email = TextEditingController();
  String _role = 'member';
  bool _sending = false;
  String? _error;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final invite = await ref.read(membersRepositoryProvider).invite(email: email, role: _role);
      ref.invalidate(memberDirectoryProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showDfToast(context, 'Invitation sent to ${invite.email}');
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _emailRegex.hasMatch(_email.text.trim());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: DfSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Invite a teammate', style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: DfSpacing.sm),
          DfTextField(
            controller: _email,
            label: 'Email address',
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            errorText: _error,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DfSpacing.sm),
          RadioGroup<String>(
            groupValue: _role,
            onChanged: (value) => setState(() => _role = value ?? 'member'),
            child: Column(children: [
              for (final role in _roles)
                RadioListTile<String>(
                  value: role.key,
                  title: Text(role.label, style: Theme.of(context).textTheme.titleSmall),
                  subtitle: Text(role.blurb, style: Theme.of(context).textTheme.bodySmall),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ]),
          ),
          const SizedBox(height: DfSpacing.xs),
          DfButton(
            label: 'Send invitation',
            loading: _sending,
            onPressed: valid ? _send : null,
          ),
        ]),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.canManage});

  final AccountMember member;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        child: Row(children: [
          DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 40),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    member.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                ),
                if (member.isYou)
                  Padding(
                    padding: const EdgeInsets.only(left: DfSpacing.xxs),
                    child: Text('(you)', style: text.labelSmall),
                  ),
              ]),
              Text(member.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            ]),
          ),
          DfStatusPill(
            label: member.role,
            colorToken: switch (member.role) {
              'admin' => 'indigo',
              'member' => 'blue',
              _ => 'grey',
            },
            height: 22,
          ),
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (action) async {
                if (action == 'remove') {
                  final confirmed = await _confirmRemoval(context, member);
                  if (!confirmed || !context.mounted) return;
                  await _run(context, () => ref.read(membersRepositoryProvider).remove(member.userId));
                } else {
                  await _run(
                    context,
                    () => ref
                        .read(membersRepositoryProvider)
                        .changeRole(userId: member.userId, role: action),
                  );
                }
                ref.invalidate(memberDirectoryProvider);
              },
              itemBuilder: (context) => [
                for (final role in _roles)
                  if (role.key != member.role)
                    PopupMenuItem(value: role.key, child: Text('Make ${role.label.toLowerCase()}')),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from account', style: TextStyle(color: DfColors.danger)),
                ),
              ],
            ),
        ]),
      ),
    );
  }

  Future<bool> _confirmRemoval(BuildContext context, AccountMember member) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.fullName}?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          'They lose access to this account. Their items and updates stay.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove', style: TextStyle(color: DfColors.danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _InviteTile extends ConsumerWidget {
  const _InviteTile({required this.invite});

  final PendingInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DfColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.mail_outline_rounded, color: DfColors.textSecondary, size: 20),
          ),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(invite.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
              Text('Invited as ${invite.role} · pending', style: text.bodySmall),
            ]),
          ),
          // Without a mail provider configured the link is the only way in, so
          // make it copyable during development.
          if (invite.devLink != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy invite link',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.devLink!));
                if (context.mounted) showDfToast(context, 'Invite link copied');
              },
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.danger),
            tooltip: 'Revoke',
            onPressed: () async {
              await _run(context, () => ref.read(membersRepositoryProvider).revokeInvite(invite.id));
              ref.invalidate(memberDirectoryProvider);
            },
          ),
        ]),
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (e) {
    if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
  }
}
