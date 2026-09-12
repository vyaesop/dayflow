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
    this.type = 'main',
    this.updatedAt,
    this.visitedAt,
  });

  final String id;
  final String name;
  final String workspaceName;
  final bool isFavorite;

  /// main | shareable | private — drives the lock/share badge in lists.
  final String type;
  final DateTime? updatedAt;
  final DateTime? visitedAt;

  factory BoardSummary.fromJson(Map<String, dynamic> json) => BoardSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        workspaceName: json['workspaceName'] as String? ?? json['workspace'] as String? ?? '',
        isFavorite: json['isFavorite'] as bool? ?? false,
        type: json['type'] as String? ?? 'main',
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
        visitedAt: json['visitedAt'] != null ? DateTime.tryParse(json['visitedAt'] as String) : null,
      );

  BoardSummary copyWith({bool? isFavorite}) => BoardSummary(
        id: id,
        name: name,
        workspaceName: workspaceName,
        isFavorite: isFavorite ?? this.isFavorite,
        type: type,
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
    this.itemCount = 0,
    this.isCustom = false,
    this.id,
    this.createdByName,
    this.createdAt,
  });

  final String key;
  final String name;
  final String description;
  final String icon;
  final String accentColor;
  final int columnCount;
  final int groupCount;
  final int itemCount;

  /// Account-authored ("Save board as template") rather than built-in.
  final bool isCustom;
  final String? id;
  final String? createdByName;
  final DateTime? createdAt;

  factory BoardTemplate.fromJson(Map<String, dynamic> json) => BoardTemplate(
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? 'grid',
        accentColor: json['accentColor'] as String? ?? 'indigo',
        columnCount: json['columnCount'] as int? ?? 0,
        groupCount: json['groupCount'] as int? ?? 0,
        itemCount: json['itemCount'] as int? ?? 0,
        isCustom: json['isCustom'] as bool? ?? false,
        id: json['id'] as String?,
        createdByName: json['createdByName'] as String?,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
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

/// Column types whose cells are rendered from item metadata and never written.
const readOnlyColumnTypes = {'item_id', 'creation_log', 'last_updated', 'auto_number'};

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.type,
    required this.title,
    required this.settings,
    required this.position,
    this.scope = 'items',
    this.width,
  });

  final String id;
  final String type;
  final String title;
  final Map<String, dynamic> settings;
  final double position;

  /// `items` (the board's rows) or `subitems` (the subitem column set).
  final String scope;
  final double? width;

  List<StatusLabel> get statusLabels => (settings['labels'] as List<dynamic>? ?? const [])
      .map((l) => StatusLabel.fromJson(l as Map<String, dynamic>))
      .toList();

  List<Map<String, dynamic>> get options =>
      (settings['options'] as List<dynamic>? ?? const []).map((o) => o as Map<String, dynamic>).toList();

  bool get isReadOnly => readOnlyColumnTypes.contains(type);
  bool get isSubitemColumn => scope == 'subitems';

  /// Rating columns: number of stars (1..10, default 5).
  int get ratingMax {
    final max = settings['max'];
    return max is int && max >= 1 && max <= 10 ? max : 5;
  }

  /// Footer summary mode from settings, or null for the type default.
  String? get summaryMode => settings['summary'] as String?;
  String? get description => settings['description'] as String?;

  factory BoardColumn.fromJson(Map<String, dynamic> json) => BoardColumn(
        id: json['id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        settings: json['settings'] as Map<String, dynamic>? ?? const {},
        position: (json['position'] as num?)?.toDouble() ?? 0,
        scope: json['scope'] as String? ?? 'items',
        width: (json['width'] as num?)?.toDouble(),
      );

  BoardColumn copyWith({String? title, Map<String, dynamic>? settings, double? position, double? width}) => BoardColumn(
        id: id,
        type: type,
        title: title ?? this.title,
        settings: settings ?? this.settings,
        position: position ?? this.position,
        scope: scope,
        width: width ?? this.width,
      );
}

