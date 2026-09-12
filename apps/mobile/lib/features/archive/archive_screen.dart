import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../board/board_controller.dart';
import '../home/home_providers.dart';
import '../item/update_card.dart' show relativeTime;
import 'archive_providers.dart';

/// Archived and trashed boards/items with restore and permanent delete.
///
/// Account-wide by default; with [boardId] it shows only that board's items
/// (the "Boards" section is hidden). [initialTab] 0 = Archive, 1 = Trash.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key, this.boardId, this.initialTab = 0});

  final String? boardId;
  final int initialTab;

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ArchiveMode.values.length,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, ArchiveMode.values.length - 1),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archive & trash'),
        leading: BackButton(onPressed: () => context.pop()),
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final mode in ArchiveMode.values) Tab(text: mode.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final mode in ArchiveMode.values) _ArchiveTab(mode: mode, boardId: widget.boardId),
        ],
      ),
    );
  }
}

class _ArchiveTab extends ConsumerStatefulWidget {
  const _ArchiveTab({required this.mode, required this.boardId});

  final ArchiveMode mode;
  final String? boardId;

  @override
  ConsumerState<_ArchiveTab> createState() => _ArchiveTabState();
}

class _ArchiveTabState extends ConsumerState<_ArchiveTab> {
  /// Ids with a request in flight, so their buttons go quiet.
  final _busy = <String>{};

  ArchiveQuery get _query => (mode: widget.mode, boardId: widget.boardId);

  Future<void> _refresh() async {
    ref.invalidate(archiveListingProvider(_query));
    await ref.read(archiveListingProvider(_query).future);
  }

  /// Everything that may have changed after a restore or permanent delete.
  void _afterChange() {
    ref.invalidate(archiveListingProvider);
    ref.invalidate(workspacesProvider);
    ref.invalidate(homeOverviewProvider);
    final boardId = widget.boardId;
    if (boardId != null) ref.invalidate(boardControllerProvider(boardId));
  }

  Future<void> _run(
    String id,
    Future<void> Function() action, {
    required String success,
    String? openLabel,
    String? openRoute,
  }) async {
    setState(() => _busy.add(id));
    try {
      await action();
      _afterChange();
      if (!mounted) return;
      _toast(context, success, openLabel: openLabel, openRoute: openRoute);
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<bool> _confirmDelete(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$name" permanently?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text('This cannot be undone.', style: Theme.of(dialogContext).textTheme.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently', style: TextStyle(color: DfColors.danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _restoreBoard(ArchivedBoard board) => _run(
        board.id,
        () => ref.read(boardRepositoryProvider).restoreBoard(board.id),
        success: 'Restored "${board.name}"',
        openLabel: 'Open',
        openRoute: '/boards/${board.id}',
      );

  Future<void> _deleteBoard(ArchivedBoard board) async {
    if (!await _confirmDelete(board.name)) return;
    await _run(
      board.id,
      () => ref.read(boardRepositoryProvider).deleteBoardPermanently(board.id),
      success: 'Deleted "${board.name}" permanently',
    );
  }

  Future<void> _restoreItem(ArchivedItem item) => _run(
        item.id,
        () => ref.read(boardRepositoryProvider).restoreItem(item.id),
        success: 'Restored "${item.name}"',
        openLabel: 'Open',
        openRoute: '/items/${item.id}',
      );

  Future<void> _deleteItem(ArchivedItem item) async {
    if (!await _confirmDelete(item.name)) return;
    await _run(
      item.id,
      () => ref.read(boardRepositoryProvider).deleteItemPermanently(item.id),
      success: 'Deleted "${item.name}" permanently',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(archiveListingProvider(_query));
    final text = Theme.of(context).textTheme;

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
            const SizedBox(height: DfSpacing.sm),
            Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: DfSpacing.md),
            DfButton(
              label: 'Try again',
              variant: DfButtonVariant.tonal,
              expand: false,
              onPressed: () => ref.invalidate(archiveListingProvider(_query)),
            ),
          ]),
        ),
      ),
      data: (listing) {
        final showBoards = widget.boardId == null && listing.boards.isNotEmpty;
        final isEmpty = !showBoards && listing.items.isEmpty;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: isEmpty
              ? _EmptyArchive(mode: widget.mode)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.sm, DfSpacing.md, DfSpacing.xxl),
                  children: [
                    if (showBoards) ...[
                      _SectionHeader(title: 'Boards', count: listing.boards.length),
                      for (final (index, board) in listing.boards.indexed)
                        _BoardTile(
                          board: board,
                          mode: widget.mode,
                          busy: _busy.contains(board.id),
                          onRestore: () => _restoreBoard(board),
                          onDelete: () => _deleteBoard(board),
                        ).animate(delay: DfMotion.staggerStep * (index.clamp(0, 8))).fadeIn(
                              duration: DfMotion.expressiveShort,
                              curve: DfMotion.enter,
                            ),
                      const SizedBox(height: DfSpacing.sm),
                    ],
                    if (listing.items.isNotEmpty) ...[
                      _SectionHeader(title: 'Items', count: listing.items.length),
                      for (final (index, item) in listing.items.indexed)
                        _ItemTile(
                          item: item,
                          mode: widget.mode,
                          busy: _busy.contains(item.id),
                          onRestore: () => _restoreItem(item),
                          onDelete: () => _deleteItem(item),
                        ).animate(delay: DfMotion.staggerStep * (index.clamp(0, 8))).fadeIn(
                              duration: DfMotion.expressiveShort,
                              curve: DfMotion.enter,
                            ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// Success toast with an optional "Open" action that navigates to the
/// restored board or item.
void _toast(BuildContext context, String message, {String? openLabel, String? openRoute}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: DfColors.success, size: 20),
        const SizedBox(width: DfSpacing.xs),
        Expanded(child: Text(message)),
      ]),
      duration: const Duration(seconds: 4),
      action: openLabel != null && openRoute != null
          ? SnackBarAction(label: openLabel, onPressed: () => context.push(openRoute))
          : null,
    ));
}

