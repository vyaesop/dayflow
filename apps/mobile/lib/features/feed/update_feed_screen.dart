import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../home/home_providers.dart';
import '../item/item_repository.dart';
import '../item/update_card.dart';

/// null boardId = all boards.
class _FeedQuery {
  const _FeedQuery({this.boardId, this.bookmarkedOnly = false});
  final String? boardId;
  final bool bookmarkedOnly;

  @override
  bool operator ==(Object other) =>
      other is _FeedQuery && other.boardId == boardId && other.bookmarkedOnly == bookmarkedOnly;

  @override
  int get hashCode => Object.hash(boardId, bookmarkedOnly);
}

final _feedFilterProvider = StateProvider<_FeedQuery>((ref) => const _FeedQuery());

final _feedProvider = FutureProvider.autoDispose<List<FeedEntry>>((ref) {
  final query = ref.watch(_feedFilterProvider);
  return ref
      .read(itemRepositoryProvider)
      .feed(boardId: query.boardId, bookmarkedOnly: query.bookmarkedOnly);
});

/// Company-wide update feed with board filter and bookmarks, per the design's
/// "Update Feed" screen.
class UpdateFeedScreen extends ConsumerWidget {
  const UpdateFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_feedProvider);
    final query = ref.watch(_feedFilterProvider);
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: state.maybeWhen(
          data: (entries) => Text('Update Feed (${entries.length})'),
          orElse: () => const Text('Update Feed'),
        ),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: Icon(
              query.bookmarkedOnly ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: query.bookmarkedOnly ? DfColors.primary : null,
            ),
            tooltip: query.bookmarkedOnly ? 'Show everything' : 'Bookmarks only',
            onPressed: () => ref.read(_feedFilterProvider.notifier).state =
                _FeedQuery(boardId: query.boardId, bookmarkedOnly: !query.bookmarkedOnly),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Filter by board',
            onPressed: () => _pickBoard(context, ref, query),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$error', style: text.bodySmall),
            const SizedBox(height: DfSpacing.md),
            DfButton(
              label: 'Try again',
              variant: DfButtonVariant.tonal,
              expand: false,
              onPressed: () => ref.invalidate(_feedProvider),
            ),
          ]),
        ),
        data: (entries) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_feedProvider);
            await ref.read(_feedProvider.future);
          },
          child: entries.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 100),
                  Center(
                    child: Column(children: [
                      Icon(
                        query.bookmarkedOnly ? Icons.bookmark_border_rounded : Icons.dynamic_feed_rounded,
                        size: 34,
                        color: DfColors.textTertiary,
                      ),
                      const SizedBox(height: DfSpacing.sm),
                      Text(
                        query.bookmarkedOnly ? 'No bookmarks yet' : 'No updates yet',
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: DfSpacing.xxs),
                      Text(
                        query.bookmarkedOnly
                            ? 'Bookmark an update to find it here later.'
                            : 'Updates from every board land here.',
                        style: text.bodySmall,
                      ),
                    ]),
                  ),
                ])
              : ListView(
                  padding: const EdgeInsets.all(DfSpacing.md),
                  children: [
                    for (final (index, entry) in entries.indexed)
                      GestureDetector(
                        onTap: entry.itemId == null ? null : () => context.push('/items/${entry.itemId}'),
                        child: UpdateCard(
                          key: ValueKey(entry.update.id),
                          update: entry.update,
                          canModify:
                              entry.update.authorId == me?.id || me?.account.role == 'admin',
                          onChanged: () => ref.invalidate(_feedProvider),
                          context2: '${entry.boardName}${entry.itemName != null ? ' › ${entry.itemName}' : ''}',
                        ),
                      )
                          .animate(delay: DfMotion.staggerStep * (index.clamp(0, 8)))
                          .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                          .slideY(
                            begin: 0.06,
                            end: 0,
                            duration: DfMotion.expressiveShort,
                            curve: DfMotion.enter,
                          ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _pickBoard(BuildContext context, WidgetRef ref, _FeedQuery query) async {
    final workspaces =
        await ref.read(workspacesProvider.future).catchError((Object _) => <WorkspaceSummary>[]);
    if (!context.mounted) return;
    final boards = workspaces.expand((w) => w.boards).toList();

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Text('Filter by board', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ListTile(
              title: const Text('All boards'),
              trailing: query.boardId == null ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
              onTap: () {
                ref.read(_feedFilterProvider.notifier).state =
                    _FeedQuery(bookmarkedOnly: query.bookmarkedOnly);
                Navigator.pop(sheetContext);
              },
            ),
            for (final board in boards)
              ListTile(
                title: Text(board.name),
                subtitle: Text(board.workspaceName),
                trailing:
                    query.boardId == board.id ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
                onTap: () {
                  ref.read(_feedFilterProvider.notifier).state =
                      _FeedQuery(boardId: board.id, bookmarkedOnly: query.bookmarkedOnly);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }
}
