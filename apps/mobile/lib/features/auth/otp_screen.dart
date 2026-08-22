import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_otp_input.dart';
import 'signup_flow_state.dart';

/// "We've sent you an email" — 6-digit verification with resend cooldown.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpKey = GlobalKey<DfOtpInputState>();
  bool _verifying = false;
  bool _hasError = false;
  String? _errorMessage;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn -= 1);
      }
    });
  }

  Future<void> _verify(String code) async {
    final flow = ref.read(signupFlowProvider);
    setState(() {
      _verifying = true;
      _hasError = false;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).verifyOtp(flow.email, code);
      if (!mounted) return;
      switch (result) {
        case OtpNewUser(:final signupToken):
          ref.read(signupFlowProvider.notifier).update((s) => s.copyWith(signupToken: signupToken));
          context.pushReplacement('/auth/create');
        case OtpExistingUser(:final selectToken, :final accounts):
          ref
              .read(signupFlowProvider.notifier)
              .update((s) => s.copyWith(selectToken: selectToken, accounts: accounts));
          if (accounts.length == 1) {
            final me = await ref
                .read(authRepositoryProvider)
                .selectAccount(selectToken: selectToken, accountId: accounts.first.id);
            ref.read(authControllerProvider.notifier).signedIn(me);
          } else {
            context.pushReplacement('/auth/accounts');
          }
      }
    } on ApiException catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.message;
      });
      _otpKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    final flow = ref.read(signupFlowProvider);
    try {
      final result =
          await ref.read(authRepositoryProvider).requestOtp(flow.email, signup: flow.isSignup);
      ref.read(signupFlowProvider.notifier).update((s) => s.copyWith(devCode: result.devCode));
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
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
            Text("We've sent you an email", textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: DfSpacing.xs),
            Text(
              'Please enter the verification code we sent to\n${flow.email}',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: DfSpacing.xxl),
            DfOtpInput(key: _otpKey, onCompleted: _verify, enabled: !_verifying, hasError: _hasError),
            if (_errorMessage != null) ...[
              const SizedBox(height: DfSpacing.sm),
              Text(_errorMessage!,
                  textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: DfColors.danger)),
            ],
            if (flow.devCode != null) ...[
              const SizedBox(height: DfSpacing.sm),
              Text('Dev code: ${flow.devCode}',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: DfColors.textTertiary)),
            ],
            const SizedBox(height: DfSpacing.xl),
            if (_verifying)
              const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
            else
              DfButton(
                label: _resendIn > 0 ? "Didn't get an email? Send again (${_resendIn}s)" : 'Send the code again',
                variant: DfButtonVariant.text,
                onPressed: _resendIn > 0 ? null : _resend,
              ),
          ],
        ),
      ),
    );
  }
}
