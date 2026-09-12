/// Rich-text support for updates (contract §10).
///
/// Pure functions over the server's `Doc` JSON plus the markdown-lite helpers
/// the composer needs; [RichDocText] is the one widget.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_misc.dart';

/// Label of the "everyone" mention; the token is `@[Everyone on this board](board)`.
const everyoneMentionLabel = 'Everyone on this board';

/// Mention target for the whole board audience.
const boardMentionTarget = 'board';

/// Mention target for one user: `user:<uuid>`.
String userMentionTarget(String userId) => 'user:$userId';

/// The stored mention token, with the trailing space the composer inserts.
String mentionToken(String label, String target) => '@[$label]($target) ';

// ------------------------------------------------------------------ rendering

List<Map<String, dynamic>> _blocksOf(Map<String, dynamic>? doc) {
  final content = doc?['content'];
  if (content is! List) return const [];
  return content.whereType<Map<String, dynamic>>().toList();
}

/// True when [doc] has at least one block to render.
bool hasRichContent(Map<String, dynamic>? doc) => _blocksOf(doc).isNotEmpty;

/// Applies text marks (`bold`, `italic`, `strike`, `code`) to [base].
///
/// Inter ships as a variable font, so weights also set the `wght` axis.
TextStyle styleWithMarks(TextStyle base, Iterable<String> marks) {
  var style = base;
  for (final mark in marks) {
    style = switch (mark) {
      'bold' => style.copyWith(fontWeight: FontWeight.w700, fontVariations: const [FontVariation('wght', 700)]),
      'italic' => style.copyWith(fontStyle: FontStyle.italic),
      'strike' => style.copyWith(
          decoration: TextDecoration.combine([
            if (style.decoration != null) style.decoration!,
            TextDecoration.lineThrough,
          ]),
        ),
      'code' => style.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Courier New', 'Courier'],
          fontSize: (style.fontSize ?? 14) * 0.92,
          backgroundColor: (style.color ?? DfColors.textPrimary).withValues(alpha: 0.08),
        ),
      _ => style,
    };
  }
  return style;
}

InlineSpan _inlineSpan(
  Map<String, dynamic> node, {
  required TextStyle base,
  required Color mentionColor,
  required Color linkColor,
  void Function(String href)? onLink,
}) {
  switch (node['type']) {
    case 'link':
      final href = node['href'] as String? ?? '';
      final label = node['text'] as String? ?? href;
      return TextSpan(
        text: label.isEmpty ? href : label,
        style: base.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: onLink == null ? null : (TapGestureRecognizer()..onTap = () => onLink(href)),
      );
    case 'mention':
      final label = node['label'] as String? ?? '';
      return TextSpan(
        text: '@$label',
        style: base.copyWith(
          color: mentionColor,
          fontWeight: FontWeight.w600,
          fontVariations: const [FontVariation('wght', 600)],
        ),
      );
    default:
      final marks = (node['marks'] as List<dynamic>? ?? const []).whereType<String>();
      return TextSpan(text: node['text'] as String? ?? '', style: styleWithMarks(base, marks));
  }
}

List<InlineSpan> _inlineSpans(
  List<dynamic> inlines, {
  required TextStyle base,
  required Color mentionColor,
  required Color linkColor,
  void Function(String href)? onLink,
}) =>
    [
      for (final node in inlines.whereType<Map<String, dynamic>>())
        _inlineSpan(node, base: base, mentionColor: mentionColor, linkColor: linkColor, onLink: onLink),
    ];

