import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/features/board/cell_editors.dart';
import 'package:dayflow/features/board/column_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BoardColumn _column(String type, {Map<String, dynamic> settings = const {}}) => BoardColumn(
      id: 'c-$type',
      type: type,
      title: type,
      settings: settings,
      position: 1,
    );

BoardItem _item({
  Map<String, dynamic> values = const {},
  int serial = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? createdByUserId,
  String? updatedByUserId,
}) =>
    BoardItem(
      id: 'i1',
      name: 'Item',
      position: 1,
      updatesCount: 0,
      values: values,
      serial: serial,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdByUserId: createdByUserId,
      updatedByUserId: updatedByUserId,
    );

const _members = [
  BoardMember(userId: 'u1', fullName: 'Alex Smith', role: 'member'),
  BoardMember(userId: 'u2', fullName: 'Bea Jones', role: 'member'),
];

/// Pumps [cellChip] for [column]/[item] inside a MaterialApp; returns whether
/// the chip was non-null.
Future<bool> _pumpChip(
  WidgetTester tester,
  BoardColumn column,
  BoardItem item, {
  List<BoardMember> members = _members,
  int? autoNumber,
}) async {
  Widget? chip;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        chip = cellChip(context, column, item, members, autoNumber: autoNumber);
        return chip ?? const SizedBox.shrink();
      }),
    ),
  ));
  return chip != null;
}

