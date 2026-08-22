import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_text_field.dart';
import 'signup_flow_state.dart';

/// Password log-in for an existing account, with a fallback to email codes.
class PasswordLoginScreen extends ConsumerStatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  ConsumerState<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends ConsumerState<PasswordLoginScreen> {
  final _password = TextEditingController();
  bool _loading = false;
  bool _sendingCode = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final flow = ref.read(signupFlowProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).passwordLogin(flow.email, _password.text);
      if (!mounted) return;
      switch (result) {
        case PasswordLoginSignedIn(:final me):
          ref.read(authControllerProvider.notifier).signedIn(me);
        case PasswordLoginChooseAccount(:final selectToken, :final accounts):
          ref
              .read(signupFlowProvider.notifier)
              .update((s) => s.copyWith(selectToken: selectToken, accounts: accounts));
          context.pushReplacement('/auth/accounts');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Falls back to the one-time-code flow for users without a password.
  Future<void> _emailACode() async {
    final flow = ref.read(signupFlowProvider);
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).requestOtp(flow.email, signup: false);
      ref.read(signupFlowProvider.notifier).update((s) => s.copyWith(devCode: result.devCode));
      if (mounted) context.push('/auth/otp');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    final text = Theme.of(context).textTheme;
    final canSubmit = _password.text.isNotEmpty && !_loading;

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl, vertical: DfSpacing.md),
          children: [
            Text('Enter your password', textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: DfSpacing.xs),
            Text(
              'Logging in as\n${flow.email}',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: DfSpacing.xxl),
            DfTextField(
              controller: _password,
              label: 'Password',
              obscure: true,
              autofocus: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              errorText: _error,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => canSubmit ? _login() : null,
            ),
            const SizedBox(height: DfSpacing.md),
            DfButton(label: 'Log in', loading: _loading, onPressed: canSubmit ? _login : null),
            const SizedBox(height: DfSpacing.xs),
            DfButton(
              label: 'Email me a one-time code instead',
              variant: DfButtonVariant.text,
              loading: _sendingCode,
              onPressed: _loading ? null : _emailACode,
            ),
          ],
        ),
      ),
    );
  }
}
