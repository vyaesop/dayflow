import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/core/theme/theme.dart';
import 'package:dayflow/features/item/rich_text.dart';
import 'package:dayflow/features/item/update_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = TextStyle(fontSize: 14, color: Colors.black);
const _mention = Colors.indigo;
const _link = Colors.blue;

List<InlineSpan> _spans(Map<String, dynamic>? doc, {void Function(String)? onLink}) =>
    docToSpans(doc, base: _base, mentionColor: _mention, linkColor: _link, onLink: onLink);

String _plain(List<InlineSpan> spans) => TextSpan(children: spans).toPlainText();

Map<String, dynamic> _doc(List<Map<String, dynamic>> blocks) => {'type': 'doc', 'content': blocks};

Map<String, dynamic> _paragraph(List<Map<String, dynamic>> inlines) => {'type': 'paragraph', 'content': inlines};

Map<String, dynamic> _text(String text, [List<String>? marks]) =>
    {'type': 'text', 'text': text, 'marks': ?marks};

TextSpan _spanWithText(List<InlineSpan> spans, String text) =>
    spans.whereType<TextSpan>().firstWhere((s) => s.text == text);

void main() {
  group('docToSpans', () {
    test('renders a paragraph as plain text with the base style', () {
      final spans = _spans(_doc([_paragraph([_text('Hello world')])]));
      expect(_plain(spans), 'Hello world');
      expect(_spanWithText(spans, 'Hello world').style, _base);
    });

    test('separates paragraphs with newlines', () {
      final spans = _spans(_doc([
        _paragraph([_text('One')]),
        _paragraph([_text('Two')]),
      ]));
      expect(_plain(spans), 'One\nTwo');
    });

    test('renders bullet lists with • prefixes', () {
      final spans = _spans(_doc([
        {
          'type': 'bulletList',
          'items': [
            [_text('first')],
            [_text('second')],
          ],
        },
      ]));
      expect(_plain(spans), '• first\n• second');
    });

    test('renders ordered lists with 1. 2. prefixes', () {
      final spans = _spans(_doc([
        {
          'type': 'orderedList',
          'items': [
            [_text('alpha')],
            [_text('beta')],
            [_text('gamma')],
          ],
        },
      ]));
      expect(_plain(spans), '1. alpha\n2. beta\n3. gamma');
    });

    test('applies bold, italic and strike marks', () {
      final spans = _spans(_doc([
        _paragraph([_text('b', ['bold']), _text('i', ['italic']), _text('s', ['strike'])]),
      ]));
      expect(_spanWithText(spans, 'b').style?.fontWeight, FontWeight.w700);
      expect(_spanWithText(spans, 'i').style?.fontStyle, FontStyle.italic);
      expect(_spanWithText(spans, 's').style?.decoration, TextDecoration.lineThrough);
    });

    test('code marks use a monospace family and a subtle background', () {
      final spans = _spans(_doc([_paragraph([_text('x = 1', ['code'])])]));
      final style = _spanWithText(spans, 'x = 1').style!;
      expect(style.fontFamily, 'monospace');
      expect(style.backgroundColor, isNotNull);
      expect(style.backgroundColor!.a, lessThan(0.5));
    });

    test('stacks several marks on one span', () {
      final spans = _spans(_doc([_paragraph([_text('both', ['bold', 'italic'])])]));
      final style = _spanWithText(spans, 'both').style!;
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontStyle, FontStyle.italic);
    });

    test('links are colored, underlined and tappable through onLink', () {
      String? tapped;
      final spans = _spans(
        _doc([
          _paragraph([
            {'type': 'link', 'href': 'https://example.com', 'text': 'Example'},
          ]),
        ]),
        onLink: (href) => tapped = href,
      );
      final span = _spanWithText(spans, 'Example');
      expect(span.style?.color, _link);
      expect(span.style?.decoration, TextDecoration.underline);
      final recognizer = span.recognizer;
      expect(recognizer, isA<TapGestureRecognizer>());
      (recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, 'https://example.com');
      recognizer.dispose();
    });

    test('links without text fall back to the href and are inert without onLink', () {
      final spans = _spans(_doc([
        _paragraph([
          {'type': 'link', 'href': 'https://dayflow.app'},
        ]),
      ]));
      final span = _spanWithText(spans, 'https://dayflow.app');
      expect(span.recognizer, isNull);
    });

    test('mentions render as @Label in the mention color, semi-bold', () {
      final spans = _spans(_doc([
        _paragraph([
          {'type': 'mention', 'label': 'Alex Smith', 'userId': 'u1'},
          _text(' please review'),
        ]),
      ]));
      final span = _spanWithText(spans, '@Alex Smith');
      expect(span.style?.color, _mention);
      expect(span.style?.fontWeight, FontWeight.w600);
      expect(_plain(spans), '@Alex Smith please review');
    });

    test('board-scope mentions render the everyone label', () {
      final spans = _spans(_doc([
        _paragraph([
          {'type': 'mention', 'label': 'Everyone on this board', 'scope': 'board'},
        ]),
      ]));
      expect(_plain(spans), '@Everyone on this board');
    });

    test('returns nothing for a null or empty doc', () {
      expect(_spans(null), isEmpty);
      expect(_spans(_doc([])), isEmpty);
      expect(hasRichContent(null), isFalse);
      expect(hasRichContent(_doc([_paragraph([_text('x')])])), isTrue);
    });
  });

  group('docToPlainText', () {
    test('flattens paragraphs, lists, links and mentions', () {
      final doc = _doc([
        _paragraph([
          _text('Hi '),
          {'type': 'mention', 'label': 'Sam', 'userId': 'u2'},
          _text(', see '),
          {'type': 'link', 'href': 'https://x.y', 'text': 'this'},
        ]),
        {
          'type': 'bulletList',
          'items': [
            [_text('a')],
            [_text('b', ['bold'])],
          ],
        },
        {
          'type': 'orderedList',
          'items': [
            [_text('one')],
          ],
        },
      ]);
      expect(docToPlainText(doc), 'Hi @Sam, see this\n• a\n• b\n1. one');
    });

    test('is empty for a missing doc', () {
      expect(docToPlainText(null), '');
    });
  });

  group('wrapSelection', () {
    test('wraps the selected range with the marker', () {
      final out = wrapSelection('make this bold', const TextSelection(baseOffset: 5, extentOffset: 9), '**');
      expect(out, 'make **this** bold');
    });

    test('supports a distinct closing marker', () {
      final out = wrapSelection('see docs', const TextSelection(baseOffset: 4, extentOffset: 8), '[',
          closing: '](https://)');
      expect(out, 'see [docs](https://)');
    });

    test('unwraps when the markers are inside the selection', () {
      final out = wrapSelection('a **b** c', const TextSelection(baseOffset: 2, extentOffset: 7), '**');
      expect(out, 'a b c');
    });

    test('unwraps when the markers hug the selection', () {
      final out = wrapSelection('a ~~b~~ c', const TextSelection(baseOffset: 4, extentOffset: 5), '~~');
      expect(out, 'a b c');
    });

    test('inserts an empty pair at a collapsed caret', () {
      expect(wrapSelection('ab', const TextSelection.collapsed(offset: 1), '_'), 'a__b');
    });

    test('wrapSelectionValue places the caret inside an inserted pair', () {
      final value = wrapSelectionValue(
        const TextEditingValue(text: 'ab', selection: TextSelection.collapsed(offset: 1)),
        '`',
      );
      expect(value.text, 'a``b');
      expect(value.selection, const TextSelection.collapsed(offset: 2));
    });

    test('treats an invalid selection as the end of the text', () {
      expect(wrapSelection('ab', const TextSelection.collapsed(offset: -1), '**'), 'ab****');
    });
  });

  group('toggleLinePrefix', () {
    test('prefixes the caret line with a bullet', () {
      final value = toggleLinePrefix(
        const TextEditingValue(text: 'one\ntwo', selection: TextSelection.collapsed(offset: 5)),
        '- ',
      );
      expect(value.text, 'one\n- two');
      expect(value.selection.baseOffset, 7);
    });

    test('removes an identical prefix and swaps a different list prefix', () {
      final removed = toggleLinePrefix(
        const TextEditingValue(text: '- item', selection: TextSelection.collapsed(offset: 6)),
        '- ',
      );
      expect(removed.text, 'item');
      final swapped = toggleLinePrefix(
        const TextEditingValue(text: '- item', selection: TextSelection.collapsed(offset: 6)),
        '1. ',
      );
      expect(swapped.text, '1. item');
    });

    test('works on an empty field', () {
      final value = toggleLinePrefix(const TextEditingValue(), '1. ');
      expect(value.text, '1. ');
      expect(value.selection.baseOffset, 3);
    });
  });

  group('insertMentionToken', () {
    test('replaces the typed @query with a user token and a trailing space', () {
      final out = insertMentionToken('hey @al', 4, 7, 'Alex Smith', 'user:u-1');
      expect(out, 'hey @[Alex Smith](user:u-1) ');
    });

    test('produces the board token for everyone', () {
      final out = insertMentionToken('@ev tail', 0, 3, everyoneMentionLabel, boardMentionTarget);
      expect(out, '@[Everyone on this board](board)  tail');
    });

    test('helpers build the targets used by the composer', () {
      expect(userMentionTarget('abc'), 'user:abc');
      expect(mentionToken('X', 'board'), '@[X](board) ');
    });
  });

  group('activeMentionQuery', () {
    test('detects a query at the start of the text', () {
      expect(activeMentionQuery('@al', 3), (start: 0, query: 'al'));
    });

    test('detects a query after a space, up to the caret', () {
      expect(activeMentionQuery('hi @sam more', 7), (start: 3, query: 'sam'));
    });

    test('detects a bare @ with an empty query', () {
      expect(activeMentionQuery('hi @', 4), (start: 3, query: ''));
    });

    test('ignores an @ inside a word (emails)', () {
      expect(activeMentionQuery('mail me@x', 9), isNull);
    });

    test('returns null when there is no @ before the caret', () {
      expect(activeMentionQuery('plain text', 5), isNull);
      expect(activeMentionQuery('', 0), isNull);
    });

    test('does not reopen for a completed token or across newlines', () {
      expect(activeMentionQuery('@[Alex](user:1) ', 16), isNull);
      expect(activeMentionQuery('@a\nb', 4), isNull);
    });

    test('rejects a caret outside the text', () {
      expect(activeMentionQuery('@a', 5), isNull);
    });
  });

  group('UpdateCard', () {
    final fixture = ItemUpdate.fromJson({
      'id': 'up1',
      'body': '@Alex Smith can you check this?',
      'markdown': '@[Alex Smith](user:u1) can you **check** this?',
      'doc': {
        'type': 'doc',
        'content': [
          {
            'type': 'paragraph',
            'content': [
              {'type': 'mention', 'label': 'Alex Smith', 'userId': 'u1'},
              {'type': 'text', 'text': ' can you '},
              {'type': 'text', 'text': 'check', 'marks': ['bold']},
              {'type': 'text', 'text': ' this?'},
            ],
          },
        ],
      },
      'author': {'userId': 'u9', 'fullName': 'Sam Lee', 'avatarUrl': null},
      'createdAt': DateTime.now().toIso8601String(),
      'editedAt': null,
      'reactions': [
        {'emoji': '🔥', 'count': 3, 'reactedByMe': true},
        {'emoji': '👍', 'count': 1, 'reactedByMe': false},
      ],
      'likesCount': 1,
      'likedByMe': false,
      'bookmarkedByMe': false,
      'files': [
        {
          'id': 'f1',
          'fileName': 'spec.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 2048,
          'isImage': false,
          'url': '/files/f1',
          'uploadedByName': 'Sam Lee',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
      'replies': [],
    });

    testWidgets('renders the mention label, reaction counts and file chip', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: dayflowLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdateCard(update: fixture, canModify: false, onChanged: () {}, onReply: () {}),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('@Alex Smith'), findsOneWidget);
      expect(find.text('Sam Lee'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('spec.pdf'), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('hides the reply affordance when onReply is null', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: dayflowLightTheme(),
          home: Scaffold(body: UpdateCard(update: fixture, canModify: false, onChanged: () {})),
        ),
      ));
      await tester.pump();
      expect(find.text('Reply'), findsNothing);
    });
  });
}
