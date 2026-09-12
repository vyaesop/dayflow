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

/// The three board privacy levels (matching the monday.com model).
const boardTypeOptions = <({String key, String label, String description, IconData icon})>[
  (
    key: 'main',
    label: 'Main',
    description: 'Visible to everyone in your account',
    icon: Icons.public_rounded,
  ),
  (
    key: 'private',
    label: 'Private',
    description: 'Only people you invite can see it',
    icon: Icons.lock_outline_rounded,
  ),
  (
    key: 'shareable',
    label: 'Shareable',
    description: 'Invite-only — the board type guests can join',
    icon: Icons.link_rounded,
  ),
];

/// Template gallery + name entry, then creates the board and opens it.
class CreateBoardScreen extends ConsumerStatefulWidget {
  const CreateBoardScreen({super.key});

  @override
  ConsumerState<CreateBoardScreen> createState() => _CreateBoardScreenState();
}

class _CreateBoardScreenState extends ConsumerState<CreateBoardScreen> {
  final _name = TextEditingController();
  String _selectedTemplate = 'blank';
  String _type = 'main';
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
            type: _type,
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

  Future<void> _deleteTemplate(BoardTemplate template) async {
    final id = template.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete template "${template.name}"?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          'Boards already created from it are not affected.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: DfColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(boardRepositoryProvider).deleteTemplate(id);
      ref.invalidate(templatesProvider);
      if (!mounted) return;
      if (_selectedTemplate == template.key) setState(() => _selectedTemplate = 'blank');
      showDfToast(context, 'Template deleted');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
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
            Text('Privacy', style: text.titleMedium),
            const SizedBox(height: DfSpacing.xs),
            for (final option in boardTypeOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                child: _TypeCard(
                  option: option,
                  selected: option.key == _type,
                  onTap: () => setState(() => _type = option.key),
                ),
              ),
            const SizedBox(height: DfSpacing.sm),
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
              data: (list) {
                final builtIn = list.where((t) => !t.isCustom).toList();
                final custom = list.where((t) => t.isCustom).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final template in builtIn)
                    _TemplateCard(
                      template: template,
                      selected: template.key == _selectedTemplate,
                      onTap: () => setState(() => _selectedTemplate = template.key),
                    ),
                  if (custom.isNotEmpty) ...[
                    const SizedBox(height: DfSpacing.sm),
                    Text('Your templates', style: text.titleMedium),
                    Text('Saved from boards in this account', style: text.bodySmall),
                    const SizedBox(height: DfSpacing.xs),
                    for (final template in custom)
                      _TemplateCard(
                        template: template,
                        selected: template.key == _selectedTemplate,
                        onTap: () => setState(() => _selectedTemplate = template.key),
                        onDelete: () => _deleteTemplate(template),
                      ),
                  ],
                ]);
              },
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

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.option, required this.selected, required this.onTap});

  final ({String key, String label, String description, IconData icon}) option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: selected
          ? (isDark ? DfColors.primary.withValues(alpha: 0.18) : DfColors.primarySubtle)
          : (isDark ? DfColors.surfaceDark : DfColors.surface),
      borderRadius: BorderRadius.circular(DfRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DfRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DfRadius.md),
            border: Border.all(
              color: selected ? DfColors.primary : (isDark ? DfColors.borderDark : DfColors.border),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(option.icon, size: 20, color: selected ? DfColors.primary : DfColors.textSecondary),
            const SizedBox(width: DfSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(option.label, style: text.titleSmall),
                Text(option.description, style: text.bodySmall),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: DfColors.primary, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.selected, required this.onTap, this.onDelete});

  final BoardTemplate template;
  final bool selected;
  final VoidCallback onTap;

  /// Custom templates only: offered via long-press and the ⋮ menu.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = DfColors.token(template.accentColor);
    final meta = StringBuffer('${template.columnCount} columns · ${template.groupCount} groups');
    if (template.isCustom) {
      meta.write(' · ${template.itemCount} item${template.itemCount == 1 ? '' : 's'}');
      if (template.createdByName != null && template.createdByName!.isNotEmpty) {
        meta.write(' · by ${template.createdByName}');
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: Material(
        color: selected
            ? (isDark ? DfColors.primary.withValues(alpha: 0.18) : DfColors.primarySubtle)
            : (isDark ? DfColors.surfaceDark : DfColors.surface),
        borderRadius: BorderRadius.circular(DfRadius.md),
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
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
                  Row(children: [
                    Flexible(
                      child: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                    ),
                    if (template.isCustom)
                      Padding(
                        padding: const EdgeInsets.only(left: DfSpacing.xs),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Custom',
                            style: text.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ]),
                  if (template.description.isNotEmpty)
                    Text(template.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(meta.toString(), style: text.labelSmall),
                ]),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: DfColors.primary),
              if (onDelete != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  tooltip: 'Template options',
                  onSelected: (_) => onDelete!(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete template', style: TextStyle(color: DfColors.danger)),
                    ),
                  ],
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
