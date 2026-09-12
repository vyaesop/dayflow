import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../item/item_repository.dart';
import '../item/rich_composer.dart';
import '../item/update_card.dart';
import 'board_controller.dart';

/// Item-less updates on a board (contract §9), newest first.
final boardUpdatesProvider = FutureProvider.autoDispose.family<List<ItemUpdate>, String>(
  (ref, boardId) => ref.read(itemRepositoryProvider).boardUpdates(boardId),
);

/// Threaded discussion about a board as a whole, with the rich composer.
class BoardDiscussionScreen extends ConsumerStatefulWidget {
  const BoardDiscussionScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardDiscussionScreen> createState() => _BoardDiscussionScreenState();
}

class _BoardDiscussionScreenState extends ConsumerState<BoardDiscussionScreen> {
  final _composerFocus = FocusNode();
  ItemUpdate? _replyTo;

  @override
  void dispose() {
    _composerFocus.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(boardUpdatesProvider(widget.boardId));

  Future<void> _post(String markdown, List<PlatformFile> attachments) async {
    final repo = ref.read(itemRepositoryProvider);
    final created = await repo.postBoardUpdate(boardId: widget.boardId, body: markdown, parentId: _replyTo?.id);
    for (final file in attachments) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      await repo.uploadFile(bytes: bytes, filename: file.name, updateId: created.id);
    }
    if (mounted) setState(() => _replyTo = null);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardUpdatesProvider(widget.boardId));
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final canEdit = ref.watch(boardControllerProvider(widget.boardId)).valueOrNull?.canEdit ?? true;
    final text = Theme.of(context).textTheme;

    bool canModify(ItemUpdate u) => u.authorId == me?.id || me?.account.role == 'admin';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Board discussion'),
      ),
      body: Column(children: [
        Expanded(
          child: state.when(
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
            data: (updates) => RefreshIndicator(
              onRefresh: () async {
                _reload();
                await ref.read(boardUpdatesProvider(widget.boardId).future);
              },
              child: updates.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 96),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(DfSpacing.xl),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.forum_outlined, size: 32, color: DfColors.textTertiary),
                            const SizedBox(height: DfSpacing.xs),
                            Text('Start the conversation about this board', style: text.titleMedium),
                            const SizedBox(height: DfSpacing.xxs),
                            Text(
                              'Updates here are about the board as a whole,\nnot a single item.',
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
                      ),
                    ])
                  : ListView(
                      padding: const EdgeInsets.all(DfSpacing.md),
                      children: [
                        for (final (index, update) in updates.indexed)
                          UpdateCard(
                            key: ValueKey(update.id),
                            update: update,
                            canModify: canModify(update),
                            canModifyReply: canModify,
                            onChanged: _reload,
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
          ),
        ),
        if (canEdit)
          SafeArea(
            top: false,
            child: RichComposer(
              focusNode: _composerFocus,
              hintText: _replyTo == null ? 'Write to the board… (@name to mention)' : 'Write a reply…',
              replyingTo: _replyTo?.authorName,
              onCancelReply: () => setState(() => _replyTo = null),
              onSubmit: _post,
            ),
          ),
      ]),
    );
  }
}
