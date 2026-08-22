/// Domain models mirrored from the Dayflow API contracts.
/// Hand-written immutable classes — no codegen, no magic.
library;

import '../api/api_client.dart' show apiBaseUrl;

/// Media URLs arrive host-relative (`/v1/files/...`) so they work from any
/// client origin; absolute URLs pass through untouched.
String? resolveMediaUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return '${apiBaseUrl()}$url';
}

class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.role,
    this.logoUrl,
    this.lastUsedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String role;
  final String? logoUrl;
  final DateTime? lastUsedAt;

  factory AccountSummary.fromJson(Map<String, dynamic> json) => AccountSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        role: json['role'] as String? ?? 'member',
        logoUrl: json['logoUrl'] as String?,
        lastUsedAt: json['lastUsedAt'] != null ? DateTime.tryParse(json['lastUsedAt'] as String) : null,
      );
}

class Me {
  const Me({
    required this.id,
    required this.email,
    required this.fullName,
    required this.language,
    required this.onboardingCompleted,
    required this.setupChecklist,
    required this.account,
    required this.accounts,
    this.avatarUrl,
    this.personalStatus,
  });

  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? personalStatus;
  final String language;
  final bool onboardingCompleted;
  final List<String> setupChecklist;
  final AccountSummary account;
  final List<AccountSummary> accounts;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  factory Me.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return Me(
      id: user['id'] as String,
      email: user['email'] as String,
      fullName: user['fullName'] as String,
      avatarUrl: resolveMediaUrl(user['avatarUrl'] as String?),
      personalStatus: user['personalStatus'] as String?,
      language: user['language'] as String? ?? 'en',
      onboardingCompleted: user['onboardingCompleted'] as bool? ?? false,
      setupChecklist: (user['setupChecklist'] as List<dynamic>? ?? const []).cast<String>(),
      account: AccountSummary.fromJson(json['account'] as Map<String, dynamic>),
      accounts: (json['accounts'] as List<dynamic>? ?? const [])
          .map((a) => AccountSummary.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SetupStep {
  const SetupStep({required this.step, required this.done});
  final String step;
  final bool done;

  String get label => switch (step) {
        'create_first_board' => 'Create your first board',
        'get_started_basics' => 'Get started with basics',
        'unlock_full_experience' => 'Unlock the full experience',
        _ => step,
      };

  String get sublabel => switch (step) {
        'create_first_board' => 'Every great project starts with a plan',
        'get_started_basics' => 'Learn how to create a workflow',
        'unlock_full_experience' => 'Try Dayflow on your desktop',
        _ => '',
      };
}

class BoardSummary {
  const BoardSummary({
    required this.id,
    required this.name,
    required this.workspaceName,
    required this.isFavorite,
    this.updatedAt,
    this.visitedAt,
  });

  final String id;
  final String name;
  final String workspaceName;
  final bool isFavorite;
  final DateTime? updatedAt;
  final DateTime? visitedAt;

  factory BoardSummary.fromJson(Map<String, dynamic> json) => BoardSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        workspaceName: json['workspaceName'] as String? ?? json['workspace'] as String? ?? '',
        isFavorite: json['isFavorite'] as bool? ?? false,
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
        visitedAt: json['visitedAt'] != null ? DateTime.tryParse(json['visitedAt'] as String) : null,
      );

  BoardSummary copyWith({bool? isFavorite}) => BoardSummary(
        id: id,
        name: name,
        workspaceName: workspaceName,
        isFavorite: isFavorite ?? this.isFavorite,
        updatedAt: updatedAt,
        visitedAt: visitedAt,
      );
}

class HomeOverview {
  const HomeOverview({
    required this.greetingName,
    required this.setupPercent,
    required this.setupSteps,
    required this.favorites,
    required this.recentlyVisited,
  });

  final String greetingName;
  final int setupPercent;
  final List<SetupStep> setupSteps;
  final List<BoardSummary> favorites;
  final List<BoardSummary> recentlyVisited;

  factory HomeOverview.fromJson(Map<String, dynamic> json) {
    final progress = json['setupProgress'] as Map<String, dynamic>? ?? const {};
    return HomeOverview(
      greetingName: json['greetingName'] as String? ?? '',
      setupPercent: progress['percent'] as int? ?? 0,
      setupSteps: (progress['steps'] as List<dynamic>? ?? const [])
          .map((s) => SetupStep(step: s['step'] as String, done: s['done'] as bool? ?? false))
          .toList(),
      favorites: (json['favorites'] as List<dynamic>? ?? const [])
          .map((b) => BoardSummary.fromJson(b as Map<String, dynamic>))
          .toList(),
      recentlyVisited: (json['recentlyVisited'] as List<dynamic>? ?? const [])
          .map((b) => BoardSummary.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WorkspaceSummary {
  const WorkspaceSummary({required this.id, required this.name, required this.boards});

  final String id;
  final String name;
  final List<BoardSummary> boards;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) => WorkspaceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        boards: (json['boards'] as List<dynamic>? ?? const [])
            .map((b) => BoardSummary.fromJson({...b as Map<String, dynamic>, 'workspaceName': json['name']}))
            .toList(),
      );
}

class BoardTemplate {
  const BoardTemplate({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.columnCount,
    required this.groupCount,
  });

  final String key;
  final String name;
  final String description;
  final String icon;
  final String accentColor;
  final int columnCount;
  final int groupCount;

  factory BoardTemplate.fromJson(Map<String, dynamic> json) => BoardTemplate(
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? 'grid',
        accentColor: json['accentColor'] as String? ?? 'indigo',
        columnCount: json['columnCount'] as int? ?? 0,
        groupCount: json['groupCount'] as int? ?? 0,
      );
}

// ---------- Board detail ----------

class StatusLabel {
  const StatusLabel({required this.id, required this.label, required this.color, required this.isDone});

  final String id;
  final String label;
  final String color;
  final bool isDone;

  factory StatusLabel.fromJson(Map<String, dynamic> json) => StatusLabel(
        id: json['id'] as String,
        label: json['label'] as String,
        color: json['color'] as String? ?? 'grey',
        isDone: json['isDone'] as bool? ?? false,
      );
}

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.type,
    required this.title,
    required this.settings,
    required this.position,
  });

  final String id;
  final String type;
  final String title;
  final Map<String, dynamic> settings;
  final double position;

  List<StatusLabel> get statusLabels => (settings['labels'] as List<dynamic>? ?? const [])
      .map((l) => StatusLabel.fromJson(l as Map<String, dynamic>))
      .toList();

  factory BoardColumn.fromJson(Map<String, dynamic> json) => BoardColumn(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        settings: json['settings'] as Map<String, dynamic>? ?? const {},
        position: (json['position'] as num?)?.toDouble() ?? 0,
      );
}

class BoardItem {
  const BoardItem({
    required this.id,
    required this.name,
    required this.position,
    required this.updatesCount,
    required this.values,
  });