void main() {
  group('validateEmail', () {
    test('accepts an empty string (clear) and a plain address', () {
      expect(validateEmail(''), isNull);
      expect(validateEmail('  '), isNull);
      expect(validateEmail('alex@example.com'), isNull);
      expect(validateEmail('first.last+tag@sub.example.co.uk'), isNull);
    });

    test('rejects malformed addresses', () {
      expect(validateEmail('alex'), isNotNull);
      expect(validateEmail('alex@'), isNotNull);
      expect(validateEmail('@example.com'), isNotNull);
      expect(validateEmail('alex@example'), isNotNull);
      expect(validateEmail('a lex@example.com'), isNotNull);
    });

    test('rejects addresses over 254 characters', () {
      final long = '${'a' * 250}@example.com';
      expect(validateEmail(long), isNotNull);
    });
  });

  group('validatePhone', () {
    test('accepts an empty string and common formats', () {
      expect(validatePhone(''), isNull);
      expect(validatePhone('+1 (555) 010-2030'), isNull);
      expect(validatePhone('555 0102'), isNull);
    });

    test('rejects letters, too-short and too-long input', () {
      expect(validatePhone('call me'), isNotNull);
      expect(validatePhone('12'), isNotNull);
      expect(validatePhone('1' * 33), isNotNull);
      expect(validatePhone('+()'), isNotNull, reason: 'needs at least one digit');
    });
  });

  group('formatTimelineLabel', () {
    test('formats both ends as MMM d', () {
      expect(formatTimelineLabel('2026-01-03', '2026-03-09'), 'Jan 3 – Mar 9');
    });

    test('falls back to the raw strings when unparseable', () {
      expect(formatTimelineLabel('soon', 'later'), 'soon – later');
    });
  });

  group('ratingLabel', () {
    test('fills the rating and outlines the rest', () {
      expect(ratingLabel(3, 5), '★★★☆☆');
      expect(ratingLabel(0, 3), '☆☆☆');
      expect(ratingLabel(10, 10), '★★★★★★★★★★');
    });

    test('clamps out-of-range values', () {
      expect(ratingLabel(9, 5), '★★★★★');
      expect(ratingLabel(-2, 4), '☆☆☆☆');
    });
  });

  group('mergeColumnSettings', () {
    test('overlays changes and deletes null keys', () {
      final merged = mergeColumnSettings(
        {'unit': r'$', 'decimals': 2, 'summary': 'none', 'labels': []},
        {'unit': null, 'decimals': 0, 'description': 'Cost'},
      );
      expect(merged, {'decimals': 0, 'summary': 'none', 'labels': [], 'description': 'Cost'});
    });
  });

  group('cellChip renders', () {
    testWidgets('item_id as #serial', (tester) async {
      await _pumpChip(tester, _column('item_id'), _item(serial: 42));
      expect(find.text('#42'), findsOneWidget);
    });

    testWidgets('rating as stars honouring settings.max', (tester) async {
      await _pumpChip(
        tester,
        _column('rating', settings: {'max': 4}),
        _item(values: {'c-rating': {'rating': 3}}),
      );
      expect(find.text('★★★☆'), findsOneWidget);
    });

    testWidgets('files as a count', (tester) async {
      await _pumpChip(tester, _column('files'), _item(values: {'c-files': {'fileIds': ['f1', 'f2', 'f3']}}));
      expect(find.text('3 files'), findsOneWidget);

      await _pumpChip(tester, _column('files'), _item(values: {'c-files': {'fileIds': ['f1']}}));
      expect(find.text('1 file'), findsOneWidget);
    });

    testWidgets('vote as a count', (tester) async {
      await _pumpChip(tester, _column('vote'), _item(values: {'c-vote': {'userIds': ['u1', 'u2']}}));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('number with unit and decimals', (tester) async {
      await _pumpChip(
        tester,
        _column('number', settings: {'unit': r'$', 'unitPosition': 'prefix', 'decimals': 2}),
        _item(values: {'c-number': {'number': 1234.5}}),
      );
      expect(find.text(r'$1,234.50'), findsOneWidget);

      await _pumpChip(
        tester,
        _column('number', settings: {'unit': 'kg'}),
        _item(values: {'c-number': {'number': 3}}),
      );
      expect(find.text('3 kg'), findsOneWidget);
    });

    testWidgets('creation_log with the creator name from members', (tester) async {
      await _pumpChip(
        tester,
        _column('creation_log'),
        _item(createdAt: DateTime(2026, 2, 14, 10), createdByUserId: 'u1'),
      );
      expect(find.text('Feb 14 · Alex Smith'), findsOneWidget);
    });

    testWidgets('creation_log falls back to Someone for an unknown creator', (tester) async {
      await _pumpChip(
        tester,
        _column('creation_log'),
        _item(createdAt: DateTime(2026, 2, 14, 10), createdByUserId: 'ghost'),
      );
      expect(find.text('Feb 14 · Someone'), findsOneWidget);
    });

    testWidgets('last_updated with the updater name', (tester) async {
      await _pumpChip(
        tester,
        _column('last_updated'),
        _item(updatedAt: DateTime(2026, 3, 1, 8), updatedByUserId: 'u2'),
      );
      expect(find.text('Mar 1 · Bea Jones'), findsOneWidget);
    });

    testWidgets('auto_number from the caller-provided index', (tester) async {
      await _pumpChip(tester, _column('auto_number'), _item(), autoNumber: 7);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('email address', (tester) async {
      await _pumpChip(tester, _column('email'), _item(values: {'c-email': {'email': 'alex@example.com'}}));
      expect(find.text('alex@example.com'), findsOneWidget);
    });

    testWidgets('phone number', (tester) async {
      await _pumpChip(
        tester,
        _column('phone'),
        _item(values: {'c-phone': {'phone': '+1 555 010 2030', 'countryCode': 'US'}}),
      );
      expect(find.text('+1 555 010 2030'), findsOneWidget);
    });

    testWidgets('long_text as its first non-empty line only', (tester) async {
      await _pumpChip(
        tester,
        _column('long_text'),
        _item(values: {'c-long_text': {'text': '\nFirst line here\nSecond line\nThird'}}),
      );
      expect(find.text('First line here'), findsOneWidget);
      expect(find.textContaining('Second'), findsNothing);
    });

    testWidgets('timeline as a date range', (tester) async {
      await _pumpChip(
        tester,
        _column('timeline'),
        _item(values: {'c-timeline': {'from': '2026-01-03', 'to': '2026-03-09'}}),
      );
      expect(find.text('Jan 3 – Mar 9'), findsOneWidget);
    });
  });

  group('cellChip returns null for empty cells', () {
    for (final type in ['long_text', 'email', 'phone', 'rating', 'vote', 'files', 'timeline', 'number']) {
      testWidgets(type, (tester) async {
        expect(await _pumpChip(tester, _column(type), _item()), isFalse);
      });
    }

    testWidgets('vote / files with empty lists', (tester) async {
      expect(await _pumpChip(tester, _column('vote'), _item(values: {'c-vote': {'userIds': []}})), isFalse);
      expect(await _pumpChip(tester, _column('files'), _item(values: {'c-files': {'fileIds': []}})), isFalse);
    });

    testWidgets('item_id without a serial', (tester) async {
      expect(await _pumpChip(tester, _column('item_id'), _item(serial: 0)), isFalse);
    });

    testWidgets('creation_log / last_updated without timestamps', (tester) async {
      expect(await _pumpChip(tester, _column('creation_log'), _item()), isFalse);
      expect(await _pumpChip(tester, _column('last_updated'), _item()), isFalse);
    });

    testWidgets('auto_number when no index is provided', (tester) async {
      expect(await _pumpChip(tester, _column('auto_number'), _item()), isFalse);
    });
  });

  group('editCell', () {
    testWidgets('rating sheet returns {rating: 3} when the third star is tapped', (tester) async {
      CellEditResult? result;
      final column = _column('rating');
      final item = _item();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editCell(context: context, column: column, item: item, members: _members);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(2));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.changed, isTrue);
      expect(result!.refresh, isFalse);
      expect(result!.value, {'rating': 3});
    });

    testWidgets('tapping the current rating again clears it', (tester) async {
      CellEditResult? result;
      final column = _column('rating');
      final item = _item(values: {'c-rating': {'rating': 2}});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editCell(context: context, column: column, item: item, members: _members);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.star_rounded).at(1));
      await tester.pumpAndSettle();

      expect(result!.changed, isTrue);
      expect(result!.value, isNull);
    });

    testWidgets('vote toggles the current user in and out', (tester) async {
      CellEditResult? result;
      final column = _column('vote');
      var item = _item();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editCell(
                  context: context,
                  column: column,
                  item: item,
                  members: _members,
                  meUserId: 'u1',
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(result!.value, {'userIds': ['u1']});

      item = item.withCell(column.id, {'userIds': ['u2', 'u1']});
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(result!.value, {'userIds': ['u2']});

      item = item.withCell(column.id, {'userIds': ['u1']});
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(result!.changed, isTrue);
      expect(result!.value, isNull, reason: 'an emptied list clears the cell');
    });

    testWidgets('read-only columns toast and return unchanged', (tester) async {
      CellEditResult? result;
      final column = _column('item_id');
      final item = _item(serial: 3);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await editCell(context: context, column: column, item: item, members: _members);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Edit'));
      await tester.pump();

      expect(result, (changed: false, value: null, refresh: false));
      expect(find.text('item_id is set automatically'), findsOneWidget);
    });
  });
}
