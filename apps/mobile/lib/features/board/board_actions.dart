import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import '../home/home_providers.dart';
import 'board_controller.dart';

/// Standalone board-level flows the board screen and menus open.
///
/// Each sheet performs its own request (so the button can show progress) and
/// pops with either its result or the [ApiException] it hit. A SnackBar shown
/// from inside a modal sheet is drawn on the Scaffold underneath and hidden by
/// the sheet, so failures are toasted here, once the sheet has closed.

/// Toasts [result] when it is an API failure; returns whether it was one.
bool _toastIfFailed(BuildContext context, Object? result) {
  if (result is ApiException) {
    showDfToast(context, result.message, icon: Icons.error_outline_rounded);
    return true;
  }
  return false;
}

Future<T?> _showSheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88),
          child: child,
        ),
      ),
    );

// ------------------------------------------------------------- duplicate board

/// Copy modes offered by `POST /boards/:id/duplicate`, in display order.
const duplicateModes = <({String key, String label, String blurb})>[
  (key: 'structure', label: 'Structure only', blurb: 'Columns, groups and views — no items'),
  (key: 'items', label: 'Structure and items', blurb: 'Everything above plus every item and subitem'),
  (key: 'items_and_updates', label: 'Structure, items and updates', blurb: 'Also copies each item\'s conversation'),
];

/// Asks for a name and copy mode, duplicates [board], and opens the copy.
Future<void> showDuplicateBoardSheet(BuildContext context, WidgetRef ref, BoardDetail board) async {
  final result = await _showSheet<Object>(context, _DuplicateBoardSheet(board: board));
  if (result == null || !context.mounted || _toastIfFailed(context, result)) return;
  final copy = result as ({String id, String name});
  ref.invalidate(workspacesProvider);
  ref.invalidate(homeOverviewProvider);
  showDfToast(context, 'Duplicated as "${copy.name}"');
  context.push('/boards/${copy.id}');
}

class _DuplicateBoardSheet extends ConsumerStatefulWidget {
  const _DuplicateBoardSheet({required this.board});

  final BoardDetail board;

  @override
  ConsumerState<_DuplicateBoardSheet> createState() => _DuplicateBoardSheetState();
}

