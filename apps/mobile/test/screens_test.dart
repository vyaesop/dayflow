import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/core/theme/theme.dart';
import 'package:dayflow/features/activity/board_activity_screen.dart';
import 'package:dayflow/features/archive/archive_providers.dart';
import 'package:dayflow/features/archive/archive_screen.dart';
import 'package:dayflow/features/board/board_controller.dart';
import 'package:dayflow/features/board/create_board_screen.dart';
import 'package:dayflow/features/home/home_providers.dart';
import 'package:dayflow/features/members/members_providers.dart';
import 'package:dayflow/features/members/members_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget screen, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: dayflowLightTheme(), home: screen),
    );

const _empty = ArchiveListing(boards: [], items: []);

ActivityEntry _entry({
  required String id,
  required String event,
  required String actor,
  Map<String, dynamic> payload = const {},
  String? itemName,
  String? columnTitle,
  bool undoable = false,
  DateTime? undoneAt,
}) =>
    ActivityEntry(
      id: id,
      event: event,
      payload: payload,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      actorId: 'u-$actor',
      actorName: actor,
      itemName: itemName,
      columnTitle: columnTitle,
      undoable: undoable,
      undoneAt: undoneAt,
    );

AccountMember _member(String name, {String role = 'member', String status = 'active', bool isYou = false}) =>
    AccountMember(
      userId: 'u-${name.toLowerCase().replaceAll(' ', '-')}',
      fullName: name,
      email: '${name.toLowerCase().replaceAll(' ', '.')}@example.com',
      role: role,
      status: status,
      isYou: isYou,
    );

