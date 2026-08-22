import 'package:dayflow/core/realtime/realtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The BoardEvent accessors decide what the board controller can apply, so the
/// distinction between "no value sent" and "value is null" matters: the latter
/// means a cell was cleared.
void main() {
  group('BoardEvent accessors', () {
    test('reads the common identifiers', () {
      final event = BoardEvent('cell.changed', {
        'type': 'cell.changed',
        'boardId': 'b1',
        'itemId': 'i1',
        'columnId': 'c1',
        'value': {'labelId': 'done'},
      });

      expect(event.type, 'cell.changed');
      expect(event.boardId, 'b1');
      expect(event.itemId, 'i1');
      expect(event.columnId, 'c1');
      expect(event.value, {'labelId': 'done'});
      expect(event.hasValue, isTrue);
    });

    test('distinguishes a cleared cell from an absent value', () {
      final cleared = BoardEvent('cell.changed', {
        'boardId': 'b1',
        'itemId': 'i1',
        'columnId': 'c1',
        'value': null,
      });
      expect(cleared.hasValue, isTrue, reason: 'the key is present, so the cell was cleared');
      expect(cleared.value, isNull);

      final absent = BoardEvent('item.updated', {'boardId': 'b1', 'itemId': 'i1'});
      expect(absent.hasValue, isFalse, reason: 'no value key means this event carries no cell');
    });

    test('exposes nested payloads for created entities', () {
      final item = BoardEvent('item.created', {
        'boardId': 'b1',
        'groupId': 'g1',
        'item': {'id': 'i9', 'name': 'New', 'position': 3, 'updatesCount': 0},
      });
      expect(item.groupId, 'g1');
      expect(item.item?['id'], 'i9');

      final group = BoardEvent('group.created', {
        'boardId': 'b1',
        'group': {'id': 'g9', 'title': 'Added', 'color': 'teal'},
      });
      expect(group.group?['title'], 'Added');

      final column = BoardEvent('column.created', {
        'boardId': 'b1',
        'column': {'id': 'c9', 'type': 'text', 'title': 'Notes'},
      });
      expect(column.column?['type'], 'text');
    });

    test('exposes patch payloads for updates', () {
      final event = BoardEvent('group.updated', {
        'boardId': 'b1',
        'groupId': 'g1',
        'patch': {'title': 'Renamed', 'color': 'red'},
      });
      expect(event.patch, {'title': 'Renamed', 'color': 'red'});
    });

    test('defaults a missing boardId to empty rather than throwing', () {
      final event = BoardEvent('board.updated', const {});
      expect(event.boardId, '');
      expect(event.itemId, isNull);
      expect(event.patch, isNull);
    });
  });
}
