import 'package:dayflow/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

BoardColumn _statusColumn({String id = 'c-status'}) => BoardColumn.fromJson({
      'id': id,
      'type': 'status',
      'title': 'Status',
      'position': 1,
      'settings': {
        'labels': [
          {'id': 'working', 'label': 'Working on it', 'color': 'amber', 'isDone': false},
          {'id': 'done', 'label': 'Done', 'color': 'green', 'isDone': true},
        ],
      },
    });

BoardDetail _board({List<BoardGroup>? groups, List<BoardColumn>? columns}) => BoardDetail(
      id: 'b1',
      name: 'Board',
      type: 'main',
      workspaceName: 'Main',
      isFavorite: false,
      columns: columns ?? [_statusColumn()],
      groups: groups ??
          [
            BoardGroup(
              id: 'g1',
              title: 'Group 1',
              color: 'blue',
              collapsed: false,
              items: const [
                BoardItem(id: 'i1', name: 'One', position: 1, updatesCount: 0, values: {}),
                BoardItem(id: 'i2', name: 'Two', position: 2, updatesCount: 0, values: {}),
              ],
            ),
            const BoardGroup(id: 'g2', title: 'Group 2', color: 'purple', collapsed: false, items: []),
          ],
      members: const [],
    );

void main() {
  group('BoardItem.withCell', () {
    const item = BoardItem(id: 'i1', name: 'One', position: 1, updatesCount: 0, values: {});

    test('sets a cell without touching the original', () {
      final updated = item.withCell('c1', {'labelId': 'done'});
      expect(updated.values, {'c1': {'labelId': 'done'}});
      expect(item.values, isEmpty, reason: 'models are immutable');
    });

    test('removes the cell when the value is null', () {
      final withValue = item.withCell('c1', {'labelId': 'done'});
      expect(withValue.withCell('c1', null).values, isEmpty);
    });

    test('leaves other cells alone', () {
      final two = item.withCell('c1', {'text': 'a'}).withCell('c2', {'number': 2});
      expect(two.withCell('c1', null).values, {'c2': {'number': 2}});
    });
  });

  group('BoardDetail.withItem', () {
    test('transforms only the matching item', () {
      final updated = _board().withItem('i2', (item) => item.copyWith(name: 'Renamed'));
      expect(updated.groups.first.items.map((i) => i.name), ['One', 'Renamed']);
    });

    test('is a no-op for an unknown id', () {
      final board = _board();
      final updated = board.withItem('nope', (item) => item.copyWith(name: 'X'));
      expect(updated.groups.first.items.map((i) => i.name), ['One', 'Two']);
    });
  });

  group('BoardDetail.withGroup', () {
    test('replaces one group and preserves order', () {
      final board = _board();
      final updated = board.withGroup(board.groups.last.copyWith(title: 'Renamed'));
      expect(updated.groups.map((g) => g.title), ['Group 1', 'Renamed']);
    });
  });

  group('BoardDetail.findItem and itemCount', () {
    test('finds an item across groups', () {
      expect(_board().findItem('i2')!.name, 'Two');
      expect(_board().findItem('missing'), isNull);
    });

    test('counts items in every group', () {
      expect(_board().itemCount, 2);
    });
  });

  group('BoardGroup.doneCount', () {
    test('counts items whose status sits on a done label', () {
      final column = _statusColumn();
      final group = BoardGroup(
        id: 'g1',
        title: 'G',
        color: 'blue',
        collapsed: false,
        items: [
          BoardItem(id: 'a', name: 'A', position: 1, updatesCount: 0, values: {
            column.id: {'labelId': 'done'},
          }),
          BoardItem(id: 'b', name: 'B', position: 2, updatesCount: 0, values: {
            column.id: {'labelId': 'working'},
          }),
          const BoardItem(id: 'c', name: 'C', position: 3, updatesCount: 0, values: {}),
        ],
      );
      expect(group.doneCount([column]), 1);
    });

    test('is zero when the board has no status column', () {
      final group = BoardGroup(
        id: 'g1',
        title: 'G',
        color: 'blue',
        collapsed: false,
        items: const [BoardItem(id: 'a', name: 'A', position: 1, updatesCount: 0, values: {})],
      );
      expect(group.doneCount(const []), 0);
    });
  });

  group('ItemDetail.fromJson', () {
    test('parses the board/group context, updates and activity', () {
      final detail = ItemDetail.fromJson({
        'id': 'i1',
        'name': 'Task',
        'board': {'id': 'b1', 'name': 'Launch plan'},
        'group': {'id': 'g1', 'title': 'This week', 'color': 'blue'},
        'workspaceName': 'Main workspace',
        'createdAt': '2026-08-01T10:00:00.000Z',
        'columns': [
          {'id': 'c1', 'type': 'text', 'title': 'Notes', 'position': 1, 'settings': <String, dynamic>{}},
        ],
        'values': {
          'c1': {'text': 'hello'},
        },
        'updates': [
          {
            'id': 'u1',
            'body': 'Started',
            'author': {'userId': 'usr', 'fullName': 'Demo User', 'avatarUrl': null},
            'createdAt': '2026-08-01T11:00:00.000Z',
            'editedAt': null,
          },
        ],
        'activity': [
          {
            'id': 'a1',
            'event': 'item_renamed',
            'payload': {'from': 'Old', 'to': 'Task'},
            'actor': {'userId': 'usr', 'fullName': 'Demo User'},
            'createdAt': '2026-08-01T10:30:00.000Z',
          },
        ],
      });

      expect(detail.boardName, 'Launch plan');
      expect(detail.groupTitle, 'This week');
      expect(detail.updates.single.authorName, 'Demo User');
      expect(detail.activity.single.description, 'renamed it to "Task"');
      // The cell values reuse the board widgets via asBoardItem.
      expect(detail.asBoardItem.values['c1'], {'text': 'hello'});
      expect(detail.asBoardItem.updatesCount, 1);
    });
  });

  group('ActivityEntry.description', () {
    test('renders known events as sentences', () {
      ActivityEntry entry(String event, [Map<String, dynamic> payload = const {}]) => ActivityEntry(
            id: 'a',
            event: event,
            payload: payload,
            createdAt: DateTime(2026),
          );

      expect(entry('item_created').description, 'created this item');
      expect(entry('column_value_changed').description, 'changed a column value');
      expect(entry('group_deleted').description, 'deleted a group');
    });

    test('humanises an event it does not know', () {
      final entry = ActivityEntry(id: 'a', event: 'some_new_event', payload: const {}, createdAt: DateTime(2026));
      expect(entry.description, 'some new event');
    });
  });

  group('MyWork.fromJson', () {
    test('parses every bucket and the done count', () {
      final work = MyWork.fromJson({
        'overdue': [
          {'id': 'i1', 'name': 'Late', 'boardId': 'b1', 'boardName': 'B', 'groupTitle': 'G', 'groupColor': 'red', 'date': '2026-01-01', 'status': {'label': 'Working on it', 'color': 'amber', 'isDone': false}},
        ],
        'today': [],
        'thisWeek': [],
        'later': [],
        'noDate': [
          {'id': 'i2', 'name': 'Someday', 'boardId': 'b1', 'boardName': 'B', 'groupTitle': 'G', 'groupColor': 'blue'},
        ],
        'doneCount': 3,
      });

      expect(work.overdue.single.name, 'Late');
      expect(work.overdue.single.statusLabel, 'Working on it');
      expect(work.overdue.single.date, DateTime.parse('2026-01-01'));
      expect(work.noDate.single.date, isNull);
      expect(work.total, 2);
      expect(work.doneCount, 3);
      expect(work.isEmpty, isFalse);
    });

    test('an all-empty payload reports empty', () {
      expect(MyWork.fromJson(const {}).isEmpty, isTrue);
      expect(MyWork.fromJson(const {}).total, 0);
    });
  });

  group('AppNotification', () {
    AppNotification build(String type, {String? actor, bool read = false}) => AppNotification.fromJson({
          'id': 'n1',
          'type': type,
          'payload': {'boardId': 'b1', 'boardName': 'Launch', 'itemId': 'i1', 'itemName': 'Task'},
          'actor': actor == null ? null : {'userId': 'u1', 'fullName': actor},
          'readAt': read ? '2026-08-01T10:00:00.000Z' : null,
          'createdAt': '2026-08-01T09:00:00.000Z',
        });

    test('writes a headline naming the actor and item', () {
      expect(build('assigned', actor: 'Robin').headline, 'Robin assigned you to "Task"');
      expect(build('mention', actor: 'Robin').headline, 'Robin mentioned you in "Task"');
    });

    test('falls back gracefully when the actor is gone', () {
      expect(build('assigned').headline, 'Someone assigned you to "Task"');
    });

    test('tracks read state and exposes navigation targets', () {
      expect(build('assigned').isRead, isFalse);
      expect(build('assigned', read: true).isRead, isTrue);
      expect(build('assigned').itemId, 'i1');
      expect(build('assigned').boardId, 'b1');
    });
  });

  group('SearchResults.fromJson', () {
    test('parses boards and items', () {
      final results = SearchResults.fromJson({
        'boards': [
          {'id': 'b1', 'name': 'Launch plan', 'workspaceName': 'Main'},
        ],
        'items': [
          {'id': 'i1', 'name': 'Ship it', 'boardId': 'b1', 'boardName': 'Launch plan', 'groupTitle': 'G', 'groupColor': 'blue'},
        ],
      });
      expect(results.boards.single.name, 'Launch plan');
      expect(results.items.single.name, 'Ship it');
      expect(results.isEmpty, isFalse);
    });

    test('an empty payload reports empty', () {
      expect(SearchResults.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('MemberDirectory.fromJson', () {
    test('parses members and pending invitations', () {
      final directory = MemberDirectory.fromJson({
        'members': [
          {
            'userId': 'u1',
            'fullName': 'Demo User',
            'email': 'demo@dayflow.app',
            'role': 'admin',
            'status': 'active',
            'isYou': true,
          },
          {
            'userId': 'u2',
            'fullName': 'Sam Teammate',
            'email': 'sam@dayflow.app',
            'role': 'viewer',
            'status': 'active',
            'isYou': false,
          },
        ],
        'invitations': [
          {
            'id': 'i1',
            'email': 'pending@dayflow.app',
            'role': 'member',
            'invitedByName': 'Demo User',
            'expiresAt': '2026-09-01T00:00:00.000Z',
            'devLink': 'dayflow://invite/abc123',
          },
        ],
      });

      expect(directory.members, hasLength(2));
      expect(directory.members.first.isYou, isTrue);
      expect(directory.invitations.single.email, 'pending@dayflow.app');
      expect(directory.invitations.single.devLink, 'dayflow://invite/abc123');
    });

    test('reflects who may edit boards', () {
      AccountMember withRole(String role) => AccountMember.fromJson({
            'userId': 'u',
            'fullName': 'X',
            'email': 'x@y.z',
            'role': role,
            'status': 'active',
            'isYou': false,
          });

      expect(withRole('admin').canEdit, isTrue);
      expect(withRole('member').canEdit, isTrue);
      expect(withRole('viewer').canEdit, isFalse);
      expect(withRole('guest').canEdit, isFalse);
    });

    test('converts to a board member for people pickers', () {
      final member = AccountMember.fromJson({
        'userId': 'u1',
        'fullName': 'Demo User',
        'email': 'demo@dayflow.app',
        'role': 'admin',
        'status': 'active',
        'isYou': true,
      });
      final asBoardMember = member.toBoardMember();
      expect(asBoardMember.userId, 'u1');
      expect(asBoardMember.fullName, 'Demo User');
    });

    test('omits invitations for non-admins, who never receive them', () {
      final directory = MemberDirectory.fromJson({
        'members': const [],
        'invitations': const [],
      });
      expect(directory.invitations, isEmpty);
    });
  });

  group('BoardTemplate.fromJson', () {
    test('parses gallery metadata with defaults', () {
      final template = BoardTemplate.fromJson({'key': 'blank', 'name': 'Blank board'});
      expect(template.icon, 'grid');
      expect(template.accentColor, 'indigo');
      expect(template.columnCount, 0);
    });
  });
}
