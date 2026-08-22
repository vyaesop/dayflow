import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import '../home/home_providers.dart';
import 'board_controller.dart';

const _templateIcons = <String, IconData>{
  'grid': Icons.grid_view_rounded,
  'check': Icons.check_circle_outline_rounded,
  'calendar': Icons.calendar_month_rounded,
  'briefcase': Icons.business_center_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'inbox': Icons.inbox_outlined,
};

/// Template gallery + name entry, then creates the board and opens it.
class CreateBoardScreen extends ConsumerStatefulWidget {
  const CreateBoardScreen({super.key});

  @override
  ConsumerState<CreateBoardScreen> createState() => _CreateBoardScreenState();
}

class _CreateBoardScreenState extends ConsumerState<CreateBoardScreen> {
  final _name = TextEditingController();
  String _selectedTemplate = 'blank';
  String? _workspaceId;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final boardId = await ref.read(boardRepositoryProvider).createBoard(
            name: name,
            template: _selectedTemplate,
            workspaceId: _workspaceId,
          );
      // The new board changes Home's lists and the setup checklist.
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
      final me = await ref.read(authRepositoryProvider).fetchMe();
      ref.read(authControllerProvider.notifier).updateMe(me);

      if (!mounted) return;
      context.pushReplacement('/boards/$boardId');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        showDfToast(context, e.message, icon: Icons.error_outline_rounded);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider);
    final workspaces = ref.watch(workspacesProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New board'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(DfSpacing.md),
          children: [
            DfTextField(
              controller: _name,
              label: 'Board name',
              hint: 'e.g. Campaign tracker',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _name.text.trim().isEmpty || _creating ? null : _create(),
            ),
            const SizedBox(height: DfSpacing.md),
            workspaces.maybeWhen(
              data: (list) => list.length < 2
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: DfSpacing.md),
                      child: DropdownButtonFormField<String>(
                        initialValue: _workspaceId ?? list.first.id,
                        decoration: const InputDecoration(labelText: 'Workspace'),
                        items: [
                          for (final workspace in list)
                            DropdownMenuItem(value: workspace.id, child: Text(workspace.name)),
                        ],
                        onChanged: (value) => setState(() => _workspaceId = value),
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            Text('Start from a template', style: text.titleMedium),
            const SizedBox(height: DfSpacing.xs),
            templates.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(DfSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: DfSpacing.md),
                child: Column(children: [
                  Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
                  const SizedBox(height: DfSpacing.sm),
                  DfButton(
                    label: 'Try again',
                    variant: DfButtonVariant.tonal,
                    expand: false,
                    onPressed: () => ref.invalidate(templatesProvider),
                  ),
                ]),
              ),
              data: (list) => Column(children: [
                for (final template in list)
                  _TemplateCard(
                    template: template,
                    selected: template.key == _selectedTemplate,
                    onTap: () => setState(() => _selectedTemplate = template.key),
                  ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: DfButton(
            label: 'Create board',
            loading: _creating,
            onPressed: _name.text.trim().isEmpty ? null : _create,
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.selected, required this.onTap});

  final BoardTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = DfColors.token(template.accentColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: Material(
        color: selected
            ? (isDark ? DfColors.primary.withValues(alpha: 0.18) : DfColors.primarySubtle)
            : (isDark ? DfColors.surfaceDark : DfColors.surface),
        borderRadius: BorderRadius.circular(DfRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DfRadius.md),
          child: Container(
            padding: const EdgeInsets.all(DfSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DfRadius.md),
              border: Border.all(
                color: selected ? DfColors.primary : (isDark ? DfColors.borderDark : DfColors.border),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(DfRadius.sm),
                ),
                child: Icon(_templateIcons[template.icon] ?? Icons.grid_view_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: DfSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(template.name, style: text.titleMedium),
                  Text(template.description, style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    '${template.columnCount} columns · ${template.groupCount} groups',
                    style: text.labelSmall,
                  ),
                ]),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: DfColors.primary),
            ]),
          ),
        ),
      ),
    );
  }
}
