import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import '../board/cell_editors.dart';
import '../members/members_providers.dart';

final notificationPrefsProvider = FutureProvider.autoDispose<NotificationPrefs>((ref) async {
  return NotificationPrefs.fromJson(await ApiClient.instance.get('/me/notification-prefs'));
});

const _personalStatuses = <({String? key, String label, IconData icon})>[
  (key: null, label: 'No status', icon: Icons.remove_circle_outline_rounded),
  (key: 'working_from_home', label: 'Working from home', icon: Icons.home_work_outlined),
  (key: 'out_sick', label: 'Out sick', icon: Icons.sick_outlined),
  (key: 'on_break', label: 'On a break', icon: Icons.coffee_outlined),
  (key: 'out_of_office', label: 'Out of office', icon: Icons.luggage_outlined),
  (key: 'working_outside', label: 'Working outside', icon: Icons.park_outlined),
  (key: 'family_time', label: 'Family time', icon: Icons.family_restroom_rounded),
  (key: 'do_not_disturb', label: 'Do not disturb', icon: Icons.do_not_disturb_on_outlined),
];

/// Editable profile plus account info and the account switcher.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _saving = false;

  Future<void> _patch(Map<String, dynamic> body) async {
    setState(() => _saving = true);
    try {
      final json = await ApiClient.instance.patch('/me', body: body);
      ref.read(authControllerProvider.notifier).updateMe(Me.fromJson(json));
      if (mounted) showDfToast(context, 'Saved');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editName(Me me) async {
    final name = await promptForText(context, title: 'Your name', initial: me.fullName);
    if (name == null || name.isEmpty || name == me.fullName) return;
    await _patch({'fullName': name});
  }

  Future<void> _uploadAvatar() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final json = await ApiClient.instance.postMultipart(
        '/me/avatar',
        bytes: file.bytes!,
        filename: file.name,
      );
      ref.read(authControllerProvider.notifier).updateMe(Me.fromJson(json));
      if (mounted) showDfToast(context, 'Profile photo updated');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Change password', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DfTextField(controller: current, label: 'Current password', obscure: true, autofocus: true),
          const SizedBox(height: DfSpacing.sm),
          DfTextField(controller: next, label: 'New password (8+ characters)', obscure: true),
          const SizedBox(height: DfSpacing.xs),
          Text(
            'Changing your password signs out your other sessions.',
            style: Theme.of(dialogContext).textTheme.labelSmall,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Change')),
        ],
      ),
    );
    if (confirmed != true) {
      current.dispose();
      next.dispose();
      return;
    }
    try {
      await ApiClient.instance.post('/auth/password/change', body: {
        'currentPassword': current.text,
        'newPassword': next.text,
      });
      if (mounted) showDfToast(context, 'Password changed');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      current.dispose();
      next.dispose();
    }
  }

  Future<void> _sendFeedback() async {
    final message = await promptForText(context, title: 'Send feedback', hint: "What's on your mind?");
    if (message == null || message.isEmpty) return;
    try {
      await ApiClient.instance.post('/me/feedback', body: {'message': message});
      if (mounted) showDfToast(context, 'Your request was sent');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _toggleNotificationPref({bool? email, bool? push}) async {
    try {
      await ApiClient.instance.patch('/me/notification-prefs', body: {
        'emailEnabled': ?email,
        'pushEnabled': ?push,
      });
      ref.invalidate(notificationPrefsProvider);
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _editStatus(Me me) async {
    final picked = await showModalBottomSheet<({String? key, String label, IconData icon})>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('Set your status', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final status in _personalStatuses)
              ListTile(
                leading: Icon(status.icon, color: DfColors.primary, size: 20),
                title: Text(status.label),
                trailing: status.key == me.personalStatus
                    ? const Icon(Icons.check_rounded, color: DfColors.primary)
                    : null,
                onTap: () => Navigator.pop(sheetContext, status),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _patch({'personalStatus': picked.key});
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final text = Theme.of(context).textTheme;

    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings'), leading: BackButton(onPressed: () => context.pop())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final status = _personalStatuses.where((s) => s.key == me.personalStatus).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: DfSpacing.md),
              child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(DfSpacing.md),
        children: [
          Center(
            child: Column(children: [
              // Tapping the avatar uploads a new photo (photos-from-device;
              // the design's selfie option needs a camera plugin).
              GestureDetector(
                onTap: _uploadAvatar,
                child: Stack(children: [
                  DfAvatar(name: me.fullName, seed: me.id, imageUrl: me.avatarUrl, size: 72),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: DfColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera_rounded, size: 12, color: Colors.white),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: DfSpacing.xs),
              Text(me.fullName, style: text.titleLarge),
              Text(me.email, style: text.bodySmall),
            ]),
          ),
          const SizedBox(height: DfSpacing.lg),
          Text('Profile', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          DfCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _EditRow(label: 'Name', value: me.fullName, onTap: () => _editName(me)),
              const Divider(height: 1),
              _EditRow(
                label: 'Status',
                value: status?.label ?? 'No status',
                onTap: () => _editStatus(me),
              ),
              const Divider(height: 1),
              _EditRow(label: 'Email', value: me.email, onTap: null),
              const Divider(height: 1),
              _EditRow(label: 'Password', value: 'Change', onTap: _changePassword),
            ]),
          ),
          const SizedBox(height: DfSpacing.md),
          Text('Notifications', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          Consumer(builder: (context, ref, _) {
            final prefs = ref.watch(notificationPrefsProvider);
            return DfCard(
              padding: EdgeInsets.zero,
              child: prefs.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(DfSpacing.md),
                  child: Center(
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(DfSpacing.md),
                  child: Text('$error', style: text.bodySmall),
                ),
                data: (p) => Column(children: [
                  SwitchListTile(
                    value: p.pushEnabled,
                    onChanged: (value) => _toggleNotificationPref(push: value),
                    title: Text('Push notifications', style: text.titleSmall),
                    subtitle: Text('Mentions, assignments and replies', style: text.bodySmall),
                    dense: true,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: p.emailEnabled,
                    onChanged: (value) => _toggleNotificationPref(email: value),
                    title: Text('Email notifications', style: text.titleSmall),
                    subtitle: Text('A summary when you are away', style: text.bodySmall),
                    dense: true,
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: DfSpacing.md),
          Text('Support', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          DfCard(
            padding: EdgeInsets.zero,
            child: _EditRow(label: 'Send feedback', value: '', onTap: _sendFeedback),
          ),
          const SizedBox(height: DfSpacing.md),
          Text('Account', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          DfCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _EditRow(label: 'Account', value: me.account.name, onTap: null),
              const Divider(height: 1),
              _EditRow(label: 'Your role', value: me.account.role, onTap: null),
              const Divider(height: 1),
              _EditRow(
                label: 'Members',
                value: 'Manage',
                onTap: () => context.push('/members'),
              ),
            ]),
          ),
          if (me.accounts.length > 1) ...[
            const SizedBox(height: DfSpacing.md),
            Text('Switch account', style: text.labelMedium),
            const SizedBox(height: DfSpacing.xs),
            for (final account in me.accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                child: DfCard(
                  padding: const EdgeInsets.all(DfSpacing.sm),
                  onTap: account.id == me.account.id
                      ? null
                      : () async {
                          await ref.read(authControllerProvider.notifier).switchAccount(account.id);
                          ref.invalidate(memberDirectoryProvider);
                          if (context.mounted) showDfToast(context, 'Switched to ${account.name}');
                        },
                  child: Row(children: [
                    DfAvatar(name: account.name, seed: account.id, size: 36),
                    const SizedBox(width: DfSpacing.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(account.name, style: text.titleMedium),
                        Text(account.role, style: text.labelSmall),
                      ]),
                    ),
                    if (account.id == me.account.id)
                      const Icon(Icons.check_circle_rounded, color: DfColors.primary),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: DfSpacing.lg),
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

class _EditRow extends StatelessWidget {
  const _EditRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
        child: Row(children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: DfSpacing.xxs),
              child: Icon(Icons.chevron_right_rounded, size: 18, color: DfColors.textTertiary),
            ),
        ]),
      ),
    );
  }
}