void main() {
  group('ArchiveScreen', () {
    testWidgets('Trash tab renders a board tile with its purge countdown and delete action', (tester) async {
      final now = DateTime.now();
      final trashed = ArchiveListing(
        boards: [
          ArchivedBoard(
            id: 'b1',
            name: 'Old roadmap',
            type: 'private',
            workspaceName: 'Main workspace',
            itemCount: 4,
            trashedAt: now.subtract(const Duration(days: 3)),
            purgeAt: now.add(const Duration(days: 27, hours: 1)),
          ),
        ],
        items: const [],
      );

      await tester.pumpWidget(_host(
        const ArchiveScreen(initialTab: 1),
        overrides: [
          archiveListingProvider.overrideWith((ref, query) async => query.mode == ArchiveMode.trash ? trashed : _empty),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Old roadmap'), findsOneWidget);
      expect(find.textContaining('Main workspace · 4 items'), findsOneWidget);
      expect(find.textContaining('purged in 27 days'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
    });

    testWidgets('Archive tab shows the empty state when nothing is archived', (tester) async {
      await tester.pumpWidget(_host(
        const ArchiveScreen(),
        overrides: [archiveListingProvider.overrideWith((ref, query) async => _empty)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nothing in the archive'), findsOneWidget);
      expect(find.text('Restore'), findsNothing);
    });

    testWidgets('hides the Boards section when scoped to one board', (tester) async {
      final listing = ArchiveListing(
        boards: [
          ArchivedBoard(id: 'b9', name: 'Should not show', type: 'main', workspaceName: 'W', itemCount: 0),
        ],
        items: [
          ArchivedItem(
            id: 'i1',
            name: 'Design review',
            boardId: 'b1',
            boardName: 'Launch',
            groupTitle: 'This week',
            groupColor: 'green',
            parentItemName: 'Homepage',
            archivedAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ],
      );
      await tester.pumpWidget(_host(
        const ArchiveScreen(boardId: 'b1'),
        overrides: [archiveListingProvider.overrideWith((ref, query) async => listing)],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Should not show'), findsNothing);
      expect(find.text('Design review'), findsOneWidget);
      expect(find.text('Launch · This week'), findsOneWidget);
      expect(find.text('in Homepage'), findsOneWidget);
      expect(find.textContaining('Archived 2h ago'), findsOneWidget);
    });

    test('archiveStamp spells out the trash purge window', () {
      final now = DateTime.now();
      final stamp = archiveStamp(
        ArchiveMode.trash,
        trashedAt: now.subtract(const Duration(days: 1)),
        purgeAt: now.add(const Duration(days: 29, hours: 1)),
      );
      expect(stamp, 'Deleted yesterday · purged in 29 days');
      expect(archiveStamp(ArchiveMode.archive, archivedAt: now), 'Archived just now');
    });
  });

  group('BoardActivityScreen', () {
    Future<ActivityPage> loader(String boardId, {String? actorId, String? cursor}) async => ActivityPage(
          entries: [
            _entry(
              id: 'a1',
              event: 'item_renamed',
              actor: 'Alex Smith',
              payload: {'from': 'Draft', 'to': 'Final'},
              itemName: 'Final',
              undoable: true,
            ),
            _entry(
              id: 'a2',
              event: 'column_value_changed',
              actor: 'Bea Jones',
              payload: {
                'from': {'labelId': 'working'},
                'to': {'labelId': 'done'},
              },
              itemName: 'Ship it',
              columnTitle: 'Status',
              undoable: true,
              undoneAt: DateTime.now(),
            ),
            _entry(id: 'a3', event: 'item_created', actor: 'Cal Stone', itemName: 'New task'),
          ],
        );

    testWidgets('renders actor + description, diffs, and Undo only for live undoable entries', (tester) async {
      await tester.pumpWidget(_host(
        const BoardActivityScreen(boardId: 'b1'),
        overrides: [activityLoaderProvider.overrideWithValue(loader)],
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Alex Smith renamed "Draft" to "Final"'), findsOneWidget);
      expect(find.text('Draft → Final'), findsOneWidget);
      expect(find.textContaining('Bea Jones changed Status on "Ship it"'), findsOneWidget);
      expect(find.text('working → done'), findsOneWidget);
      expect(find.textContaining('Cal Stone created "New task"'), findsOneWidget);

      // Column chip and the Undone tag for the reverted entry.
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Undone'), findsOneWidget);

      // Only the rename is undoable and not yet undone.
      expect(find.widgetWithText(TextButton, 'Undo'), findsOneWidget);
      expect(find.text('Beginning of the log'), findsOneWidget);
    });

    testWidgets('event-group chips filter client-side', (tester) async {
      await tester.pumpWidget(_host(
        const BoardActivityScreen(boardId: 'b1'),
        overrides: [activityLoaderProvider.overrideWithValue(loader)],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Values'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bea Jones'), findsOneWidget);
      expect(find.textContaining('Alex Smith'), findsNothing);
      expect(find.textContaining('Cal Stone'), findsNothing);
    });

    test('describeActivityValue picks the telling key of a cell value', () {
      expect(describeActivityValue({'labelId': 'done'}), 'done');
      expect(describeActivityValue({'text': 'hello'}), 'hello');
      expect(describeActivityValue({'number': 3.0}), '3');
      expect(describeActivityValue({'date': '2026-09-12', 'time': '09:30'}), '2026-09-12 09:30');
      expect(describeActivityValue({'userIds': ['a', 'b']}), '2 people');
      expect(describeActivityValue({'optionIds': ['a']}), '1 tag');
      expect(describeActivityValue(null), '—');
    });
  });

  group('MembersScreen', () {
    final directory = MemberDirectory(
      members: [
        _member('Me Admin', role: 'admin', isYou: true),
        _member('Cal Stone', status: 'deactivated'),
        _member('Bea Jones'),
      ],
      invitations: const [],
    );

    testWidgets('marks deactivated members, sorts them last, and offers Guest in the role sheet', (tester) async {
      await tester.pumpWidget(_host(
        const MembersScreen(),
        overrides: [
          memberDirectoryProvider.overrideWith((ref) async => directory),
          canManageMembersProvider.overrideWithValue(true),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Deactivated'), findsOneWidget);
      expect(find.text('2 active · 1 deactivated'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Cal Stone')).dy,
        greaterThan(tester.getTopLeft(find.text('Bea Jones')).dy),
        reason: 'deactivated members sort after active ones',
      );

      // Admins get a menu on everyone but themselves.
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Deactivate'), findsOneWidget);
      await tester.tap(find.text('Change role'));
      await tester.pumpAndSettle();

      expect(find.text('Guest'), findsOneWidget);
      expect(find.text("Only sees shareable boards they're added to"), findsOneWidget);
    });

    testWidgets('offers Reactivate for a deactivated member and no menus to non-admins', (tester) async {
      await tester.pumpWidget(_host(
        const MembersScreen(),
        overrides: [
          memberDirectoryProvider.overrideWith((ref) async => directory),
          canManageMembersProvider.overrideWithValue(true),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('Reactivate'), findsOneWidget);
      expect(find.text('Deactivate'), findsNothing);

      await tester.pumpWidget(_host(
        const MembersScreen(),
        overrides: [
          memberDirectoryProvider.overrideWith((ref) async => directory),
          canManageMembersProvider.overrideWithValue(false),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });
  });

  group('CreateBoardScreen', () {
    testWidgets('lists built-in templates first and custom ones under "Your templates"', (tester) async {
      const templates = [
        BoardTemplate(
          key: 'blank',
          name: 'Blank board',
          description: 'Start from scratch',
          icon: 'grid',
          accentColor: 'indigo',
          columnCount: 3,
          groupCount: 1,
        ),
        BoardTemplate(
          key: 'custom_1',
          name: 'Sprint board',
          description: 'Our sprint layout',
          icon: 'check',
          accentColor: 'green',
          columnCount: 6,
          groupCount: 3,
          itemCount: 12,
          isCustom: true,
          id: 't1',
          createdByName: 'Alex Smith',
        ),
      ];

      await tester.pumpWidget(_host(
        const CreateBoardScreen(),
        overrides: [
          templatesProvider.overrideWith((ref) async => templates),
          workspacesProvider.overrideWith((ref) async => const <WorkspaceSummary>[]),
        ],
      ));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Your templates'), 200, scrollable: scrollable);
      await tester.pumpAndSettle();

      expect(find.text('Your templates'), findsOneWidget);
      expect(find.text('Sprint board'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('6 columns · 3 groups · 12 items · by Alex Smith'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget, reason: 'only custom templates get a menu');
      expect(
        tester.getTopLeft(find.text('Blank board')).dy,
        lessThan(tester.getTopLeft(find.text('Sprint board')).dy),
      );
    });
  });
}