/// Converts a `Doc` into spans for [Text.rich].
///
/// Blocks are separated by newlines; list items render as "• " / "1. "
/// prefixed lines. Links get a tap recognizer only when [onLink] is given —
/// callers that pass one must dispose the recognizers (see [RichDocText]).
List<InlineSpan> docToSpans(
  Map<String, dynamic>? doc, {
  required TextStyle base,
  required Color mentionColor,
  required Color linkColor,
  void Function(String href)? onLink,
}) {
  final spans = <InlineSpan>[];
  for (final (index, block) in _blocksOf(doc).indexed) {
    if (index > 0) spans.add(TextSpan(text: '\n', style: base));
    final type = block['type'];
    if (type == 'bulletList' || type == 'orderedList') {
      final items = (block['items'] as List<dynamic>? ?? const []);
      for (final (i, item) in items.indexed) {
        if (i > 0) spans.add(TextSpan(text: '\n', style: base));
        spans.add(TextSpan(text: type == 'bulletList' ? '• ' : '${i + 1}. ', style: base));
        spans.addAll(_inlineSpans(
          item is List ? item : const [],
          base: base,
          mentionColor: mentionColor,
          linkColor: linkColor,
          onLink: onLink,
        ));
      }
    } else {
      spans.addAll(_inlineSpans(
        block['content'] as List<dynamic>? ?? const [],
        base: base,
        mentionColor: mentionColor,
        linkColor: linkColor,
        onLink: onLink,
      ));
    }
  }
  return spans;
}

String _inlineText(List<dynamic> inlines) {
  final buffer = StringBuffer();
  for (final node in inlines.whereType<Map<String, dynamic>>()) {
    switch (node['type']) {
      case 'link':
        final href = node['href'] as String? ?? '';
        final text = node['text'] as String? ?? '';
        buffer.write(text.isEmpty ? href : text);
      case 'mention':
        buffer.write('@${node['label'] ?? ''}');
      default:
        buffer.write(node['text'] ?? '');
    }
  }
  return buffer.toString();
}

/// Plain-text fallback: one line per block, list items prefixed like the
/// rendered form, mentions as `@Name`.
String docToPlainText(Map<String, dynamic>? doc) {
  final lines = <String>[];
  for (final block in _blocksOf(doc)) {
    final type = block['type'];
    if (type == 'bulletList' || type == 'orderedList') {
      final items = (block['items'] as List<dynamic>? ?? const []);
      for (final (i, item) in items.indexed) {
        final prefix = type == 'bulletList' ? '• ' : '${i + 1}. ';
        lines.add('$prefix${_inlineText(item is List ? item : const [])}');
      }
    } else {
      lines.add(_inlineText(block['content'] as List<dynamic>? ?? const []));
    }
  }
  return lines.join('\n');
}

// ------------------------------------------------------------------ composing

/// Wraps the selection in [marker]…[closing] (defaults to [marker]), or
/// unwraps it when the markers are already there — either inside the
/// selection (`**word**` selected) or hugging it (`**` + `word` + `**`).
/// A collapsed selection inserts an empty pair at the caret.
String wrapSelection(String text, TextSelection selection, String marker, {String? closing}) =>
    wrapSelectionValue(TextEditingValue(text: text, selection: selection), marker, closing: closing).text;

/// [wrapSelection] that also places the caret/selection sensibly afterwards.
TextEditingValue wrapSelectionValue(TextEditingValue value, String marker, {String? closing}) {
  final text = value.text;
  final close = closing ?? marker;
  final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: text.length);
  final start = selection.start.clamp(0, text.length);
  final end = selection.end.clamp(start, text.length);
  final selected = text.substring(start, end);
  final before = text.substring(0, start);
  final after = text.substring(end);

  if (start == end) {
    return TextEditingValue(
      text: '$before$marker$close$after',
      selection: TextSelection.collapsed(offset: start + marker.length),
    );
  }

  // Unwrap: markers inside the selection.
  if (selected.length >= marker.length + close.length && selected.startsWith(marker) && selected.endsWith(close)) {
    final inner = selected.substring(marker.length, selected.length - close.length);
    return TextEditingValue(
      text: '$before$inner$after',
      selection: TextSelection(baseOffset: start, extentOffset: start + inner.length),
    );
  }

  // Unwrap: markers hugging the selection.
  if (before.endsWith(marker) && after.startsWith(close)) {
    final newStart = start - marker.length;
    return TextEditingValue(
      text: '${before.substring(0, newStart)}$selected${after.substring(close.length)}',
      selection: TextSelection(baseOffset: newStart, extentOffset: newStart + selected.length),
    );
  }

  return TextEditingValue(
    text: '$before$marker$selected$close$after',
    selection: TextSelection(baseOffset: start + marker.length, extentOffset: end + marker.length),
  );
}

