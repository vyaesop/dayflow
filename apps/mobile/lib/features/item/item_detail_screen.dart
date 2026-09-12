import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../board/board_controller.dart';
import '../board/cell_editors.dart';
import '../members/members_providers.dart';
import 'item_repository.dart';
import 'rich_composer.dart';
import 'update_card.dart';

export 'update_card.dart' show relativeTime;

final itemDetailProvider = FutureProvider.autoDispose.family<ItemDetail, String>((ref, itemId) {
  return ref.read(itemRepositoryProvider).fetch(itemId);
});

final itemFilesProvider = FutureProvider.autoDispose.family<List<AppFile>, String>((ref, itemId) {
  return ref.read(itemRepositoryProvider).filesForItem(itemId);
});

/// The signed-in user's id, or null while signed out.
String? _meUserId(WidgetRef ref) {
  final auth = ref.read(authControllerProvider);
  return auth is SignedIn ? auth.me.id : null;
}

void _toastError(BuildContext context, ApiException e) {
  if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
}

/// Item card: Columns / Updates / Files tabs, plus Subitems for top-level items.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  void _reload() {
    ref.invalidate(itemDetailProvider(widget.itemId));
    ref.invalidate(itemFilesProvider(widget.itemId));
  }

  void _reloadBoard(ItemDetail item) => ref.invalidate(boardControllerProvider(item.boardId));

  Future<void> _rename(ItemDetail item) async {
    final name = await promptForText(context, title: 'Rename item', initial: item.name);
    if (name == null || name.isEmpty || name == item.name) return;
    try {
      await ref.read(boardRepositoryProvider).renameItem(item.id, name);
      _reload();
      _reloadBoard(item);
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  Future<void> _archive(ItemDetail item) async {
    try {
      await ref.read(boardRepositoryProvider).archiveItem(item.id);
      _reloadBoard(item);
      if (!mounted) return;
      showDfToast(context, 'Archived "${item.name}"', icon: Icons.archive_outlined);
      context.pop();
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  Future<void> _trash(ItemDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${item.name}"?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          item.subitems.isEmpty
              ? 'It moves to the trash and is deleted for good after 30 days unless you restore it.'
              : 'It and its ${item.subitems.length} subitem${item.subitems.length == 1 ? '' : 's'} move to the '
                  'trash and are deleted for good after 30 days unless you restore them.',
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
      await ref.read(boardRepositoryProvider).trashItem(item.id);
      _reloadBoard(item);
      if (!mounted) return;
      showDfToast(context, 'Moved "${item.name}" to the trash', icon: Icons.delete_outline_rounded);
      context.pop();
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  String _metaLine(ItemDetail item) {
    final parts = <String>[];
    if (item.serial > 0) parts.add('#${item.serial}');
    if (item.createdAt != null) parts.add('created ${relativeTime(item.createdAt!)}');
    if (item.groupTitle.isNotEmpty) parts.add(item.groupTitle);
    return parts.isEmpty ? item.boardName : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemDetailProvider(widget.itemId));
    final item = state.valueOrNull;
    final text = Theme.of(context).textTheme;
    final showSubitems = item != null && !item.isSubitem;

    return DefaultTabController(
      length: showSubitems ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.pop()),
          centerTitle: false,
          titleSpacing: 0,
          title: item == null
              ? const Text('Item')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(_metaLine(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelSmall),
                  ],
                ),
          actions: [
            if (item != null) ...[
              IconButton(
                icon: const Icon(Icons.dashboard_outlined),
                tooltip: 'Open board',
                onPressed: () => context.pushReplacement('/boards/${item.boardId}'),
              ),
              if (item.canEdit)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (action) => switch (action) {
                    'rename' => _rename(item),
                    'archive' => _archive(item),
                    _ => _trash(item),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'archive', child: Text('Archive')),
                    PopupMenuItem(value: 'trash', child: Text('Delete', style: TextStyle(color: DfColors.danger))),
                  ],
                ),
            ],
          ],
          bottom: TabBar(
            labelColor: DfColors.primary,
            indicatorColor: DfColors.primary,
            isScrollable: showSubitems,
            tabAlignment: showSubitems ? TabAlignment.start : null,
            tabs: [
              const Tab(text: 'Columns'),
              Tab(text: item == null ? 'Updates' : 'Updates (${item.updates.length})'),
              const Tab(text: 'Files'),
              if (showSubitems) Tab(text: 'Subitems (${item.subitems.length})'),
            ],
          ),
        ),
        body: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
                const SizedBox(height: DfSpacing.sm),
                Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
                const SizedBox(height: DfSpacing.md),
                DfButton(label: 'Try again', variant: DfButtonVariant.tonal, expand: false, onPressed: _reload),
              ]),
            ),
          ),
          data: (item) => Column(children: [
            if (item.isSubitem) _ParentBreadcrumb(item: item),
            Expanded(
              child: TabBarView(
                children: [
                  _ColumnsTab(item: item, onChanged: _reload),
                  _UpdatesTab(item: item, onChanged: _reload),
                  _FilesTab(item: item, onChanged: _reload),
                  if (!item.isSubitem) _SubitemsTab(item: item, onChanged: _reload),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `↑ in <parent>` row shown on subitems; tap opens the parent item.
class _ParentBreadcrumb extends StatelessWidget {
  const _ParentBreadcrumb({required this.item});

  final ItemDetail item;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    return Material(
      color: isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
      child: InkWell(
        onTap: () => context.push('/items/${item.parentId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
          child: Row(children: [
            const Icon(Icons.arrow_upward_rounded, size: 16, color: DfColors.primary),
            const SizedBox(width: DfSpacing.xs),
            Expanded(
              child: Text(
                'in ${item.parentName ?? 'parent item'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(color: DfColors.primary),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: DfColors.primary),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Columns

class _ColumnsTab extends ConsumerWidget {
  const _ColumnsTab({required this.item, required this.onChanged});

  final ItemDetail item;
  final VoidCallback onChanged;

  Future<void> _editCell(BuildContext context, WidgetRef ref, BoardColumn column) async {
    final assignable =
        await ref.read(assignableMembersProvider.future).catchError((Object _) => const <BoardMember>[]);
    if (!context.mounted) return;

    final result = await editCell(
      context: context,
      column: column,
      item: item.asBoardItem,
      members: assignable,
      meUserId: _meUserId(ref),
      files: ref.read(itemRepositoryProvider),
    );
    if (!context.mounted) return;
    if (result.refresh) {
      onChanged();
      ref.invalidate(boardControllerProvider(item.boardId));
    }
    if (!result.changed) return;
    try {
      await ref.read(boardRepositoryProvider).setCellValue(itemId: item.id, columnId: column.id, value: result.value);
      onChanged();
      ref.invalidate(boardControllerProvider(item.boardId));
    } on ApiException catch (e) {
      if (context.mounted) _toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final members = ref.watch(assignableMembersProvider).valueOrNull ?? const <BoardMember>[];
    final boardItem = item.asBoardItem;

    return ListView(
      padding: const EdgeInsets.all(DfSpacing.md),
      children: [
        for (final (index, column) in item.columns.indexed)
          Builder(builder: (context) {
            final editable = item.canEdit && !column.isReadOnly;
            return Padding(
              padding: const EdgeInsets.only(bottom: DfSpacing.xs),
              child: DfCard(
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
                onTap: editable ? () => _editCell(context, ref, column) : null,
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: Row(children: [
                      Flexible(child: Text(column.title, style: text.labelMedium, overflow: TextOverflow.ellipsis)),
                      if (column.isReadOnly) ...[
                        const SizedBox(width: DfSpacing.xxs),
                        const Icon(Icons.lock_outline_rounded, size: 12, color: DfColors.textTertiary),
                      ],
                    ]),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: cellChip(context, column, boardItem, members) ??
                          Text(
                            editable ? 'Set ${column.title.toLowerCase()}' : '—',
                            style: text.bodySmall?.copyWith(color: DfColors.textTertiary),
                          ),
                    ),
                  ),
                  if (editable) const Icon(Icons.chevron_right_rounded, size: 18, color: DfColors.textTertiary),
                ]),
              ),
            )
                .animate(delay: DfMotion.staggerStep * index)
                .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                .slideY(begin: 0.08, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter);
          }),
        const SizedBox(height: DfSpacing.md),
        // Activity lives under Columns, as secondary context.
        if (item.activity.isNotEmpty) ...[
          Text('Activity', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          for (final entry in item.activity.take(15)) _ActivityRow(entry: entry),
        ],
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final undone = entry.isUndone;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.sm),
      child: Row(children: [
        DfAvatar(
          name: entry.actorName ?? '?',
          seed: entry.actorId ?? entry.actorName ?? entry.id,
          imageUrl: entry.actorAvatarUrl,
          size: 24,
        ),
        const SizedBox(width: DfSpacing.xs),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: entry.actorName ?? 'Someone', style: text.titleSmall),
              TextSpan(text: ' ${entry.description}', style: text.bodySmall),
            ]),
            style: undone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
          ),
        ),
        if (undone) ...[
          const SizedBox(width: DfSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
              borderRadius: BorderRadius.circular(DfRadius.sm),
            ),
            child: Text('undone', style: text.labelSmall?.copyWith(color: DfColors.textTertiary)),
          ),
        ],
        const SizedBox(width: DfSpacing.xs),
        Text(relativeTime(entry.createdAt), style: text.labelSmall),
      ]),
    );
  }
}

// ------------------------------------------------------------------- Updates

class _UpdatesTab extends ConsumerStatefulWidget {
  const _UpdatesTab({required this.item, required this.onChanged});

  final ItemDetail item;
  final VoidCallback onChanged;

  @override
  ConsumerState<_UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends ConsumerState<_UpdatesTab> {
  final _composerFocus = FocusNode();

  /// When set, the composer posts a reply to this update.
  ItemUpdate? _replyTo;

  @override
  void dispose() {
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _post(String markdown, List<PlatformFile> attachments) async {
    final repo = ref.read(itemRepositoryProvider);
    final created = await repo.postUpdate(itemId: widget.item.id, body: markdown, parentId: _replyTo?.id);
    for (final file in attachments) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      await repo.uploadFile(bytes: bytes, filename: file.name, updateId: created.id);
    }
    if (mounted) setState(() => _replyTo = null);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final updates = widget.item.updates;
    final canEdit = widget.item.canEdit;
    final text = Theme.of(context).textTheme;

    bool canModify(ItemUpdate u) => u.authorId == me?.id || me?.account.role == 'admin';

    return Column(children: [
      Expanded(
        child: updates.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(DfSpacing.xl),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.forum_outlined, size: 32, color: DfColors.textTertiary),
                    const SizedBox(height: DfSpacing.xs),
                    Text('Write the first update in this item', style: text.titleMedium),
                    const SizedBox(height: DfSpacing.xxs),
                    Text(
                      'Mention someone or upload files to share\nwith your team',
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                  ])
                      .animate()
                      .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                      .scale(
                        begin: const Offset(0.95, 0.95),
                        end: const Offset(1, 1),
                        duration: DfMotion.expressiveShort,
                        curve: DfMotion.emphasize,
                      ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(DfSpacing.md),
                children: [
                  for (final (index, update) in updates.indexed)
                    UpdateCard(
                      key: ValueKey(update.id),
                      update: update,
                      canModify: canModify(update),
                      canModifyReply: canModify,
                      onChanged: widget.onChanged,
                      onReply: canEdit
                          ? () {
                              setState(() => _replyTo = update);
                              _composerFocus.requestFocus();
                            }
                          : null,
                    )
                        .animate(delay: DfMotion.staggerStep * (index.clamp(0, 8)))
                        .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                        .slideY(begin: 0.06, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                ],
              ),
      ),
      if (canEdit)
        SafeArea(
          top: false,
          child: RichComposer(
            focusNode: _composerFocus,
            hintText: _replyTo == null ? 'Write an update… (@name to mention)' : 'Write a reply…',
            replyingTo: _replyTo?.authorName,
            onCancelReply: () => setState(() => _replyTo = null),
            onSubmit: _post,
          ),
        ),
    ]);
  }
}

// --------------------------------------------------------------------- Files

class _FilesTab extends ConsumerStatefulWidget {
  const _FilesTab({required this.item, required this.onChanged});

  final ItemDetail item;
  final VoidCallback onChanged;

  @override
  ConsumerState<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<_FilesTab> {
  bool _uploading = false;

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(itemRepositoryProvider).uploadFile(bytes: file.bytes!, filename: file.name, itemId: widget.item.id);
      ref.invalidate(itemFilesProvider(widget.item.id));
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemFilesProvider(widget.item.id));
    final text = Theme.of(context).textTheme;
    final canEdit = widget.item.canEdit;

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error', style: text.bodySmall)),
      data: (files) => Column(children: [
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DfSpacing.xl),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.folder_open_rounded, size: 32, color: DfColors.textTertiary),
                      const SizedBox(height: DfSpacing.xs),
                      Text('There are no files in this item', style: text.titleMedium),
                      const SizedBox(height: DfSpacing.xxs),
                      Text(
                        'Upload files to keep everything for this\nitem in one place.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall,
                      ),
                    ]),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(DfSpacing.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: DfSpacing.sm,
                    crossAxisSpacing: DfSpacing.sm,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return _FileTile(
                      file: file,
                      onDelete: !canEdit
                          ? null
                          : () async {
                              try {
                                await ref.read(itemRepositoryProvider).deleteFile(file.id);
                                ref.invalidate(itemFilesProvider(widget.item.id));
                                widget.onChanged();
                              } on ApiException catch (e) {
                                if (context.mounted) _toastError(context, e);
                              }
                            },
                    )
                        .animate(delay: DfMotion.staggerStep * index)
                        .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                        .scale(
                          begin: const Offset(0.94, 0.94),
                          end: const Offset(1, 1),
                          duration: DfMotion.expressiveShort,
                          curve: DfMotion.emphasize,
                        );
                  },
                ),
        ),
        if (canEdit)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: DfButton(
                label: 'Upload file',
                icon: const Icon(Icons.upload_file_rounded, size: 20),
                loading: _uploading,
                onPressed: _upload,
              ),
            ),
          ),
      ]),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.onDelete});

  final AppFile file;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DfCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(DfRadius.lg)),
            child: SizedBox.expand(
              child: file.isImage
                  ? Image.network(
                      file.url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const Center(
                        child: Icon(Icons.broken_image_outlined, color: DfColors.textTertiary),
                      ),
                    )
                  : Container(
                      color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                      child: const Center(
                        child: Icon(Icons.description_outlined, size: 34, color: DfColors.textSecondary),
                      ),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(DfSpacing.xs),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text('${file.sizeLabel} · ${file.uploadedByName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelSmall),
              ]),
            ),
            if (onDelete != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: DfColors.textTertiary),
                tooltip: 'Delete file',
                onPressed: onDelete,
              ),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Subitems

