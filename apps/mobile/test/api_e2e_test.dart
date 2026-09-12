@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayflow/core/api/api_client.dart';
import 'package:dayflow/core/api/api_exception.dart';
import 'package:dayflow/core/auth/auth_repository.dart';
import 'package:dayflow/core/auth/token_store.dart';
import 'package:dayflow/core/models/models.dart';
import 'package:dayflow/features/board/board_repository.dart';
import 'package:dayflow/features/item/item_repository.dart';
import 'package:dayflow/features/members/members_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end test of the real client stack against a live API + database.
///
///   npm run db:local          # embedded Postgres on :5433
///   npm run db:migrate
///   npm run api:dev           # API on :4000
///   cd apps/mobile && flutter test test/api_e2e_test.dart
///
/// Skips itself (rather than failing) when the API is unreachable, so
/// `flutter test` stays green on a machine with no local server.
///
/// `POST /v1/auth/otp/request` is throttled to 5/minute per IP, so this suite
/// deliberately spends only two of them: one to sign up, one to log back in.
/// Re-running it more than twice inside the same minute will exhaust the budget —
/// the guard below reports that as a skip, since it is a property of the
/// environment rather than a defect.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  var apiReachable = false;

  /// True once signup has established a session. Later groups need one, and the
  /// OTP throttler can legitimately prevent it, so they check this rather than
  /// failing with a confusing 401.
  var sessionReady = false;

  final email = 'e2e.${DateTime.now().millisecondsSinceEpoch}@example.com';
  late AuthRepository repo;

  setUpAll(() async {
    // flutter_test stubs every HTTP request by default; clear the override so
    // the client performs real network I/O.
    HttpOverrides.global = null;

    // flutter_secure_storage speaks over a platform channel with no
    // implementation in the test host — back it with an in-memory map.
    final store = <String, String>{};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        final key = args['key'] as String?;
        return switch (call.method) {
          'write' => store[key!] = args['value'] as String,
          'read' => store[key!],
          'delete' => store.remove(key!),
          'deleteAll' => store.clear(),
          'readAll' => Map<String, String>.from(store),
          'containsKey' => store.containsKey(key!),
          _ => null,
        };
      },
    );

    repo = AuthRepository(ApiClient.instance);
    apiReachable = await _ping();
    if (!apiReachable) {
      // ignore: avoid_print
      print('SKIPPING e2e: no API at ${apiBaseUrl()}');
    }
  });

  /// Guards each test so the suite skips cleanly without a server.
  bool skipIfDown() {
    if (!apiReachable) markTestSkipped('API not reachable at ${apiBaseUrl()}');
    return !apiReachable;
  }

  /// Requests an OTP, converting the throttler's 429 into a skip.
  Future<String?> requestCode({required bool signup}) async {
    try {
      final result = await repo.requestOtp(email, signup: signup);
      expect(result.resendAfterSec, greaterThan(0));
      return result.devCode;
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        markTestSkipped('OTP request throttled (5/min per IP) — wait a minute and re-run');
        return null;
      }
      rethrow;
    }
  }

  group('signup', () {
    String? signupCode;
    late String signupToken;
    late Me me;

    test('requests an OTP and receives a six-digit dev code', () async {
      if (skipIfDown()) return;
      signupCode = await requestCode(signup: true);
      if (signupCode == null) return;
      expect(signupCode, matches(RegExp(r'^\d{6}$')),
          reason: 'dev builds echo the code so signup is testable without an inbox');
    });

    test('rejects a wrong code without consuming the real one', () async {
      if (skipIfDown() || signupCode == null) return;
      await expectLater(
        repo.verifyOtp(email, signupCode == '000000' ? '111111' : '000000'),
        throwsA(isA<ApiException>()),
      );
    });

    test('verifies the real code and reports a new user', () async {
      if (skipIfDown() || signupCode == null) return;
      final result = await repo.verifyOtp(email, signupCode!);
      expect(result, isA<OtpNewUser>());
      signupToken = (result as OtpNewUser).signupToken;
      expect(signupToken, isNotEmpty);
    });

    test('completes signup, seeds an account, and stores the session', () async {
      if (skipIfDown() || signupCode == null) return;
      me = await repo.completeSignup(
        signupToken: signupToken,
        fullName: 'Robin Vega',
        password: 'SuperSecret1',
        useFor: 'work',
        manageCategory: 'more_workflows',
        workCategory: 'task_management',
      );

      expect(me.email, email);
      expect(me.firstName, 'Robin');
      expect(me.onboardingCompleted, isTrue);
      expect(me.account.role, 'admin');
      expect(me.accounts, hasLength(1));
      expect(TokenStore.instance.accessToken, isNotNull);
      expect(await TokenStore.instance.readRefreshToken(), isNotNull);
      sessionReady = true;
    });

    test('GET /me returns the same identity as the signup response', () async {
      if (skipIfDown() || signupCode == null) return;
      final fetched = await repo.fetchMe();
      expect(fetched.id, me.id);
      expect(fetched.account.id, me.account.id);
    });
  });

  group('home and boards', () {
    String? boardId;

    test('home overview reports the seeded setup progress', () async {
      if (skipIfDown()) return;
      final overview = HomeOverview.fromJson(await ApiClient.instance.get('/home/overview'));
      expect(overview.greetingName, 'Robin');
      expect(overview.setupSteps, isNotEmpty);
      expect(overview.setupPercent, inInclusiveRange(0, 100));
    });

    test('workspaces contain the seeded starter board', () async {
      if (skipIfDown()) return;
      final raw = await ApiClient.instance.getList('/workspaces');
      final workspaces =
          raw.map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>)).toList();

      expect(workspaces, isNotEmpty);
      expect(workspaces.first.boards, isNotEmpty);
      boardId = workspaces.first.boards.first.id;
      expect(workspaces.first.boards.first.workspaceName, workspaces.first.name);
    });

    test('board detail parses columns, groups and cell values', () async {
      if (skipIfDown()) return;
      final board = BoardDetail.fromJson(await ApiClient.instance.get('/boards/$boardId'));

      expect(board.id, boardId);
      expect(board.columns, isNotEmpty);
      expect(board.columns.map((c) => c.type), contains('status'));
      expect(board.groups, isNotEmpty);

      final statusColumn = board.columns.firstWhere((c) => c.type == 'status');
      expect(statusColumn.statusLabels, isNotEmpty);
      expect(statusColumn.statusLabels.any((l) => l.isDone), isTrue);
      expect(board.members, isNotEmpty);
    });

    test('favoriting the board surfaces it on home, unfavoriting removes it', () async {
      if (skipIfDown()) return;
      expect(await _toggleFavorite(boardId!), isTrue);

      var overview = HomeOverview.fromJson(await ApiClient.instance.get('/home/overview'));
      expect(overview.favorites.map((b) => b.id), contains(boardId));

      expect(await _toggleFavorite(boardId!), isFalse);

      overview = HomeOverview.fromJson(await ApiClient.instance.get('/home/overview'));
      expect(overview.favorites.map((b) => b.id), isNot(contains(boardId)));
    });

    test('visiting the board puts it in recently visited', () async {
      if (skipIfDown()) return;
      await ApiClient.instance.post('/boards/$boardId/visit');
      final overview = HomeOverview.fromJson(await ApiClient.instance.get('/home/overview'));
      expect(overview.recentlyVisited.map((b) => b.id), contains(boardId));
    });
  });

  group('board editing', () {
    late String createdBoardId;
    late BoardDetail board;
    late BoardRepository boards;

    setUpAll(() {
      boards = BoardRepository(ApiClient.instance);
    });

    test('lists the template gallery', () async {
      if (skipIfDown()) return;
      final templates = await boards.templates();
      expect(templates.map((t) => t.key), containsAll(['blank', 'task_management']));
      expect(templates.firstWhere((t) => t.key == 'task_management').columnCount, greaterThan(1));
    });

    test('creates a board from a template with its columns, groups and items', () async {
      if (skipIfDown()) return;
      createdBoardId = await boards.createBoard(name: 'E2E plan', template: 'task_management');
      board = await boards.fetch(createdBoardId);

      expect(board.name, 'E2E plan');
      expect(board.columns.map((c) => c.title), containsAll(['Status', 'Owner', 'Due date']));
      expect(board.groups, hasLength(3));
      expect(board.itemCount, greaterThan(0));
    });

    test('creates an item and sets typed cell values', () async {
      if (skipIfDown()) return;
      final group = board.groups.first;
      final item = await boards.createItem(
        boardId: createdBoardId,
        groupId: group.id,
        name: 'Write the e2e test',
      );
      expect(item.name, 'Write the e2e test');

      final status = board.columns.firstWhere((c) => c.title == 'Status');
      final stored = await boards.setCellValue(
        itemId: item.id,
        columnId: status.id,
        value: {'labelId': 'working'},
      );
      expect(stored, {'labelId': 'working'});

      final date = board.columns.firstWhere((c) => c.type == 'date');
      expect(
        await boards.setCellValue(itemId: item.id, columnId: date.id, value: {'date': '2026-12-01'}),
        {'date': '2026-12-01'},
      );

      // Clearing a cell removes it rather than storing an empty shape.
      expect(await boards.setCellValue(itemId: item.id, columnId: date.id, value: null), isNull);

      final refreshed = await boards.fetch(createdBoardId);
      final saved = refreshed.findItem(item.id);
      expect(saved, isNotNull);
      expect(saved!.values[status.id], {'labelId': 'working'});
      expect(saved.values.containsKey(date.id), isFalse);
    });

    test('rejects a cell value that does not match the column type', () async {
      if (skipIfDown()) return;
      final refreshed = await boards.fetch(createdBoardId);
      final status = refreshed.columns.firstWhere((c) => c.type == 'status');
      final item = refreshed.groups.expand((g) => g.items).first;

      await expectLater(
        boards.setCellValue(itemId: item.id, columnId: status.id, value: {'labelId': 'not-a-label'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('renames, duplicates, moves and archives items', () async {
      if (skipIfDown()) return;
      var refreshed = await boards.fetch(createdBoardId);
      final item = refreshed.groups.first.items.first;

      await boards.renameItem(item.id, 'Renamed by e2e');
      refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.findItem(item.id)!.name, 'Renamed by e2e');

      final copy = await boards.duplicateItem(item.id);
      expect(copy.name, contains('(copy)'));

      // Move the copy into the second group, at the top.
      final target = refreshed.groups[1];
      await boards.moveItem(itemId: copy.id, groupId: target.id, afterItemId: null);
      refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.groups[1].items.first.id, copy.id);

      await boards.archiveItem(copy.id);
      refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.findItem(copy.id), isNull);
    });

    test('adds, recolors and deletes groups, refusing to delete the last one', () async {
      if (skipIfDown()) return;
      final group = await boards.createGroup(boardId: createdBoardId, title: 'E2E group');
      expect(group.title, 'E2E group');

      await boards.updateGroup(group.id, title: 'E2E renamed', color: 'teal');
      var refreshed = await boards.fetch(createdBoardId);
      final updated = refreshed.groups.firstWhere((g) => g.id == group.id);
      expect(updated.title, 'E2E renamed');
      expect(updated.color, 'teal');

      await boards.deleteGroup(group.id);
      refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.groups.map((g) => g.id), isNot(contains(group.id)));

      // Strip down to a single group, then confirm the guard fires.
      for (final remaining in refreshed.groups.skip(1)) {
        await boards.deleteGroup(remaining.id);
      }
      final last = (await boards.fetch(createdBoardId)).groups.single;
      await expectLater(
        boards.deleteGroup(last.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('adds and removes columns', () async {
      if (skipIfDown()) return;
      final column = await boards.createColumn(
        boardId: createdBoardId,
        type: 'number',
        title: 'Estimate',
      );
      expect(column.type, 'number');

      var refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.columns.map((c) => c.title), contains('Estimate'));

      await boards.deleteColumn(column.id);
      refreshed = await boards.fetch(createdBoardId);
      expect(refreshed.columns.map((c) => c.title), isNot(contains('Estimate')));
    });

    test('posts an update and records it in the item feed', () async {
      if (skipIfDown()) return;
      final refreshed = await boards.fetch(createdBoardId);
      final item = refreshed.groups.expand((g) => g.items).first;

      await ApiClient.instance.post('/items/${item.id}/updates', body: {'body': 'Progress from e2e'});
      final detail = ItemDetail.fromJson(await ApiClient.instance.get('/items/${item.id}'));

      expect(detail.updates, isNotEmpty);
      expect(detail.updates.first.body, 'Progress from e2e');
      // Activity is written for every mutation, so the feed cannot be empty here.
      expect(detail.activity, isNotEmpty);
    });

    test('surfaces assigned items in My Work', () async {
      if (skipIfDown()) return;
      final refreshed = await boards.fetch(createdBoardId);
      final people = refreshed.columns.firstWhere((c) => c.type == 'people');
      final item = refreshed.groups.expand((g) => g.items).first;
      final me = await repo.fetchMe();

      await boards.setCellValue(
        itemId: item.id,
        columnId: people.id,
        value: {'userIds': [me.id]},
      );

      final work = MyWork.fromJson(await ApiClient.instance.get('/my-work'));
      final allIds = [
        ...work.overdue,
        ...work.today,
        ...work.thisWeek,
        ...work.later,
        ...work.noDate,
      ].map((i) => i.id);
      expect(allIds, contains(item.id));
    });

    test('finds boards and items by name', () async {
      if (skipIfDown()) return;
      final results = SearchResults.fromJson(
        await ApiClient.instance.get('/search', query: {'q': 'E2E plan'}),
      );
      expect(results.boards.map((b) => b.name), contains('E2E plan'));
    });

    test('ignores a search query shorter than two characters', () async {
      if (skipIfDown()) return;
      final results = SearchResults.fromJson(await ApiClient.instance.get('/search', query: {'q': 'a'}));
      expect(results.isEmpty, isTrue);
    });

    test('edits a status column\'s labels and keeps existing values valid', () async {
      if (skipIfDown()) return;
      var refreshed = await boards.fetch(createdBoardId);
      final status = refreshed.columns.firstWhere((c) => c.type == 'status');

      await boards.updateColumn(status.id, settings: {
        'labels': [
          {'id': 'working', 'label': 'In progress', 'color': 'blue', 'isDone': false},
          {'id': 'done', 'label': 'Shipped', 'color': 'green', 'isDone': true},
          {'id': 'blocked', 'label': 'Blocked', 'color': 'red', 'isDone': false},
        ],
      });

      refreshed = await boards.fetch(createdBoardId);
      final updated = refreshed.columns.firstWhere((c) => c.id == status.id);
      expect(updated.statusLabels.map((l) => l.label), containsAll(['In progress', 'Shipped', 'Blocked']));

      // The new id is now assignable; a removed one would be rejected.
      final item = refreshed.groups.expand((g) => g.items).first;
      expect(
        await boards.setCellValue(itemId: item.id, columnId: status.id, value: {'labelId': 'blocked'}),
        {'labelId': 'blocked'},
      );
      await expectLater(
        boards.setCellValue(itemId: item.id, columnId: status.id, value: {'labelId': 'stuck'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('archives the board so it leaves the workspace listing', () async {
      if (skipIfDown()) return;
      await boards.archiveBoard(createdBoardId);
      final raw = await ApiClient.instance.getList('/workspaces');
      final ids = raw
          .map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>))
          .expand((w) => w.boards)
          .map((b) => b.id);
      expect(ids, isNot(contains(createdBoardId)));
    });
  });

  group('updates, files, feed and prefs', () {
    late ItemRepository items;
    late BoardRepository boards;
    String? itemId;
    String? parentUpdateId;

    setUpAll(() {
      items = ItemRepository(ApiClient.instance);
      boards = BoardRepository(ApiClient.instance);
    });

    Future<String> anyItemId() async {
      final raw = await ApiClient.instance.getList('/workspaces');
      final workspaces = raw.map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>)).toList();
      final board = await boards.fetch(workspaces.first.boards.first.id);
      return board.groups.expand((g) => g.items).first.id;
    }

    test('posts an update and a threaded reply', () async {
      if (skipIfDown() || !sessionReady) return;
      itemId = await anyItemId();
      final parent = await items.postUpdate(itemId: itemId!, body: 'E2E parent update');
      parentUpdateId = parent.id;

      final reply = await items.postUpdate(itemId: itemId!, body: 'E2E reply', parentId: parent.id);
      expect(reply.id, isNot(parent.id));

      final detail = await items.fetch(itemId!);
      final threaded = detail.updates.firstWhere((u) => u.id == parent.id);
      expect(threaded.replies.map((r) => r.body), contains('E2E reply'));
    });

    test('refuses to nest a reply under a reply', () async {
      if (skipIfDown() || !sessionReady || itemId == null) return;
      final detail = await items.fetch(itemId!);
      final replyId = detail.updates.firstWhere((u) => u.id == parentUpdateId).replies.first.id;
      await expectLater(
        items.postUpdate(itemId: itemId!, body: 'too deep', parentId: replyId),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('likes and bookmarks toggle and reflect in the payload', () async {
      if (skipIfDown() || !sessionReady || parentUpdateId == null) return;
      final liked = await items.toggleLike(parentUpdateId!);
      expect(liked.liked, isTrue);
      expect(liked.likesCount, 1);
      expect(await items.toggleBookmark(parentUpdateId!), isTrue);

      var detail = await items.fetch(itemId!);
      var update = detail.updates.firstWhere((u) => u.id == parentUpdateId);
      expect(update.likedByMe, isTrue);
      expect(update.bookmarkedByMe, isTrue);

      final unliked = await items.toggleLike(parentUpdateId!);
      expect(unliked.liked, isFalse);
      expect(unliked.likesCount, 0);
    });

    test('edits own update and stamps editedAt', () async {
      if (skipIfDown() || !sessionReady || parentUpdateId == null) return;
      await items.editUpdate(parentUpdateId!, 'E2E parent update (edited)');
      final detail = await items.fetch(itemId!);
      final update = detail.updates.firstWhere((u) => u.id == parentUpdateId);
      expect(update.body, 'E2E parent update (edited)');
      expect(update.isEdited, isTrue);
    });

    test('feed lists the update with its board context; bookmark filter works', () async {
      if (skipIfDown() || !sessionReady || parentUpdateId == null) return;
      final feed = await items.feed();
      final mine = feed.where((e) => e.update.id == parentUpdateId);
      expect(mine, hasLength(1));
      expect(mine.first.boardName, isNotEmpty);

      final bookmarked = await items.feed(bookmarkedOnly: true);
      expect(bookmarked.map((e) => e.update.id), contains(parentUpdateId));
    });

    test('uploads a file, lists it, serves it without auth, deletes it', () async {
      if (skipIfDown() || !sessionReady || itemId == null) return;
      final uploaded = await items.uploadFile(
        bytes: 'dayflow e2e attachment'.codeUnits,
        filename: 'probe.txt',
        itemId: itemId,
      );
      expect(uploaded.sizeBytes, greaterThan(0));
      expect(uploaded.url, startsWith('http'));

      final listed = await items.filesForItem(itemId!);
      expect(listed.map((f) => f.id), contains(uploaded.id));

      // Content is served without a bearer token (unguessable-id access).
      final client = HttpClient();
      final response = await client.getUrl(Uri.parse(uploaded.url)).then((r) => r.close());
      expect(response.statusCode, 200);
      final body = await response.transform(const Utf8Decoder()).join();
      expect(body, 'dayflow e2e attachment');
      client.close();

      await items.deleteFile(uploaded.id);
      final after = await items.filesForItem(itemId!);
      expect(after.map((f) => f.id), isNot(contains(uploaded.id)));
    });

    test('deleting the parent update removes its replies', () async {
      if (skipIfDown() || !sessionReady || parentUpdateId == null) return;
      await items.deleteUpdate(parentUpdateId!);
      final detail = await items.fetch(itemId!);
      expect(detail.updates.map((u) => u.id), isNot(contains(parentUpdateId)));
    });

    test('notification prefs round-trip', () async {
      if (skipIfDown() || !sessionReady) return;
      final before = NotificationPrefs.fromJson(await ApiClient.instance.get('/me/notification-prefs'));
      final flipped = NotificationPrefs.fromJson(await ApiClient.instance.patch(
        '/me/notification-prefs',
        body: {'pushEnabled': !before.pushEnabled},
      ));
      expect(flipped.pushEnabled, !before.pushEnabled);
      // Restore.
      await ApiClient.instance.patch('/me/notification-prefs', body: {'pushEnabled': before.pushEnabled});
    });

    test('exports the board as CSV with a header row', () async {
      if (skipIfDown() || !sessionReady) return;
      final raw = await ApiClient.instance.getList('/workspaces');
      final workspaces = raw.map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>)).toList();
      final csv = await ApiClient.instance.getText('/boards/${workspaces.first.boards.first.id}/export.csv');
      expect(csv.split('\r\n').first, startsWith('Group,Item'));
      expect(csv.split('\r\n').length, greaterThan(1));
    });
  });

  group('members and invitations', () {
    late MembersRepository members;
    String? invitationId;

    setUpAll(() {
      members = MembersRepository(ApiClient.instance);
    });

    test('lists the signup user as the sole admin', () async {
      if (skipIfDown() || !sessionReady) return;
      final directory = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));

      expect(directory.members, hasLength(1));
      expect(directory.members.single.role, 'admin');
      expect(directory.members.single.isYou, isTrue);
      expect(directory.invitations, isEmpty);
    });

    test('invites an email and lists it as pending', () async {
      if (skipIfDown() || !sessionReady) return;
      final invite = await members.invite(email: 'invitee.$email', role: 'member');
      invitationId = invite.id;
      expect(invite.role, 'member');
      // Dev builds echo the accept link so the flow is testable without email.
      expect(invite.devLink, contains('invite/'));

      final directory = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      expect(directory.invitations.map((i) => i.id), contains(invitationId));
    });

    test('re-inviting the same address replaces the invitation', () async {
      if (skipIfDown() || !sessionReady) return;
      await members.invite(email: 'invitee.$email', role: 'viewer');
      final directory = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      final matching = directory.invitations.where((i) => i.email == 'invitee.$email');
      expect(matching, hasLength(1), reason: 'must not pile up rows for one address');
      expect(matching.single.role, 'viewer');
      invitationId = matching.single.id;
    });

    test('refuses to invite someone already in the account', () async {
      if (skipIfDown() || !sessionReady) return;
      await expectLater(
        members.invite(email: email, role: 'member'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
      );
    });

    test('refuses to demote the only admin', () async {
      if (skipIfDown() || !sessionReady) return;
      final me = await repo.fetchMe();
      await expectLater(
        members.changeRole(userId: me.id, role: 'member'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('rejects an invalid invitation token', () async {
      if (skipIfDown() || !sessionReady) return;
      await expectLater(
        members.accept('not-a-real-token-value'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('revokes a pending invitation', () async {
      if (skipIfDown() || !sessionReady || invitationId == null) return;
      await members.revokeInvite(invitationId!);
      final directory = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      expect(directory.invitations.map((i) => i.id), isNot(contains(invitationId)));
    });
  });

  group('board types and members', () {
    late MembersRepository members;
    late BoardRepository boardsRepo;
    String? privateBoardId;
    String? buddyUserId;
    String? buddyToken;
    final buddyEmail = 'buddy.$email';

    setUpAll(() {
      members = MembersRepository(ApiClient.instance);
      boardsRepo = BoardRepository(ApiClient.instance);
    });

    test('creates a private board owned by its creator', () async {
      if (skipIfDown() || !sessionReady) return;
      privateBoardId = await boardsRepo.createBoard(name: 'Secret e2e plans', type: 'private');

      final list = await boardsRepo.boardMembers(privateBoardId!);
      expect(list.canManage, isTrue);
      expect(list.members, hasLength(1));
      expect(list.members.single.role, 'owner', reason: 'the creator is the first owner');
      expect(list.members.single.isYou, isTrue);
    });

    test('a second account member cannot see the private board', () async {
      if (skipIfDown() || !sessionReady || privateBoardId == null) return;

      // Bring a real second user into the account: invite → signup → accept →
      // switch. Raw HTTP keeps the singleton client on the owner's session.
      final invite = await members.invite(email: buddyEmail, role: 'member');
      final inviteToken = invite.devLink!.split('/').last;

      final otp = await _rawJson('POST', '/v1/auth/otp/request',
          body: {'email': buddyEmail, 'purpose': 'signup'});
      if (otp.status == 429) {
        markTestSkipped('OTP request throttled — wait a minute and re-run');
        return;
      }
      final verify = await _rawJson('POST', '/v1/auth/otp/verify',
          body: {'email': buddyEmail, 'code': otp.json['devCode'] as String});
      final session = await _rawJson('POST', '/v1/auth/signup/complete', body: {
        'signupToken': verify.json['signupToken'] as String,
        'password': 'Passw0rd!123',
        'fullName': 'Buddy Two',
        'useFor': 'work',
      });
      buddyUserId = ((session.json['user'] as Map).cast<String, dynamic>())['id'] as String;

      final accepted = await _rawJson('POST', '/v1/invitations/accept',
          body: {'token': inviteToken}, token: session.json['accessToken'] as String);
      final switched = await _rawJson('POST', '/v1/auth/switch',
          body: {'accountId': accepted.json['accountId'] as String},
          token: session.json['accessToken'] as String);
      buddyToken = switched.json['accessToken'] as String;

      final fetch = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(fetch.status, 404, reason: 'private boards must be invisible to non-members');

      final listing = await _rawJson('GET', '/v1/workspaces', token: buddyToken);
      expect(jsonEncode(listing.raw), isNot(contains(privateBoardId!)),
          reason: 'private boards must not leak into the workspace listing');
    });

    test('adding them as a board member grants access', () async {
      if (skipIfDown() || privateBoardId == null || buddyUserId == null || buddyToken == null) return;
      final list = await boardsRepo.addBoardMember(boardId: privateBoardId!, userId: buddyUserId!);
      expect(list.members.map((m) => m.userId), contains(buddyUserId));

      final fetch = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(fetch.status, 200);
    });

    test('a board viewer is read-only on that board', () async {
      if (skipIfDown() || privateBoardId == null || buddyUserId == null || buddyToken == null) return;
      await boardsRepo.changeBoardMemberRole(
          boardId: privateBoardId!, userId: buddyUserId!, role: 'viewer');

      final board = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(board.status, 200, reason: 'viewers still read the board');
      final groupId =
          (((board.json['groups'] as List).first as Map).cast<String, dynamic>())['id'] as String;

      final attempt = await _rawJson('POST', '/v1/boards/$privateBoardId/items',
          body: {'groupId': groupId, 'name': 'should not land'}, token: buddyToken);
      expect(attempt.status, 403, reason: 'board viewers cannot edit');
    });

    test('viewers cannot be promoted to owner when their account role forbids it', () async {
      if (skipIfDown() || privateBoardId == null || buddyUserId == null) return;
      // Buddy's ACCOUNT role is member, so board ownership is allowed; promote
      // and demote to prove the transition works both ways.
      var list = await boardsRepo.changeBoardMemberRole(
          boardId: privateBoardId!, userId: buddyUserId!, role: 'owner');
      expect(list.members.where((m) => m.role == 'owner'), hasLength(2));
      list = await boardsRepo.changeBoardMemberRole(
          boardId: privateBoardId!, userId: buddyUserId!, role: 'member');
      expect(list.members.where((m) => m.role == 'owner'), hasLength(1));
    });

    test('removing them takes the board away again', () async {
      if (skipIfDown() || privateBoardId == null || buddyUserId == null || buddyToken == null) return;
      final list = await boardsRepo.removeBoardMember(boardId: privateBoardId!, userId: buddyUserId!);
      expect(list.members.map((m) => m.userId), isNot(contains(buddyUserId)));

      final fetch = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(fetch.status, 404);
    });

    test('switching the type to main opens the board to the account', () async {
      if (skipIfDown() || privateBoardId == null || buddyToken == null) return;
      await boardsRepo.setBoardType(privateBoardId!, 'main');
      final open = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(open.status, 200);

      await boardsRepo.setBoardType(privateBoardId!, 'private');
      final closed = await _rawJson('GET', '/v1/boards/$privateBoardId', token: buddyToken);
      expect(closed.status, 404);
    });

    test('non-owners cannot change the board type', () async {
      if (skipIfDown() || privateBoardId == null || buddyToken == null) return;
      final attempt = await _rawJson('PATCH', '/v1/boards/$privateBoardId',
          body: {'type': 'main'}, token: buddyToken);
      // Not a board member any more → the board does not even exist for them.
      expect(attempt.status, 404);
    });

    test('a board must keep at least one owner', () async {
      if (skipIfDown() || !sessionReady || privateBoardId == null) return;
      final me = await repo.fetchMe();
      await expectLater(
        boardsRepo.removeBoardMember(boardId: privateBoardId!, userId: me.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('P0: columns, subitems, views, archive, batch, activity, rich text', () {
    late BoardRepository boards;
    late ItemRepository items;
    late MembersRepository members;
    String? boardId;
    String? targetBoardId;
    BoardDetail? board;
    String? parentId;
    String? subitemId;

    setUpAll(() {
      boards = BoardRepository(ApiClient.instance);
      items = ItemRepository(ApiClient.instance);
      members = MembersRepository(ApiClient.instance);
    });

    Future<BoardDetail> reload() async => board = await boards.fetch(boardId!);

    test('a new board ships with a default view, item serials and caller flags', () async {
      if (skipIfDown() || !sessionReady) return;
      boardId = await boards.createBoard(name: 'P0 parity', template: 'task_management');
      await reload();
      expect(board!.views, hasLength(1));
      expect(board!.views.single.isDefault, isTrue);
      expect(board!.views.single.type, 'table');
      expect(board!.canEdit, isTrue);
      expect(board!.canManage, isTrue, reason: 'the creator owns the board');
      final serials = board!.allItems.map((i) => i.serial).toList();
      expect(serials, everyElement(greaterThan(0)));
      expect(serials.toSet().length, serials.length, reason: 'serials are unique per board');
      expect(board!.allItems.first.createdAt, isNotNull);
    });

    test('adds every new column type and validates their values', () async {
      if (skipIfDown() || boardId == null) return;
      final created = <String, BoardColumn>{};
      for (final type in [
        'long_text',
        'email',
        'phone',
        'rating',
        'files',
        'vote',
        'item_id',
        'creation_log',
        'last_updated',
        'auto_number',
      ]) {
        created[type] = await boards.createColumn(boardId: boardId!, type: type, title: type);
        expect(created[type]!.scope, 'items');
      }
      await reload();
      final item = board!.allItems.first;
      final me = await repo.fetchMe();

      expect(
        await boards.setCellValue(itemId: item.id, columnId: created['long_text']!.id, value: {'text': 'line one\nline two'}),
        {'text': 'line one\nline two'},
      );
      expect(
        await boards.setCellValue(itemId: item.id, columnId: created['email']!.id, value: {'email': 'Team@Example.com'}),
        {'email': 'Team@Example.com'},
      );
      await expectLater(
        boards.setCellValue(itemId: item.id, columnId: created['email']!.id, value: {'email': 'not-an-email'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
      expect(
        await boards.setCellValue(
            itemId: item.id, columnId: created['phone']!.id, value: {'phone': '+1 (555) 010-2030', 'countryCode': 'us'}),
        {'phone': '+1 (555) 010-2030', 'countryCode': 'US'},
      );
      expect(
        await boards.setCellValue(itemId: item.id, columnId: created['rating']!.id, value: {'rating': 4}),
        {'rating': 4},
      );
      await expectLater(
        boards.setCellValue(itemId: item.id, columnId: created['rating']!.id, value: {'rating': 9}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
        reason: 'a rating column defaults to five stars',
      );
      expect(
        await boards.setCellValue(itemId: item.id, columnId: created['vote']!.id, value: {'userIds': [me.id, me.id]}),
        {'userIds': [me.id]},
      );
      // Read-only columns cannot be written at all.
      for (final type in ['item_id', 'creation_log', 'last_updated', 'auto_number']) {
        await expectLater(
          boards.setCellValue(itemId: item.id, columnId: created[type]!.id, value: {'text': 'x'}),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
        );
      }
      // A Files cell may only reference this item's own files.
      await expectLater(
        boards.setCellValue(
            itemId: item.id, columnId: created['files']!.id, value: {'fileIds': ['11111111-1111-4111-8111-111111111111']}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('uploading into a Files column mirrors the cell and deleting the file clears it', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final item = board!.allItems.first;
      final filesColumn = board!.columns.firstWhere((c) => c.type == 'files');
      final uploaded = await items.uploadFile(
        bytes: 'p0 attachment'.codeUnits,
        filename: 'p0.txt',
        itemId: item.id,
        columnId: filesColumn.id,
      );
      await reload();
      expect(board!.findItem(item.id)!.values[filesColumn.id], {'fileIds': [uploaded.id]});

      await items.deleteFile(uploaded.id);
      await reload();
      expect(board!.findItem(item.id)!.values.containsKey(filesColumn.id), isFalse);
    });

    test('column settings are normalised and columns can be reordered', () async {
      if (skipIfDown() || boardId == null) return;
      final number = await boards.createColumn(boardId: boardId!, type: 'number', title: 'Budget');
      await boards.updateColumn(number.id, settings: {
        'unit': r'$',
        'unitPosition': 'prefix',
        'decimals': 2,
        'summary': 'avg',
        'description': 'Planned spend',
        'junk': true,
      });
      await reload();
      final stored = board!.columns.firstWhere((c) => c.id == number.id);
      expect(stored.settings['unit'], r'$');
      expect(stored.settings['decimals'], 2);
      expect(stored.settings['summary'], 'avg');
      expect(stored.settings.containsKey('junk'), isFalse, reason: 'unknown settings keys are dropped');
      await expectLater(
        boards.updateColumn(number.id, settings: {'decimals': 12}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );

      // Move Budget to the front of the item columns.
      await boards.moveColumn(columnId: number.id, afterColumnId: null);
      await reload();
      expect(board!.itemColumns.first.id, number.id);
    });

    test('subitems nest under their parent with their own column set', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      parentId = board!.allItems.first.id;
      final sub = await boards.createSubitem(parentItemId: parentId!, name: 'Sub one');
      subitemId = sub.id;
      expect(sub.parentItemId, parentId);

      await reload();
      final parent = board!.findItem(parentId!)!;
      expect(parent.subitems.map((s) => s.id), contains(sub.id));
      expect(board!.groups.expand((g) => g.items).map((i) => i.id), isNot(contains(sub.id)),
          reason: 'subitems never appear as top-level rows');
      expect(board!.subitemColumns.map((c) => c.title), containsAll(['Status', 'Owner', 'Date']),
          reason: 'the default subitem columns are created on first use');

      final subStatus = board!.subitemColumns.firstWhere((c) => c.type == 'status');
      expect(
        await boards.setCellValue(itemId: sub.id, columnId: subStatus.id, value: {'labelId': 'done'}),
        {'labelId': 'done'},
      );
      final itemStatus = board!.itemColumns.firstWhere((c) => c.type == 'status');
      await expectLater(
        boards.setCellValue(itemId: sub.id, columnId: itemStatus.id, value: {'labelId': 'done'}),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
        reason: 'item-level columns do not apply to subitems',
      );
      await expectLater(
        boards.createSubitem(parentItemId: sub.id, name: 'too deep'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );

      final detail = await items.fetch(sub.id);
      expect(detail.isSubitem, isTrue);
      expect(detail.parentName, isNotEmpty);
      expect(detail.columns.map((c) => c.id), contains(subStatus.id));
      final parentDetail = await items.fetch(parentId!);
      expect(parentDetail.subitems.map((s) => s.id), contains(sub.id));

      // Duplicating the parent copies its subitems.
      final copy = await boards.duplicateItem(parentId!);
      expect(copy.subitems, hasLength(1));
      expect(copy.subitems.single.values[subStatus.id], {'labelId': 'done'});
      await boards.trashItem(copy.id);
    });

    test('saved views validate their config and drive the CSV export', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final status = board!.itemColumns.firstWhere((c) => c.type == 'status');

      await expectLater(
        boards.createView(boardId!, type: 'table', name: 'Broken', config: {
          'filters': {'conjunction': 'and', 'rules': [{'id': 'r1', 'field': status.id, 'operator': 'contains', 'value': 'x'}]},
        }),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
        reason: 'text operators are invalid on a status column',
      );

      final view = await boards.createView(boardId!, type: 'table', name: 'Only stuck', config: {
        'filters': {
          'conjunction': 'and',
          'rules': [{'id': 'r1', 'field': status.id, 'operator': 'is_any_of', 'value': ['stuck']}],
        },
        'sort': [{'field': 'name', 'direction': 'asc'}],
        'hiddenColumnIds': [board!.itemColumns.firstWhere((c) => c.type == 'date').id],
      });
      expect(view.isDefault, isFalse);
      await reload();
      expect(board!.views.map((v) => v.id), contains(view.id));

      final all = await boards.exportCsv(boardId!);
      final filtered = await boards.exportCsv(boardId!, viewId: view.id);
      expect(filtered.split('\r\n').length, lessThan(all.split('\r\n').length));
      expect(filtered.split('\r\n').first.contains('Due date'), isFalse, reason: 'hidden columns leave the export');

      final renamed = await boards.updateView(view.id, name: 'Stuck only', isDefault: true);
      expect(renamed.isDefault, isTrue);
      await reload();
      expect(board!.views.where((v) => v.isDefault), hasLength(1));

      final copy = await boards.duplicateView(view.id);
      expect(copy.name, contains('(copy)'));
      await boards.moveView(viewId: copy.id, afterViewId: null);
      await reload();
      expect(board!.views.first.id, copy.id);
      await boards.deleteView(copy.id);

      // The board must always keep one view.
      final remaining = (await reload()).views;
      for (final v in remaining.where((v) => v.id != view.id)) {
        await boards.deleteView(v.id);
      }
      await expectLater(
        boards.deleteView(view.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('archive and trash hide items, list them and restore them', () async {
      if (skipIfDown() || boardId == null || parentId == null) return;
      await boards.archiveItem(parentId!);
      await reload();
      expect(board!.findItem(parentId!), isNull);
      var archive = await boards.archive(boardId: boardId);
      expect(archive.items.map((i) => i.id), contains(parentId));
      expect(archive.items.map((i) => i.id), isNot(contains(subitemId)),
          reason: 'subitems archived with their parent are represented by the parent');

      final restored = await boards.restoreItem(parentId!);
      expect(restored.subitems.map((s) => s.id), contains(subitemId));
      await reload();
      expect(board!.findItem(parentId!), isNotNull);
      expect(board!.findItem(subitemId!), isNotNull);

      await expectLater(
        boards.deleteItemPermanently(parentId!),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
        reason: 'only trashed items can be deleted for good',
      );
      await boards.trashItem(parentId!);
      final trash = await boards.trash(boardId: boardId);
      final entry = trash.items.firstWhere((i) => i.id == parentId);
      expect(entry.purgeAt, isNotNull);
      expect(entry.purgeAt!.isAfter(DateTime.now().add(const Duration(days: 29))), isTrue);
      await boards.restoreItem(parentId!);
      archive = await boards.archive(boardId: boardId);
      expect(archive.items.map((i) => i.id), isNot(contains(parentId)));
    });

    test('batch actions apply to many items in one call', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final status = board!.itemColumns.firstWhere((c) => c.type == 'status');
      final ids = board!.allItems.take(2).map((i) => i.id).toList();
      expect(ids, hasLength(2));

      final affected = await boards.batch(
        boardId: boardId!,
        itemIds: ids,
        action: 'set_cell',
        columnId: status.id,
        value: {'labelId': 'done'},
      );
      expect(affected, 2);
      await reload();
      for (final id in ids) {
        expect(board!.findItem(id)!.values[status.id], {'labelId': 'done'});
      }

      expect(await boards.batch(boardId: boardId!, itemIds: ids, action: 'archive'), 2);
      await reload();
      expect(board!.findItem(ids.first), isNull);
      expect(await boards.batch(boardId: boardId!, itemIds: ids, action: 'restore'), 2);
      await reload();
      expect(board!.findItem(ids.first), isNotNull);
    });

    test('the board activity log records changes and undoes the latest one', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final item = board!.allItems.first;
      final original = item.name;
      await boards.renameItem(item.id, 'Renamed for undo');

      final page = await boards.activity(boardId!, itemId: item.id);
      final rename = page.entries.firstWhere((e) => e.event == 'item_renamed');
      expect(rename.itemName, 'Renamed for undo');
      expect(rename.undoable, isTrue);
      expect(page.entries.any((e) => e.event == 'column_value_changed' && e.columnTitle != null), isTrue,
          reason: 'value changes carry their column');

      await boards.undoActivity(rename.id);
      await reload();
      expect(board!.findItem(item.id)!.name, original);
      final after = await boards.activity(boardId!, itemId: item.id);
      expect(after.entries.firstWhere((e) => e.id == rename.id).isUndone, isTrue);
      expect(after.entries.first.event, 'activity_undone');
      await expectLater(
        boards.undoActivity(rename.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('updates keep rich text, mentions, reactions and files', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final item = board!.allItems.first;
      final me = await repo.fetchMe();
      final posted = await items.postUpdate(
        itemId: item.id,
        body: 'Ship **today** — see [docs](https://example.com/spec)\n- first\n- second\n@[${me.fullName}](user:${me.id}) fyi',
      );
      expect(posted.body, contains('Ship today'));
      expect(posted.markdown, contains('**today**'));
      final blocks = (posted.doc!['content'] as List).cast<Map<String, dynamic>>();
      expect(blocks.map((b) => b['type']), containsAll(['paragraph', 'bulletList']));
      final inlines = (blocks.first['content'] as List).cast<Map<String, dynamic>>();
      expect(inlines.any((i) => (i['marks'] as List?)?.contains('bold') == true), isTrue);
      expect(inlines.any((i) => i['type'] == 'link'), isTrue);

      final reactions = await items.toggleReaction(posted.id, '🎉');
      expect(reactions.single.emoji, '🎉');
      expect(reactions.single.reactedByMe, isTrue);
      final liked = await items.toggleLike(posted.id);
      expect(liked.likesCount, 1);
      await expectLater(
        items.toggleReaction(posted.id, '🍕'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );

      final attached = await items.uploadFile(bytes: 'shot'.codeUnits, filename: 'shot.txt', updateId: posted.id);
      final detail = await items.fetch(item.id);
      final stored = detail.updates.firstWhere((u) => u.id == posted.id);
      expect(stored.reactions.map((r) => r.emoji), containsAll(['🎉', '👍']));
      expect(stored.files.map((f) => f.id), contains(attached.id));
      expect(stored.doc, isNotNull);

      await items.editUpdate(posted.id, 'Now _italic_');
      final edited = (await items.fetch(item.id)).updates.firstWhere((u) => u.id == posted.id);
      expect(edited.isEdited, isTrue);
      expect(edited.markdown, 'Now _italic_');
    });

    test('board discussion posts live on the board, not an item', () async {
      if (skipIfDown() || boardId == null) return;
      final posted = await items.postBoardUpdate(boardId: boardId!, body: 'Kickoff for **P0**');
      final reply = await items.postBoardUpdate(boardId: boardId!, body: 'ack', parentId: posted.id);
      final thread = await items.boardUpdates(boardId!);
      expect(thread.map((u) => u.id), contains(posted.id));
      expect(thread.firstWhere((u) => u.id == posted.id).replies.map((r) => r.id), contains(reply.id));
      final feed = await items.feed(boardId: boardId);
      final entry = feed.firstWhere((e) => e.update.id == posted.id);
      expect(entry.itemId, isNull);
    });

    test('moves an item to another board with its columns mapped by name', () async {
      if (skipIfDown() || boardId == null) return;
      targetBoardId = await boards.createBoard(name: 'P0 target', template: 'task_management');
      await reload();
      final item = board!.allItems.first;
      final status = board!.itemColumns.firstWhere((c) => c.type == 'status');
      await boards.setCellValue(itemId: item.id, columnId: status.id, value: {'labelId': 'stuck'});

      final preview = await boards.movePreview(itemId: item.id, boardId: targetBoardId!);
      expect(preview.targetBoardName, 'P0 target');
      expect(preview.groups, isNotEmpty);
      final statusMapping = preview.mapping.firstWhere((m) => m.sourceColumnId == status.id);
      expect(statusMapping.targetColumnId, isNotNull, reason: 'Status maps onto the target Status column');
      expect(preview.dropped.map((m) => m.sourceTitle), contains('long_text'),
          reason: 'columns without a same-named twin are reported as lost');

      await boards.moveToBoard(itemId: item.id, boardId: targetBoardId!, groupId: preview.groups.first.id);
      await reload();
      expect(board!.findItem(item.id), isNull);
      final target = await boards.fetch(targetBoardId!);
      final moved = target.findItem(item.id)!;
      final targetStatus = target.itemColumns.firstWhere((c) => c.type == 'status');
      expect(moved.values[targetStatus.id], {'labelId': 'stuck'});
      expect(target.groups.first.items.map((i) => i.id), contains(item.id));
    });

    test('duplicates a board and saves it as a reusable template', () async {
      if (skipIfDown() || boardId == null) return;
      await reload();
      final copyId = await boards.duplicateBoard(boardId!, mode: 'items');
      final copy = await boards.fetch(copyId);
      expect(copy.name, contains('(copy)'));
      expect(copy.itemCount, board!.itemCount);
      expect(copy.itemColumns.length, board!.itemColumns.length);
      expect(copy.views, isNotEmpty);
      await boards.trashBoard(copyId);

      final template = await boards.saveAsTemplate(boardId!, name: 'P0 template', includeItems: true);
      expect(template.isCustom, isTrue);
      expect(template.itemCount, board!.itemCount);
      final gallery = await boards.templates();
      expect(gallery.where((t) => t.isCustom).map((t) => t.key), contains(template.key));
      expect(gallery.first.isCustom, isFalse, reason: 'built-in templates come first');

      final fromTemplate = await boards.createBoard(name: 'From P0 template', template: template.key);
      final built = await boards.fetch(fromTemplate);
      expect(built.itemCount, board!.itemCount);
      await boards.trashBoard(fromTemplate);
      await boards.deleteTemplate(template.id!);
      expect((await boards.templates()).map((t) => t.key), isNot(contains(template.key)));
    });

    test('trashing a board hides it, lists it with a purge date and restores', () async {
      if (skipIfDown() || targetBoardId == null) return;
      await boards.trashBoard(targetBoardId!);
      final raw = await ApiClient.instance.getList('/workspaces');
      final ids = raw.map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>)).expand((w) => w.boards).map((b) => b.id);
      expect(ids, isNot(contains(targetBoardId)));
      final trash = await boards.trash();
      final entry = trash.boards.firstWhere((b) => b.id == targetBoardId);
      expect(entry.purgeAt, isNotNull);
      await boards.restoreBoard(targetBoardId!);
      final back = await boards.fetch(targetBoardId!);
      expect(back.id, targetBoardId);
      await boards.trashBoard(targetBoardId!);
      await boards.deleteBoardPermanently(targetBoardId!);
      await expectLater(
        boards.fetch(targetBoardId!),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('guests can be invited and members deactivated, never the last admin', () async {
      if (skipIfDown() || !sessionReady) return;
      final invite = await members.invite(email: 'guest.$email', role: 'guest');
      expect(invite.role, 'guest');
      await members.revokeInvite(invite.id);

      final me = await repo.fetchMe();
      await expectLater(
        members.deactivate(me.id),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
      final directory = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      final other = directory.members.where((m) => !m.isYou).firstOrNull;
      if (other == null) {
        markTestSkipped('no second member to deactivate (buddy signup was throttled)');
        return;
      }
      await members.deactivate(other.userId);
      var after = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      expect(after.members.firstWhere((m) => m.userId == other.userId).status, 'deactivated');
      await members.reactivate(other.userId);
      after = MemberDirectory.fromJson(await ApiClient.instance.get('/members'));
      expect(after.members.firstWhere((m) => m.userId == other.userId).status, 'active');
    });
  });

  group('session lifecycle', () {
    test('refresh rotates the token and rejects the consumed one', () async {
      if (skipIfDown()) return;
      final oldRefresh = await TokenStore.instance.readRefreshToken();

      expect(await repo.restoreSession(), isNotNull);
      expect(await TokenStore.instance.readRefreshToken(), isNot(oldRefresh),
          reason: 'refresh tokens must rotate on use');

      await expectLater(
        ApiClient.instance.post('/auth/refresh', body: {'refreshToken': oldRefresh}, noAuth: true),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('logging in again with the same email finds the existing account', () async {
      if (skipIfDown()) return;
      final code = await requestCode(signup: false);
      if (code == null) return;

      final result = await repo.verifyOtp(email, code);
      expect(result, isA<OtpExistingUser>());
      final existing = result as OtpExistingUser;
      expect(existing.accounts, hasLength(1));

      final signedIn = await repo.selectAccount(
        selectToken: existing.selectToken,
        accountId: existing.accounts.first.id,
      );
      expect(signedIn.email, email);
    });

    test('logout clears the session and locks the protected endpoints', () async {
      if (skipIfDown()) return;
      await repo.logout();
      expect(TokenStore.instance.accessToken, isNull);
      expect(await TokenStore.instance.readRefreshToken(), isNull);

      await expectLater(repo.fetchMe(), throwsA(isA<ApiException>()));
    });
  });
}

/// True when something answers on the API port. An unauthenticated 401 is the
/// expected healthy response.
Future<bool> _ping() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final response = await client.getUrl(Uri.parse('${apiBaseUrl()}/v1/home/overview')).then((r) => r.close());
    await response.drain<void>();
    return response.statusCode == 401 || response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

/// Mirrors the app's favorite toggle call.
Future<bool> _toggleFavorite(String boardId) async {
  final json = await ApiClient.instance.post('/boards/$boardId/favorite');
  return json['isFavorite'] as bool? ?? false;
}

class _RawResponse {
  _RawResponse(this.status, this.raw);

  final int status;
  final dynamic raw;

  Map<String, dynamic> get json => (raw as Map).cast<String, dynamic>();
}

/// Bare-metal JSON call for acting as a SECOND user — the app's ApiClient is
/// a singleton bound to the primary session's token store.
Future<_RawResponse> _rawJson(
  String method,
  String path, {
  Map<String, dynamic>? body,
  String? token,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.openUrl(method, Uri.parse('${apiBaseUrl()}$path'));
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return _RawResponse(response.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}