class _DuplicateBoardSheetState extends ConsumerState<_DuplicateBoardSheet> {
  late final _name = TextEditingController(text: '${widget.board.name} (copy)');
  String _mode = 'items';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(boardRepositoryProvider).duplicateBoard(widget.board.id, name: name, mode: _mode);
      if (mounted) Navigator.pop(context, (id: id, name: name));
    } on ApiException catch (e) {
      if (mounted) Navigator.pop(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _SheetFrame(
      title: 'Duplicate board',
      subtitle: widget.board.name,
      scrollable: true,
      children: [
        DfTextField(
          controller: _name,
          label: 'Name',
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
        const SizedBox(height: DfSpacing.sm),
        Text('What to copy', style: text.labelMedium),
        RadioGroup<String>(
          groupValue: _mode,
          onChanged: (value) => setState(() => _mode = value ?? 'items'),
          child: Column(children: [
            for (final mode in duplicateModes)
              RadioListTile<String>(
                value: mode.key,
                title: Text(mode.label, style: text.titleSmall),
                subtitle: Text(mode.blurb, style: text.bodySmall),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
          ]),
        ),
        const SizedBox(height: DfSpacing.xs),
        DfButton(
          label: 'Duplicate',
          loading: _busy,
          onPressed: _name.text.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ save as template

/// Saves [board]'s blueprint as an account template.
Future<void> showSaveAsTemplateSheet(BuildContext context, WidgetRef ref, BoardDetail board) async {
  final result = await _showSheet<Object>(context, _SaveAsTemplateSheet(board: board));
  if (result == null || !context.mounted || _toastIfFailed(context, result)) return;
  ref.invalidate(templatesProvider);
  showDfToast(context, 'Saved as template');
}

class _SaveAsTemplateSheet extends ConsumerStatefulWidget {
  const _SaveAsTemplateSheet({required this.board});

  final BoardDetail board;

  @override
  ConsumerState<_SaveAsTemplateSheet> createState() => _SaveAsTemplateSheetState();
}

class _SaveAsTemplateSheetState extends ConsumerState<_SaveAsTemplateSheet> {
  late final _name = TextEditingController(text: widget.board.name);
  late final _description = TextEditingController(text: widget.board.description ?? '');
  bool _includeItems = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final description = _description.text.trim();
      final template = await ref.read(boardRepositoryProvider).saveAsTemplate(
            widget.board.id,
            name: name,
            description: description.isEmpty ? null : description,
            includeItems: _includeItems,
          );
      if (mounted) Navigator.pop(context, template);
    } on ApiException catch (e) {
      if (mounted) Navigator.pop(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final itemCount = widget.board.itemCount;
    return _SheetFrame(
      title: 'Save as template',
      subtitle: 'Anyone in your account can start a board from it',
      scrollable: true,
      children: [
        DfTextField(
          controller: _name,
          label: 'Template name',
          autofocus: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: DfSpacing.sm),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          style: text.bodyLarge,
          decoration: const InputDecoration(labelText: 'Description (optional)', alignLabelWithHint: true),
        ),
        const SizedBox(height: DfSpacing.xs),
        SwitchListTile.adaptive(
          value: _includeItems,
          onChanged: (value) => setState(() => _includeItems = value),
          title: Text('Include items', style: text.titleSmall),
          subtitle: Text(
            itemCount == 0
                ? 'This board has no items yet'
                : 'Copies $itemCount item${itemCount == 1 ? '' : 's'} as sample rows (no subitems or updates)',
            style: text.bodySmall,
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: DfSpacing.xs),
        DfButton(
          label: 'Save template',
          loading: _busy,
          onPressed: _name.text.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- move item to board

/// Two-step flow: pick a target board, then review the column mapping and
/// choose a group. Returns true when the item was moved.
Future<bool> showMoveItemToBoardFlow(
  BuildContext context,
  WidgetRef ref, {
  required BoardItem item,
  required BoardDetail board,
}) async {
  final target = await _showSheet<BoardSummary>(context, _PickBoardSheet(excludeBoardId: board.id, item: item));
  if (target == null || !context.mounted) return false;

  final result = await _showSheet<Object>(context, _MovePreviewSheet(item: item, target: target));
  if (!context.mounted || result == null || _toastIfFailed(context, result)) return false;
  showDfToast(context, 'Moved to ${target.name}');
  return true;
}

class _PickBoardSheet extends ConsumerStatefulWidget {
  const _PickBoardSheet({required this.excludeBoardId, required this.item});

  final String excludeBoardId;
  final BoardItem item;

  @override
  ConsumerState<_PickBoardSheet> createState() => _PickBoardSheetState();
}

class _PickBoardSheetState extends ConsumerState<_PickBoardSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaces = ref.watch(workspacesProvider);
    final text = Theme.of(context).textTheme;
    final query = _query.text.trim().toLowerCase();

    return _SheetFrame(
      title: 'Move to another board',
      subtitle: '"${widget.item.name}"',
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: text.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search boards',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
        ),
        const SizedBox(height: DfSpacing.xs),
        Flexible(
          child: workspaces.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(DfSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
                const SizedBox(height: DfSpacing.sm),
                DfButton(
                  label: 'Try again',
                  variant: DfButtonVariant.tonal,
                  expand: false,
                  onPressed: () => ref.invalidate(workspacesProvider),
                ),
              ]),
            ),
            data: (list) {
              final sections = [
                for (final workspace in list)
                  (
                    workspace: workspace,
                    boards: workspace.boards
                        .where((b) => b.id != widget.excludeBoardId)
                        .where((b) => query.isEmpty || b.name.toLowerCase().contains(query))
                        .toList(),
                  ),
              ].where((s) => s.boards.isNotEmpty).toList();

              if (sections.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(DfSpacing.xl),
                  child: Text(
                    query.isEmpty ? 'There is no other board to move this item to.' : 'No boards match "$query".',
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                );
              }

              return ListView(
                shrinkWrap: true,
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: DfSpacing.sm, bottom: DfSpacing.xxs),
                      child: Text(section.workspace.name, style: text.labelMedium),
                    ),
                    for (final board in section.boards)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const DfBoardGlyph(size: 36),
                        title: Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        trailing: switch (board.type) {
                          'private' => const Icon(Icons.lock_outline_rounded, size: 16, color: DfColors.textTertiary),
                          'shareable' => const Icon(Icons.link_rounded, size: 16, color: DfColors.textTertiary),
                          _ => const Icon(Icons.chevron_right_rounded, size: 18, color: DfColors.textTertiary),
                        },
                        onTap: () => Navigator.pop(context, board),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MovePreviewSheet extends ConsumerStatefulWidget {
  const _MovePreviewSheet({required this.item, required this.target});

  final BoardItem item;
  final BoardSummary target;

  @override
  ConsumerState<_MovePreviewSheet> createState() => _MovePreviewSheetState();
}

class _MovePreviewSheetState extends ConsumerState<_MovePreviewSheet> {
  MovePreview? _preview;
  String? _error;
  String? _groupId;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _preview = null;
      _error = null;
    });
    try {
      final preview = await ref
          .read(boardRepositoryProvider)
          .movePreview(itemId: widget.item.id, boardId: widget.target.id);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _groupId ??= preview.groups.firstOrNull?.id;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _move() async {
    final groupId = _groupId;
    if (groupId == null) return;
    setState(() => _moving = true);
    try {
      await ref
          .read(boardRepositoryProvider)
          .moveToBoard(itemId: widget.item.id, boardId: widget.target.id, groupId: groupId);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) Navigator.pop(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _preview;

    return _SheetFrame(
      title: 'Move to ${widget.target.name}',
      subtitle: '"${widget.item.name}"',
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DfSpacing.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
              const SizedBox(height: DfSpacing.sm),
              Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
              const SizedBox(height: DfSpacing.sm),
              DfButton(
                label: 'Try again',
                variant: DfButtonVariant.tonal,
                expand: false,
                onPressed: _loadPreview,
              ),
            ]),
          )
        else if (preview == null)
          const Padding(
            padding: EdgeInsets.all(DfSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Text('Group', style: text.labelMedium),
                if (preview.groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DfSpacing.xs),
                    child: Text('That board has no groups yet.', style: text.bodySmall),
                  )
                else
                  RadioGroup<String>(
                    groupValue: _groupId,
                    onChanged: (value) => setState(() => _groupId = value),
                    child: Column(children: [
                      for (final group in preview.groups)
                        RadioListTile<String>(
                          value: group.id,
                          title: Row(children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: DfColors.token(group.color), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: DfSpacing.xs),
                            Flexible(
                              child: Text(group.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                            ),
                          ]),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                    ]),
                  ),
                const SizedBox(height: DfSpacing.sm),
                Text('What moves', style: text.labelMedium),
                const SizedBox(height: DfSpacing.xxs),
                if (preview.mapping.isEmpty)
                  Text('The item name moves; it has no column values to carry over.', style: text.bodySmall),
                for (final mapping in preview.mapping.where((m) => !m.isDropped))
                  _MappingRow(
                    icon: Icons.check_rounded,
                    color: DfColors.success,
                    label: mapping.sourceTitle == mapping.targetTitle
                        ? mapping.sourceTitle
                        : '${mapping.sourceTitle} → ${mapping.targetTitle}',
                  ),
                for (final dropped in preview.dropped)
                  _MappingRow(
                    icon: Icons.warning_amber_rounded,
                    color: DfColors.statusAmber,
                    label: '${dropped.sourceTitle} will be lost',
                    subtitle: 'No matching ${_typeLabel(dropped.sourceType)} column on ${widget.target.name}',
                  ),
                if (preview.subitemCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: DfSpacing.xs),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: DfColors.textSecondary),
                      const SizedBox(width: DfSpacing.xs),
                      Expanded(
                        child: Text(
                          '${preview.subitemCount} subitem${preview.subitemCount == 1 ? '' : 's'} move along and '
                          "map to the target board's subitem columns.",
                          style: text.bodySmall,
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: DfSpacing.xs),
                Text(
                  'Updates, files and activity travel with the item.',
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: DfSpacing.sm),
          DfButton(
            label: 'Move',
            loading: _moving,
            onPressed: _groupId == null ? null : _move,
          ),
        ],
      ],
    );
  }
}

String _typeLabel(String type) => switch (type) {
      'long_text' => 'long text',
      'item_id' => 'item ID',
      'creation_log' => 'creation log',
      'last_updated' => 'last updated',
      'auto_number' => 'auto number',
      _ => type,
    };

class _MappingRow extends StatelessWidget {
  const _MappingRow({required this.icon, required this.color, required this.label, this.subtitle});

  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: DfSpacing.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: text.bodyMedium),
            if (subtitle != null) Text(subtitle!, style: text.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------- frame

/// Handle, title and optional subtitle above a sheet's content. The frame
/// shrinks to fit; [scrollable] wraps fixed content so it scrolls under the
/// keyboard on short screens, while list sheets bring their own [Flexible].
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children, this.subtitle, this.scrollable = false});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: DfSpacing.md),
          Text(title, style: text.titleMedium),
          if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          const SizedBox(height: DfSpacing.sm),
          if (scrollable)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            )
          else
            ...children,
        ]),
      ),
    );
  }
}
