import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/core/theme/theme.dart';
import 'package:dayflow/core/theme/tokens.dart';
import 'package:dayflow/features/board/board_filters.dart';
import 'package:dayflow/features/board/board_screen.dart';
import 'package:dayflow/features/board/filter_builder_sheet.dart';
import 'package:dayflow/features/board/sort_sheet.dart';
import 'package:dayflow/features/board/subitem_rows.dart';
import 'package:dayflow/features/board/summary_footer.dart';
import 'package:dayflow/features/board/view_engine.dart';
import 'package:dayflow/features/board/view_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- Fixture ----------

Map<String, dynamic> _col(String id, String type, String title, {Map<String, dynamic> settings = const {}, String scope = 'items'}) =>
    {'id': id, 'type': type, 'title': title, 'position': 0, 'scope': scope, 'settings': settings};

Map<String, dynamic> _item(
  String id,
  String name, {
  required double position,
  Map<String, dynamic> values = const {},
  List<Map<String, dynamic>> subitems = const [],
  String? parentItemId,
}) =>
    {
      'id': id,
      'name': name,
      'position': position,
      'updatesCount': 0,
      'serial': position.toInt(),
      'values': values,
      'parentItemId': parentItemId,
      'subitems': subitems,
    };

const _statusLabels = {
  'labels': [
    {'id': 'todo', 'label': 'To do', 'color': 'amber', 'isDone': false},
    {'id': 'done', 'label': 'Done', 'color': 'green', 'isDone': true},
  ],
};

BoardDetail _board({List<Map<String, dynamic>> views = const [], bool canEdit = true}) => BoardDetail.fromJson({
      'id': 'b1',
      'name': 'Launch',
      'type': 'main',
      'workspace': {'id': 'w1', 'name': 'Main workspace'},
      'isFavorite': false,
      'columns': [
        _col('c_status', 'status', 'Status', settings: _statusLabels),
        _col('c_num', 'number', 'Budget'),
        _col('c_text', 'text', 'Notes'),
        _col('s_status', 'status', 'Status', settings: _statusLabels, scope: 'subitems'),
      ],
      'groups': [
        {
          'id': 'g1',
          'title': 'This week',
          'color': 'blue',
          'collapsed': false,
          'items': [
            _item('i1', 'Alpha', position: 1, values: {
              'c_status': {'labelId': 'done'},
              'c_num': {'number': 10},
            }, subitems: [
              _item('s1', 'Sub one', position: 1, parentItemId: 'i1', values: {
                's_status': {'labelId': 'done'},
              }),
              _item('s2', 'Sub two', position: 2, parentItemId: 'i1'),
            ]),
            _item('i2', 'Beta', position: 2, values: {
              'c_status': {'labelId': 'todo'},
              'c_num': {'number': 20},
            }),
          ],
        },
      ],
      'members': [
        {'userId': 'u1', 'fullName': 'Ada Lovelace', 'role': 'owner'},
      ],
      'views': views,
      'me': {'userId': 'u1', 'canEdit': canEdit, 'canManage': true},
    });

/// Records calls; every mutation resolves immediately.
class _FakeActions implements BoardTableActions {
  final calls = <String>[];

  @override
  Future<void> addItem({required String groupId, required String name}) async => calls.add('addItem:$name');
  @override
  Future<BoardItem?> addSubitem({required String parentItemId, required String name}) async {
    calls.add('addSubitem:$name');
    return null;
  }

  @override
  Future<void> renameItem(String itemId, String name) async => calls.add('rename:$itemId');
  @override
  Future<void> duplicateItem(String itemId) async => calls.add('duplicate:$itemId');
  @override
  Future<void> archiveItem(String itemId) async => calls.add('archive:$itemId');
  @override
  Future<void> trashItem(String itemId) async => calls.add('trash:$itemId');
  @override
  Future<void> moveItem({required String itemId, required String groupId, String? afterItemId}) async =>
      calls.add('move:$itemId');
  @override
  Future<void> setCell({required String itemId, required String columnId, required Map<String, dynamic>? value}) async =>
      calls.add('setCell:$itemId:$columnId');
  @override
  Future<void> addGroup(String title) async => calls.add('addGroup:$title');
  @override
  Future<void> renameGroup(String groupId, String title) async => calls.add('renameGroup:$groupId');
  @override
  Future<void> recolorGroup(String groupId, String color) async => calls.add('recolorGroup:$groupId');
  @override
  Future<void> deleteGroup(String groupId) async => calls.add('deleteGroup:$groupId');
  @override
  Future<void> toggleCollapsed(String groupId) async => calls.add('toggleCollapsed:$groupId');
  @override
  Future<void> refresh() async => calls.add('refresh');
}

