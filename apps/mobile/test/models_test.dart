import 'package:dayflow/core/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Me.fromJson', () {
    test('parses the session payload returned by /auth/login/select', () {
      final me = Me.fromJson({
        'user': {
          'id': 'u1',
          'email': 'alex.smith@example.com',
          'fullName': 'Alex Smith',
          'avatarUrl': null,
          'language': 'en',
          'onboardingCompleted': true,
          'setupChecklist': ['create_first_board'],
        },
        'account': {
          'id': 'a1',
          'name': "Alex's team",
          'slug': 'alex-s-team-2f68e9',
          'role': 'admin',
          'lastUsedAt': '2026-07-03T16:11:46.000Z',
        },
        'accounts': [
          {'id': 'a1', 'name': "Alex's team", 'slug': 'alex-s-team-2f68e9', 'role': 'admin'},
        ],
        'accessToken': 'at',
        'refreshToken': 'rt',
      });

      expect(me.id, 'u1');
      expect(me.firstName, 'Alex');
      expect(me.setupChecklist, ['create_first_board']);
      expect(me.account.role, 'admin');
      expect(me.accounts, hasLength(1));
    });
  });

  group('HomeOverview.fromJson', () {
    test('parses setup progress, favorites and recents', () {
      final overview = HomeOverview.fromJson({
        'greetingName': 'Alex',
        'setupProgress': {
          'steps': [
            {'step': 'create_first_board', 'done': true},
            {'step': 'get_started_basics', 'done': false},
          ],
          'percent': 33,
        },
        'favorites': [],
        'recentlyVisited': [
          {'id': 'b1', 'name': 'Your first board', 'workspaceName': 'Main workspace', 'isFavorite': false},
        ],
      });

      expect(overview.greetingName, 'Alex');
      expect(overview.setupPercent, 33);
      expect(overview.setupSteps.first.label, 'Create your first board');
      expect(overview.favorites, isEmpty);
      expect(overview.recentlyVisited.single.name, 'Your first board');
    });

    test('tolerates a missing setupProgress block', () {
      final overview = HomeOverview.fromJson({'greetingName': 'Sam'});
      expect(overview.setupPercent, 0);
      expect(overview.setupSteps, isEmpty);
    });
  });

  group('BoardDetail.fromJson', () {
    test('parses columns, groups and item cell values', () {
      final board = BoardDetail.fromJson({
        'id': 'b1',
        'name': 'Your first board',
        'description': 'Plan, track and execute.',
        'type': 'main',
        'workspace': {'id': 'w1', 'name': 'Main workspace'},
        'isFavorite': true,
        'columns': [
          {
            'id': 'c1',
            'type': 'status',
            'title': 'Status',
            'position': 1,
            'settings': {
              'labels': [
                {'id': 'done', 'label': 'Done', 'color': 'green', 'isDone': true},
              ],
            },
          },
        ],
        'groups': [
          {
            'id': 'g1',
            'title': 'To-Do',
            'color': 'blue',
            'collapsed': false,
            'items': [
              {
                'id': 'i1',
                'name': 'Task 1',
                'position': 1,
                'updatesCount': 2,
                'values': {
                  'c1': {'labelId': 'done'},
                },
              },
            ],
          },
        ],
        'members': [
          {'userId': 'u1', 'fullName': 'Alex Smith', 'role': 'admin'},
        ],
      });

      expect(board.workspaceName, 'Main workspace');
      expect(board.isFavorite, isTrue);
      expect(board.columns.single.statusLabels.single.isDone, isTrue);
      expect(board.groups.single.items.single.updatesCount, 2);
      expect(board.groups.single.items.single.values['c1'], {'labelId': 'done'});
      expect(board.members.single.fullName, 'Alex Smith');
    });
  });

  group('WorkspaceSummary.fromJson', () {
    test('stamps the workspace name onto nested boards', () {
      final workspace = WorkspaceSummary.fromJson({
        'id': 'w1',
        'name': 'Main workspace',
        'boards': [
          {'id': 'b1', 'name': 'Your first board', 'isFavorite': false},
        ],
      });

      expect(workspace.boards.single.workspaceName, 'Main workspace');
    });
  });
}