  final String id;
  final String name;
  final double position;
  final int updatesCount;

  /// columnId → raw value json (shape owned by the column type).
  final Map<String, dynamic> values;

  factory BoardItem.fromJson(Map<String, dynamic> json) => BoardItem(
        id: json['id'] as String,
        name: json['name'] as String,
        position: (json['position'] as num?)?.toDouble() ?? 0,
        updatesCount: json['updatesCount'] as int? ?? 0,
        values: json['values'] as Map<String, dynamic>? ?? const {},
      );

  BoardItem copyWith({String? name, int? updatesCount, Map<String, dynamic>? values}) => BoardItem(
        id: id,
        name: name ?? this.name,
        position: position,
        updatesCount: updatesCount ?? this.updatesCount,
        values: values ?? this.values,
      );

  /// Returns a copy with one cell set, or removed when `value` is null.
  BoardItem withCell(String columnId, Map<String, dynamic>? value) {
    final next = Map<String, dynamic>.of(values);
    if (value == null) {
      next.remove(columnId);
    } else {
      next[columnId] = value;
    }
    return copyWith(values: next);
  }
}

class BoardGroup {
  const BoardGroup({
    required this.id,
    required this.title,
    required this.color,
    required this.collapsed,
    required this.items,
  });

  final String id;
  final String title;
  final String color;
  final bool collapsed;
  final List<BoardItem> items;

