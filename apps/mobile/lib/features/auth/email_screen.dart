import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_text_field.dart';
import 'signup_flow_state.dart';

/// "Create new account" / "Log in" — Google/Apple buttons + email entry.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key, required this.isSignup});

  final bool isSignup;

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  bool _valid = false;
  bool _loading = false;
  String? _error;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Log in goes to the password screen (no code spent); sign up needs an OTP
  /// to prove the address before an account is created.
  Future<void> _continue() async {
    final email = _email.text.trim();
    ref.read(signupFlowProvider.notifier).start(email: email, isSignup: widget.isSignup);

    if (!widget.isSignup) {
      context.push('/auth/password');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).requestOtp(email, signup: true);
      ref.read(signupFlowProvider.notifier).update((s) => s.copyWith(devCode: result.devCode));
      if (mounted) context.push('/auth/otp');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isSignup ? 'Create new account' : 'Log in to your account';
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, size: 22),
            tooltip: 'Help',
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl, vertical: DfSpacing.md),
          children: [
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: DfSpacing.xxl),
            DfButton(
              label: widget.isSignup ? 'Sign up with Google' : 'Log in with Google',
              icon: const _GoogleG(),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Google sign-in will be enabled once a client ID is configured.')),
              ),
            ),
            const SizedBox(height: DfSpacing.sm),
            DfButton(
              label: widget.isSignup ? 'Sign up with Apple' : 'Log in with Apple',
              variant: DfButtonVariant.outline,
              icon: const Icon(Icons.apple_rounded, size: 22),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sign in with Apple is coming soon.')),
              ),
            ),
            const SizedBox(height: DfSpacing.xl),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
                child: Text('or', style: Theme.of(context).textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: DfSpacing.xl),
            DfTextField(
              controller: _email,
              label: 'Email address',
              hint: 'Enter your work email address',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              errorText: _error,
              autofocus: true,
              onChanged: (v) => setState(() => _valid = _emailRegex.hasMatch(v.trim())),
              onSubmitted: (_) => _valid && !_loading ? _continue() : null,
            ),
            const SizedBox(height: DfSpacing.md),
            DfButton(
              label: widget.isSignup ? 'Create account' : 'Continue with email',
              loading: _loading,
              onPressed: _valid ? _continue : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal Google "G" in brand colors (no external asset needed).
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          fontVariations: [FontVariation('wght', 800)],
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
