import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_misc.dart';
import 'signup_flow_state.dart';

/// "Choose an account to log in" — shown when the email maps to several accounts.
class AccountPickerScreen extends ConsumerStatefulWidget {
  const AccountPickerScreen({super.key});

  @override
  ConsumerState<AccountPickerScreen> createState() => _AccountPickerScreenState();
}

class _AccountPickerScreenState extends ConsumerState<AccountPickerScreen> {
  String? _selectingId;

  Future<void> _select(AccountSummary account) async {
    final flow = ref.read(signupFlowProvider);
    final token = flow.selectToken;
    if (token == null || _selectingId != null) return;
    setState(() => _selectingId = account.id);
    try {
      final me =
          await ref.read(authRepositoryProvider).selectAccount(selectToken: token, accountId: account.id);
      ref.read(authControllerProvider.notifier).signedIn(me);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _selectingId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl, vertical: DfSpacing.md),
          children: [
            Text('Choose an account to log in', textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: DfSpacing.xs),
            Text(
              "We've found several accounts linked to\n${flow.email}",
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: DfSpacing.xl),
            for (final account in flow.accounts) ...[
              DfCard(
                onTap: () => _select(account),
                child: Row(children: [
                  DfAvatar(name: account.name, seed: account.id, size: 40),
                  const SizedBox(width: DfSpacing.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(account.slug, style: text.titleMedium),
                      if (account.lastUsedAt != null)
                        Text('Last used: ${_relative(account.lastUsedAt!)}', style: text.bodySmall),
                    ]),
                  ),
                  if (_selectingId == account.id)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    const Icon(Icons.chevron_right_rounded, color: DfColors.textTertiary),
                ]),
              ),
              const SizedBox(height: DfSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  String _relative(DateTime time) {
    final delta = DateTime.now().difference(time);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} minutes ago';
    if (delta.inHours < 24) return '${delta.inHours} hours ago';
    if (delta.inDays < 2) return 'yesterday';
    return DateFormat.yMMMd().format(time);
  }
}
