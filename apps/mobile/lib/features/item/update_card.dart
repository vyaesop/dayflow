import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_misc.dart';
import '../board/cell_editors.dart';
import 'item_repository.dart';

/// Compact relative timestamp: "just now", "4h", "yesterday", "12 Mar".
String relativeTime(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  if (delta.inDays == 1) return 'yesterday';
  if (delta.inDays < 7) return '${delta.inDays}d';
  return DateFormat.MMMd().format(time);
}

/// One update with its interactions and (optionally) its reply thread.
///
/// Owns its like/bookmark state locally so taps feel instant; the parent
/// refreshes for anything structural (reply added, edit, delete).
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({
    super.key,
    required this.update,
    required this.canModify,
    required this.onChanged,
    this.onReply,
    this.context2,
  });

  final ItemUpdate update;

  /// Whether the current user may edit/delete this update.
  final bool canModify;

  /// Called after anything structural changed (reply, edit, delete).
  final VoidCallback onChanged;

  /// Reply affordance; null hides it (replies cannot nest).
  final VoidCallback? onReply;

  /// Optional "where" line for feed contexts, e.g. "Launch plan · Item 3".
  final String? context2;

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> with SingleTickerProviderStateMixin {
  late bool _liked = widget.update.likedByMe;
  late int _likes = widget.update.likesCount;
  late bool _bookmarked = widget.update.bookmarkedByMe;

  late final AnimationController _likeBurst = AnimationController(
    vsync: this,
    duration: DfMotion.expressiveShort,
  );

  @override
  void didUpdateWidget(covariant UpdateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.update.id != widget.update.id ||
        oldWidget.update.likesCount != widget.update.likesCount) {
      _liked = widget.update.likedByMe;
      _likes = widget.update.likesCount;
      _bookmarked = widget.update.bookmarkedByMe;
    }
  }

  @override
  void dispose() {
    _likeBurst.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    // Optimistic flip with the emphasize pop; reconcile with the server after.
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    if (_liked) _likeBurst.forward(from: 0);
    try {
      final result = await ref.read(itemRepositoryProvider).toggleLike(widget.update.id);
      if (mounted) {
        setState(() {
          _liked = result.liked;
          _likes = result.likesCount;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likes += _liked ? 1 : -1;
        });
        showDfToast(context, e.message, icon: Icons.error_outline_rounded);
      }
    }
  }

  Future<void> _toggleBookmark() async {
    setState(() => _bookmarked = !_bookmarked);
    try {
      final stored = await ref.read(itemRepositoryProvider).toggleBookmark(widget.update.id);
      if (mounted) setState(() => _bookmarked = stored);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _bookmarked = !_bookmarked);
        showDfToast(context, e.message, icon: Icons.error_outline_rounded);
      }
    }
  }

  Future<void> _edit() async {
    final body = await promptForText(context, title: 'Edit update', initial: widget.update.body);
    if (body == null || body.isEmpty || body == widget.update.body) return;
    try {
      await ref.read(itemRepositoryProvider).editUpdate(widget.update.id, body);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete this update?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          widget.update.replies.isEmpty
              ? 'This cannot be undone.'
              : 'Its ${widget.update.replies.length} repl${widget.update.replies.length == 1 ? 'y' : 'ies'} will be deleted too.',
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
    if (confirmed != true) return;
    try {
      await ref.read(itemRepositoryProvider).deleteUpdate(widget.update.id);
      widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final update = widget.update;

    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.sm),
      child: DfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DfAvatar(name: update.authorName, seed: update.authorId, imageUrl: update.authorAvatarUrl, size: 28),
            const SizedBox(width: DfSpacing.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(update.authorName, style: text.titleSmall),
                Text(
                  '${relativeTime(update.createdAt)}${update.isEdited ? ' · edited' : ''}'
                  '${widget.context2 != null ? ' · ${widget.context2}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall,
                ),
              ]),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                size: 18,
                color: _bookmarked ? DfColors.primary : DfColors.textTertiary,
              ),
              tooltip: _bookmarked ? 'Remove bookmark' : 'Bookmark',
              onPressed: _toggleBookmark,
            ),
            if (widget.canModify)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, size: 18, color: DfColors.textTertiary),
                onSelected: (action) => action == 'edit' ? _edit() : _delete(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: DfColors.danger)),
                  ),
                ],
              ),
          ]),
          const SizedBox(height: DfSpacing.xs),
          Text(update.body, style: text.bodyMedium),
          const SizedBox(height: DfSpacing.xs),
          Row(children: [
            _LikeButton(liked: _liked, likes: _likes, burst: _likeBurst, onTap: _toggleLike),
            if (widget.onReply != null) ...[
              const SizedBox(width: DfSpacing.md),
              InkWell(
                onTap: widget.onReply,
                borderRadius: BorderRadius.circular(DfRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 4),
                  child: Row(children: [
                    const Icon(Icons.reply_rounded, size: 16, color: DfColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('Reply', style: text.labelMedium),
                  ]),
                ),
              ),
            ],
          ]),
          // Replies, indented under their parent.
          if (update.replies.isNotEmpty) ...[
            const SizedBox(height: DfSpacing.xs),
            for (final reply in update.replies)
              Padding(
                padding: const EdgeInsets.only(left: DfSpacing.lg, top: DfSpacing.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    DfAvatar(
                      name: reply.authorName,
                      seed: reply.authorId,
                      imageUrl: reply.authorAvatarUrl,
                      size: 22,
                    ),
                    const SizedBox(width: DfSpacing.xs),
                    Text(reply.authorName, style: text.titleSmall),
                    const SizedBox(width: DfSpacing.xs),
                    Text(relativeTime(reply.createdAt), style: text.labelSmall),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 30, top: 2),
                    child: Text(reply.body, style: text.bodyMedium),
                  ),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Like control with the Vibe "emphasize" pop on activation.
class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.likes, required this.burst, required this.onTap});

  final bool liked;
  final int likes;
  final AnimationController burst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = liked ? DfColors.primary : DfColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DfRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 4),
        child: Row(children: [
          ScaleTransition(
            // 1 → 1.35 → 1 with the overshoot curve; idle when not animating.
            scale: TweenSequence<double>([
              TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 45),
              TweenSequenceItem(tween: Tween(begin: 1.35, end: 1), weight: 55),
            ]).animate(CurvedAnimation(parent: burst, curve: DfMotion.emphasize)),
            child: Icon(
              liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            likes == 0 ? 'Like' : '$likes',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ]),
      ),
    );
  }
}