/// "Archived 3d ago" / "Deleted yesterday · purged in 27 days".
String archiveStamp(ArchiveMode mode, {DateTime? archivedAt, DateTime? trashedAt, DateTime? purgeAt}) {
  final verb = mode == ArchiveMode.trash ? 'Deleted' : 'Archived';
  final at = mode == ArchiveMode.trash ? (trashedAt ?? archivedAt) : (archivedAt ?? trashedAt);
  final buffer = StringBuffer(verb);
  if (at != null) {
    final rel = relativeTime(at);
    if (RegExp(r'^\d+[mhd]$').hasMatch(rel)) {
      buffer.write(' $rel ago');
    } else if (rel == 'just now' || rel == 'yesterday') {
      buffer.write(' $rel');
    } else {
      buffer.write(' on $rel');
    }
  }
  if (mode == ArchiveMode.trash && purgeAt != null) {
    final days = purgeAt.difference(DateTime.now()).inDays;
    buffer.write(days <= 0 ? ' · purged soon' : ' · purged in $days day${days == 1 ? '' : 's'}');
  }
  return buffer.toString();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs, top: DfSpacing.xxs),
      child: Row(children: [
        Text(title, style: text.titleMedium),
        const SizedBox(width: DfSpacing.xs),
        Text('$count', style: text.labelSmall),
      ]),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.mode,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final ArchivedBoard board;
  final ArchiveMode mode;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final typeIcon = switch (board.type) {
      'private' => Icons.lock_outline_rounded,
      'shareable' => Icons.link_rounded,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const DfBoardGlyph(size: 40),
            const SizedBox(width: DfSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                  ),
                  if (typeIcon != null)
                    Padding(
                      padding: const EdgeInsets.only(left: DfSpacing.xxs),
                      child: Tooltip(
                        message: board.type == 'private' ? 'Private board' : 'Shareable board',
                        child: Icon(typeIcon, size: 16, color: DfColors.textTertiary),
                      ),
                    ),
                ]),
                Text(
                  '${board.workspaceName} · ${board.itemCount} item${board.itemCount == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  archiveStamp(mode, archivedAt: board.archivedAt, trashedAt: board.trashedAt, purgeAt: board.purgeAt),
                  style: text.labelSmall,
                ),
              ]),
            ),
          ]),
          _ActionRow(mode: mode, busy: busy, onRestore: onRestore, onDelete: onDelete),
        ]),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.mode,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final ArchivedItem item;
  final ArchiveMode mode;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 3,
              height: 40,
              margin: const EdgeInsets.only(right: DfSpacing.xs, top: 2),
              decoration: BoxDecoration(
                color: DfColors.token(item.groupColor),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: DfColors.token(item.groupColor), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: DfSpacing.xxs),
                  Flexible(
                    child: Text(
                      '${item.boardName} · ${item.groupTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                ]),
                if (item.parentItemName != null)
                  Row(children: [
                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: DfColors.textTertiary),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        'in ${item.parentItemName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ),
                  ]),
                const SizedBox(height: 2),
                Text(
                  archiveStamp(mode, archivedAt: item.archivedAt, trashedAt: item.trashedAt, purgeAt: item.purgeAt),
                  style: text.labelSmall,
                ),
              ]),
            ),
          ]),
          _ActionRow(mode: mode, busy: busy, onRestore: onRestore, onDelete: onDelete),
        ]),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.mode, required this.busy, required this.onRestore, required this.onDelete});

  final ArchiveMode mode;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DfSpacing.xxs),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: DfSpacing.sm),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (mode == ArchiveMode.trash)
          TextButton.icon(
            onPressed: busy ? null : onDelete,
            style: TextButton.styleFrom(foregroundColor: DfColors.danger),
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: const Text('Delete permanently'),
          ),
        TextButton.icon(
          onPressed: busy ? null : onRestore,
          icon: const Icon(Icons.restore_rounded, size: 18),
          label: const Text('Restore'),
        ),
      ]),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive({required this.mode});

  final ArchiveMode mode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTrash = mode == ArchiveMode.trash;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.xl),
            child: Column(children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isTrash ? Icons.delete_outline_rounded : Icons.inventory_2_outlined,
                  size: 34,
                  color: DfColors.primary,
                ),
              ),
              const SizedBox(height: DfSpacing.md),
              Text(
                isTrash ? 'The trash is empty' : 'Nothing in the archive',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: DfSpacing.xxs),
              Text(
                isTrash
                    ? 'Deleted boards and items stay here for 30 days\nbefore they are purged for good.'
                    : 'Archived boards and items show up here,\nready to restore whenever you need them.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ])
                .animate()
                .fadeIn(duration: DfMotion.expressiveLong, curve: DfMotion.enter)
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1, 1),
                  duration: DfMotion.expressiveLong,
                  curve: DfMotion.emphasize,
                ),
          ),
        ),
      ],
    );
  }
}
