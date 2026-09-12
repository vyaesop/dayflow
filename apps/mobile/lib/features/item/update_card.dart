import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_misc.dart';
import 'item_repository.dart';
import 'rich_composer.dart';
import 'rich_text.dart';

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
/// Bookmark and reaction state live locally so taps feel instant; the parent
/// refreshes for anything structural (reply added, edit, delete).
class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({
    super.key,
    required this.update,
    required this.canModify,
    required this.onChanged,
    this.onReply,
    this.context2,
    this.canModifyReply,
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

  /// Decides per reply whether it gets an edit/delete menu; null = never.
  final bool Function(ItemUpdate reply)? canModifyReply;

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  late bool _bookmarked = widget.update.bookmarkedByMe;

  @override
  void didUpdateWidget(covariant UpdateCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.update.id != widget.update.id || oldWidget.update.bookmarkedByMe != widget.update.bookmarkedByMe) {
      _bookmarked = widget.update.bookmarkedByMe;
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
            if (widget.canModify) _UpdateMenu(update: update, onChanged: widget.onChanged),
          ]),
          const SizedBox(height: DfSpacing.xs),
          RichDocText(update.doc, fallback: update.body, style: text.bodyMedium),
          if (update.files.isNotEmpty) ...[
            const SizedBox(height: DfSpacing.xs),
            UpdateAttachments(files: update.files),
          ],
          const SizedBox(height: DfSpacing.xs),
          ReactionsRow(update: update, onReply: widget.onReply),
          // Replies, indented under their parent.
          if (update.replies.isNotEmpty) ...[
            const SizedBox(height: DfSpacing.xs),
            for (final reply in update.replies)
              Padding(
                padding: const EdgeInsets.only(left: DfSpacing.lg, top: DfSpacing.xs),
                child: _ReplyTile(
                  key: ValueKey(reply.id),
                  reply: reply,
                  canModify: widget.canModifyReply?.call(reply) ?? false,
                  onChanged: widget.onChanged,
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({super.key, required this.reply, required this.canModify, required this.onChanged});

  final ItemUpdate reply;
  final bool canModify;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        DfAvatar(name: reply.authorName, seed: reply.authorId, imageUrl: reply.authorAvatarUrl, size: 22),
        const SizedBox(width: DfSpacing.xs),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: reply.authorName, style: text.titleSmall),
              TextSpan(
                text: '  ${relativeTime(reply.createdAt)}${reply.isEdited ? ' · edited' : ''}',
                style: text.labelSmall,
              ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canModify) _UpdateMenu(update: reply, onChanged: onChanged),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 30, top: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RichDocText(reply.doc, fallback: reply.body, style: text.bodyMedium),
          if (reply.files.isNotEmpty) ...[
            const SizedBox(height: DfSpacing.xxs),
            UpdateAttachments(files: reply.files),
          ],
          const SizedBox(height: DfSpacing.xxs),
          ReactionsRow(update: reply),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- edit/delete

/// ⋯ menu with Edit (rich composer in a bottom sheet) and Delete.
class _UpdateMenu extends ConsumerWidget {
  const _UpdateMenu({required this.update, required this.onChanged});

  final ItemUpdate update;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz_rounded, size: 18, color: DfColors.textTertiary),
        onSelected: (action) => action == 'edit'
            ? editUpdateInSheet(context, ref, update, onChanged: onChanged)
            : deleteUpdateWithConfirm(context, ref, update, onChanged: onChanged),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: DfColors.danger))),
        ],
      );
}

/// Opens a full-width bottom sheet with the [RichComposer] pre-filled with
/// the update's markdown; saves through `PATCH /updates/:id`, then uploads
/// any newly attached files against the update.
Future<void> editUpdateInSheet(
  BuildContext context,
  WidgetRef ref,
  ItemUpdate update, {
  required VoidCallback onChanged,
}) async {
  final repo = ref.read(itemRepositoryProvider);
  final initial = update.markdown ?? update.body;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.xs, 0),
          child: Row(children: [
            Expanded(child: Text('Edit update', style: Theme.of(sheetContext).textTheme.titleMedium)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ]),
        ),
        RichComposer(
          initialText: initial,
          hintText: 'Edit your update…',
          autofocus: true,
          onSubmit: (markdown, attachments) async {
            if (markdown != initial) await repo.editUpdate(update.id, markdown);
            for (final file in attachments) {
              final bytes = file.bytes;
              if (bytes == null) continue;
              await repo.uploadFile(bytes: bytes, filename: file.name, updateId: update.id);
            }
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            onChanged();
          },
        ),
      ]),
    ),
  );
}