  factory BoardGroup.fromJson(Map<String, dynamic> json) => BoardGroup(
        id: json['id'] as String,
        title: json['title'] as String,
        color: json['color'] as String? ?? 'blue',
        collapsed: json['collapsed'] as bool? ?? false,
        items:
            (json['items'] as List<dynamic>? ?? const []).map((i) => BoardItem.fromJson(i as Map<String, dynamic>)).toList(),
      );

  BoardGroup copyWith({String? title, String? color, bool? collapsed, List<BoardItem>? items}) => BoardGroup(
        id: id,
        title: title ?? this.title,
        color: color ?? this.color,
        collapsed: collapsed ?? this.collapsed,
        items: items ?? this.items,
      );

  /// Count of items whose status cell sits on a label marked done.
  int doneCount(List<BoardColumn> columns) {
    final statusColumn = columns.where((c) => c.type == 'status').firstOrNull;
    if (statusColumn == null) return 0;
    final doneIds = statusColumn.statusLabels.where((l) => l.isDone).map((l) => l.id).toSet();
    return items.where((item) {
      final cell = item.values[statusColumn.id];
      return cell is Map<String, dynamic> && doneIds.contains(cell['labelId']);
    }).length;
  }
}

class BoardMember {
  const BoardMember({required this.userId, required this.fullName, required this.role, this.avatarUrl});

  final String userId;
  final String fullName;
  final String role;
  final String? avatarUrl;

