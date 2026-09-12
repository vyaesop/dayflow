import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/features/board/dashboard_data.dart';
import 'package:flutter_test/flutter_test.dart';

BoardDetail _board({List<BoardColumn>? columns, List<BoardGroup>? groups}) => BoardDetail(
      id: 'b1',
      name: 'Launch',
      type: 'main',
      workspaceName: 'Main workspace',
      isFavorite: false,
      columns: columns ?? const [],
      groups: groups ?? const [],
      members: const [],
    );

BoardColumn _statusColumn() => const BoardColumn(
      id: 'status',
      type: 'status',
      title: 'Status',
      settings: {
        'labels': [
          {'id': 'todo', 'label': 'To do', 'color': 'grey', 'isDone': false},
          {'id': 'working', 'label': 'Working on it', 'color': 'amber', 'isDone': false},
          {'id': 'done', 'label': 'Done', 'color': 'green', 'isDone': true},
        ],
      },
      position: 1,
    );

BoardItem _item(String id, {Map<String, dynamic> values = const {}}) =>
    BoardItem(id: id, name: 'Item $id', position: 1, updatesCount: 0, values: values);

void main() {
  final today = DateTime(2026, 8, 22);

  group('computeDashboard', () {
    test('empty board yields zeroes and no widgets', () {
      final data = computeDashboard(_board(), now: today);
      expect(data.itemCount, 0);
      expect(data.donePercent, 0);
      expect(data.statusSlices, isEmpty);
      expect(data.numberSummaries, isEmpty);
      expect(data.upcoming, isEmpty);
    });

    test('counts status distribution, done, and the no-status bucket', () {
      final data = computeDashboard(
        _board(
          columns: [_statusColumn()],
          groups: [
            BoardGroup(id: 'g1', title: 'Sprint', color: 'blue', collapsed: false, items: [
              _item('1', values: {'status': {'labelId': 'done'}}),
              _item('2', values: {'status': {'labelId': 'done'}}),
              _item('3', values: {'status': {'labelId': 'working'}}),
              _item('4'),
            ]),
          ],
        ),
        now: today,
      );

      expect(data.itemCount, 4);
      expect(data.doneCount, 2);
      expect(data.donePercent, 0.5);
      expect(data.statusSlices.first.label, 'Done');
      expect(data.statusSlices.first.count, 2);
      expect(data.statusSlices.last.label, 'No status');
      expect(data.statusSlices.last.count, 1);
      // Labels with zero items don't clutter the legend.
      expect(data.statusSlices.map((s) => s.label), isNot(contains('To do')));
    });

    test('sums and averages number columns over items that have a value', () {
      const numberColumn = BoardColumn(id: 'n1', type: 'number', title: 'Budget', settings: {}, position: 2);
      final data = computeDashboard(
        _board(
          columns: [numberColumn],
          groups: [
            BoardGroup(id: 'g1', title: 'G', color: 'blue', collapsed: false, items: [
              _item('1', values: {'n1': {'number': 10}}),
              _item('2', values: {'n1': {'number': 4.5}}),
              _item('3'),
            ]),
          ],
        ),
        now: today,
      );

      final summary = data.numberSummaries.single;
      expect(summary.title, 'Budget');
      expect(summary.sum, 14.5);
      expect(summary.count, 2);
      expect(summary.average, closeTo(7.25, 0.001));
    });

    test('splits dated items into overdue and upcoming, skipping done ones', () {
      final data = computeDashboard(
        _board(
          columns: [
            _statusColumn(),
            const BoardColumn(id: 'due', type: 'date', title: 'Due', settings: {}, position: 3),
          ],
          groups: [
            BoardGroup(id: 'g1', title: 'G', color: 'pink', collapsed: false, items: [
              _item('late', values: {'due': {'date': '2026-08-20'}}),
              _item('today', values: {'due': {'date': '2026-08-22'}}),
              _item('soon', values: {'due': {'date': '2026-08-25'}}),
              // Done and overdue — completed work is not "overdue".
              _item('done-late', values: {
                'due': {'date': '2026-08-01'},
                'status': {'labelId': 'done'},
              }),
            ]),
          ],
        ),
        now: today,
      );

      expect(data.overdueCount, 1);
      expect(data.upcoming.map((u) => u.itemId), ['today', 'soon']);
      expect(data.upcoming.first.groupColorToken, 'pink');
    });

    test('caps and sorts the upcoming list', () {
      final items = [
        for (var day = 1; day <= 9; day++)
          _item('d$day', values: {'due': {'date': '2026-09-0$day'}}),
      ]..shuffle();
      final data = computeDashboard(
        _board(
          columns: [const BoardColumn(id: 'due', type: 'date', title: 'Due', settings: {}, position: 1)],
          groups: [BoardGroup(id: 'g', title: 'G', color: 'blue', collapsed: false, items: items)],
        ),
        now: today,
        upcomingLimit: 3,
      );

      expect(data.upcoming.map((u) => u.itemId), ['d1', 'd2', 'd3']);
    });

    test('reports items per group in board order', () {
      final data = computeDashboard(
        _board(groups: [
          BoardGroup(id: 'a', title: 'First', color: 'blue', collapsed: false, items: [_item('1')]),
          BoardGroup(id: 'b', title: 'Second', color: 'red', collapsed: false, items: [_item('2'), _item('3')]),
        ]),
        now: today,
      );

      expect(data.groupSlices.map((g) => g.title), ['First', 'Second']);
      expect(data.groupSlices.map((g) => g.count), [1, 2]);
    });
  });
}