Widget _host(BoardDetail board, {ViewConfig config = const ViewConfig.empty(), BoardTableActions? actions}) =>
    ProviderScope(
      child: MaterialApp(
        theme: dayflowLightTheme(),
        home: Scaffold(
          body: BoardTableBody(
            board: board,
            actions: actions ?? _FakeActions(),
            config: config,
            quickFilter: const BoardFilter(),
            meUserId: 'u1',
            now: DateTime(2026, 9, 12),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('BoardTableBody', () {
    testWidgets('renders every item and every column without a view', (tester) async {
      await tester.pumpWidget(_host(_board()));
      await _settle(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // Unset text cells render a "+ Notes" placeholder per row.
      expect(find.text('Notes'), findsNWidgets(2));
    });

    testWidgets('a saved view filter hides non-matching items', (tester) async {
      final config = ViewConfig.fromJson({
        'filters': {
          'conjunction': 'and',
          'rules': [
            {'id': 'r1', 'field': 'c_status', 'operator': 'is_any_of', 'value': ['done']},
          ],
        },
      });
      await tester.pumpWidget(_host(_board(), config: config));
      await _settle(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      // The header counter reflects the narrowed list.
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('hidden columns are not rendered', (tester) async {
      await tester.pumpWidget(_host(_board(), config: const ViewConfig(hiddenColumnIds: ['c_text'])));
      await _settle(tester);

      expect(find.text('Notes'), findsNothing);
      // Budget cells are all set, so the title appears only as the footer label.
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('the summary footer shows the number sum', (tester) async {
      await tester.pumpWidget(_host(_board()));
      await _settle(tester);

      expect(find.byType(SummaryFooter), findsOneWidget);
      expect(find.text('Σ 30'), findsOneWidget);
      expect(find.text('1/2 done'), findsOneWidget);
    });

    testWidgets('a row with subitems shows the roll-up chip and expands on tap', (tester) async {
      await tester.pumpWidget(_host(_board()));
      await _settle(tester);

      expect(find.text('2 subitems · 1 done'), findsOneWidget);
      expect(find.text('Sub one'), findsNothing);

      await tester.tap(find.text('2 subitems · 1 done'));
      await _settle(tester);

      expect(find.byType(SubitemRows), findsOneWidget);
      expect(find.text('Sub one'), findsOneWidget);
      expect(find.text('Sub two'), findsOneWidget);

      await tester.tap(find.text('2 subitems · 1 done'));
      await _settle(tester);
      expect(find.text('Sub one'), findsNothing);
    });

    testWidgets('a conditional row colour tints the matching row at 12% alpha', (tester) async {
      final config = ViewConfig.fromJson({
        'conditionalColors': [
          {'id': 'k1', 'field': 'c_status', 'operator': 'is_any_of', 'value': ['done'], 'color': 'green', 'applyTo': 'row'},
        ],
      });
      await tester.pumpWidget(_host(_board(), config: config));
      await _settle(tester);

      final tinted = tester.widget<Container>(find.byKey(const ValueKey('row-tint:i1')));
      expect(tinted.color, DfColors.token('green').withValues(alpha: 0.12));
      expect(find.byKey(const ValueKey('row-tint:i2')), findsNothing);
    });

    testWidgets('a conditional cell colour wraps only that chip', (tester) async {
      final config = ViewConfig.fromJson({
        'conditionalColors': [
          {'id': 'k1', 'field': 'c_num', 'operator': 'gt', 'value': 15, 'color': 'red', 'applyTo': 'cell'},
        ],
      });
      await tester.pumpWidget(_host(_board(), config: config));
      await _settle(tester);

      expect(find.byKey(const ValueKey('cell-tint:i2:c_num')), findsOneWidget);
      expect(find.byKey(const ValueKey('cell-tint:i1:c_num')), findsNothing);
    });

    testWidgets('viewers get no add affordances', (tester) async {
      await tester.pumpWidget(_host(_board(canEdit: false)));
      await _settle(tester);

      expect(find.text('Add item'), findsNothing);
      expect(find.text('Add group'), findsNothing);
    });
  });

  group('working-copy diff', () {
    test('viewConfigsEqual ignores construction order and empties', () {
      final a = ViewConfig.fromJson({
        'filters': {
          'conjunction': 'and',
          'rules': [
            {'id': 'r1', 'field': 'name', 'operator': 'contains', 'value': 'a'},
          ],
        },
        'hiddenColumnIds': ['c1'],
      });
      final b = const ViewConfig(hiddenColumnIds: ['c1']).copyWith(
        filters: () => const FilterGroup(rules: [FilterRule(id: 'r1', field: 'name', operator: 'contains', value: 'a')]),
      );
      expect(viewConfigsEqual(a, b), isTrue);
      expect(viewConfigsEqual(a, b.copyWith(hiddenColumnIds: ['c2'])), isFalse);
      expect(viewConfigsEqual(const ViewConfig.empty(), const ViewConfig(sort: [])), isTrue);
    });

    test('jsonDeepEquals compares nested structures by value', () {
      expect(jsonDeepEquals({'a': [1, 2, {'b': 'c'}]}, {'a': [1, 2, {'b': 'c'}]}), isTrue);
      expect(jsonDeepEquals({'a': [1, 2]}, {'a': [2, 1]}), isFalse);
      expect(jsonDeepEquals({'a': 1}, {'a': 1, 'b': null}), isFalse);
      expect(jsonDeepEquals(1, 1.0), isTrue);
    });
  });

  group('view helpers', () {
    final views = [
      {'id': 'v1', 'boardId': 'b1', 'type': 'table', 'name': 'Main table', 'isDefault': false, 'position': 1, 'config': <String, dynamic>{}},
      {'id': 'v2', 'boardId': 'b1', 'type': 'kanban', 'name': 'Board', 'isDefault': true, 'position': 2, 'config': <String, dynamic>{}},
    ];

    test('resolveActiveView prefers the chosen id, then the default', () {
      final board = _board(views: views);
      expect(resolveActiveView(board, 'v1')?.id, 'v1');
      expect(resolveActiveView(board, 'missing')?.id, 'v2');
      expect(resolveActiveView(board, null)?.id, 'v2');
      expect(resolveActiveView(_board(), null), isNull);
    });

    test('routeForView carries the view id as a query parameter', () {
      final board = _board(views: views);
      expect(routeForView('b1', board.views[1]), '/boards/b1/kanban?viewId=v2');
      expect(routeForView('b1', board.views[0]), '/boards/b1');
      expect(isTableLikeView('list'), isTrue);
      expect(isTableLikeView('calendar'), isFalse);
    });

    test('visibleItemIds applies saved and quick filters in display order', () {
      final board = _board();
      expect(visibleItemIds(board, const ViewConfig.empty(), const BoardFilter()), ['i1', 'i2']);
      expect(visibleItemIds(board, const ViewConfig.empty(), const BoardFilter(query: 'bet')), ['i2']);
      final sorted = ViewConfig.fromJson({
        'sort': [
          {'field': 'c_num', 'direction': 'desc'},
        ],
      });
      expect(visibleItemIds(board, sorted, const BoardFilter()), ['i2', 'i1']);
    });
  });

  group('field catalogues', () {
    test('filterable fields list Name, Group, then item columns only', () {
      final ids = filterableFields(_board()).map((f) => f.id).toList();
      expect(ids, ['name', 'group', 'c_status', 'c_num', 'c_text']);
    });

    test('sortable fields list the built-ins first', () {
      final ids = sortableFields(_board()).map((f) => f.id).toList();
      expect(ids.take(4), ['name', 'created_at', 'updated_at', 'serial']);
      expect(ids.contains('s_status'), isFalse);
    });

    test('ruleValueLabel names choices, people and dates', () {
      final board = _board();
      expect(
        ruleValueLabel(board, board.members, const FilterRule(id: 'r', field: 'c_status', operator: 'is_any_of', value: ['done'])),
        'Done',
      );
      expect(
        ruleValueLabel(board, board.members, const FilterRule(id: 'r', field: 'c_status', operator: 'is_any_of')),
        'value',
      );
      expect(
        ruleValueLabel(board, board.members, const FilterRule(id: 'r', field: 'c_status', operator: 'is_empty')),
        '',
      );
      expect(
        ruleValueLabel(board, board.members, const FilterRule(id: 'r', field: 'group', operator: 'is_any_of', value: ['g1'])),
        'This week',
      );
      expect(SubitemToggleChip.label(1, 0), '1 subitem · 0 done');
    });
  });
}
