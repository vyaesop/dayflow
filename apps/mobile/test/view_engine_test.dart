import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/features/board/view_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Fixture ----------

BoardColumn _col(String id, String type, {Map<String, dynamic> settings = const {}, String scope = 'items'}) =>
    BoardColumn.fromJson({
      'id': id,
      'type': type,
      'title': id,
      'position': 0,
      'scope': scope,
      'settings': settings,
    });

final _columns = <BoardColumn>[
  _col('c_status', 'status', settings: {
    'labels': [
      {'id': 'todo', 'label': 'To do', 'color': 'amber', 'isDone': false},
      {'id': 'working', 'label': 'Working on it', 'color': 'blue', 'isDone': false},
      {'id': 'done', 'label': 'Done', 'color': 'green', 'isDone': true},
    ],
  }),
  _col('c_people', 'people'),
  _col('c_date', 'date'),
  _col('c_timeline', 'timeline'),
  _col('c_text', 'text'),
  _col('c_long', 'long_text'),
  _col('c_number', 'number', settings: {'unit': r'$', 'unitPosition': 'prefix', 'decimals': 2}),
  _col('c_check', 'checkbox'),
  _col('c_dropdown', 'dropdown', settings: {
    'options': [
      {'id': 'low', 'label': 'Low'},
      {'id': 'med', 'label': 'Medium'},
      {'id': 'high', 'label': 'High'},
    ],
  }),
  _col('c_tags', 'tags', settings: {
    'options': [
      {'id': 'a', 'label': 'A'},
      {'id': 'b', 'label': 'B'},
      {'id': 'c', 'label': 'C'},
    ],
  }),
  _col('c_link', 'link'),
  _col('c_email', 'email'),
  _col('c_phone', 'phone'),
  _col('c_location', 'location'),
  _col('c_files', 'files'),
  _col('c_rating', 'rating', settings: {'max': 5}),
  _col('c_vote', 'vote'),
  _col('c_itemid', 'item_id'),
  _col('c_created', 'creation_log'),
  _col('c_updated', 'last_updated'),
  _col('c_auto', 'auto_number'),
  _col('s_status', 'status', scope: 'subitems'),
  _col('s_owner', 'people', scope: 'subitems'),
];

BoardItem _item(
  String id,
  String name, {
  required int serial,
  required double position,
  String? createdAt,
  String? updatedAt,
  Map<String, dynamic> values = const {},
  List<Map<String, dynamic>> subitems = const [],
}) =>
    BoardItem.fromJson({
      'id': id,
      'name': name,
      'position': position,
      'updatesCount': 0,
      'serial': serial,
      'createdAt': createdAt ?? '2026-09-01T12:00:00.000Z',
      'updatedAt': updatedAt ?? '2026-09-10T12:00:00.000Z',
      'parentItemId': null,
      'subitems': subitems,
      'values': values,
    });

final _alpha = _item(
  'i1',
  'Alpha',
  serial: 1,
  position: 1,
  createdAt: '2026-09-01T12:00:00.000Z',
  updatedAt: '2026-09-10T12:00:00.000Z',
  values: {
    'c_status': {'labelId': 'todo'},
    'c_people': {'userIds': ['u1']},
    'c_date': {'date': '2026-09-12', 'time': '09:00'},
    'c_timeline': {'from': '2026-09-01', 'to': '2026-09-20'},
    'c_text': {'text': 'Hello World'},
    'c_long': {'text': 'Long body'},
    'c_number': {'number': 10.5},
    'c_check': {'checked': true},
    'c_dropdown': {'optionIds': ['low']},
    'c_tags': {'optionIds': ['a', 'b']},
    'c_link': {'url': 'https://example.com/a', 'label': 'Example'},
    'c_email': {'email': 'alpha@example.com'},
    'c_phone': {'phone': '+1 555 0100'},
    'c_location': {'address': 'Paris, France'},
    'c_files': {'fileIds': ['f1', 'f2']},
    'c_rating': {'rating': 4},
    'c_vote': {'userIds': ['u1', 'u2']},
  },
  subitems: [
    {
      'id': 'sub1',
      'name': 'Sub one',
      'position': 1,
      'serial': 9,
      'parentItemId': 'i1',
      'values': {
        's_status': {'labelId': 'done'},
      },
    },
  ],
);

final _beta = _item(
  'i2',
  'beta',
  serial: 2,
  position: 2,
  createdAt: '2026-09-03T12:00:00.000Z',
  updatedAt: '2026-09-11T12:00:00.000Z',
  values: {
    'c_status': {'labelId': 'done'},
    'c_people': {'userIds': ['u2']},
    'c_date': {'date': '2026-09-05'},
    'c_timeline': {'from': '2026-09-10', 'to': '2026-09-30'},
    'c_text': {'text': 'Other text'},
    'c_number': {'number': 20},
    'c_dropdown': {'optionIds': ['high']},
    'c_tags': {'optionIds': ['c']},
    'c_rating': {'rating': 2},
    'c_check': {'checked': false},
  },
);

/// No cell values at all.
final _gamma = _item(
  'i3',
  'Gamma',
  serial: 3,
  position: 3,
  createdAt: '2026-08-20T12:00:00.000Z',
  updatedAt: '2026-08-21T12:00:00.000Z',
);

final _delta = _item(
  'i4',
  'delta',
  serial: 4,
  position: 1,
  createdAt: '2026-09-05T12:00:00.000Z',
  updatedAt: '2026-09-12T12:00:00.000Z',
  values: {
    'c_status': {'labelId': 'working'},
    'c_people': {'userIds': ['u2', 'u1']},
    'c_date': {'date': '2026-09-14'},
    'c_text': {'text': 'hello again'},
    'c_number': {'number': -3.25},
    'c_dropdown': {'optionIds': ['med']},
    'c_tags': {'optionIds': ['b']},
    'c_rating': {'rating': 5},
    'c_vote': {'userIds': ['u2']},
  },
);

BoardDetail _board() => BoardDetail(
      id: 'b1',
      name: 'Board',
      type: 'main',
      workspaceName: 'Main',
      isFavorite: false,
      columns: _columns,
      groups: [
        BoardGroup(id: 'g1', title: 'Group 1', color: 'blue', collapsed: false, items: [_alpha, _beta, _gamma]),
        BoardGroup(id: 'g2', title: 'Group 2', color: 'purple', collapsed: false, items: [_delta]),
      ],
      members: const [
        BoardMember(userId: 'u1', fullName: 'Zed Ali', role: 'owner'),
        BoardMember(userId: 'u2', fullName: 'Amy Brown', role: 'member'),
      ],
    );

