import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import 'members_providers.dart';

/// Account roles offered for invites and role changes, in display order.
const memberRoles = <({String key, String label, String blurb})>[
  (key: 'admin', label: 'Admin', blurb: 'Full access, can manage members'),
  (key: 'member', label: 'Member', blurb: 'Can create and edit boards'),
  (key: 'viewer', label: 'Viewer', blurb: 'Read-only access'),
  (key: 'guest', label: 'Guest', blurb: "Only sees shareable boards they're added to"),
];

/// Active members first (in server order), deactivated ones last.
List<AccountMember> sortMembers(List<AccountMember> members) => [
      ...members.where((m) => m.status == 'active'),
      ...members.where((m) => m.status != 'active'),
    ];

enum _MemberAction { changeRole, deactivate, reactivate, remove }

/// Account members and pending invitations.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(memberDirectoryProvider);
    final isAdmin = ref.watch(canManageMembersProvider);
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
        data: (directory) {
          final members = sortMembers(directory.members);
          final deactivated = members.where((m) => m.status != 'active').length;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberDirectoryProvider);
              await ref.read(memberDirectoryProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(DfSpacing.md),
              children: [
                Text(
                  deactivated == 0
                      ? '${members.length} member(s)'
                      : '${members.length - deactivated} active · $deactivated deactivated',
                  style: text.labelMedium,
                ),
                const SizedBox(height: DfSpacing.xs),
                for (final member in members) _MemberTile(member: member, canManage: isAdmin),
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
          );
        },
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

/// Radio list of [memberRoles]; used by the invite sheet and the role picker.
class _RoleRadios extends StatelessWidget {
  const _RoleRadios({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RadioGroup<String>(
      groupValue: value,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      child: Column(children: [
        for (final role in memberRoles)
          RadioListTile<String>(
            value: role.key,
            title: Text(role.label, style: text.titleSmall),
            subtitle: Text(role.blurb, style: text.bodySmall),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
      ]),
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
          const _SheetHandle(),
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
          _RoleRadios(value: _role, onChanged: (role) => setState(() => _role = role)),
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

/// Picks a new account role for [member]; pops with the role or null.
class _RoleSheet extends StatefulWidget {
  const _RoleSheet({required this.member});

  final AccountMember member;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late String _role = widget.member.role;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const _SheetHandle(),
          const SizedBox(height: DfSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Change role', style: text.titleMedium),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.member.fullName, style: text.bodySmall),
          ),
          const SizedBox(height: DfSpacing.sm),
          _RoleRadios(value: _role, onChanged: (role) => setState(() => _role = role)),
          const SizedBox(height: DfSpacing.xs),
          DfButton(
            label: 'Save',
            onPressed: _role == widget.member.role ? null : () => Navigator.pop(context, _role),
          ),
        ]),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
      );
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member, required this.canManage});

  final AccountMember member;
  final bool canManage;

  bool get _inactive => member.status != 'active';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = _inactive ? 0.5 : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        child: Row(children: [
          Opacity(
            opacity: dim,
            child: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 40),
          ),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Opacity(
              opacity: dim,
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
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: dim,
              child: DfStatusPill(
                label: member.role,
                colorToken: switch (member.role) {
                  'admin' => 'indigo',
                  'member' => 'blue',
                  'guest' => 'amber',
                  _ => 'grey',
                },
                height: 22,
              ),
            ),
            if (_inactive)
              Padding(
                padding: const EdgeInsets.only(top: DfSpacing.xxs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
                  ),
                  child: Text('Deactivated', style: text.labelSmall),
                ),
              ),
          ]),
          // Admins manage everyone but themselves: the server refuses self-
          // deactivation and demoting the last admin, so don't offer it.
          if (canManage && !member.isYou)
            PopupMenuButton<_MemberAction>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              tooltip: 'Member options',
              onSelected: (action) => _handle(context, ref, action),
              itemBuilder: (context) => [
                const PopupMenuItem(value: _MemberAction.changeRole, child: Text('Change role')),
                if (_inactive)
                  const PopupMenuItem(value: _MemberAction.reactivate, child: Text('Reactivate'))
                else
                  const PopupMenuItem(value: _MemberAction.deactivate, child: Text('Deactivate')),
                const PopupMenuItem(
                  value: _MemberAction.remove,
                  child: Text('Remove from account', style: TextStyle(color: DfColors.danger)),
                ),
              ],
            ),
        ]),
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _MemberAction action) async {
    final repo = ref.read(membersRepositoryProvider);
    switch (action) {
      case _MemberAction.changeRole:
        final role = await showModalBottomSheet<String>(
          context: context,
          // Four roles plus header and button outgrow the default half-height sheet.
          isScrollControlled: true,
          builder: (sheetContext) => _RoleSheet(member: member),
        );
        if (role == null || !context.mounted) return;
        if (await _run(context, () => repo.changeRole(userId: member.userId, role: role)) && context.mounted) {
          final label = memberRoles.where((r) => r.key == role).firstOrNull?.label ?? role;
          showDfToast(context, '${member.fullName} is now $label');
        }
      case _MemberAction.deactivate:
        final confirmed = await _confirm(
          context,
          title: 'Deactivate ${member.fullName}?',
          body: "They won't be able to sign in to this account until reactivated. "
              'Their items and updates stay.',
          action: 'Deactivate',
        );
        if (!confirmed || !context.mounted) return;
        if (await _run(context, () => repo.deactivate(member.userId)) && context.mounted) {
          showDfToast(context, '${member.fullName} deactivated');
        }
      case _MemberAction.reactivate:
        if (await _run(context, () => repo.reactivate(member.userId)) && context.mounted) {
          showDfToast(context, '${member.fullName} reactivated');
        }
      case _MemberAction.remove:
        final confirmed = await _confirm(
          context,
          title: 'Remove ${member.fullName}?',
          body: 'They lose access to this account. Their items and updates stay.',
          action: 'Remove',
        );
        if (!confirmed || !context.mounted) return;
        if (await _run(context, () => repo.remove(member.userId)) && context.mounted) {
          showDfToast(context, '${member.fullName} removed');
        }
    }
    ref.invalidate(memberDirectoryProvider);
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(body, style: Theme.of(dialogContext).textTheme.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action, style: const TextStyle(color: DfColors.danger)),
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

/// Runs [action], toasting an API failure; returns whether it succeeded.
Future<bool> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    return false;
  }
}
