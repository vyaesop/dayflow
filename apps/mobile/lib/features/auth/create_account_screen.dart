import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_text_field.dart';
import 'signup_flow_state.dart';

/// "Let's create your account" — full name + password, then the persona wizard.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();

  bool get _valid => _name.text.trim().isNotEmpty && _password.text.length >= 8;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _next() {
    ref
        .read(signupFlowProvider.notifier)
        .update((s) => s.copyWith(fullName: _name.text.trim(), password: _password.text));
    context.push('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const _StepProgress(progress: 0.25),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl, vertical: DfSpacing.md),
          children: [
            Text("Let's create your account", textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: DfSpacing.xs),
            Text(
              'Enter your name and password to create an account for\n${flow.email}',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: DfSpacing.xxl),
            DfTextField(
              controller: _name,
              label: 'Your full name',
              autofocus: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: DfSpacing.md),
            DfTextField(
              controller: _password,
              label: 'Create password (8+ characters)',
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _valid ? _next() : null,
            ),
            const SizedBox(height: DfSpacing.xl),
            DfButton(label: 'Next', onPressed: _valid ? _next : null),
          ],
        ),
      ),
    );
  }
}

/// Thin onboarding progress bar shown in the app bar.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 160,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: DfColors.primarySubtle,
            color: DfColors.primary,
          ),
        ),
      ),
    );
  }
}
