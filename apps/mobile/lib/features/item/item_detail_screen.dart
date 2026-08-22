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
import 'update_card.dart';

export 'update_card.dart' show relativeTime;

final itemDetailProvider = FutureProvider.autoDispose.family<ItemDetail, String>((ref, itemId) {
  return ref.read(itemRepositoryProvider).fetch(itemId);
});

final itemFilesProvider = FutureProvider.autoDispose.family<List<AppFile>, String>((ref, itemId) {
  return ref.read(itemRepositoryProvider).filesForItem(itemId);
});

/// Item card, matching the design's Columns / Updates / Files tabs.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(itemDetailProvider(widget.itemId));
    ref.invalidate(itemFilesProvider(widget.itemId));
  }

  Future<void> _rename(ItemDetail item) async {
    final name = await promptForText(context, title: 'Rename item', initial: item.name);
    if (name == null || name.isEmpty || name == item.name) return;
    try {
      await ref.read(boardRepositoryProvider).renameItem(item.id, name);
      _reload();
      ref.invalidate(boardControllerProvider(item.boardId));
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemDetailProvider(widget.itemId));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        centerTitle: false,
        titleSpacing: 0,
        title: state.maybeWhen(
          data: (item) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${item.boardName} › ${item.groupTitle}', style: text.labelSmall),
            ],
          ),
          orElse: () => const Text('Item'),
        ),
        actions: [
          ...state.maybeWhen(
            data: (item) => [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename',
                onPressed: () => _rename(item),
              ),
              IconButton(
                icon: const Icon(Icons.dashboard_outlined),
                tooltip: 'Open board',
                onPressed: () => context.pushReplacement('/boards/${item.boardId}'),
              ),
            ],
            orElse: () => const <Widget>[],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: DfColors.primary,
          indicatorColor: DfColors.primary,
          tabs: [
            const Tab(text: 'Columns'),
            Tab(text: state.maybeWhen(data: (i) => 'Updates (${i.updates.length})', orElse: () => 'Updates')),
            const Tab(text: 'Files'),
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
        data: (item) => TabBarView(
          controller: _tabs,
          children: [
            _ColumnsTab(item: item, onChanged: _reload),
            _UpdatesTab(item: item, onChanged: _reload),
            _FilesTab(itemId: item.id, onChanged: _reload),
          ],
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
    final assignable = await ref
        .read(assignableMembersProvider.future)
        .catchError((Object _) => const <BoardMember>[]);
    if (!context.mounted) return;

    final result = await editCell(
      context: context,
      column: column,
      item: item.asBoardItem,
      members: assignable,
    );
    if (!result.changed || !context.mounted) return;
    try {
      await ref.read(boardRepositoryProvider).setCellValue(
            itemId: item.id,
            columnId: column.id,
            value: result.value,
          );
      onChanged();
      ref.invalidate(boardControllerProvider(item.boardId));
    } on ApiException catch (e) {
      if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(DfSpacing.md),
      children: [
        for (final (index, column) in item.columns.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: DfSpacing.xs),
            child: DfCard(
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
              onTap: () => _editCell(context, ref, column),
              child: Row(children: [
                Expanded(flex: 2, child: Text(column.title, style: text.labelMedium)),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: cellChip(context, column, item.asBoardItem, const []) ??
                        Text(
                          'Set ${column.title.toLowerCase()}',
                          style: text.bodySmall?.copyWith(color: DfColors.textTertiary),
                        ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: DfColors.textTertiary),
              ]),
            ),
          )
              .animate(delay: DfMotion.staggerStep * index)
              .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
              .slideY(begin: 0.08, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
        const SizedBox(height: DfSpacing.md),
        // Activity lives under Columns, as secondary context.
        if (item.activity.isNotEmpty) ...[
          Text('Activity', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          for (final entry in item.activity.take(15))
            Padding(
              padding: const EdgeInsets.only(bottom: DfSpacing.sm),
              child: Row(children: [
                DfAvatar(name: entry.actorName ?? '?', seed: entry.actorName ?? entry.id, size: 24),
                const SizedBox(width: DfSpacing.xs),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: entry.actorName ?? 'Someone', style: text.titleSmall),
                    TextSpan(text: ' ${entry.description}', style: text.bodySmall),
                  ])),
                ),
                Text(relativeTime(entry.createdAt), style: text.labelSmall),
              ]),
            ),
        ],
      ],
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
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  bool _posting = false;

  /// When set, the composer posts a reply to this update.
  ItemUpdate? _replyTo;

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    setState(() => _posting = true);
    try {
      await ref.read(itemRepositoryProvider).postUpdate(
            itemId: widget.item.id,
            body: body,
            parentId: _replyTo?.id,
          );
      _composer.clear();
      setState(() => _replyTo = null);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _attach() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    try {
      await ref.read(itemRepositoryProvider).uploadFile(
            bytes: file.bytes!,
            filename: file.name,
            itemId: widget.item.id,
          );
      widget.onChanged();
      if (mounted) showDfToast(context, 'Attached ${file.name}');
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final updates = widget.item.updates;
    final text = Theme.of(context).textTheme;

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
                      canModify: update.authorId == me?.id || me?.account.role == 'admin',
                      onChanged: widget.onChanged,
                      onReply: () {
                        setState(() => _replyTo = update);
                        _composerFocus.requestFocus();
                      },
                    )
                        .animate(delay: DfMotion.staggerStep * index)
                        .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                        .slideY(begin: 0.06, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                ],
              ),
      ),
      SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
              color: Theme.of(context).brightness == Brightness.dark
                  ? DfColors.surfaceAltDark
                  : DfColors.primarySubtle,
              child: Row(children: [
                const Icon(Icons.reply_rounded, size: 16, color: DfColors.primary),
                const SizedBox(width: DfSpacing.xs),
                Expanded(
                  child: Text(
                    'Replying to ${_replyTo!.authorName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(DfSpacing.sm),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.attach_file_rounded, color: DfColors.textSecondary),
                tooltip: 'Attach a file',
                onPressed: _attach,
              ),
              Expanded(
                child: TextField(
                  controller: _composer,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _replyTo == null ? 'Write an update… (@name to mention)' : 'Write a reply…',
                  ),
                ),
              ),
              const SizedBox(width: DfSpacing.xs),
              IconButton.filled(
                onPressed: _posting ? null : _post,
                icon: _posting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                tooltip: 'Post',
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// --------------------------------------------------------------------- Files

class _FilesTab extends ConsumerStatefulWidget {
  const _FilesTab({required this.itemId, required this.onChanged});

  final String itemId;
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
      await ref.read(itemRepositoryProvider).uploadFile(
            bytes: file.bytes!,
            filename: file.name,
            itemId: widget.itemId,
          );
      ref.invalidate(itemFilesProvider(widget.itemId));
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemFilesProvider(widget.itemId));
    final text = Theme.of(context).textTheme;

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
                      onDelete: () async {
                        try {
                          await ref.read(itemRepositoryProvider).deleteFile(file.id);
                          ref.invalidate(itemFilesProvider(widget.itemId));
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            showDfToast(context, e.message, icon: Icons.error_outline_rounded);
                          }
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
  final VoidCallback onDelete;

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