class BoardItem {
  const BoardItem({
    required this.id,
    required this.name,
    required this.position,
    required this.updatesCount,
    required this.values,
    this.serial = 0,
    this.createdAt,
    this.updatedAt,
    this.createdByUserId,
    this.updatedByUserId,
    this.parentItemId,
    this.subitems = const [],
  });

  final String id;
  final String name;
  final double position;
  final int updatesCount;

  /// columnId → raw value json (shape owned by the column type).
  final Map<String, dynamic> values;

  /// Stable per-board number shown by the Item ID column.
  final int serial;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdByUserId;
  final String? updatedByUserId;

  /// Set on subitems; they live under their parent, not in the group list.
  final String? parentItemId;

  /// Only populated on top-level items.
  final List<BoardItem> subitems;

  bool get isSubitem => parentItemId != null;

  factory BoardItem.fromJson(Map<String, dynamic> json) => BoardItem(
        id: json['id'] as String,
        name: json['name'] as String,
        position: (json['position'] as num?)?.toDouble() ?? 0,
        updatesCount: json['updatesCount'] as int? ?? 0,
        values: json['values'] as Map<String, dynamic>? ?? const {},
        serial: json['serial'] as int? ?? 0,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
        updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
        createdByUserId: json['createdByUserId'] as String?,
        updatedByUserId: json['updatedByUserId'] as String?,
        parentItemId: json['parentItemId'] as String?,
        subitems: (json['subitems'] as List<dynamic>? ?? const [])
            .map((s) => BoardItem.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  BoardItem copyWith({
    String? name,
    int? updatesCount,
    Map<String, dynamic>? values,
    DateTime? updatedAt,
    String? updatedByUserId,
    List<BoardItem>? subitems,
  }) =>
      BoardItem(
        id: id,
        name: name ?? this.name,
        position: position,
        updatesCount: updatesCount ?? this.updatesCount,
        values: values ?? this.values,
        serial: serial,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdByUserId: createdByUserId,
        updatedByUserId: updatedByUserId ?? this.updatedByUserId,
        parentItemId: parentItemId,
        subitems: subitems ?? this.subitems,
      );

  /// Count of subitems whose status cell sits on a label marked done.
  int subitemsDone(List<BoardColumn> columns) {
    final statusColumn = columns.where((c) => c.type == 'status' && c.scope == 'subitems').firstOrNull;
    if (statusColumn == null) return 0;
    final doneIds = statusColumn.statusLabels.where((l) => l.isDone).map((l) => l.id).toSet();
    return subitems.where((s) {
      final cell = s.values[statusColumn.id];
      return cell is Map<String, dynamic> && doneIds.contains(cell['labelId']);
    }).length;
  }

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
    final statusColumn = columns.where((c) => c.type == 'status' && c.scope != 'subitems').firstOrNull;
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

/// A row from GET /boards/:id/members — richer than the board payload's
/// member stubs: it carries the account role, which drives the ownership
/// rules (viewers/guests cannot own boards).
class BoardMemberEntry {
  const BoardMemberEntry({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.accountRole,
    required this.isYou,
    this.avatarUrl,
  });

  final String userId;
  final String fullName;
  final String email;

  /// Role on this board: owner | member | viewer.
  final String role;

  /// Role in the account: admin | member | viewer | guest.
  final String accountRole;
  final bool isYou;
  final String? avatarUrl;

  bool get canBeOwner => accountRole == 'admin' || accountRole == 'member';

  factory BoardMemberEntry.fromJson(Map<String, dynamic> json) => BoardMemberEntry(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'member',
        accountRole: json['accountRole'] as String? ?? 'member',
        isYou: json['isYou'] as bool? ?? false,
        avatarUrl: resolveMediaUrl(json['avatarUrl'] as String?),
      );
}

class BoardMemberList {
  const BoardMemberList({required this.members, required this.canManage});

  final List<BoardMemberEntry> members;

  /// True when the caller is a board owner or an account admin.
  final bool canManage;

  factory BoardMemberList.fromJson(Map<String, dynamic> json) => BoardMemberList(
        members: (json['members'] as List<dynamic>? ?? const [])
            .map((m) => BoardMemberEntry.fromJson(m as Map<String, dynamic>))
            .toList(),
        canManage: json['canManage'] as bool? ?? false,
      );
}

/// A saved view: name, type and the raw config (parsed by the view engine).
class BoardView {
  const BoardView({
    required this.id,
    required this.boardId,
    required this.type,
    required this.name,
    required this.isDefault,
    required this.position,
    required this.config,
    this.createdByUserId,
  });

  final String id;
  final String boardId;
  final String type;
  final String name;
  final bool isDefault;
  final double position;
  final Map<String, dynamic> config;
  final String? createdByUserId;

  factory BoardView.fromJson(Map<String, dynamic> json) => BoardView(
        id: json['id'] as String,
        boardId: json['boardId'] as String? ?? '',
        type: json['type'] as String? ?? 'table',
        name: json['name'] as String? ?? 'View',
        isDefault: json['isDefault'] as bool? ?? false,
        position: (json['position'] as num?)?.toDouble() ?? 0,
        config: json['config'] as Map<String, dynamic>? ?? const {},
        createdByUserId: json['createdByUserId'] as String?,
      );

  BoardView copyWith({String? name, bool? isDefault, Map<String, dynamic>? config}) => BoardView(
        id: id,
        boardId: boardId,
        type: type,
        name: name ?? this.name,
        isDefault: isDefault ?? this.isDefault,
        position: position,
        config: config ?? this.config,
        createdByUserId: createdByUserId,
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
    this.workspaceId = '',
    this.views = const [],
    this.canEdit = true,
    this.canManage = false,
  });

  final String id;
  final String name;
  final String? description;
  final String type;
  final String workspaceId;
  final String workspaceName;
  final bool isFavorite;

  /// Every column, both scopes; use [itemColumns] / [subitemColumns].
  final List<BoardColumn> columns;
  final List<BoardGroup> groups;
  final List<BoardMember> members;
  final List<BoardView> views;

  /// Server-computed for the caller: viewers/guests cannot edit; owners/admins manage.
  final bool canEdit;
  final bool canManage;

  List<BoardColumn> get itemColumns => columns.where((c) => c.scope != 'subitems').toList();
  List<BoardColumn> get subitemColumns => columns.where((c) => c.scope == 'subitems').toList();
  BoardView? get defaultView => views.where((v) => v.isDefault).firstOrNull ?? views.firstOrNull;

  factory BoardDetail.fromJson(Map<String, dynamic> json) {
    final me = json['me'] as Map<String, dynamic>? ?? const {};
    return BoardDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'main',
      workspaceId: (json['workspace'] as Map<String, dynamic>?)?['id'] as String? ?? '',
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
      views: (json['views'] as List<dynamic>? ?? const [])
          .map((v) => BoardView.fromJson(v as Map<String, dynamic>))
          .toList(),
      canEdit: me['canEdit'] as bool? ?? true,
      canManage: me['canManage'] as bool? ?? false,
    );
  }

  BoardDetail copyWith({
    String? name,
    String? description,
    bool? isFavorite,
    List<BoardColumn>? columns,
    List<BoardGroup>? groups,
    List<BoardView>? views,
  }) =>
      BoardDetail(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        isFavorite: isFavorite ?? this.isFavorite,
        columns: columns ?? this.columns,
        groups: groups ?? this.groups,
        members: members,
        views: views ?? this.views,
        canEdit: canEdit,
        canManage: canManage,
      );

  /// Replaces one group in place, preserving order.
  BoardDetail withGroup(BoardGroup group) => copyWith(
        groups: [for (final g in groups) if (g.id == group.id) group else g],
      );

  /// Applies a transform to [itemId], whether it is a top-level item or a subitem.
  BoardDetail withItem(String itemId, BoardItem Function(BoardItem) transform) => copyWith(
        groups: [
          for (final g in groups)
            g.copyWith(items: [
              for (final i in g.items)
                if (i.id == itemId)
                  transform(i)
                else if (i.subitems.any((s) => s.id == itemId))
                  i.copyWith(subitems: [for (final s in i.subitems) if (s.id == itemId) transform(s) else s])
                else
                  i,
            ]),
        ],
      );

  /// Removes [itemId] wherever it lives (top level or under a parent).
  BoardDetail withoutItem(String itemId) => copyWith(
        groups: [
          for (final g in groups)
            g.copyWith(items: [
              for (final i in g.items)
                if (i.id != itemId) i.copyWith(subitems: i.subitems.where((s) => s.id != itemId).toList()),
            ]),
        ],
      );

  /// Finds a top-level item or a subitem by id.
  BoardItem? findItem(String itemId) {
    for (final group in groups) {
      for (final item in group.items) {
        if (item.id == itemId) return item;
        for (final sub in item.subitems) {
          if (sub.id == itemId) return sub;
        }
      }
    }
    return null;
  }

  /// The top-level items in board order (groups then positions).
  List<BoardItem> get allItems => [for (final g in groups) ...g.items];

  int get itemCount => groups.fold(0, (sum, g) => sum + g.items.length);
}

// ---------- Item detail ----------

/// Emoji reactions the server allows on updates, in picker order.
const reactionEmojis = ['👍', '❤️', '🎉', '😂', '😮', '😢', '🙏', '👀', '🔥', '✅'];

class Reaction {
  const Reaction({required this.emoji, required this.count, required this.reactedByMe});

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        emoji: json['emoji'] as String,
        count: json['count'] as int? ?? 0,
        reactedByMe: json['reactedByMe'] as bool? ?? false,
      );

