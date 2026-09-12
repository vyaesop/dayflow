import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'board_controller.dart';
import 'cell_editors.dart' show promptForText;
import 'view_engine.dart';

/// In-memory working copy of the active view's config. Null means "show the
/// stored config as-is"; non-null means the person has tweaked filters,
/// sort, columns or colors without saving them to the view yet.
final workingViewConfigProvider = StateProvider.autoDispose.family<ViewConfig?, String>((ref, boardId) => null);

const viewTypes = <({String type, String label, IconData icon})>[
  (type: 'table', label: 'Table', icon: Icons.table_rows_outlined),
  (type: 'list', label: 'List', icon: Icons.view_list_outlined),
  (type: 'kanban', label: 'Kanban', icon: Icons.view_kanban_outlined),
  (type: 'calendar', label: 'Calendar', icon: Icons.calendar_month_outlined),
  (type: 'dashboard', label: 'Dashboard', icon: Icons.insert_chart_outlined_rounded),
];

IconData viewTypeIcon(String type) =>
    viewTypes.where((t) => t.type == type).firstOrNull?.icon ?? Icons.table_rows_outlined;

String viewTypeLabel(String type) => viewTypes.where((t) => t.type == type).firstOrNull?.label ?? type;

/// True for the view types the table screen renders in place.
bool isTableLikeView(String type) => type == 'table' || type == 'list';

/// Resolves the active view for a board: the chosen id when it still exists,
/// otherwise the default view (or null when the board has no views yet).
BoardView? resolveActiveView(BoardDetail board, String? activeViewId) =>
    board.views.where((v) => v.id == activeViewId).firstOrNull ?? board.defaultView;

/// Structural equality of two configs by their canonical JSON. Used to decide
/// whether the working copy differs from what the view stores.
bool viewConfigsEqual(ViewConfig a, ViewConfig b) => jsonDeepEquals(a.toJson(), b.toJson());

/// Deep equality over JSON-ish values (maps, lists, scalars).
bool jsonDeepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonDeepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

/// Where a non-table view lives, so the switcher can push to it.
String routeForView(String boardId, BoardView view) => switch (view.type) {
      'kanban' => '/boards/$boardId/kanban?viewId=${view.id}',
      'calendar' => '/boards/$boardId/calendar?viewId=${view.id}',
      'dashboard' => '/boards/$boardId/dashboard?viewId=${view.id}',
      _ => '/boards/$boardId',
    };

/// View switcher: every saved view with a type icon, the default star and a
/// check on the active one; long-press (or ⋮) for Rename / Duplicate / Set as
/// default / Delete; "+ New view" at the bottom.
///
/// [currentConfig] seeds a new table/list view so the working filters travel
/// with it.
Future<void> showViewSwitcherSheet(
  BuildContext context,
  WidgetRef ref, {
  required BoardDetail board,
  required String? activeViewId,
  required ViewConfig currentConfig,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ViewSwitcherSheet(
      boardId: board.id,
      activeViewId: activeViewId,
      currentConfig: currentConfig,
    ),
  );
}

class _ViewSwitcherSheet extends ConsumerWidget {
  const _ViewSwitcherSheet({required this.boardId, required this.activeViewId, required this.currentConfig});

