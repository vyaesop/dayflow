import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../auth/signup_flow_state.dart';

class _Option {
  const _Option(this.key, this.label);
  final String key;
  final String label;
}

const _useForOptions = [
  _Option('work', 'Work'),
  _Option('personal', 'Personal'),
  _Option('school', 'School'),
];

const _manageOptions = [
  _Option('more_workflows', 'More Workflows'),
  _Option('construction', 'Construction'),
  _Option('operations', 'Operations'),
  _Option('product_management', 'Product management'),
  _Option('hr_recruiting', 'HR and Recruiting'),
];

const _workOptions = [
  _Option('task_management', 'Task management'),
  _Option('business_operations', 'Business operations'),
  _Option('client_projects', 'Client projects'),
  _Option('content_calendar', 'Content calendar'),
  _Option('event_management', 'Event management'),
  _Option('digital_asset_management', 'Digital asset management'),
  _Option('requests_and_approvals', 'Requests and approvals'),
  _Option('resource_management', 'Resource management'),
  _Option('portfolio_management', 'Portfolio management'),
  _Option('goals_and_strategy', 'Goals and strategy'),
];

/// Three persona questions with animated transitions; the last step creates
/// the account server-side and signs the user in.
class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  @override
  ConsumerState<OnboardingWizardScreen> createState() => _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends ConsumerState<OnboardingWizardScreen> {
  int _step = 0;
  bool _creating = false;

  Future<void> _createAccount() async {
    final flow = ref.read(signupFlowProvider);
    setState(() => _creating = true);
    try {
      final me = await ref.read(authRepositoryProvider).completeSignup(
            signupToken: flow.signupToken!,
            fullName: flow.fullName,
            password: flow.password,
            useFor: flow.useFor,
            manageCategory: flow.manageCategory,
            workCategory: flow.workCategory,
          );
      ref.read(signupFlowProvider.notifier).reset();
      ref.read(authControllerProvider.notifier).signedIn(me, isFirstRun: true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _selectAndAdvance(void Function(SignupFlowNotifier) apply) {
    apply(ref.read(signupFlowProvider.notifier));
    if (_step < 2) {
      setState(() => _step += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(signupFlowProvider);
    final text = Theme.of(context).textTheme;

    final (Widget title, List<_Option> options, String? selectedKey) = switch (_step) {
      0 => (
          Text.rich(
            TextSpan(children: [
              TextSpan(text: "I'm here for ", style: text.headlineSmall),
              TextSpan(text: '________', style: text.headlineSmall?.copyWith(color: DfColors.textTertiary)),
            ]),
            textAlign: TextAlign.center,
          ),
          _useForOptions,
          flow.useFor,
        ),
      1 => (
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'I want to manage ', style: text.headlineSmall),
              TextSpan(text: '________', style: text.headlineSmall?.copyWith(color: DfColors.textTertiary)),
            ]),
            textAlign: TextAlign.center,
          ),
          _manageOptions,
          flow.manageCategory,
        ),
      _ => (
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'I want to manage ${_label(_manageOptions, flow.manageCategory)}',
                  style: text.headlineSmall?.copyWith(decoration: TextDecoration.underline)),
              TextSpan(text: '\nand I mainly work on ', style: text.headlineSmall),
              TextSpan(
                text: flow.workCategory == null ? '________' : _label(_workOptions, flow.workCategory),
                style: flow.workCategory == null
                    ? text.headlineSmall?.copyWith(color: DfColors.textTertiary)
                    : text.headlineSmall?.copyWith(decoration: TextDecoration.underline),
              ),
            ]),
            textAlign: TextAlign.center,
          ),
          _workOptions,
          flow.workCategory,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          if (_step > 0) {
            setState(() => _step -= 1);
          } else {
            context.pop();
          }
        }),
        title: SizedBox(
          width: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (_step + 2) / 4),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: DfColors.primarySubtle,
                color: DfColors.primary,
              ),
            ),
          ),
        ),
        actions: [
          if (_step == 0)
            TextButton(
              onPressed: _creating ? null : _createAccount,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xl, vertical: DfSpacing.md),
                children: [
                  title,
                  const SizedBox(height: DfSpacing.xl),
                  for (final option in options) ...[
                    _OptionCard(
                      label: option.label,
                      selected: selectedKey == option.key,
                      onTap: _creating
                          ? null
                          : () => _selectAndAdvance((n) => n.update((s) => switch (_step) {
                                0 => s.copyWith(useFor: option.key),
                                1 => s.copyWith(manageCategory: option.key),
                                _ => s.copyWith(workCategory: option.key),
                              })),
                    ),
                    const SizedBox(height: DfSpacing.sm),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DfSpacing.xl, 0, DfSpacing.xl, DfSpacing.md),
            child: Column(children: [
              Text(
                'By signing up you agree to the Terms of Use and Privacy Policy',
                textAlign: TextAlign.center,
                style: text.labelSmall,
              ),
              if (_step == 2) ...[
                const SizedBox(height: DfSpacing.sm),
                DfButton(
                  label: 'Create your account',
                  loading: _creating,
                  onPressed: flow.workCategory != null ? _createAccount : null,
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  String _label(List<_Option> options, String? key) =>
      options.firstWhere((o) => o.key == key, orElse: () => const _Option('', '________')).label;
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected
            ? (isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle)
            : (isDark ? DfColors.surfaceDark : DfColors.surface),
        borderRadius: BorderRadius.circular(DfRadius.md),
        border: Border.all(
          color: selected ? DfColors.primary : (isDark ? DfColors.borderDark : DfColors.border),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DfRadius.md),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: selected ? DfColors.primary : null,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
