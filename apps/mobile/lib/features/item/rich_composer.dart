import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_misc.dart';
import '../members/members_providers.dart';
import 'rich_text.dart';

/// Posts markdown-lite plus any files picked while composing.
typedef RichSubmit = Future<void> Function(String markdown, List<PlatformFile> attachments);

/// Update composer shared by item updates and board discussion (contract §10).
///
/// Multiline field with a formatting toolbar, `@` mention suggestions,
/// pending-attachment chips, an optional "Replying to" banner and a Send
/// button. On a successful [onSubmit] the draft is cleared; an
/// [ApiException] is toasted and the draft kept.
class RichComposer extends ConsumerStatefulWidget {
  const RichComposer({
    super.key,
    required this.onSubmit,
    this.initialText,
    this.hintText = 'Write an update… (@name to mention)',
    this.replyingTo,
    this.onCancelReply,
    this.focusNode,
    this.autofocus = false,
  });

  final RichSubmit onSubmit;
  final String? initialText;
  final String hintText;

  /// Author name shown in the "Replying to X" banner; null hides it.
  final String? replyingTo;
  final VoidCallback? onCancelReply;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  ConsumerState<RichComposer> createState() => _RichComposerState();
}

class _RichComposerState extends ConsumerState<RichComposer> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText ?? '')
    ..selection = TextSelection.collapsed(offset: widget.initialText?.length ?? 0);
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  final List<PlatformFile> _attachments = [];
  bool _submitting = false;
  ({int start, String query})? _mention;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.value;
    final next = value.selection.isCollapsed ? activeMentionQuery(value.text, value.selection.extentOffset) : null;
    if (next?.start != _mention?.start || next?.query != _mention?.query) {
      setState(() => _mention = next);
    } else {
      // Send-enabled state depends on the text.
      setState(() {});
    }
  }

  void _apply(TextEditingValue Function(TextEditingValue value) transform) {
    _controller.value = transform(_controller.value);
    _focus.requestFocus();
  }

  void _wrap(String marker, {String? closing}) => _apply((v) => wrapSelectionValue(v, marker, closing: closing));

  void _insertMention(String label, String target) {
    final mention = _mention;
    if (mention == null) return;
    final caret = _controller.selection.extentOffset;
    final text = insertMentionToken(_controller.text, mention.start, caret, label, target);
    final offset = mention.start + mentionToken(label, target).length;
    _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
    _focus.requestFocus();
  }

  Future<void> _attach() async {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (picked == null || !mounted) return;
    setState(() => _attachments.addAll(picked.files.where((f) => f.bytes != null)));
  }

  Future<void> _submit() async {
    final markdown = _controller.text.trim();
    if (markdown.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(markdown, List.of(_attachments));
      if (!mounted) return;
      _controller.clear();
      setState(() => _attachments.clear());
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canSend = _controller.text.trim().isNotEmpty && !_submitting;

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_mention != null) _MentionPanel(query: _mention!.query, onPick: _insertMention),
      if (widget.replyingTo != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
          color: isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
          child: Row(children: [
            const Icon(Icons.reply_rounded, size: 16, color: DfColors.primary),
            const SizedBox(width: DfSpacing.xs),
            Expanded(
              child: Text(
                'Replying to ${widget.replyingTo}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium,
              ),
            ),
            if (widget.onCancelReply != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 16),
                tooltip: 'Cancel reply',
                onPressed: widget.onCancelReply,
              ),
          ]),
        ),
      if (_attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(DfSpacing.sm, DfSpacing.xs, DfSpacing.sm, 0),
          child: Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xxs, children: [
            for (final (index, file) in _attachments.indexed)
              InputChip(
                avatar: Icon(_isImageName(file.name) ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 16),
                label: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                labelStyle: text.labelSmall,
                visualDensity: VisualDensity.compact,
                onDeleted: _submitting ? null : () => setState(() => _attachments.removeAt(index)),
              ),
          ]),
        ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xxs),
        child: Row(children: [
          _ToolButton(icon: Icons.attach_file_rounded, tooltip: 'Attach a file', onTap: _attach),
          _ToolButton(icon: Icons.format_bold_rounded, tooltip: 'Bold', onTap: () => _wrap('**')),
          _ToolButton(icon: Icons.format_italic_rounded, tooltip: 'Italic', onTap: () => _wrap('_')),
          _ToolButton(icon: Icons.strikethrough_s_rounded, tooltip: 'Strikethrough', onTap: () => _wrap('~~')),
          _ToolButton(icon: Icons.code_rounded, tooltip: 'Code', onTap: () => _wrap('`')),
          _ToolButton(
            icon: Icons.link_rounded,
            tooltip: 'Link',
            onTap: () => _wrap('[', closing: '](https://)'),
          ),
          _ToolButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'Bullet list',
            onTap: () => _apply((v) => toggleLinePrefix(v, '- ')),
          ),
          _ToolButton(
            icon: Icons.format_list_numbered_rounded,
            tooltip: 'Numbered list',
            onTap: () => _apply((v) => toggleLinePrefix(v, '1. ')),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.sm, 0, DfSpacing.sm, DfSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(hintText: widget.hintText),
            ),
          ),
          const SizedBox(width: DfSpacing.xs),
          IconButton.filled(
            onPressed: canSend ? _submit : null,
            tooltip: 'Send',
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, size: 20),
          ),
        ]),
      ),
    ]);
  }
}

bool _isImageName(String name) {
  final lower = name.toLowerCase();
  return const ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic', '.bmp'].any(lower.endsWith);
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: DfColors.textSecondary,
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
      );
}

/// Suggestions for the `@query` being typed: "Everyone on this board" first,
/// then account members whose name starts with the query.
class _MentionPanel extends ConsumerWidget {
  const _MentionPanel({required this.query, required this.onPick});

  final String query;
  final void Function(String label, String target) onPick;

  bool _matches(String label) {
    final q = query.toLowerCase();
    if (q.isEmpty) return true;
    final lower = label.toLowerCase();
    return lower.startsWith(q) || lower.split(' ').any((word) => word.startsWith(q));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(assignableMembersProvider).valueOrNull ?? const <BoardMember>[];
    final people = members.where((m) => _matches(m.fullName)).take(6).toList();
    final everyone = _matches(everyoneMentionLabel) || _matches('everyone');
    if (!everyone && people.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(DfSpacing.sm, 0, DfSpacing.sm, DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceDark : DfColors.surface,
        borderRadius: BorderRadius.circular(DfRadius.md),
        border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
        boxShadow: DfShadows.card,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (everyone)
          ListTile(
            dense: true,
            leading: const CircleAvatar(
              radius: 12,
              backgroundColor: DfColors.primarySubtle,
              child: Icon(Icons.groups_rounded, size: 14, color: DfColors.primary),
            ),
            title: Text(everyoneMentionLabel, style: text.bodyMedium),
            subtitle: Text('Notifies every member of this board', style: text.labelSmall),
            onTap: () => onPick(everyoneMentionLabel, boardMentionTarget),
          ),
        for (final member in people)
          ListTile(
            dense: true,
            leading: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 24),
            title: Text(member.fullName, style: text.bodyMedium),
            onTap: () => onPick(member.fullName, userMentionTarget(member.userId)),
          ),
      ]),
    );
  }
}