class _SubitemsTab extends ConsumerStatefulWidget {
  const _SubitemsTab({required this.item, required this.onChanged});

  final ItemDetail item;
  final VoidCallback onChanged;

  @override
  ConsumerState<_SubitemsTab> createState() => _SubitemsTabState();
}

class _SubitemsTabState extends ConsumerState<_SubitemsTab> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    widget.onChanged();
    ref.invalidate(boardControllerProvider(widget.item.boardId));
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      await ref.read(boardRepositoryProvider).createSubitem(parentItemId: widget.item.id, name: name);
      _nameController.clear();
      _refresh();
      _nameFocus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editCell(BoardItem sub, BoardColumn column) async {
    final assignable =
        await ref.read(assignableMembersProvider.future).catchError((Object _) => const <BoardMember>[]);
    if (!mounted) return;
    final result = await editCell(
      context: context,
      column: column,
      item: sub,
      members: assignable,
      meUserId: _meUserId(ref),
      files: ref.read(itemRepositoryProvider),
    );
    if (!mounted) return;
    if (result.refresh) _refresh();
    if (!result.changed) return;
    try {
      await ref.read(boardRepositoryProvider).setCellValue(itemId: sub.id, columnId: column.id, value: result.value);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  Future<void> _archive(BoardItem sub) async {
    try {
      await ref.read(boardRepositoryProvider).archiveItem(sub.id);
      _refresh();
      if (mounted) showDfToast(context, 'Archived "${sub.name}"', icon: Icons.archive_outlined);
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  Future<void> _trash(BoardItem sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${sub.name}"?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          'It moves to the trash and is deleted for good after 30 days unless you restore it.',
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
      await ref.read(boardRepositoryProvider).trashItem(sub.id);
      _refresh();
      if (mounted) showDfToast(context, 'Moved "${sub.name}" to the trash', icon: Icons.delete_outline_rounded);
    } on ApiException catch (e) {
      if (mounted) _toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final text = Theme.of(context).textTheme;
    final members = ref.watch(assignableMembersProvider).valueOrNull ?? const <BoardMember>[];
    final columns = item.subitemColumns;
    final canEdit = item.canEdit;

    return Column(children: [
      Expanded(
        child: item.subitems.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(DfSpacing.xl),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.account_tree_outlined, size: 32, color: DfColors.textTertiary),
                    const SizedBox(height: DfSpacing.xs),
                    Text('No subitems yet', style: text.titleMedium),
                    const SizedBox(height: DfSpacing.xxs),
                    Text(
                      canEdit
                          ? 'Break this item into smaller steps\nyou can track one by one.'
                          : 'This item has not been broken into steps.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
                    ),
                  ]),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(DfSpacing.md),
                children: [
                  for (final (index, sub) in item.subitems.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                      child: DfCard(
                        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xs, DfSpacing.xs, DfSpacing.sm),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => context.push('/items/${sub.id}'),
                                borderRadius: BorderRadius.circular(DfRadius.sm),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: DfSpacing.xxs),
                                  child: Row(children: [
                                    Expanded(
                                      child: Text(
                                        sub.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.titleSmall,
                                      ),
                                    ),
                                    if (sub.updatesCount > 0) ...[
                                      const Icon(Icons.chat_bubble_outline_rounded,
                                          size: 14, color: DfColors.textTertiary),
                                      const SizedBox(width: 2),
                                      Text('${sub.updatesCount}', style: text.labelSmall),
                                    ],
                                  ]),
                                ),
                              ),
                            ),
                            if (canEdit)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_horiz_rounded, size: 18, color: DfColors.textTertiary),
                                onSelected: (action) => action == 'archive' ? _archive(sub) : _trash(sub),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                                  PopupMenuItem(
                                    value: 'trash',
                                    child: Text('Delete', style: TextStyle(color: DfColors.danger)),
                                  ),
                                ],
                              )
                            else
                              const SizedBox(width: DfSpacing.xs),
                          ]),
                          if (columns.isNotEmpty)
                            Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xxs, children: [
                              for (final column in columns)
                                _SubitemChip(
                                  column: column,
                                  chip: cellChip(context, column, sub, members),
                                  onTap: canEdit && !column.isReadOnly ? () => _editCell(sub, column) : null,
                                ),
                            ]),
                        ]),
                      ),
                    )
                        .animate(delay: DfMotion.staggerStep * (index.clamp(0, 8)))
                        .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                        .slideY(begin: 0.06, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                ],
              ),
      ),
      if (canEdit)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.sm),
            child: Row(children: [
              const SizedBox(width: DfSpacing.xs),
              const Icon(Icons.subdirectory_arrow_right_rounded, size: 20, color: DfColors.textTertiary),
              const SizedBox(width: DfSpacing.xs),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(hintText: 'Add subitem'),
                ),
              ),
              const SizedBox(width: DfSpacing.xs),
              IconButton.filled(
                onPressed: _adding ? null : _add,
                tooltip: 'Add subitem',
                icon: _adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_rounded, size: 20),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// A subitem's cell rendered as a tappable chip labelled with its column.
class _SubitemChip extends StatelessWidget {
  const _SubitemChip({required this.column, required this.chip, required this.onTap});

  final BoardColumn column;
  final Widget? chip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DfRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xxs, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${column.title}: ', style: text.labelSmall),
          chip ??
              Container(
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(DfRadius.sm),
                ),
                child: Text(onTap == null ? '—' : 'Set', style: text.labelSmall),
              ),
        ]),
      ),
    );
  }
}