  final String boardId;
  final String? activeViewId;
  final ViewConfig currentConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final board = ref.watch(boardControllerProvider(boardId)).value;
    if (board == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    final controller = ref.read(boardControllerProvider(boardId).notifier);
    final active = resolveActiveView(board, activeViewId);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Views', style: text.titleLarge)),
          if (board.canEdit)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: DfColors.primary),
              tooltip: 'New view',
              onPressed: () => _createView(context, ref, board, controller),
            ),
        ]),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (board.views.isEmpty)
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('No saved views yet. The table shows every item.', style: text.bodySmall),
            ),
          for (final view in board.views)
            ListTile(
              leading: Icon(
                viewTypeIcon(view.type),
                color: view.id == active?.id ? DfColors.primary : DfColors.textSecondary,
              ),
              title: Row(children: [
                Flexible(child: Text(view.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (view.isDefault) ...[
                  const SizedBox(width: DfSpacing.xxs),
                  const Icon(Icons.star_rounded, size: 16, color: DfColors.accentAmber),
                ],
              ]),
              subtitle: Text(viewTypeLabel(view.type)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (view.id == active?.id) const Icon(Icons.check_rounded, color: DfColors.primary),
                if (board.canEdit)
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    onPressed: () => _viewMenu(context, ref, board, controller, view),
                  ),
              ]),
              onTap: () => _open(context, ref, view),
              onLongPress: board.canEdit ? () => _viewMenu(context, ref, board, controller, view) : null,
            ),
          if (board.canEdit)
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: DfButton(
                label: 'New view',
                variant: DfButtonVariant.tonal,
                icon: const Icon(Icons.add_rounded, size: 20),
                onPressed: () => _createView(context, ref, board, controller),
              ),
            ),
        ]),
      ),
    ]);
  }

  void _open(BuildContext context, WidgetRef ref, BoardView view) {
    Navigator.pop(context);
    if (isTableLikeView(view.type)) {
      ref.read(activeViewIdProvider(boardId).notifier).state = view.id;
      ref.read(workingViewConfigProvider(boardId).notifier).state = null;
    } else {
      context.push(routeForView(boardId, view));
    }
  }

  Future<void> _createView(BuildContext context, WidgetRef ref, BoardDetail board, BoardController controller) async {
    final draft = await showNewViewSheet(context);
    if (draft == null || !context.mounted) return;
    await _guard(context, () async {
      final created = await controller.createView(
        type: draft.type,
        name: draft.name,
        config: isTableLikeView(draft.type) && !currentConfig.isEmpty ? currentConfig.toJson() : null,
      );
      if (created == null || !context.mounted) return;
      Navigator.pop(context);
      if (isTableLikeView(created.type)) {
        ref.read(activeViewIdProvider(boardId).notifier).state = created.id;
        ref.read(workingViewConfigProvider(boardId).notifier).state = null;
      } else {
        context.push(routeForView(boardId, created));
      }
    });
  }

  Future<void> _viewMenu(
    BuildContext context,
    WidgetRef ref,
    BoardDetail board,
    BoardController controller,
    BoardView view,
  ) async {
    final onlyView = board.views.length <= 1;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (menuContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(view.name, style: Theme.of(menuContext).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(menuContext, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Duplicate'),
            onTap: () => Navigator.pop(menuContext, 'duplicate'),
          ),
          ListTile(
            leading: Icon(view.isDefault ? Icons.star_rounded : Icons.star_border_rounded),
            title: const Text('Set as default'),
            enabled: !view.isDefault,
            onTap: () => Navigator.pop(menuContext, 'default'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: onlyView ? DfColors.textTertiary : DfColors.danger),
            title: Text('Delete', style: TextStyle(color: onlyView ? DfColors.textTertiary : DfColors.danger)),
            subtitle: onlyView ? const Text('A board keeps at least one view') : null,
            enabled: !onlyView,
            onTap: () => Navigator.pop(menuContext, 'delete'),
          ),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'rename':
        final name = await promptForText(context, title: 'Rename view', initial: view.name);
        if (name == null || name.isEmpty || name == view.name || !context.mounted) return;
        await _guard(context, () => controller.renameView(view.id, name));
      case 'duplicate':
        await _guard(context, () async {
          await controller.duplicateView(view.id);
        });
      case 'default':
        await _guard(context, () => controller.setDefaultView(view.id));
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Delete "${view.name}"?', style: Theme.of(dialogContext).textTheme.titleMedium),
            content: Text(
              'Its filters, sort and column settings are lost. Items are not affected.',
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
        if (confirmed != true || !context.mounted) return;
        await _guard(context, () async {
          await controller.deleteView(view.id);
          if (ref.read(activeViewIdProvider(boardId)) == view.id) {
            ref.read(activeViewIdProvider(boardId).notifier).state = null;
            ref.read(workingViewConfigProvider(boardId).notifier).state = null;
          }
        });
    }
  }
}

/// Small "new view" sheet: a type picker and a name. Returns null when dismissed.
Future<({String type, String name})?> showNewViewSheet(BuildContext context) {
  return showModalBottomSheet<({String type, String name})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => const _NewViewSheet(),
  );
}

class _NewViewSheet extends StatefulWidget {
  const _NewViewSheet();

  @override
  State<_NewViewSheet> createState() => _NewViewSheetState();
}

class _NewViewSheetState extends State<_NewViewSheet> {
  String _type = 'table';
  final _name = TextEditingController();
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = viewTypeLabel(_type);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New view', style: text.titleLarge),
          const SizedBox(height: DfSpacing.sm),
          Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xs, children: [
            for (final option in viewTypes)
              ChoiceChip(
                avatar: Icon(option.icon, size: 16, color: _type == option.type ? DfColors.primary : null),
                label: Text(option.label),
                selected: _type == option.type,
                onSelected: (_) => setState(() => _type = option.type),
                selectedColor: isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle,
                shape: const StadiumBorder(),
                showCheckmark: false,
              ),
          ]),
          const SizedBox(height: DfSpacing.md),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _touched = true),
            decoration: InputDecoration(hintText: placeholder, labelText: 'Name'),
            onSubmitted: (_) => _submit(placeholder),
          ),
          const SizedBox(height: DfSpacing.md),
          DfButton(label: 'Create view', onPressed: () => _submit(placeholder)),
        ]),
      ),
    );
  }

  void _submit(String placeholder) {
    final raw = _name.text.trim();
    final name = raw.isEmpty || !_touched ? placeholder : raw;
    Navigator.pop(context, (type: _type, name: name));
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on ApiException catch (e) {
    if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
  }
}