/// Saturday.
final _saturday = DateTime(2026, 9, 12, 15, 30);

/// Monday.
final _monday = DateTime(2026, 9, 14, 8);

ViewContext _ctx({DateTime? now, String? me = 'u1'}) => ViewContext.forBoard(_board(), meUserId: me, now: now ?? _saturday);

FilterRule _rule(String field, String op, [Object? value]) => FilterRule(id: 'r', field: field, operator: op, value: value);

bool _match(BoardItem item, String field, String op, [Object? value]) =>
    matchesRule(item, _rule(field, op, value), _columns, _ctx());

List<String> _sorted(List<BoardItem> items, String field, String direction, {ViewContext? ctx}) {
  final c = ctx ?? _ctx();
  final copy = [...items]..sort((a, b) => compareItems(a, b, [SortRule(field: field, direction: direction)], _columns, c));
  return copy.map((i) => i.id).toList();
}

void main() {
  final all = [_alpha, _beta, _gamma, _delta];

  group('fieldKindFor', () {
    test('maps pseudo fields and every column type', () {
      expect(fieldKindFor('name', _columns), FieldKind.text);
      expect(fieldKindFor('group', _columns), FieldKind.group);
      final expected = {
        'c_status': FieldKind.choice,
        'c_dropdown': FieldKind.choice,
        'c_tags': FieldKind.choice,
        'c_people': FieldKind.people,
        'c_vote': FieldKind.people,
        'c_date': FieldKind.date,
        'c_timeline': FieldKind.date,
        'c_created': FieldKind.date,
        'c_updated': FieldKind.date,
        'c_text': FieldKind.text,
        'c_long': FieldKind.text,
        'c_email': FieldKind.text,
        'c_phone': FieldKind.text,
        'c_link': FieldKind.text,
        'c_location': FieldKind.text,
        'c_number': FieldKind.number,
        'c_rating': FieldKind.number,
        'c_itemid': FieldKind.number,
        'c_auto': FieldKind.number,
        'c_check': FieldKind.checkbox,
        'c_files': FieldKind.files,
      };
      for (final entry in expected.entries) {
        expect(fieldKindFor(entry.key, _columns), entry.value, reason: entry.key);
      }
    });

    test('returns null for unknown fields and types', () {
      expect(fieldKindFor('missing', _columns), isNull);
      expect(fieldKindForType('mystery'), isNull);
    });
  });

  group('operatorsFor and labels', () {
    test('lists the contract operators per kind', () {
      expect(operatorsFor(FieldKind.text), ['contains', 'not_contains', 'is', 'is_not', 'is_empty', 'is_not_empty']);
      expect(operatorsFor(FieldKind.choice), ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty']);
      expect(operatorsFor(FieldKind.people), ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty']);
      expect(operatorsFor(FieldKind.date), ['is', 'is_before', 'is_after', 'is_between', 'is_empty', 'is_not_empty']);
      expect(operatorsFor(FieldKind.number), ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty']);
      expect(operatorsFor(FieldKind.checkbox), ['is_checked', 'is_not_checked']);
      expect(operatorsFor(FieldKind.group), ['is_any_of', 'is_none_of']);
      expect(operatorsFor(FieldKind.files), ['is_empty', 'is_not_empty']);
    });

    test('every operator has a human label', () {
      final labels = {
        'contains': 'contains',
        'not_contains': 'does not contain',
        'is': 'is',
        'is_not': 'is not',
        'is_any_of': 'is any of',
        'is_none_of': 'is none of',
        'is_empty': 'is empty',
        'is_not_empty': 'is not empty',
        'is_before': 'is before',
        'is_after': 'is after',
        'is_between': 'is between',
        'eq': '=',
        'neq': '≠',
        'gt': '>',
        'gte': '≥',
        'lt': '<',
        'lte': '≤',
        'is_checked': 'is checked',
        'is_not_checked': 'is not checked',
      };
      for (final kind in FieldKind.values) {
        for (final op in operatorsFor(kind)) {
          expect(operatorLabel(op), labels[op], reason: op);
        }
      }
      expect(operatorNeedsValue('is_empty'), isFalse);
      expect(operatorNeedsValue('is_checked'), isFalse);
      expect(operatorNeedsValue('contains'), isTrue);
    });

    test('date presets all have labels', () {
      expect(datePresets, hasLength(11));
      for (final preset in datePresets) {
        expect(datePresetLabel(preset), isNot(preset), reason: preset);
      }
      expect(datePresetLabel('this_week'), 'This week');
      expect(datePresetLabel('past'), 'In the past');
    });
  });

  group('resolveDateRange', () {
    test('from a Saturday', () {
      final now = _saturday;
      expect(resolveDateRange('today', now), (from: '2026-09-12', to: '2026-09-12'));
      expect(resolveDateRange('yesterday', now), (from: '2026-09-11', to: '2026-09-11'));
      expect(resolveDateRange('tomorrow', now), (from: '2026-09-13', to: '2026-09-13'));
      expect(resolveDateRange('this_week', now), (from: '2026-09-07', to: '2026-09-13'));
      expect(resolveDateRange('last_week', now), (from: '2026-08-31', to: '2026-09-06'));
      expect(resolveDateRange('next_week', now), (from: '2026-09-14', to: '2026-09-20'));
      expect(resolveDateRange('this_month', now), (from: '2026-09-01', to: '2026-09-30'));
      expect(resolveDateRange('last_month', now), (from: '2026-08-01', to: '2026-08-31'));
      expect(resolveDateRange('next_month', now), (from: '2026-10-01', to: '2026-10-31'));
      expect(resolveDateRange('past', now), (from: '0001-01-01', to: '2026-09-11'));
      expect(resolveDateRange('future', now), (from: '2026-09-13', to: '9999-12-31'));
    });

    test('from a Monday the week starts today', () {
      expect(resolveDateRange('this_week', _monday), (from: '2026-09-14', to: '2026-09-20'));
      expect(resolveDateRange('last_week', _monday), (from: '2026-09-07', to: '2026-09-13'));
      expect(resolveDateRange('next_week', _monday), (from: '2026-09-21', to: '2026-09-27'));
    });

    test('a Sunday still belongs to the week that started the previous Monday', () {
      final sunday = DateTime(2026, 9, 13, 23, 59);
      expect(resolveDateRange('this_week', sunday), (from: '2026-09-07', to: '2026-09-13'));
    });

    test('month presets roll over years', () {
      final jan = DateTime(2026, 1, 15);
      expect(resolveDateRange('last_month', jan), (from: '2025-12-01', to: '2025-12-31'));
      final dec = DateTime(2026, 12, 31);
      expect(resolveDateRange('next_month', dec), (from: '2027-01-01', to: '2027-01-31'));
      expect(resolveDateRange('this_month', DateTime(2028, 2, 10)), (from: '2028-02-01', to: '2028-02-29'));
    });

    test('a literal date is a one-day range', () {
      expect(resolveDateRange('2026-03-04', _saturday), (from: '2026-03-04', to: '2026-03-04'));
    });
  });

  group('ViewContext.forBoard', () {
    test('derives member names, group ids and auto-number index', () {
      final ctx = _ctx();
      expect(ctx.meUserId, 'u1');
      expect(ctx.memberNames, {'u1': 'Zed Ali', 'u2': 'Amy Brown'});
      expect(ctx.groupIdByItemId['i1'], 'g1');
      expect(ctx.groupIdByItemId['i4'], 'g2');
      expect(ctx.groupIdByItemId['sub1'], 'g1', reason: 'subitems belong to the parent group');
      expect(ctx.indexByItemId, {'i1': 1, 'i2': 2, 'i3': 3, 'i4': 4});
      expect(flattenForAutoNumber(_board()).map((i) => i.id), ['i1', 'i2', 'i3', 'i4']);
      expect(autoNumberIndex(_board())['i4'], 4);
    });
  });

  group('matchesRule text', () {
    test('contains is case-insensitive and false on empty cells', () {
      expect(_match(_alpha, 'c_text', 'contains', 'hello'), isTrue);
      expect(_match(_alpha, 'c_text', 'contains', 'WORLD'), isTrue);
      expect(_match(_beta, 'c_text', 'contains', 'hello'), isFalse);
      expect(_match(_gamma, 'c_text', 'contains', 'hello'), isFalse);
    });

    test('not_contains is true on empty cells', () {
      expect(_match(_alpha, 'c_text', 'not_contains', 'hello'), isFalse);
      expect(_match(_beta, 'c_text', 'not_contains', 'hello'), isTrue);
      expect(_match(_gamma, 'c_text', 'not_contains', 'hello'), isTrue);
    });

    test('is / is_not compare whole values case-insensitively', () {
      expect(_match(_alpha, 'c_text', 'is', 'hello world'), isTrue);
      expect(_match(_alpha, 'c_text', 'is', 'hello'), isFalse);
      expect(_match(_alpha, 'c_text', 'is_not', 'hello'), isTrue);
      expect(_match(_gamma, 'c_text', 'is', 'x'), isFalse);
      expect(_match(_gamma, 'c_text', 'is_not', 'x'), isTrue);
    });

    test('is_empty / is_not_empty', () {
      expect(_match(_gamma, 'c_text', 'is_empty'), isTrue);
      expect(_match(_alpha, 'c_text', 'is_empty'), isFalse);
      expect(_match(_alpha, 'c_text', 'is_not_empty'), isTrue);
      expect(_match(_gamma, 'c_text', 'is_not_empty'), isFalse);
      final blank = _alpha.withCell('c_text', {'text': ''});
      expect(_match(blank, 'c_text', 'is_empty'), isTrue, reason: 'an empty string counts as empty');
    });

    test('name is a text field', () {
      expect(_match(_alpha, 'name', 'contains', 'alp'), isTrue);
      expect(_match(_alpha, 'name', 'is', 'ALPHA'), isTrue);
      expect(_match(_alpha, 'name', 'is_empty'), isFalse);
    });

    test('reads the right key for each text-ish type', () {
      expect(_match(_alpha, 'c_long', 'contains', 'body'), isTrue);
      expect(_match(_alpha, 'c_link', 'contains', 'example.com'), isTrue);
      expect(_match(_alpha, 'c_email', 'is', 'Alpha@Example.com'), isTrue);
      expect(_match(_alpha, 'c_phone', 'contains', '555'), isTrue);
      expect(_match(_alpha, 'c_location', 'contains', 'paris'), isTrue);
      expect(_match(_gamma, 'c_link', 'is_empty'), isTrue);
    });
  });

  group('matchesRule choice', () {
    test('status is_any_of / is_none_of / empty', () {
      expect(_match(_alpha, 'c_status', 'is_any_of', ['todo', 'done']), isTrue);
      expect(_match(_delta, 'c_status', 'is_any_of', ['todo', 'done']), isFalse);
      expect(_match(_alpha, 'c_status', 'is_none_of', ['todo']), isFalse);
      expect(_match(_delta, 'c_status', 'is_none_of', ['todo']), isTrue);
      expect(_match(_gamma, 'c_status', 'is_none_of', ['todo']), isTrue, reason: 'empty is none of anything');
      expect(_match(_gamma, 'c_status', 'is_any_of', ['todo']), isFalse);
      expect(_match(_gamma, 'c_status', 'is_empty'), isTrue);
      expect(_match(_alpha, 'c_status', 'is_not_empty'), isTrue);
    });

    test('tags overlap on any selected option', () {
      expect(_match(_alpha, 'c_tags', 'is_any_of', ['b']), isTrue);
      expect(_match(_alpha, 'c_tags', 'is_any_of', ['c']), isFalse);
      expect(_match(_alpha, 'c_tags', 'is_none_of', ['c']), isTrue);
      expect(_match(_alpha, 'c_tags', 'is_none_of', ['a', 'c']), isFalse);
      expect(_match(_gamma, 'c_tags', 'is_empty'), isTrue);
      final emptyList = _alpha.withCell('c_tags', {'optionIds': <String>[]});
      expect(_match(emptyList, 'c_tags', 'is_empty'), isTrue);
    });

    test('dropdown accepts a single string value too', () {
      expect(_match(_beta, 'c_dropdown', 'is_any_of', 'high'), isTrue);
      expect(_match(_beta, 'c_dropdown', 'is_any_of', ['low', 'med']), isFalse);
    });
  });

  group('matchesRule people', () {
    test("'me' resolves to the current user", () {
      expect(_match(_alpha, 'c_people', 'is_any_of', ['me']), isTrue);
      expect(_match(_beta, 'c_people', 'is_any_of', ['me']), isFalse);
      expect(_match(_beta, 'c_people', 'is_none_of', ['me']), isTrue);
      expect(_match(_delta, 'c_people', 'is_any_of', ['me']), isTrue, reason: 'second assignee');
    });

    test("'me' matches nobody when signed-out context", () {
      final ctx = _ctx(me: null);
      expect(matchesRule(_alpha, _rule('c_people', 'is_any_of', ['me']), _columns, ctx), isFalse);
      expect(matchesRule(_alpha, _rule('c_people', 'is_any_of', ['me', 'u1']), _columns, ctx), isTrue);
    });

    test('empty checks and vote column', () {
      expect(_match(_gamma, 'c_people', 'is_empty'), isTrue);
      expect(_match(_gamma, 'c_people', 'is_none_of', ['u1']), isTrue);
      expect(_match(_alpha, 'c_people', 'is_not_empty'), isTrue);
      expect(_match(_alpha, 'c_vote', 'is_any_of', ['u2']), isTrue);
      expect(_match(_delta, 'c_vote', 'is_none_of', ['me']), isTrue);
    });
  });

  group('matchesRule date', () {
    test('is with a preset means inside the range', () {
      expect(_match(_alpha, 'c_date', 'is', 'today'), isTrue);
      expect(_match(_beta, 'c_date', 'is', 'today'), isFalse);
      expect(_match(_beta, 'c_date', 'is', 'this_week'), isFalse, reason: 'Sep 5 is last week');
      expect(_match(_beta, 'c_date', 'is', 'last_week'), isTrue);
      expect(_match(_alpha, 'c_date', 'is', 'this_week'), isTrue);
      expect(_match(_delta, 'c_date', 'is', 'next_week'), isTrue);
      expect(_match(_delta, 'c_date', 'is', 'this_month'), isTrue);
      expect(_match(_delta, 'c_date', 'is', 'future'), isTrue);
      expect(_match(_beta, 'c_date', 'is', 'past'), isTrue);
      expect(_match(_alpha, 'c_date', 'is', 'past'), isFalse);
      expect(_match(_alpha, 'c_date', 'is', 'future'), isFalse);
    });

    test('is with a literal date', () {
      expect(_match(_beta, 'c_date', 'is', '2026-09-05'), isTrue);
      expect(_match(_beta, 'c_date', 'is', '2026-09-06'), isFalse);
    });

    test('is_before compares to the range start, is_after to the range end', () {
      expect(_match(_beta, 'c_date', 'is_before', 'today'), isTrue);
      expect(_match(_alpha, 'c_date', 'is_before', 'today'), isFalse);
      expect(_match(_alpha, 'c_date', 'is_before', 'this_week'), isFalse);
      expect(_match(_beta, 'c_date', 'is_before', 'this_week'), isTrue);
      expect(_match(_delta, 'c_date', 'is_after', 'this_week'), isTrue);
      expect(_match(_alpha, 'c_date', 'is_after', 'this_week'), isFalse, reason: 'Saturday is inside the week');
      expect(_match(_delta, 'c_date', 'is_after', 'today'), isTrue);
      expect(_match(_delta, 'c_date', 'is_after', '2026-09-14'), isFalse);
      expect(_match(_delta, 'c_date', 'is_after', '2026-09-13'), isTrue);
    });

    test('is_between accepts a [from,to] list, a map, and presets', () {
      expect(_match(_alpha, 'c_date', 'is_between', ['2026-09-10', '2026-09-12']), isTrue);
      expect(_match(_alpha, 'c_date', 'is_between', ['2026-09-10', '2026-09-11']), isFalse);
      expect(_match(_alpha, 'c_date', 'is_between', {'from': '2026-09-12', 'to': '2026-09-30'}), isTrue);
      expect(_match(_beta, 'c_date', 'is_between', ['last_week', 'this_week']), isTrue);
      expect(_match(_alpha, 'c_date', 'is_between', ['bogus']), isFalse);
    });

    test('empty cells never match comparisons but do match is_empty', () {
      expect(_match(_gamma, 'c_date', 'is', 'today'), isFalse);
      expect(_match(_gamma, 'c_date', 'is_before', 'today'), isFalse);
      expect(_match(_gamma, 'c_date', 'is_after', 'past'), isFalse);
      expect(_match(_gamma, 'c_date', 'is_empty'), isTrue);
      expect(_match(_alpha, 'c_date', 'is_empty'), isFalse);
      expect(_match(_alpha, 'c_date', 'is_not_empty'), isTrue);
    });

    test('timeline uses from; creation/last-updated logs use item timestamps', () {
      expect(_match(_alpha, 'c_timeline', 'is', '2026-09-01'), isTrue);
      expect(_match(_alpha, 'c_timeline', 'is', '2026-09-20'), isFalse);
      expect(_match(_beta, 'c_timeline', 'is', 'last_week'), isFalse);
      expect(_match(_beta, 'c_timeline', 'is', 'this_week'), isTrue);
      expect(_match(_gamma, 'c_timeline', 'is_empty'), isTrue);

      expect(_match(_alpha, 'c_created', 'is', '2026-09-01'), isTrue);
      expect(_match(_alpha, 'c_created', 'is', 'this_month'), isTrue);
      expect(_match(_gamma, 'c_created', 'is', 'last_month'), isTrue);
      expect(_match(_gamma, 'c_created', 'is_not_empty'), isTrue);
      expect(_match(_delta, 'c_updated', 'is', 'today'), isTrue);
      expect(_match(_alpha, 'c_updated', 'is_before', 'today'), isTrue);
    });
  });

  group('matchesRule number', () {
    test('all comparisons on a number column', () {
      expect(_match(_beta, 'c_number', 'eq', 20), isTrue);
      expect(_match(_beta, 'c_number', 'eq', 21), isFalse);
      expect(_match(_beta, 'c_number', 'neq', 21), isTrue);
      expect(_match(_beta, 'c_number', 'neq', 20), isFalse);
      expect(_match(_beta, 'c_number', 'gt', 19.9), isTrue);
      expect(_match(_beta, 'c_number', 'gt', 20), isFalse);
      expect(_match(_beta, 'c_number', 'gte', 20), isTrue);
      expect(_match(_beta, 'c_number', 'lt', 20), isFalse);
      expect(_match(_delta, 'c_number', 'lt', 0), isTrue);
      expect(_match(_beta, 'c_number', 'lte', 20), isTrue);
      expect(_match(_alpha, 'c_number', 'lte', 10), isFalse);
    });

    test('value strings are coerced; garbage never matches', () {
      expect(_match(_beta, 'c_number', 'eq', '20'), isTrue);
      expect(_match(_beta, 'c_number', 'gt', ' 5 '), isTrue);
      expect(_match(_beta, 'c_number', 'gt', 'abc'), isFalse);
      expect(_match(_beta, 'c_number', 'eq', null), isFalse);
    });

    test('missing values: neq is true, everything else false', () {
      expect(_match(_gamma, 'c_number', 'eq', 0), isFalse);
      expect(_match(_gamma, 'c_number', 'neq', 0), isTrue);
      expect(_match(_gamma, 'c_number', 'gt', -1), isFalse);
      expect(_match(_gamma, 'c_number', 'is_empty'), isTrue);
      expect(_match(_gamma, 'c_number', 'is_not_empty'), isFalse);
      expect(_match(_alpha, 'c_number', 'is_not_empty'), isTrue);
    });

    test('rating, item_id (serial) and auto_number (board index)', () {
      expect(_match(_delta, 'c_rating', 'gte', 5), isTrue);
      expect(_match(_beta, 'c_rating', 'lt', 3), isTrue);
      expect(_match(_gamma, 'c_rating', 'is_empty'), isTrue);

      expect(_match(_delta, 'c_itemid', 'eq', 4), isTrue);
      expect(_match(_alpha, 'c_itemid', 'lte', 1), isTrue);
      expect(_match(_alpha, 'c_itemid', 'is_not_empty'), isTrue);

      expect(_match(_delta, 'c_auto', 'eq', 4), isTrue, reason: 'delta is the 4th top-level item');
      expect(_match(_gamma, 'c_auto', 'eq', 3), isTrue);
      expect(_match(_gamma, 'c_auto', 'is_not_empty'), isTrue);
      final unknown = _item('zz', 'Z', serial: 99, position: 9);
      expect(_match(unknown, 'c_auto', 'is_empty'), isTrue, reason: 'not on the board, no index');
    });
  });

  group('matchesRule checkbox, group, files', () {
    test('checkbox', () {
      expect(_match(_alpha, 'c_check', 'is_checked'), isTrue);
      expect(_match(_beta, 'c_check', 'is_checked'), isFalse, reason: 'explicit false');
      expect(_match(_gamma, 'c_check', 'is_checked'), isFalse, reason: 'missing');
      expect(_match(_gamma, 'c_check', 'is_not_checked'), isTrue);
      expect(_match(_alpha, 'c_check', 'is_not_checked'), isFalse);
    });

    test('group uses the context map', () {
      expect(_match(_alpha, 'group', 'is_any_of', ['g1']), isTrue);
      expect(_match(_delta, 'group', 'is_any_of', ['g1']), isFalse);
      expect(_match(_delta, 'group', 'is_none_of', ['g1']), isTrue);
      expect(_match(_delta, 'group', 'is_none_of', ['g1', 'g2']), isFalse);
      final orphan = _item('zz', 'Z', serial: 99, position: 9);
      expect(_match(orphan, 'group', 'is_any_of', ['g1']), isFalse);
      expect(_match(orphan, 'group', 'is_none_of', ['g1']), isTrue);
    });

    test('files', () {
      expect(_match(_alpha, 'c_files', 'is_not_empty'), isTrue);
      expect(_match(_alpha, 'c_files', 'is_empty'), isFalse);
      expect(_match(_gamma, 'c_files', 'is_empty'), isTrue);
      final emptyList = _alpha.withCell('c_files', {'fileIds': <String>[]});
      expect(_match(emptyList, 'c_files', 'is_empty'), isTrue);
    });
  });

  group('matchesRule validity', () {
    test('an unknown field or an operator invalid for the kind never matches', () {
      expect(_match(_alpha, 'nope', 'is_empty'), isFalse);
      expect(_match(_alpha, 'c_text', 'gt', 1), isFalse);
      expect(_match(_alpha, 'c_check', 'is_empty'), isFalse);
      expect(_match(_alpha, 'c_number', 'contains', '1'), isFalse);
    });
  });

  group('matchesFilters', () {
    final ctx = _ctx();

    test('null or empty group passes everything', () {
      expect(matchesFilters(_gamma, null, _columns, ctx), isTrue);
      expect(matchesFilters(_gamma, const FilterGroup(), _columns, ctx), isTrue);
    });

    test('and requires every rule, or requires one', () {
      final rules = [_rule('c_status', 'is_any_of', ['todo']), _rule('c_people', 'is_any_of', ['me'])];
      final and = FilterGroup(conjunction: 'and', rules: rules);
      final or = FilterGroup(conjunction: 'or', rules: rules);
      expect(matchesFilters(_alpha, and, _columns, ctx), isTrue);
      expect(matchesFilters(_delta, and, _columns, ctx), isFalse, reason: 'working, but assigned to me');
      expect(matchesFilters(_delta, or, _columns, ctx), isTrue);
      expect(matchesFilters(_beta, or, _columns, ctx), isFalse);
    });

    test('rules on deleted columns or with bad operators are skipped', () {
      final group = FilterGroup(rules: [_rule('deleted', 'is_empty'), _rule('c_status', 'is_any_of', ['done'])]);
      expect(matchesFilters(_beta, group, _columns, ctx), isTrue);
      expect(matchesFilters(_alpha, group, _columns, ctx), isFalse);
      final onlyBad = FilterGroup(conjunction: 'or', rules: [_rule('deleted', 'is_empty'), _rule('c_text', 'gt', 1)]);
      expect(matchesFilters(_gamma, onlyBad, _columns, ctx), isTrue, reason: 'nothing usable → pass');
    });
  });

  group('compareItems', () {
    test('name is case-insensitive, both directions', () {
      expect(_sorted(all, 'name', 'asc'), ['i1', 'i2', 'i4', 'i3']);
      expect(_sorted(all, 'name', 'desc'), ['i3', 'i4', 'i2', 'i1']);
    });

    test('status by label index with missing last in both directions', () {
      expect(_sorted(all, 'c_status', 'asc'), ['i1', 'i4', 'i2', 'i3']);
      expect(_sorted(all, 'c_status', 'desc'), ['i2', 'i4', 'i1', 'i3']);
    });

    test('dropdown and tags by first option index', () {
      expect(_sorted(all, 'c_dropdown', 'asc'), ['i1', 'i4', 'i2', 'i3']);
      expect(_sorted(all, 'c_dropdown', 'desc'), ['i2', 'i4', 'i1', 'i3']);
      // alpha [a,b] → a(0); delta [b] → 1; beta [c] → 2
      expect(_sorted(all, 'c_tags', 'asc'), ['i1', 'i4', 'i2', 'i3']);
    });

    test('people by first assignee display name', () {
      // alpha → Zed Ali, beta → Amy Brown, delta → [u2,u1] → Amy Brown (tie → position 1 beats 2)
      expect(_sorted(all, 'c_people', 'asc'), ['i4', 'i2', 'i1', 'i3']);
      expect(_sorted(all, 'c_people', 'desc'), ['i1', 'i4', 'i2', 'i3']);
    });

    test('people fall back to the id when the member is unknown', () {
      final ctx = ViewContext(now: _saturday);
      expect(_sorted([_alpha, _beta], 'c_people', 'asc', ctx: ctx), ['i1', 'i2'], reason: "'u1' < 'u2'");
    });

    test('text-ish case-insensitive', () {
      expect(_sorted(all, 'c_text', 'asc'), ['i4', 'i1', 'i2', 'i3']);
      expect(_sorted(all, 'c_text', 'desc'), ['i2', 'i1', 'i4', 'i3']);
    });

    test('dates by string, timeline by from, logs by timestamp', () {
      expect(_sorted(all, 'c_date', 'asc'), ['i2', 'i1', 'i4', 'i3']);
      expect(_sorted(all, 'c_date', 'desc'), ['i4', 'i1', 'i2', 'i3']);
      // gamma and delta have no timeline: both last, ordered by position (delta 1 < gamma 3).
      expect(_sorted(all, 'c_timeline', 'asc'), ['i1', 'i2', 'i4', 'i3']);
      expect(_sorted(all, 'c_created', 'asc'), ['i3', 'i1', 'i2', 'i4']);
      expect(_sorted(all, 'c_updated', 'desc'), ['i4', 'i2', 'i1', 'i3']);
      expect(_sorted(all, 'created_at', 'desc'), ['i4', 'i2', 'i1', 'i3']);
      expect(_sorted(all, 'updated_at', 'asc'), ['i3', 'i1', 'i2', 'i4']);
    });

    test('numbers numeric, rating, serial, item_id and auto_number', () {
      expect(_sorted(all, 'c_number', 'asc'), ['i4', 'i1', 'i2', 'i3']);
      expect(_sorted(all, 'c_number', 'desc'), ['i2', 'i1', 'i4', 'i3']);
      expect(_sorted(all, 'c_rating', 'desc'), ['i4', 'i1', 'i2', 'i3']);
      expect(_sorted(all, 'serial', 'desc'), ['i4', 'i3', 'i2', 'i1']);
      expect(_sorted(all, 'c_itemid', 'asc'), ['i1', 'i2', 'i3', 'i4']);
      expect(_sorted(all.reversed.toList(), 'c_auto', 'asc'), ['i1', 'i2', 'i3', 'i4']);
    });

    test('checkbox: checked first on asc, unchecked and missing are both "unchecked"', () {
      expect(_sorted(all, 'c_check', 'asc'), ['i1', 'i4', 'i2', 'i3']);
      expect(_sorted(all, 'c_check', 'desc'), ['i4', 'i2', 'i3', 'i1']);
    });

    test('files by count, missing last', () {
      expect(_sorted([_gamma, _alpha], 'c_files', 'asc'), ['i1', 'i3']);
      expect(_sorted([_gamma, _alpha], 'c_files', 'desc'), ['i1', 'i3']);
    });

    test('ties fall back to board position, then id', () {
      expect(_sorted(all, 'c_long', 'asc'), ['i1', 'i4', 'i2', 'i3'], reason: 'only alpha has a value');
      final twin = _item('i0', 'Alpha', serial: 5, position: 1);
      expect(_sorted([_alpha, twin], 'name', 'asc'), ['i0', 'i1']);
    });

    test('multiple rules apply in order', () {
      final ctx = _ctx();
      final rules = [const SortRule(field: 'c_check', direction: 'desc'), const SortRule(field: 'name', direction: 'desc')];
      final copy = [...all]..sort((a, b) => compareItems(a, b, rules, _columns, ctx));
      expect(copy.map((i) => i.id), ['i3', 'i4', 'i2', 'i1']);
    });

    test('an unknown sort field is a no-op', () {
      expect(_sorted(all, 'deleted', 'asc'), ['i1', 'i4', 'i2', 'i3'], reason: 'position, then id');
    });
  });

  group('applyView', () {
    test('filters top-level items per group and keeps empty groups', () {
      final board = _board();
      final config = ViewConfig(filters: FilterGroup(rules: [_rule('c_status', 'is_any_of', ['done'])]));
      final groups = applyView(board, config, _ctx());
      expect(groups.map((g) => g.id), ['g1', 'g2']);
      expect(groups[0].items.map((i) => i.id), ['i2']);
      expect(groups[1].items, isEmpty);
      expect(board.groups[0].items, hasLength(3), reason: 'input untouched');
    });

    test('or conjunction and extraFilter applied on top', () {
      final config = ViewConfig(
        filters: FilterGroup(conjunction: 'or', rules: [
          _rule('c_status', 'is_any_of', ['done']),
          _rule('c_people', 'is_any_of', ['me']),
        ]),
      );
      final groups = applyView(_board(), config, _ctx());
      expect(groups[0].items.map((i) => i.id), ['i1', 'i2']);
      expect(groups[1].items.map((i) => i.id), ['i4']);

      final quick = applyView(_board(), config, _ctx(), extraFilter: (i) => i.name.startsWith('b'));
      expect(quick[0].items.map((i) => i.id), ['i2']);
      expect(quick[1].items, isEmpty);
    });

    test('sorts when configured and leaves board order otherwise', () {
      final unsorted = applyView(_board(), const ViewConfig.empty(), _ctx());
      expect(unsorted[0].items.map((i) => i.id), ['i1', 'i2', 'i3']);
      final sorted = applyView(
        _board(),
        const ViewConfig(sort: [SortRule(field: 'c_number', direction: 'desc')]),
        _ctx(),
      );
      expect(sorted[0].items.map((i) => i.id), ['i2', 'i1', 'i3']);
      expect(_board().groups[0].items.map((i) => i.id), ['i1', 'i2', 'i3'], reason: 'source list not sorted in place');
    });

    test('subitems ride with their parent and are not filtered', () {
      final config = ViewConfig(filters: FilterGroup(rules: [_rule('c_status', 'is_any_of', ['todo'])]));
      final board = _board();
      final groups = applyView(board, config, _ctx());
      final kept = groups[0].items.single;
      expect(identical(kept, board.groups[0].items.first), isTrue);
      expect(kept.subitems, hasLength(1));
    });
  });

  group('visibleColumns', () {
    test('defaults to the items scope in board order', () {
      final visible = visibleColumns(_columns, const ViewConfig.empty());
      expect(visible.map((c) => c.id), isNot(contains('s_status')));
      expect(visible, hasLength(21));
      expect(visible.first.id, 'c_status');
    });

    test('scope subitems returns only subitem columns', () {
      expect(visibleColumns(_columns, const ViewConfig.empty(), scope: 'subitems').map((c) => c.id), ['s_status', 's_owner']);
    });

    test('hidden ids are dropped', () {
      final visible = visibleColumns(_columns, const ViewConfig(hiddenColumnIds: ['c_status', 'c_auto']));
      expect(visible.map((c) => c.id), isNot(contains('c_status')));
      expect(visible.map((c) => c.id), isNot(contains('c_auto')));
      expect(visible, hasLength(19));
    });

    test('columnOrder first, then the rest in board order; unknown ids ignored', () {
      final visible = visibleColumns(
        _columns,
        const ViewConfig(columnOrder: ['c_number', 'ghost', 'c_status', 's_status'], hiddenColumnIds: ['c_people']),
      );
      expect(visible.take(3).map((c) => c.id), ['c_number', 'c_status', 'c_date']);
      expect(visible.map((c) => c.id), isNot(contains('c_people')));
      expect(visible.map((c) => c.id), isNot(contains('s_status')));
    });

    test('columns without a scope count as items', () {
      final legacy = BoardColumn.fromJson({'id': 'x', 'type': 'text', 'title': 'X', 'position': 1});
      expect(visibleColumns([legacy], const ViewConfig.empty()).single.id, 'x');
    });
  });

  group('conditional colors', () {
    final config = ViewConfig(conditionalColors: [
      ConditionalColor(id: 'a', field: 'c_status', operator: 'is_any_of', value: const ['done'], color: 'green', applyTo: 'cell'),
      const ConditionalColor(id: 'b', field: 'c_number', operator: 'gt', value: 15, color: 'red', applyTo: 'row'),
      const ConditionalColor(id: 'c', field: 'c_number', operator: 'gt', value: 0, color: 'blue', applyTo: 'cell'),
      const ConditionalColor(id: 'd', field: 'c_number', operator: 'gt', value: 5, color: 'purple', applyTo: 'cell'),
      const ConditionalColor(id: 'e', field: 'c_people', operator: 'is_any_of', value: ['me'], color: 'teal', applyTo: 'row'),
    ]);
    final number = _columns.firstWhere((c) => c.id == 'c_number');
    final status = _columns.firstWhere((c) => c.id == 'c_status');

    test('cell colors only come from cell rules on that column; first match wins', () {
      expect(cellColorFor(_beta, status, config, _columns, _ctx()), 'green');
      expect(cellColorFor(_alpha, status, config, _columns, _ctx()), isNull);
      expect(cellColorFor(_beta, number, config, _columns, _ctx()), 'blue', reason: 'c before d; b is a row rule');
      expect(cellColorFor(_delta, number, config, _columns, _ctx()), isNull, reason: 'negative number');
      expect(cellColorFor(_gamma, number, config, _columns, _ctx()), isNull);
    });

    test('row colors only come from row rules; first match wins', () {
      expect(rowColorFor(_beta, config, _columns, _ctx()), 'red');
      expect(rowColorFor(_alpha, config, _columns, _ctx()), 'teal');
      expect(rowColorFor(_delta, config, _columns, _ctx()), 'teal', reason: 'number rule fails, people rule matches me');
      expect(rowColorFor(_gamma, config, _columns, _ctx()), isNull);
    });

    test('no rules → null', () {
      expect(cellColorFor(_beta, status, const ViewConfig.empty(), _columns, _ctx()), isNull);
      expect(rowColorFor(_beta, const ViewConfig.empty(), _columns, _ctx()), isNull);
    });
  });

  group('summarize', () {
    BoardColumn numberCol(Map<String, dynamic> settings) => _col('c_number', 'number', settings: settings);

    test('number sum is the default, formatted with the column settings', () {
      final s = summarize(numberCol({'unit': r'$', 'unitPosition': 'prefix', 'decimals': 2}), all);
      expect(s, isA<NumberSummary>());
      final n = s! as NumberSummary;
      expect(n.mode, 'sum');
      expect(n.value, closeTo(27.25, 1e-9));
      expect(n.formatted, r'$27.25');
    });

    test('number avg / min / max / count', () {
      expect((summarize(numberCol({'summary': 'avg'}), all)! as NumberSummary).formatted, '9.08');
      expect((summarize(numberCol({'summary': 'min'}), all)! as NumberSummary).formatted, '-3.25');
      expect((summarize(numberCol({'summary': 'max'}), all)! as NumberSummary).formatted, '20');
      final count = summarize(numberCol({'summary': 'count', 'unit': 'kg'}), all)! as NumberSummary;
      expect(count.value, 3);
      expect(count.mode, 'count');
      expect(count.formatted, '3', reason: 'count never carries the unit');
    });

    test('number none hides and empty columns give null', () {
      expect(summarize(numberCol({'summary': 'none'}), all), isNull);
      expect(summarize(numberCol({}), [_gamma]), isNull);
      expect(summarize(numberCol({'summary': 'count'}), [_gamma]), isNull);
    });

    test('rating average with one decimal', () {
      final r = summarize(_columns.firstWhere((c) => c.id == 'c_rating'), all)! as RatingSummary;
      expect(r.average, closeTo(11 / 3, 1e-9));
      expect(r.formatted, '★ 3.7');
      expect(summarize(_columns.firstWhere((c) => c.id == 'c_rating'), [_gamma]), isNull);
    });

    test('status distribution in label order with total', () {
      final s = summarize(_columns.firstWhere((c) => c.id == 'c_status'), all)! as StatusSummary;
      expect(s.counts.keys.toList(), ['todo', 'working', 'done']);
      expect(s.counts, {'todo': 1, 'working': 1, 'done': 1});
      expect(s.total, 4);
      expect(summarize(_columns.firstWhere((c) => c.id == 'c_status'), const []), isNull);
      final unlabelled = summarize(_columns.firstWhere((c) => c.id == 'c_status'), [_gamma])! as StatusSummary;
      expect(unlabelled.counts, isEmpty);
      expect(unlabelled.total, 1);
    });

    test('checkbox checked/total', () {
      final s = summarize(_columns.firstWhere((c) => c.id == 'c_check'), all)! as CheckboxSummary;
      expect(s.checked, 1);
      expect(s.total, 4);
      expect(s.formatted, '1/4');
      expect(summarize(_columns.firstWhere((c) => c.id == 'c_check'), const []), isNull);
    });

    test('people distinct assignees', () {
      final s = summarize(_columns.firstWhere((c) => c.id == 'c_people'), all)! as PeopleSummary;
      expect(s.distinct, 2);
      expect(summarize(_columns.firstWhere((c) => c.id == 'c_people'), [_gamma]), isNull);
    });

    test('date min–max and timeline earliest from – latest to', () {
      final d = summarize(_columns.firstWhere((c) => c.id == 'c_date'), all)! as DateRangeSummary;
      expect(d.from, '2026-09-05');
      expect(d.to, '2026-09-14');
      expect(d.formatted, 'Sep 5 – Sep 14');
      final single = summarize(_columns.firstWhere((c) => c.id == 'c_date'), [_alpha])! as DateRangeSummary;
      expect(single.formatted, 'Sep 12');
      final t = summarize(_columns.firstWhere((c) => c.id == 'c_timeline'), all)! as DateRangeSummary;
      expect(t.from, '2026-09-01');
      expect(t.to, '2026-09-30');
      expect(t.formatted, 'Sep 1 – Sep 30');
      expect(summarize(_columns.firstWhere((c) => c.id == 'c_date'), [_gamma]), isNull);
    });

    test('types without a summary return null', () {
      for (final id in ['c_text', 'c_long', 'c_dropdown', 'c_tags', 'c_link', 'c_email', 'c_phone', 'c_location', 'c_files', 'c_vote', 'c_itemid', 'c_created', 'c_updated', 'c_auto']) {
        expect(summarize(_columns.firstWhere((c) => c.id == id), all), isNull, reason: id);
      }
    });
  });

  group('formatNumberCell', () {
    BoardColumn col(Map<String, dynamic> settings) => _col('n', 'number', settings: settings);

    test('prefix unit with fixed decimals', () {
      expect(formatNumberCell(col({'unit': r'$', 'unitPosition': 'prefix', 'decimals': 2}), 1234.5), r'$1,234.50');
      expect(formatNumberCell(col({'unit': '€', 'unitPosition': 'prefix', 'decimals': 0}), 1234.5), '€1,235');
    });

    test('suffix unit: glued when one character, spaced otherwise', () {
      expect(formatNumberCell(col({'unit': '%'}), 50), '50%');
      expect(formatNumberCell(col({'unit': 'kg', 'unitPosition': 'suffix'}), 3), '3 kg');
      expect(formatNumberCell(col({'unit': 'kg', 'decimals': 1}), 3), '3.0 kg');
    });

    test('defaults: integers plain, otherwise up to two decimals', () {
      expect(formatNumberCell(col({}), 1000), '1,000');
      expect(formatNumberCell(col({}), 1000.0), '1,000');
      expect(formatNumberCell(col({}), 2.5), '2.5');
      expect(formatNumberCell(col({}), 2.456), '2.46');
      expect(formatNumberCell(col({}), -0.125), '-0.13');
    });

    test('decimals are clamped to 0..6', () {
      expect(formatNumberCell(col({'decimals': 9}), 1), '1.000000');
      expect(formatNumberCell(col({'decimals': -2}), 1.7), '2');
    });
  });

  group('ViewConfig json', () {
    test('empty config serialises to an empty map and reports empty', () {
      const empty = ViewConfig.empty();
      expect(empty.toJson(), <String, dynamic>{});
      expect(empty.isEmpty, isTrue);
      expect(empty.hasFilters, isFalse);
      expect(empty.hasSort, isFalse);
      expect(ViewConfig.fromJson(const {}).isEmpty, isTrue);
    });

    test('empty lists and a filter group without rules are omitted', () {
      const config = ViewConfig(filters: FilterGroup(), sort: [], hiddenColumnIds: [], laneColumnId: 'c_status');
      expect(config.toJson(), {'laneColumnId': 'c_status'});
      expect(config.hasFilters, isFalse);
      expect(config.isEmpty, isFalse);
    });

    test('round-trips a full config', () {
      final json = <String, dynamic>{
        'filters': {
          'conjunction': 'or',
          'rules': [
            {'id': 'r1', 'field': 'c_status', 'operator': 'is_any_of', 'value': ['done']},
            {'id': 'r2', 'field': 'c_text', 'operator': 'is_empty'},
          ],
        },
        'sort': [
          {'field': 'name', 'direction': 'desc'},
        ],
        'hiddenColumnIds': ['c_auto'],
        'columnOrder': ['c_number', 'c_status'],
        'conditionalColors': [
          {'id': 'k1', 'field': 'c_number', 'operator': 'gt', 'value': 10, 'color': 'red', 'applyTo': 'row'},
        ],
        'laneColumnId': 'c_status',
        'dateColumnId': 'c_date',
      };
      final config = ViewConfig.fromJson(json);
      expect(config.filters!.conjunction, 'or');
      expect(config.filters!.rules, hasLength(2));
      expect(config.filters!.rules[1].value, isNull);
      expect(config.sort.single.isDescending, isTrue);
      expect(config.conditionalColors.single.applyTo, 'row');
      expect(config.hasFilters, isTrue);
      expect(config.hasSort, isTrue);
      expect(config.toJson(), json);
    });

    test('defaults tolerate sparse json', () {
      final rule = FilterRule.fromJson(const {'field': 'name', 'operator': 'contains', 'value': 'a'});
      expect(rule.id, '');
      expect(FilterGroup.fromJson(const {}).conjunction, 'and');
      expect(SortRule.fromJson(const {'field': 'name'}).direction, 'asc');
      final color = ConditionalColor.fromJson(const {'field': 'name', 'operator': 'is_empty'});
      expect(color.color, 'blue');
      expect(color.applyTo, 'cell');
      expect(color.asRule.operator, 'is_empty');
      expect(ViewConfig.fromJson(const {'filters': 'garbage'}).filters, isNull);
    });

    test('copyWith replaces and clears', () {
      final base = ViewConfig.fromJson(const {
        'filters': {'conjunction': 'and', 'rules': [{'id': 'r', 'field': 'name', 'operator': 'is_empty'}]},
        'laneColumnId': 'c_status',
      });
      final cleared = base.copyWith(filters: () => null, laneColumnId: () => null, sort: const [SortRule(field: 'name')]);
      expect(cleared.filters, isNull);
      expect(cleared.laneColumnId, isNull);
      expect(cleared.sort.single.field, 'name');
      expect(base.filters, isNotNull, reason: 'immutable');

      final rule = base.filters!.rules.single.copyWith(operator: 'contains', value: () => 'x');
      expect(rule.operator, 'contains');
      expect(rule.value, 'x');
      expect(rule.copyWith(value: () => null).value, isNull);
      expect(base.filters!.copyWith(conjunction: 'or').conjunction, 'or');
      expect(const SortRule(field: 'a').copyWith(direction: 'desc').isDescending, isTrue);
      const color = ConditionalColor(id: 'k', field: 'name', operator: 'is_empty', color: 'red');
      expect(color.copyWith(applyTo: 'row', color: 'grey').toJson(), {
        'id': 'k',
        'field': 'name',
        'operator': 'is_empty',
        'color': 'grey',
        'applyTo': 'row',
      });
    });

    test('palette tokens', () {
      expect(viewColorPalette, ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo', 'grey']);
    });
  });
}