Future<void> deleteUpdateWithConfirm(
  BuildContext context,
  WidgetRef ref,
  ItemUpdate update, {
  required VoidCallback onChanged,
}) async {
  final replies = update.replies.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete this update?', style: Theme.of(dialogContext).textTheme.titleMedium),
      content: Text(
        replies == 0 ? 'This cannot be undone.' : 'Its $replies repl${replies == 1 ? 'y' : 'ies'} will be deleted too.',
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
    await ref.read(itemRepositoryProvider).deleteUpdate(update.id);
    onChanged();
  } on ApiException catch (e) {
    if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
  }
}

// ---------------------------------------------------------------- attachments

/// Image thumbnails in a 96px strip (tap → full-screen viewer) and other
/// files as name + size chips (tap → copies the link).
class UpdateAttachments extends StatelessWidget {
  const UpdateAttachments({super.key, required this.files});

  final List<AppFile> files;

  Future<void> _copyLink(BuildContext context, AppFile file) async {
    await Clipboard.setData(ClipboardData(text: file.url));
    if (context.mounted) showDfToast(context, 'Link copied', icon: Icons.link_rounded);
  }

  void _openImage(BuildContext context, AppFile file) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  file.url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: DfSpacing.sm,
            right: DfSpacing.sm,
            child: SafeArea(
              child: IconButton.filledTonal(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ),
          Positioned(
            left: DfSpacing.md,
            right: DfSpacing.md,
            bottom: DfSpacing.md,
            child: SafeArea(
              child: Text(
                '${file.fileName} · ${file.sizeLabel}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = files.where((f) => f.isImage).toList();
    final others = files.where((f) => !f.isImage).toList();
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (images.isNotEmpty)
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (context, index) => const SizedBox(width: DfSpacing.xs),
            itemBuilder: (context, index) {
              final file = images[index];
              return GestureDetector(
                onTap: () => _openImage(context, file),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DfRadius.md),
                  child: Image.network(
                    file.url,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Container(
                      width: 96,
                      height: 96,
                      color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                      child: const Icon(Icons.broken_image_outlined, color: DfColors.textTertiary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      if (images.isNotEmpty && others.isNotEmpty) const SizedBox(height: DfSpacing.xs),
      if (others.isNotEmpty)
        Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xxs, children: [
          for (final file in others)
            ActionChip(
              avatar: const Icon(Icons.insert_drive_file_outlined, size: 16, color: DfColors.textSecondary),
              label: Text('${file.fileName} · ${file.sizeLabel}', maxLines: 1, overflow: TextOverflow.ellipsis),
              labelStyle: text.labelSmall,
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyLink(context, file),
            ),
        ]),
    ]);
  }
}

// ------------------------------------------------------------------ reactions

/// Reaction pills (👍 always first, with the like burst), a "+" picker and
/// the optional Reply affordance. Toggles are optimistic and reconciled with
/// the server's returned list; an [ApiException] rolls back.
class ReactionsRow extends ConsumerStatefulWidget {
  const ReactionsRow({super.key, required this.update, this.onReply});

  final ItemUpdate update;
  final VoidCallback? onReply;

  @override
  ConsumerState<ReactionsRow> createState() => _ReactionsRowState();
}

class _ReactionsRowState extends ConsumerState<ReactionsRow> with SingleTickerProviderStateMixin {
  static const _thumbs = '👍';

  late List<Reaction> _reactions = _initial(widget.update);

  late final AnimationController _likeBurst = AnimationController(vsync: this, duration: DfMotion.expressiveShort);

  /// Legacy payloads carry only likes; fold them into a 👍 reaction.
  static List<Reaction> _initial(ItemUpdate update) {
    if (update.reactions.isNotEmpty || update.likesCount == 0) return List.of(update.reactions);
    return [Reaction(emoji: _thumbs, count: update.likesCount, reactedByMe: update.likedByMe)];
  }

  @override
  void didUpdateWidget(covariant ReactionsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.update.id != widget.update.id || !_sameReactions(oldWidget.update.reactions, widget.update.reactions)) {
      _reactions = _initial(widget.update);
    }
  }

  static bool _sameReactions(List<Reaction> a, List<Reaction> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].emoji != b[i].emoji || a[i].count != b[i].count || a[i].reactedByMe != b[i].reactedByMe) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _likeBurst.dispose();
    super.dispose();
  }

  Future<void> _toggle(String emoji) async {
    final previous = _reactions;
    final existing = previous.where((r) => r.emoji == emoji).firstOrNull;
    final adding = existing == null || !existing.reactedByMe;
    final List<Reaction> next;
    if (existing == null) {
      next = [...previous, Reaction(emoji: emoji, count: 1, reactedByMe: true)];
    } else if (adding) {
      next = [for (final r in previous) r.emoji == emoji ? r.copyWith(count: r.count + 1, reactedByMe: true) : r];
    } else if (existing.count <= 1) {
      next = previous.where((r) => r.emoji != emoji).toList();
    } else {
      next = [for (final r in previous) r.emoji == emoji ? r.copyWith(count: r.count - 1, reactedByMe: false) : r];
    }
    setState(() => _reactions = next);
    if (adding && emoji == _thumbs) _likeBurst.forward(from: 0);
    try {
      final stored = await ref.read(itemRepositoryProvider).toggleReaction(widget.update.id, emoji);
      if (mounted) setState(() => _reactions = stored);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _reactions = previous);
        showDfToast(context, e.message, icon: Icons.error_outline_rounded);
      }
    }
  }

  Future<void> _pick() async {
    final mine = {for (final r in _reactions) if (r.reactedByMe) r.emoji};
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('React', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: DfSpacing.sm),
            Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xs, children: [
              for (final e in reactionEmojis)
                Material(
                  color: mine.contains(e) ? DfColors.primarySubtle : Colors.transparent,
                  borderRadius: BorderRadius.circular(DfRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DfRadius.md),
                    onTap: () => Navigator.pop(sheetContext, e),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (emoji != null && mounted) await _toggle(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final thumbs = _reactions.where((r) => r.emoji == _thumbs).firstOrNull ??
        const Reaction(emoji: _thumbs, count: 0, reactedByMe: false);
    final rest = _reactions.where((r) => r.emoji != _thumbs);

    return Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      _ReactionPill(
        emoji: thumbs.emoji,
        count: thumbs.count,
        active: thumbs.reactedByMe,
        burst: _likeBurst,
        onTap: () => _toggle(_thumbs),
      ),
      for (final reaction in rest)
        _ReactionPill(
          key: ValueKey(reaction.emoji),
          emoji: reaction.emoji,
          count: reaction.count,
          active: reaction.reactedByMe,
          onTap: () => _toggle(reaction.emoji),
        ),
      _ReactionPill(icon: Icons.add_reaction_outlined, tooltip: 'Add reaction', onTap: _pick),
      if (widget.onReply != null)
        InkWell(
          onTap: widget.onReply,
          borderRadius: BorderRadius.circular(DfRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.reply_rounded, size: 16, color: DfColors.textSecondary),
              const SizedBox(width: 4),
              Text('Reply', style: text.labelMedium),
            ]),
          ),
        ),
    ]);
  }
}

