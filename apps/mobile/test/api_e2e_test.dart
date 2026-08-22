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