/// Replaces the `@query` being typed (from [atIndex] to [caret]) with the
/// stored mention token — `@[Label](user:uuid) ` or `@[Label](board) `.
String insertMentionToken(String text, int atIndex, int caret, String label, String target) {
  final start = atIndex.clamp(0, text.length);
  final end = caret.clamp(start, text.length);
  return text.replaceRange(start, end, mentionToken(label, target));
}

final _mentionStopChars = RegExp(r'[\n\[\]()@]');

/// The `@query` immediately before [caret], if the user is typing a mention.
///
/// The `@` must start the text or follow whitespace (so emails don't trigger),
/// and the query may not contain newlines, brackets or another `@` — a
/// completed token therefore never reopens the panel. Returns null otherwise.
({int start, String query})? activeMentionQuery(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  final at = before.lastIndexOf('@');
  if (at == -1) return null;
  if (at > 0 && before[at - 1].trim().isNotEmpty) return null;
  final query = before.substring(at + 1);
  if (query.isNotEmpty && query[0].trim().isEmpty) return null;
  if (query.length > 40 || _mentionStopChars.hasMatch(query)) return null;
  return (start: at, query: query);
}

// --------------------------------------------------------------------- widget

/// Renders a `Doc` with [Text.rich]; falls back to plain [fallback] text when
/// the document is missing or empty. Tapping a link copies it to the
/// clipboard (no URL launcher package is available) and toasts.
class RichDocText extends StatefulWidget {
  const RichDocText(this.doc, {super.key, this.fallback, this.style, this.maxLines, this.overflow});

  final Map<String, dynamic>? doc;
  final String? fallback;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<RichDocText> createState() => _RichDocTextState();
}

class _RichDocTextState extends State<RichDocText> {
  List<InlineSpan> _spans = const [];

  void _disposeRecognizers() {
    // visitChildren visits the span itself and then its descendants.
    for (final span in _spans) {
      span.visitChildren((child) {
        if (child is TextSpan) child.recognizer?.dispose();
        return true;
      });
    }
    _spans = const [];
  }

  Future<void> _copyLink(String href) async {
    await Clipboard.setData(ClipboardData(text: href));
    if (mounted) showDfToast(context, 'Link copied', icon: Icons.link_rounded);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    _disposeRecognizers();
    if (!hasRichContent(widget.doc)) {
      return Text(widget.fallback ?? '', style: base, maxLines: widget.maxLines, overflow: widget.overflow);
    }
    _spans = docToSpans(
      widget.doc,
      base: base,
      mentionColor: DfColors.primary,
      linkColor: DfColors.primary,
      onLink: _copyLink,
    );
    return Text.rich(
      TextSpan(children: _spans, style: base),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

// ------------------------------------------------------------- line prefixes

final _listPrefixPattern = RegExp(r'^(- |\* |\d+\. )');

/// Toggles a list prefix (`- ` or `1. `) on the line holding the caret.
///
/// An existing identical prefix is removed; a different list prefix is
/// swapped for [prefix]; a plain line gets [prefix] inserted. The caret keeps
/// its position relative to the line's text.
TextEditingValue toggleLinePrefix(TextEditingValue value, String prefix) {
  final text = value.text;
  final caret = value.selection.isValid ? value.selection.start.clamp(0, text.length) : text.length;
  final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
  final newlineAt = text.indexOf('\n', lineStart);
  final lineEnd = newlineAt == -1 ? text.length : newlineAt;
  final line = text.substring(lineStart, lineEnd);
  final existing = _listPrefixPattern.firstMatch(line)?.group(0) ?? '';

  final String replacement;
  if (existing == prefix) {
    replacement = line.substring(existing.length);
  } else {
    replacement = '$prefix${line.substring(existing.length)}';
  }
  final delta = replacement.length - line.length;
  final newCaret = (caret + delta).clamp(lineStart, lineStart + replacement.length);
  return TextEditingValue(
    text: text.replaceRange(lineStart, lineEnd, replacement),
    selection: TextSelection.collapsed(offset: newCaret),
  );
}