  factory BoardMember.fromJson(Map<String, dynamic> json) => BoardMember(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String,
        role: json['role'] as String? ?? 'member',
        avatarUrl: resolveMediaUrl(json['avatarUrl'] as String?),
      );
}

class BoardDetail {
  const BoardDetail({
    required this.id,
    required this.name,
    required this.type,
    required this.workspaceName,
    required this.isFavorite,
    required this.columns,
    required this.groups,
    required this.members,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final String type;
  final String workspaceName;
  final bool isFavorite;
  final List<BoardColumn> columns;
  final List<BoardGroup> groups;
  final List<BoardMember> members;

  factory BoardDetail.fromJson(Map<String, dynamic> json) => BoardDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        type: json['type'] as String? ?? 'main',
        workspaceName: (json['workspace'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        isFavorite: json['isFavorite'] as bool? ?? false,
        columns: (json['columns'] as List<dynamic>? ?? const [])
            .map((c) => BoardColumn.fromJson(c as Map<String, dynamic>))
            .toList(),
        groups: (json['groups'] as List<dynamic>? ?? const [])
            .map((g) => BoardGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
        members: (json['members'] as List<dynamic>? ?? const [])
            .map((m) => BoardMember.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  BoardDetail copyWith({
    String? name,
    String? description,
    bool? isFavorite,
    List<BoardColumn>? columns,
    List<BoardGroup>? groups,
  }) =>
      BoardDetail(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type,
        workspaceName: workspaceName,
        isFavorite: isFavorite ?? this.isFavorite,
        columns: columns ?? this.columns,
        groups: groups ?? this.groups,
        members: members,
      );

  /// Replaces one group in place, preserving order.
  BoardDetail withGroup(BoardGroup group) => copyWith(
        groups: [for (final g in groups) if (g.id == group.id) group else g],
      );

  /// Applies a transform to whichever group holds [itemId].
  BoardDetail withItem(String itemId, BoardItem Function(BoardItem) transform) => copyWith(
        groups: [
          for (final g in groups)
            g.copyWith(items: [
              for (final i in g.items) if (i.id == itemId) transform(i) else i,
            ]),
        ],
      );

  BoardItem? findItem(String itemId) {
    for (final group in groups) {
      for (final item in group.items) {
        if (item.id == itemId) return item;
      }
    }
    return null;
  }

  int get itemCount => groups.fold(0, (sum, g) => sum + g.items.length);
}

// ---------- Item detail ----------

class ItemUpdate {
  const ItemUpdate({
    required this.id,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.likesCount,
    required this.likedByMe,
    required this.bookmarkedByMe,
    required this.replies,
    this.editedAt,
    this.authorAvatarUrl,
  });

  final String id;
  final String body;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int likesCount;
  final bool likedByMe;
  final bool bookmarkedByMe;
  final List<ItemUpdate> replies;

  bool get isEdited => editedAt != null;

  factory ItemUpdate.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return ItemUpdate(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      authorId: author['userId'] as String? ?? '',
      authorName: author['fullName'] as String? ?? '',
      authorAvatarUrl: resolveMediaUrl(author['avatarUrl'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      editedAt: json['editedAt'] != null ? DateTime.tryParse(json['editedAt'] as String) : null,
      likesCount: json['likesCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      bookmarkedByMe: json['bookmarkedByMe'] as bool? ?? false,
      replies: (json['replies'] as List<dynamic>? ?? const [])
          .map((r) => ItemUpdate.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  ItemUpdate copyWith({int? likesCount, bool? likedByMe, bool? bookmarkedByMe}) => ItemUpdate(
        id: id,
        body: body,
        authorId: authorId,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        createdAt: createdAt,
        editedAt: editedAt,
        likesCount: likesCount ?? this.likesCount,
        likedByMe: likedByMe ?? this.likedByMe,
        bookmarkedByMe: bookmarkedByMe ?? this.bookmarkedByMe,
        replies: replies,
      );
}

/// A feed entry is an update plus where it lives.
class FeedEntry {
  const FeedEntry({required this.update, required this.boardId, required this.boardName, this.itemId, this.itemName});

  final ItemUpdate update;
  final String boardId;
  final String boardName;
  final String? itemId;
  final String? itemName;

  factory FeedEntry.fromJson(Map<String, dynamic> json) => FeedEntry(
        update: ItemUpdate.fromJson(json),
        boardId: json['boardId'] as String? ?? '',
        boardName: json['boardName'] as String? ?? '',
        itemId: json['itemId'] as String?,
        itemName: json['itemName'] as String?,
      );
}

class AppFile {
  const AppFile({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.isImage,
    required this.url,
    required this.uploadedByName,
    required this.createdAt,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final bool isImage;

  /// Absolute URL, already resolved against the API origin.
  final String url;
  final String uploadedByName;
  final DateTime createdAt;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory AppFile.fromJson(Map<String, dynamic> json) => AppFile(
        id: json['id'] as String,
        fileName: json['fileName'] as String? ?? 'file',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        isImage: json['isImage'] as bool? ?? false,
        url: resolveMediaUrl(json['url'] as String?) ?? '',
        uploadedByName: json['uploadedByName'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class NotificationPrefs {
  const NotificationPrefs({required this.emailEnabled, required this.pushEnabled});

  final bool emailEnabled;
  final bool pushEnabled;

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) => NotificationPrefs(
        emailEnabled: json['emailEnabled'] as bool? ?? true,
        pushEnabled: json['pushEnabled'] as bool? ?? true,
      );
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.event,
    required this.payload,
    required this.createdAt,
    this.actorName,
  });

  final String id;
  final String event;
  final Map<String, dynamic> payload;
  final String? actorName;
  final DateTime createdAt;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        id: json['id'] as String,
        event: json['event'] as String,
        payload: json['payload'] as Map<String, dynamic>? ?? const {},
        actorName: (json['actor'] as Map<String, dynamic>?)?['fullName'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  /// Human-readable sentence for the activity feed.
  String get description => switch (event) {
        'item_created' => 'created this item',
        'item_renamed' => 'renamed it to "${payload['to'] ?? ''}"',
        'item_moved' => 'moved it to another group',
        'item_duplicated' => 'duplicated an item',
        'item_archived' => 'archived it',
        'column_value_changed' => 'changed a column value',
        'board_created' => 'created the board',
        'board_renamed' => 'renamed the board',
        'group_created' => 'added a group',
        'group_renamed' => 'renamed a group',
        'group_deleted' => 'deleted a group',
        'column_created' => 'added a column',
        'column_renamed' => 'renamed a column',
        'column_deleted' => 'deleted a column',
        _ => event.replaceAll('_', ' '),
      };
}

class ItemDetail {
  const ItemDetail({
    required this.id,
    required this.name,
    required this.boardId,
    required this.boardName,
    required this.groupTitle,
    required this.groupColor,
    required this.workspaceName,
    required this.columns,
    required this.values,
    required this.updates,
    required this.activity,
  });

  final String id;
  final String name;
  final String boardId;
  final String boardName;
  final String groupTitle;
  final String groupColor;
  final String workspaceName;
  final List<BoardColumn> columns;
  final Map<String, dynamic> values;
  final List<ItemUpdate> updates;
  final List<ActivityEntry> activity;

  /// The cell values shaped as a [BoardItem] so cell widgets can be reused.
  BoardItem get asBoardItem =>
      BoardItem(id: id, name: name, position: 0, updatesCount: updates.length, values: values);

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    final board = json['board'] as Map<String, dynamic>? ?? const {};
    final group = json['group'] as Map<String, dynamic>? ?? const {};
    return ItemDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      boardId: board['id'] as String? ?? '',
      boardName: board['name'] as String? ?? '',
      groupTitle: group['title'] as String? ?? '',
      groupColor: group['color'] as String? ?? 'blue',
      workspaceName: json['workspaceName'] as String? ?? '',
      columns: (json['columns'] as List<dynamic>? ?? const [])
          .map((c) => BoardColumn.fromJson(c as Map<String, dynamic>))
          .toList(),
      values: json['values'] as Map<String, dynamic>? ?? const {},
      updates: (json['updates'] as List<dynamic>? ?? const [])
          .map((u) => ItemUpdate.fromJson(u as Map<String, dynamic>))
          .toList(),
      activity: (json['activity'] as List<dynamic>? ?? const [])
          .map((a) => ActivityEntry.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ---------- My Work ----------

class MyWorkItem {
  const MyWorkItem({
    required this.id,
    required this.name,
    required this.boardId,
    required this.boardName,
    required this.groupTitle,
    required this.groupColor,
    this.date,
    this.statusLabel,
    this.statusColor,
  });

  final String id;
  final String name;
  final String boardId;
  final String boardName;
  final String groupTitle;
  final String groupColor;
  final DateTime? date;
  final String? statusLabel;
  final String? statusColor;

  factory MyWorkItem.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as Map<String, dynamic>?;
    return MyWorkItem(
      id: json['id'] as String,
      name: json['name'] as String,
      boardId: json['boardId'] as String? ?? '',
      boardName: json['boardName'] as String? ?? '',
      groupTitle: json['groupTitle'] as String? ?? '',
      groupColor: json['groupColor'] as String? ?? 'blue',
      date: json['date'] != null ? DateTime.tryParse(json['date'] as String) : null,
      statusLabel: status?['label'] as String?,
      statusColor: status?['color'] as String?,
    );
  }
}

class MyWork {
  const MyWork({
    required this.overdue,
    required this.today,
    required this.thisWeek,
    required this.later,
    required this.noDate,
    required this.done,
    required this.doneCount,
  });

  final List<MyWorkItem> overdue;
  final List<MyWorkItem> today;
  final List<MyWorkItem> thisWeek;
  final List<MyWorkItem> later;
  final List<MyWorkItem> noDate;

  /// Populated only when the request asked to include done items.
  final List<MyWorkItem> done;
  final int doneCount;

  bool get isEmpty =>
      overdue.isEmpty && today.isEmpty && thisWeek.isEmpty && later.isEmpty && noDate.isEmpty && done.isEmpty;

  int get total => overdue.length + today.length + thisWeek.length + later.length + noDate.length;

  factory MyWork.fromJson(Map<String, dynamic> json) {
    List<MyWorkItem> bucket(String key) => (json[key] as List<dynamic>? ?? const [])
        .map((i) => MyWorkItem.fromJson(i as Map<String, dynamic>))
        .toList();
    return MyWork(
      overdue: bucket('overdue'),
      today: bucket('today'),
      thisWeek: bucket('thisWeek'),
      later: bucket('later'),
      noDate: bucket('noDate'),
      done: bucket('done'),
      doneCount: json['doneCount'] as int? ?? 0,
    );
  }
}

// ---------- Notifications ----------

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.isRead,
    this.actorName,
    this.actorAvatarUrl,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final bool isRead;
  final String? actorName;
  final String? actorAvatarUrl;

  String? get boardId => payload['boardId'] as String?;
  String? get itemId => payload['itemId'] as String?;
  String get boardName => payload['boardName'] as String? ?? '';
  String get itemName => payload['itemName'] as String? ?? '';
  String? get snippet => payload['snippet'] as String?;

  String get headline => switch (type) {
        'assigned' => '${actorName ?? 'Someone'} assigned you to "$itemName"',
        'mention' => '${actorName ?? 'Someone'} mentioned you in "$itemName"',
        'reply' => '${actorName ?? 'Someone'} replied to your update',
        'update_on_subscribed' => 'New update on "$itemName"',
        'board_invite' => '${actorName ?? 'Someone'} invited you to "$boardName"',
        'account_invite' => '${actorName ?? 'Someone'} invited you to their account',
        _ => type.replaceAll('_', ' '),
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? const {},
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      isRead: json['readAt'] != null,
      actorName: actor?['fullName'] as String?,
      actorAvatarUrl: resolveMediaUrl(actor?['avatarUrl'] as String?),
    );
  }
}

// ---------- Members and invitations ----------

class AccountMember {
  const AccountMember({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    required this.isYou,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final bool isYou;
  final String? avatarUrl;

  /// Viewers and guests cannot edit boards; the UI hides write affordances.
  bool get canEdit => role == 'admin' || role == 'member';

  factory AccountMember.fromJson(Map<String, dynamic> json) => AccountMember(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'member',
        status: json['status'] as String? ?? 'active',
        isYou: json['isYou'] as bool? ?? false,
        avatarUrl: resolveMediaUrl(json['avatarUrl'] as String?),
      );

  /// People pickers work with board members, so allow a cheap conversion.
  BoardMember toBoardMember() =>
      BoardMember(userId: userId, fullName: fullName, role: role, avatarUrl: avatarUrl);
}

class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.invitedByName,
    required this.expiresAt,
    this.devLink,
  });

  final String id;
  final String email;
  final String role;
  final String invitedByName;
  final DateTime expiresAt;

  /// Dev-only accept link, so the flow is testable without an inbox.
  final String? devLink;

  factory PendingInvite.fromJson(Map<String, dynamic> json) => PendingInvite(
        id: json['id'] as String,
        email: json['email'] as String,
        role: json['role'] as String? ?? 'member',
        invitedByName: json['invitedByName'] as String? ?? '',
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ?? DateTime.now(),
        devLink: json['devLink'] as String?,
      );
}

class MemberDirectory {
  const MemberDirectory({required this.members, required this.invitations});

  final List<AccountMember> members;
  final List<PendingInvite> invitations;

  factory MemberDirectory.fromJson(Map<String, dynamic> json) => MemberDirectory(
        members: (json['members'] as List<dynamic>? ?? const [])
            .map((m) => AccountMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        invitations: (json['invitations'] as List<dynamic>? ?? const [])
            .map((i) => PendingInvite.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

// ---------- Search ----------

class SearchResults {
  const SearchResults({required this.boards, required this.items});

  final List<BoardSummary> boards;
  final List<MyWorkItem> items;

  bool get isEmpty => boards.isEmpty && items.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        boards: (json['boards'] as List<dynamic>? ?? const [])
            .map((b) => BoardSummary.fromJson(b as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((i) => MyWorkItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}