  Reaction copyWith({int? count, bool? reactedByMe}) =>
      Reaction(emoji: emoji, count: count ?? this.count, reactedByMe: reactedByMe ?? this.reactedByMe);
}

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
    this.doc,
    this.markdown,
    this.reactions = const [],
    this.files = const [],
  });

  final String id;

  /// Plain-text rendering of the body (legacy field, always present).
  final String body;

  /// Rich document (`{type:'doc', content:[...]}`), rendered by the rich-text widget.
  final Map<String, dynamic>? doc;

  /// Canonical markdown-lite for the editor to pre-fill.
  final String? markdown;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final DateTime createdAt;
  final DateTime? editedAt;
  final int likesCount;
  final bool likedByMe;
  final bool bookmarkedByMe;
  final List<Reaction> reactions;
  final List<AppFile> files;
  final List<ItemUpdate> replies;

  bool get isEdited => editedAt != null;

  factory ItemUpdate.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>? ?? const {};
    return ItemUpdate(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      doc: json['doc'] as Map<String, dynamic>?,
      markdown: json['markdown'] as String?,
      authorId: author['userId'] as String? ?? '',
      authorName: author['fullName'] as String? ?? '',
      authorAvatarUrl: resolveMediaUrl(author['avatarUrl'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      editedAt: json['editedAt'] != null ? DateTime.tryParse(json['editedAt'] as String) : null,
      likesCount: json['likesCount'] as int? ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      bookmarkedByMe: json['bookmarkedByMe'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>? ?? const [])
          .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
          .toList(),
      files: (json['files'] as List<dynamic>? ?? const [])
          .map((f) => AppFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      replies: (json['replies'] as List<dynamic>? ?? const [])
          .map((r) => ItemUpdate.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  ItemUpdate copyWith({int? likesCount, bool? likedByMe, bool? bookmarkedByMe, List<Reaction>? reactions}) =>
      ItemUpdate(
        id: id,
        body: body,
        doc: doc,
        markdown: markdown,
        authorId: authorId,
        authorName: authorName,
        authorAvatarUrl: authorAvatarUrl,
        createdAt: createdAt,
        editedAt: editedAt,
        likesCount: likesCount ?? this.likesCount,
        likedByMe: likedByMe ?? this.likedByMe,
        bookmarkedByMe: bookmarkedByMe ?? this.bookmarkedByMe,
        reactions: reactions ?? this.reactions,
        files: files,
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
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.itemId,
    this.itemName,
    this.columnId,
    this.columnTitle,
    this.columnType,
    this.undoable = false,
    this.undoneAt,
  });

  final String id;
  final String event;
  final Map<String, dynamic> payload;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;
  final String? itemId;
  final String? itemName;
  final String? columnId;
  final String? columnTitle;
  final String? columnType;
  final bool undoable;
  final DateTime? undoneAt;
  final DateTime createdAt;

  bool get isUndone => undoneAt != null;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    final item = json['item'] as Map<String, dynamic>?;
    final column = json['column'] as Map<String, dynamic>?;
    return ActivityEntry(
      id: json['id'] as String,
      event: json['event'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? const {},
      actorId: actor?['userId'] as String?,
      actorName: actor?['fullName'] as String?,
      actorAvatarUrl: resolveMediaUrl(actor?['avatarUrl'] as String?),
      itemId: item?['id'] as String?,
      itemName: item?['name'] as String?,
      columnId: column?['id'] as String?,
      columnTitle: column?['title'] as String?,
      columnType: column?['type'] as String?,
      undoable: json['undoable'] as bool? ?? false,
      undoneAt: json['undoneAt'] != null ? DateTime.tryParse(json['undoneAt'] as String) : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  ActivityEntry copyWith({DateTime? undoneAt, bool? undoable}) => ActivityEntry(
        id: id,
        event: event,
        payload: payload,
        createdAt: createdAt,
        actorId: actorId,
        actorName: actorName,
        actorAvatarUrl: actorAvatarUrl,
        itemId: itemId,
        itemName: itemName,
        columnId: columnId,
        columnTitle: columnTitle,
        columnType: columnType,
        undoable: undoable ?? this.undoable,
        undoneAt: undoneAt ?? this.undoneAt,
      );

  /// Human-readable sentence for the activity feed (item-scoped wording).
  String get description => switch (event) {
        'item_created' => payload['parentItemId'] != null ? 'added a subitem' : 'created this item',
        'item_renamed' => 'renamed it to "${payload['to'] ?? ''}"',
        'item_moved' => 'moved it to another group',
        'item_moved_to_board' => 'moved it to another board',
        'item_duplicated' => 'duplicated an item',
        'item_archived' => 'archived it',
        'item_trashed' => 'deleted it',
        'item_restored' => 'restored it',
        'column_value_changed' => columnTitle != null ? 'changed $columnTitle' : 'changed a column value',
        'board_created' => 'created the board',
        'board_renamed' => 'renamed the board to "${payload['to'] ?? ''}"',
        'board_archived' => 'archived the board',
        'board_trashed' => 'deleted the board',
        'board_restored' => 'restored the board',
        'group_created' => 'added a group',
        'group_renamed' => 'renamed a group to "${payload['to'] ?? ''}"',
        'group_deleted' => 'deleted a group',
        'column_created' => 'added the column "${payload['title'] ?? ''}"',
        'column_renamed' => 'renamed a column to "${payload['to'] ?? ''}"',
        'column_moved' => 'reordered columns',
        'column_deleted' => 'deleted the column "${payload['title'] ?? ''}"',
        'member_added' => 'added a member',
        'member_removed' => 'removed a member',
        'activity_undone' => 'undid a change',
        _ => event.replaceAll('_', ' '),
      };

  /// Board-feed wording: names the item when there is one.
  String get boardDescription {
    final target = itemName != null ? ' "$itemName"' : '';
    return switch (event) {
      'item_created' => payload['parentItemId'] != null ? 'added subitem$target' : 'created$target',
      'item_renamed' => 'renamed "${payload['from'] ?? ''}" to "${payload['to'] ?? ''}"',
      'item_moved' => 'moved$target to another group',
      'item_archived' => 'archived$target',
      'item_trashed' => 'deleted$target',
      'item_restored' => 'restored$target',
      'item_duplicated' => 'duplicated "${payload['name'] ?? ''}"',
      'column_value_changed' => 'changed ${columnTitle ?? 'a value'} on$target',
      _ => description,
    };
  }
}

class ItemDetail {
  const ItemDetail({
    required this.id,
    required this.name,
    required this.boardId,
    required this.boardName,
    required this.groupId,
    required this.groupTitle,
    required this.groupColor,
    required this.workspaceName,
    required this.columns,
    required this.values,
    required this.updates,
    required this.activity,
    this.serial = 0,
    this.createdAt,
    this.updatedAt,
    this.createdByUserId,
    this.updatedByUserId,
    this.parentId,
    this.parentName,
    this.subitems = const [],
    this.subitemColumns = const [],
    this.canEdit = true,
  });

  final String id;
  final String name;
  final String boardId;
  final String boardName;
  final String groupId;
  final String groupTitle;
  final String groupColor;
  final String workspaceName;

  /// Columns of this item's own level (item columns, or subitem columns for a subitem).
  final List<BoardColumn> columns;
  final Map<String, dynamic> values;
  final List<ItemUpdate> updates;
  final List<ActivityEntry> activity;
  final int serial;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdByUserId;
  final String? updatedByUserId;

  /// Set when this item is a subitem.
  final String? parentId;
  final String? parentName;
  final List<BoardItem> subitems;
  final List<BoardColumn> subitemColumns;
  final bool canEdit;

  bool get isSubitem => parentId != null;

  /// The cell values shaped as a [BoardItem] so cell widgets can be reused.
  BoardItem get asBoardItem => BoardItem(
        id: id,
        name: name,
        position: 0,
        updatesCount: updates.length,
        values: values,
        serial: serial,
        createdAt: createdAt,
        updatedAt: updatedAt,
        createdByUserId: createdByUserId,
        updatedByUserId: updatedByUserId,
        parentItemId: parentId,
        subitems: subitems,
      );

  factory ItemDetail.fromJson(Map<String, dynamic> json) {
    final board = json['board'] as Map<String, dynamic>? ?? const {};
    final group = json['group'] as Map<String, dynamic>? ?? const {};
    final parent = json['parent'] as Map<String, dynamic>?;
    return ItemDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      boardId: board['id'] as String? ?? '',
      boardName: board['name'] as String? ?? '',
      groupId: group['id'] as String? ?? '',
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
      serial: json['serial'] as int? ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
      createdByUserId: json['createdByUserId'] as String?,
      updatedByUserId: json['updatedByUserId'] as String?,
      parentId: parent?['id'] as String?,
      parentName: parent?['name'] as String?,
      subitems: (json['subitems'] as List<dynamic>? ?? const [])
          .map((s) => BoardItem.fromJson(s as Map<String, dynamic>))
          .toList(),
      subitemColumns: (json['subitemColumns'] as List<dynamic>? ?? const [])
          .map((c) => BoardColumn.fromJson(c as Map<String, dynamic>))
          .toList(),
      canEdit: json['canEdit'] as bool? ?? true,
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

// ---------- Archive & trash ----------

class ArchivedBoard {
  const ArchivedBoard({
    required this.id,
    required this.name,
    required this.type,
    required this.workspaceName,
    required this.itemCount,
    this.archivedAt,
    this.trashedAt,
    this.purgeAt,
  });

  final String id;
  final String name;
  final String type;
  final String workspaceName;
  final int itemCount;
  final DateTime? archivedAt;
  final DateTime? trashedAt;
  final DateTime? purgeAt;

  factory ArchivedBoard.fromJson(Map<String, dynamic> json) => ArchivedBoard(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String? ?? 'main',
        workspaceName: json['workspaceName'] as String? ?? '',
        itemCount: json['itemCount'] as int? ?? 0,
        archivedAt: json['archivedAt'] != null ? DateTime.tryParse(json['archivedAt'] as String) : null,
        trashedAt: json['trashedAt'] != null ? DateTime.tryParse(json['trashedAt'] as String) : null,
        purgeAt: json['purgeAt'] != null ? DateTime.tryParse(json['purgeAt'] as String) : null,
      );
}

class ArchivedItem {
  const ArchivedItem({
    required this.id,
    required this.name,
    required this.boardId,
    required this.boardName,
    required this.groupTitle,
    required this.groupColor,
    this.parentItemName,
    this.archivedAt,
    this.trashedAt,
    this.purgeAt,
  });

  final String id;
  final String name;
  final String boardId;
  final String boardName;
  final String groupTitle;
  final String groupColor;
  final String? parentItemName;
  final DateTime? archivedAt;
  final DateTime? trashedAt;
  final DateTime? purgeAt;

  factory ArchivedItem.fromJson(Map<String, dynamic> json) => ArchivedItem(
        id: json['id'] as String,
        name: json['name'] as String,
        boardId: json['boardId'] as String? ?? '',
        boardName: json['boardName'] as String? ?? '',
        groupTitle: json['groupTitle'] as String? ?? '',
        groupColor: json['groupColor'] as String? ?? 'blue',
        parentItemName: json['parentItemName'] as String?,
        archivedAt: json['archivedAt'] != null ? DateTime.tryParse(json['archivedAt'] as String) : null,
        trashedAt: json['trashedAt'] != null ? DateTime.tryParse(json['trashedAt'] as String) : null,
        purgeAt: json['purgeAt'] != null ? DateTime.tryParse(json['purgeAt'] as String) : null,
      );
}

class ArchiveListing {
  const ArchiveListing({required this.boards, required this.items});

  final List<ArchivedBoard> boards;
  final List<ArchivedItem> items;

  bool get isEmpty => boards.isEmpty && items.isEmpty;

  factory ArchiveListing.fromJson(Map<String, dynamic> json) => ArchiveListing(
        boards: (json['boards'] as List<dynamic>? ?? const [])
            .map((b) => ArchivedBoard.fromJson(b as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((i) => ArchivedItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

// ---------- Move item to another board ----------

class ColumnMapping {
  const ColumnMapping({
    required this.sourceColumnId,
    required this.sourceTitle,
    required this.sourceType,
    this.targetColumnId,
    this.targetTitle,
  });

  final String sourceColumnId;
  final String sourceTitle;
  final String sourceType;
  final String? targetColumnId;
  final String? targetTitle;

  bool get isDropped => targetColumnId == null;

  factory ColumnMapping.fromJson(Map<String, dynamic> json) => ColumnMapping(
        sourceColumnId: json['sourceColumnId'] as String,
        sourceTitle: json['sourceTitle'] as String? ?? '',
        sourceType: json['sourceType'] as String? ?? '',
        targetColumnId: json['targetColumnId'] as String?,
        targetTitle: json['targetTitle'] as String?,
      );
}

class MoveTargetGroup {
  const MoveTargetGroup({required this.id, required this.title, required this.color});

  final String id;
  final String title;
  final String color;
}

class MovePreview {
  const MovePreview({
    required this.targetBoardId,
    required this.targetBoardName,
    required this.groups,
    required this.mapping,
    required this.subitemCount,
  });

  final String targetBoardId;
  final String targetBoardName;
  final List<MoveTargetGroup> groups;
  final List<ColumnMapping> mapping;
  final int subitemCount;

  List<ColumnMapping> get dropped => mapping.where((m) => m.isDropped).toList();

  factory MovePreview.fromJson(Map<String, dynamic> json) {
    final target = json['targetBoard'] as Map<String, dynamic>? ?? const {};
    return MovePreview(
      targetBoardId: target['id'] as String? ?? '',
      targetBoardName: target['name'] as String? ?? '',
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .map((g) => g as Map<String, dynamic>)
          .map((g) => MoveTargetGroup(
                id: g['id'] as String,
                title: g['title'] as String? ?? '',
                color: g['color'] as String? ?? 'blue',
              ))
          .toList(),
      mapping: (json['mapping'] as List<dynamic>? ?? const [])
          .map((m) => ColumnMapping.fromJson(m as Map<String, dynamic>))
          .toList(),
      subitemCount: json['subitemCount'] as int? ?? 0,
    );
  }
}

// ---------- Activity page ----------

class ActivityPage {
  const ActivityPage({required this.entries, this.nextCursor});

  final List<ActivityEntry> entries;
  final String? nextCursor;

  factory ActivityPage.fromJson(Map<String, dynamic> json) => ActivityPage(
        entries: (json['entries'] as List<dynamic>? ?? const [])
            .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}