/// Emoji + count pill; filled when the current user reacted. With [burst]
/// set, the emoji plays the Vibe "emphasize" pop on activation.
class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    super.key,
    this.emoji,
    this.icon,
    this.count = 0,
    this.active = false,
    this.burst,
    this.tooltip,
    required this.onTap,
  });

  final String? emoji;
  final IconData? icon;
  final int count;
  final bool active;
  final AnimationController? burst;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    Widget glyph = emoji != null
        ? Text(emoji!, style: const TextStyle(fontSize: 14, height: 1.2))
        : Icon(icon, size: 16, color: DfColors.textSecondary);
    if (burst != null) {
      glyph = ScaleTransition(
        // 1 → 1.35 → 1 with the overshoot curve; idle when not animating.
        scale: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 45),
          TweenSequenceItem(tween: Tween(begin: 1.35, end: 1), weight: 55),
        ]).animate(CurvedAnimation(parent: burst!, curve: DfMotion.emphasize)),
        child: glyph,
      );
    }
    final pill = Material(
      color: active
          ? (isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle)
          : (isDark ? DfColors.surfaceDark : DfColors.surface),
      borderRadius: BorderRadius.circular(DfRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DfRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DfRadius.pill),
            border: Border.all(
              color: active ? DfColors.primaryBorder : (isDark ? DfColors.borderDark : DfColors.border),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            glyph,
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: text.labelMedium?.copyWith(color: active ? DfColors.primary : DfColors.textSecondary),
              ),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}
