/// Pure view engine behind saved board views: typed `ViewConfig`, filter
/// matching, sorting, column visibility, conditional colors and column
/// summaries. No widgets, no Riverpod — everything here is unit-tested.
///
/// Semantics mirror the TS engine on the API (P0 contract §3/§4) so the CSV
/// export and the mobile table agree on what a view shows.
library;

import 'package:intl/intl.dart';

import '../../core/models/models.dart';

// ---------- Config ----------

/// Colour tokens a conditional colour rule may use.
const viewColorPalette = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo', 'grey'];

class FilterRule {
  const FilterRule({required this.id, required this.field, required this.operator, this.value});

  final String id;

  /// Column id, `name` or `group`.
  final String field;
  final String operator;
  final Object? value;

  factory FilterRule.fromJson(Map<String, dynamic> json) => FilterRule(
        id: json['id'] as String? ?? '',
        field: json['field'] as String? ?? '',
        operator: json['operator'] as String? ?? '',
        value: json['value'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field,
        'operator': operator,
        if (value != null) 'value': value,
      };

  FilterRule copyWith({String? id, String? field, String? operator, Object? Function()? value}) => FilterRule(
        id: id ?? this.id,
        field: field ?? this.field,
        operator: operator ?? this.operator,
        value: value != null ? value() : this.value,
      );
}

class FilterGroup {
  const FilterGroup({this.conjunction = 'and', this.rules = const []});

  /// `and` | `or`.
  final String conjunction;
  final List<FilterRule> rules;

  bool get isEmpty => rules.isEmpty;

  factory FilterGroup.fromJson(Map<String, dynamic> json) => FilterGroup(
        conjunction: json['conjunction'] as String? ?? 'and',
        rules: (json['rules'] as List<dynamic>? ?? const [])
            .map((r) => FilterRule.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'conjunction': conjunction,
        'rules': [for (final r in rules) r.toJson()],
      };

  FilterGroup copyWith({String? conjunction, List<FilterRule>? rules}) =>
      FilterGroup(conjunction: conjunction ?? this.conjunction, rules: rules ?? this.rules);
}

class SortRule {
  const SortRule({required this.field, this.direction = 'asc'});

  /// Column id, `name`, `created_at`, `updated_at` or `serial`.
  final String field;

  /// `asc` | `desc`.
  final String direction;

  bool get isDescending => direction == 'desc';

  factory SortRule.fromJson(Map<String, dynamic> json) => SortRule(
        field: json['field'] as String? ?? '',
        direction: json['direction'] as String? ?? 'asc',
      );

  Map<String, dynamic> toJson() => {'field': field, 'direction': direction};

  SortRule copyWith({String? field, String? direction}) =>
      SortRule(field: field ?? this.field, direction: direction ?? this.direction);
}

class ConditionalColor {
  const ConditionalColor({
    required this.id,
    required this.field,
    required this.operator,
    required this.color,
    this.value,
    this.applyTo = 'cell',
  });

  final String id;
  final String field;
  final String operator;
  final Object? value;

  /// One of [viewColorPalette].
  final String color;

  /// `cell` | `row`.
  final String applyTo;

  FilterRule get asRule => FilterRule(id: id, field: field, operator: operator, value: value);

  factory ConditionalColor.fromJson(Map<String, dynamic> json) => ConditionalColor(
        id: json['id'] as String? ?? '',
        field: json['field'] as String? ?? '',
        operator: json['operator'] as String? ?? '',
        value: json['value'],
        color: json['color'] as String? ?? 'blue',
        applyTo: json['applyTo'] as String? ?? 'cell',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field,
        'operator': operator,
        if (value != null) 'value': value,
        'color': color,
        'applyTo': applyTo,
      };

  ConditionalColor copyWith({
    String? id,
    String? field,
    String? operator,
    Object? Function()? value,
    String? color,
    String? applyTo,
  }) =>
      ConditionalColor(
        id: id ?? this.id,
        field: field ?? this.field,
        operator: operator ?? this.operator,
        value: value != null ? value() : this.value,
        color: color ?? this.color,
        applyTo: applyTo ?? this.applyTo,
      );
}

/// The `config` jsonb of a saved view. Immutable; `toJson` omits anything
/// empty so the stored blob stays small.
class ViewConfig {
  const ViewConfig({
    this.filters,
    this.sort = const [],
    this.hiddenColumnIds = const [],
    this.columnOrder = const [],
    this.conditionalColors = const [],
    this.laneColumnId,
    this.dateColumnId,
  });

  const ViewConfig.empty() : this();

  final FilterGroup? filters;
  final List<SortRule> sort;
  final List<String> hiddenColumnIds;

  /// Explicit column order; columns missing from it follow in board order.
  final List<String> columnOrder;
  final List<ConditionalColor> conditionalColors;

  /// Kanban: a status/dropdown column.
  final String? laneColumnId;

  /// Calendar: a date/timeline column.
  final String? dateColumnId;

  bool get hasFilters => filters != null && filters!.rules.isNotEmpty;
  bool get hasSort => sort.isNotEmpty;
  bool get isEmpty =>
      !hasFilters &&
      !hasSort &&
      hiddenColumnIds.isEmpty &&
      columnOrder.isEmpty &&
      conditionalColors.isEmpty &&
      laneColumnId == null &&
      dateColumnId == null;

  factory ViewConfig.fromJson(Map<String, dynamic> json) => ViewConfig(
        filters: json['filters'] is Map<String, dynamic>
            ? FilterGroup.fromJson(json['filters'] as Map<String, dynamic>)
            : null,
        sort: (json['sort'] as List<dynamic>? ?? const [])
            .map((s) => SortRule.fromJson(s as Map<String, dynamic>))
            .toList(),
        hiddenColumnIds: (json['hiddenColumnIds'] as List<dynamic>? ?? const []).cast<String>(),
        columnOrder: (json['columnOrder'] as List<dynamic>? ?? const []).cast<String>(),
        conditionalColors: (json['conditionalColors'] as List<dynamic>? ?? const [])
            .map((c) => ConditionalColor.fromJson(c as Map<String, dynamic>))
            .toList(),
        laneColumnId: json['laneColumnId'] as String?,
        dateColumnId: json['dateColumnId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (hasFilters) 'filters': filters!.toJson(),
        if (sort.isNotEmpty) 'sort': [for (final s in sort) s.toJson()],
        if (hiddenColumnIds.isNotEmpty) 'hiddenColumnIds': hiddenColumnIds,
        if (columnOrder.isNotEmpty) 'columnOrder': columnOrder,
        if (conditionalColors.isNotEmpty) 'conditionalColors': [for (final c in conditionalColors) c.toJson()],
        if (laneColumnId != null) 'laneColumnId': laneColumnId,
        if (dateColumnId != null) 'dateColumnId': dateColumnId,
      };

  ViewConfig copyWith({
    FilterGroup? Function()? filters,
    List<SortRule>? sort,
    List<String>? hiddenColumnIds,
    List<String>? columnOrder,
    List<ConditionalColor>? conditionalColors,
    String? Function()? laneColumnId,
    String? Function()? dateColumnId,
  }) =>
      ViewConfig(
        filters: filters != null ? filters() : this.filters,
        sort: sort ?? this.sort,
        hiddenColumnIds: hiddenColumnIds ?? this.hiddenColumnIds,
        columnOrder: columnOrder ?? this.columnOrder,
        conditionalColors: conditionalColors ?? this.conditionalColors,
        laneColumnId: laneColumnId != null ? laneColumnId() : this.laneColumnId,
        dateColumnId: dateColumnId != null ? dateColumnId() : this.dateColumnId,
      );
}

// ---------- Field kinds and operators ----------

enum FieldKind { text, choice, people, date, number, checkbox, group, files }

/// Kind of a filterable field: a column id, `name` or `group`. Null when the
/// field is unknown (e.g. a deleted column) or the type has no filters.
FieldKind? fieldKindFor(String field, List<BoardColumn> columns) {
  if (field == 'name') return FieldKind.text;
  if (field == 'group') return FieldKind.group;
  final column = columns.where((c) => c.id == field).firstOrNull;
  if (column == null) return null;
  return fieldKindForType(column.type);
}

FieldKind? fieldKindForType(String type) => switch (type) {
      'text' || 'long_text' || 'email' || 'phone' || 'link' || 'location' => FieldKind.text,
      'status' || 'dropdown' || 'tags' => FieldKind.choice,
      'people' || 'vote' => FieldKind.people,
      'date' || 'timeline' || 'creation_log' || 'last_updated' => FieldKind.date,
      'number' || 'rating' || 'item_id' || 'auto_number' => FieldKind.number,
      'checkbox' => FieldKind.checkbox,
      'files' => FieldKind.files,
      _ => null,
    };

List<String> operatorsFor(FieldKind kind) => switch (kind) {
      FieldKind.text => const ['contains', 'not_contains', 'is', 'is_not', 'is_empty', 'is_not_empty'],
      FieldKind.choice => const ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty'],
      FieldKind.people => const ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty'],
      FieldKind.date => const ['is', 'is_before', 'is_after', 'is_between', 'is_empty', 'is_not_empty'],
      FieldKind.number => const ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty'],
      FieldKind.checkbox => const ['is_checked', 'is_not_checked'],
      FieldKind.group => const ['is_any_of', 'is_none_of'],
      FieldKind.files => const ['is_empty', 'is_not_empty'],
    };

/// Operators that take no value.
bool operatorNeedsValue(String op) => !const {'is_empty', 'is_not_empty', 'is_checked', 'is_not_checked'}.contains(op);

String operatorLabel(String op) => switch (op) {
      'contains' => 'contains',
      'not_contains' => 'does not contain',
      'is' => 'is',
      'is_not' => 'is not',
      'is_any_of' => 'is any of',
      'is_none_of' => 'is none of',
      'is_empty' => 'is empty',
      'is_not_empty' => 'is not empty',
      'is_before' => 'is before',
      'is_after' => 'is after',
      'is_between' => 'is between',
      'eq' => '=',
      'neq' => '≠',
      'gt' => '>',
      'gte' => '≥',
      'lt' => '<',
      'lte' => '≤',
      'is_checked' => 'is checked',
      'is_not_checked' => 'is not checked',
      _ => op.replaceAll('_', ' '),
    };

// ---------- Dates ----------

const datePresets = [
  'today',
  'yesterday',
  'tomorrow',
  'this_week',
  'last_week',
  'next_week',
  'this_month',
  'last_month',
  'next_month',
  'past',
  'future',
];

String datePresetLabel(String preset) => switch (preset) {
      'today' => 'Today',
      'yesterday' => 'Yesterday',
      'tomorrow' => 'Tomorrow',
      'this_week' => 'This week',
      'last_week' => 'Last week',
      'next_week' => 'Next week',
      'this_month' => 'This month',
      'last_month' => 'Last month',
      'next_month' => 'Next month',
      'past' => 'In the past',
      'future' => 'In the future',
      _ => preset,
    };

/// Formats a local calendar day as `YYYY-MM-DD`.
String formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Resolves a preset to an inclusive `YYYY-MM-DD` range in the local calendar
/// of [now]. Weeks start on Monday. A value that is not a preset is treated
/// as a literal date and becomes a one-day range.
({String from, String to}) resolveDateRange(String preset, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(int offset) => DateTime(today.year, today.month, today.day + offset);
  ({String from, String to}) range(DateTime a, DateTime b) => (from: formatYmd(a), to: formatYmd(b));
  ({String from, String to}) week(int weekOffset) {
    final monday = day(-(today.weekday - DateTime.monday) + weekOffset * 7);
    return range(monday, DateTime(monday.year, monday.month, monday.day + 6));
  }
  ({String from, String to}) month(int monthOffset) {
    final first = DateTime(today.year, today.month + monthOffset, 1);
    return range(first, DateTime(first.year, first.month + 1, 0));
  }

  return switch (preset) {
    'today' => range(today, today),
    'yesterday' => range(day(-1), day(-1)),
    'tomorrow' => range(day(1), day(1)),
    'this_week' => week(0),
    'last_week' => week(-1),
    'next_week' => week(1),
    'this_month' => month(0),
    'last_month' => month(-1),
    'next_month' => month(1),
    'past' => (from: '0001-01-01', to: formatYmd(day(-1))),
    'future' => (from: formatYmd(day(1)), to: '9999-12-31'),
    _ => (from: preset, to: preset),
  };
}

// ---------- Context ----------

/// Everything a rule needs beyond the item itself. Build with
/// [ViewContext.forBoard]; tests inject `now`.
class ViewContext {
  const ViewContext({
    required this.now,
    this.meUserId,
    this.memberNames = const {},
    this.groupIdByItemId = const {},
    this.indexByItemId = const {},
  });

  factory ViewContext.forBoard(BoardDetail board, {String? meUserId, DateTime? now}) {
    final groupIds = <String, String>{};
    for (final group in board.groups) {
      for (final item in group.items) {
        groupIds[item.id] = group.id;
        for (final sub in _subitemsOf(item)) {
          groupIds[sub.id] = group.id;
        }
      }
    }
    return ViewContext(
      now: now ?? DateTime.now(),
      meUserId: meUserId,
      memberNames: {for (final m in board.members) m.userId: m.fullName},
      groupIdByItemId: groupIds,
      indexByItemId: autoNumberIndex(board),
    );
  }

  final String? meUserId;
  final DateTime now;

  /// userId → display name (people sort).
  final Map<String, String> memberNames;

  /// itemId → groupId (`group` field).
  final Map<String, String> groupIdByItemId;

  /// itemId → 1-based position among top-level items (`auto_number`).
  final Map<String, int> indexByItemId;
}

/// Top-level items in board order (groups then positions as delivered).
List<BoardItem> flattenForAutoNumber(BoardDetail board) => [for (final g in board.groups) ...g.items];

/// itemId → 1-based index in [flattenForAutoNumber].
Map<String, int> autoNumberIndex(BoardDetail board) {
  final items = flattenForAutoNumber(board);
  return {for (var i = 0; i < items.length; i++) items[i].id: i + 1};
}

// ---------- Value extraction ----------

Map<String, dynamic>? _cell(BoardItem item, String columnId) {
  final raw = item.values[columnId];
  return raw is Map<String, dynamic> ? raw : null;
}

/// Tolerant reads of the new item fields so this module compiles whether the
/// coordinator declares them nullable or not.
DateTime? _asDateTime(Object? v) => v is DateTime ? v : (v is String ? DateTime.tryParse(v) : null);
num? _asNum(Object? v) => v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
List<BoardItem> _subitemsOf(BoardItem item) => _asItemList(item.subitems);
List<BoardItem> _asItemList(Object? v) => v is List<BoardItem> ? v : const [];
String _scopeOf(BoardColumn column) => _asScope(column.scope);
String _asScope(Object? v) => v is String && v.isNotEmpty ? v : 'items';

List<String> _asStringList(Object? v) {
  if (v is List) return [for (final e in v) if (e != null) e.toString()];
  if (v is String && v.isNotEmpty) return [v];
  return const [];
}

/// Text-ish cell value, or null when empty.
String? _textOf(BoardItem item, BoardColumn? column) {
  if (column == null) return item.name;
  final cell = _cell(item, column.id);
  if (cell == null) return null;
  final raw = switch (column.type) {
    'link' => cell['url'] ?? cell['label'],
    'email' => cell['email'],
    'phone' => cell['phone'],
    'location' => cell['address'],
    _ => cell['text'],
  };
  final text = raw?.toString();
  return text == null || text.isEmpty ? null : text;
}

/// Selected label/option ids of a choice cell.
List<String> _choiceIdsOf(BoardItem item, BoardColumn column) {
  final cell = _cell(item, column.id);
  if (cell == null) return const [];
  if (column.type == 'status') {
    final id = cell['labelId'];
    return id is String && id.isNotEmpty ? [id] : const [];
  }
  return _asStringList(cell['optionIds']);
}

List<String> _userIdsOf(BoardItem item, BoardColumn column) => _asStringList(_cell(item, column.id)?['userIds']);

/// `YYYY-MM-DD` of a date-kind cell in the local calendar, or null.
String? _dateOf(BoardItem item, BoardColumn column) {
  switch (column.type) {
    case 'creation_log':
      final at = _asDateTime(item.createdAt);
      return at == null ? null : formatYmd(at.toLocal());
    case 'last_updated':
      final at = _asDateTime(item.updatedAt);
      return at == null ? null : formatYmd(at.toLocal());
    case 'timeline':
      final from = _cell(item, column.id)?['from'];
      return from is String && from.isNotEmpty ? from : null;
    default:
      final date = _cell(item, column.id)?['date'];
      return date is String && date.isNotEmpty ? date : null;
  }
}

/// Numeric value of a number-kind cell, or null.
num? _numberOf(BoardItem item, BoardColumn column, ViewContext ctx) => switch (column.type) {
      'item_id' => _asNum(item.serial),
      'auto_number' => ctx.indexByItemId[item.id],
      'rating' => _asNum(_cell(item, column.id)?['rating']),
      _ => _asNum(_cell(item, column.id)?['number']),
    };

bool _isChecked(BoardItem item, BoardColumn column) => _cell(item, column.id)?['checked'] == true;

List<String> _fileIdsOf(BoardItem item, BoardColumn column) => _asStringList(_cell(item, column.id)?['fileIds']);

// ---------- Filtering ----------

/// True when [item] satisfies [rule]. A rule on an unknown field or with an
/// operator invalid for its kind can never be satisfied (returns false);
/// [matchesFilters] skips such rules instead.
bool matchesRule(BoardItem item, FilterRule rule, List<BoardColumn> columns, ViewContext ctx) {
  final kind = fieldKindFor(rule.field, columns);
  if (kind == null || !operatorsFor(kind).contains(rule.operator)) return false;
  final column = columns.where((c) => c.id == rule.field).firstOrNull;
  final op = rule.operator;

  switch (kind) {
    case FieldKind.text:
      final text = _textOf(item, column);
      final needle = (rule.value?.toString() ?? '').toLowerCase();
      final haystack = text?.toLowerCase();
      return switch (op) {
        'is_empty' => text == null,
        'is_not_empty' => text != null,
        'contains' => haystack != null && haystack.contains(needle),
        'not_contains' => haystack == null || !haystack.contains(needle),
        'is' => haystack != null && haystack == needle,
        'is_not' => haystack == null || haystack != needle,
        _ => false,
      };

    case FieldKind.choice:
    case FieldKind.people:
    case FieldKind.group:
      final List<String> selected;
      if (kind == FieldKind.group) {
        final groupId = ctx.groupIdByItemId[item.id];
        selected = groupId == null ? const [] : [groupId];
      } else if (kind == FieldKind.people) {
        selected = _userIdsOf(item, column!);
      } else {
        selected = _choiceIdsOf(item, column!);
      }
      final wanted = _asStringList(rule.value)
          .map((v) => kind == FieldKind.people && v == 'me' ? ctx.meUserId : v)
          .whereType<String>()
          .toSet();
      final overlaps = selected.any(wanted.contains);
      return switch (op) {
        'is_empty' => selected.isEmpty,
        'is_not_empty' => selected.isNotEmpty,
        'is_any_of' => overlaps,
        'is_none_of' => !overlaps,
        _ => false,
      };

    case FieldKind.date:
      final date = _dateOf(item, column!);
      if (op == 'is_empty') return date == null;
      if (op == 'is_not_empty') return date != null;
      if (date == null) return false;
      if (op == 'is_between') {
        final bounds = _betweenBounds(rule.value);
        if (bounds == null) return false;
        final from = resolveDateRange(bounds.$1, ctx.now).from;
        final to = resolveDateRange(bounds.$2, ctx.now).to;
        return date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
      }
      final preset = rule.value?.toString();
      if (preset == null || preset.isEmpty) return false;
      final range = resolveDateRange(preset, ctx.now);
      return switch (op) {
        'is' => date.compareTo(range.from) >= 0 && date.compareTo(range.to) <= 0,
        'is_before' => date.compareTo(range.from) < 0,
        'is_after' => date.compareTo(range.to) > 0,
        _ => false,
      };

    case FieldKind.number:
      final actual = _numberOf(item, column!, ctx);
      if (op == 'is_empty') return actual == null;
      if (op == 'is_not_empty') return actual != null;
      final expected = _asNum(rule.value);
      if (expected == null) return false;
      if (actual == null) return op == 'neq';
      return switch (op) {
        'eq' => actual == expected,
        'neq' => actual != expected,
        'gt' => actual > expected,
        'gte' => actual >= expected,
        'lt' => actual < expected,
        'lte' => actual <= expected,
        _ => false,
      };

    case FieldKind.checkbox:
      final checked = _isChecked(item, column!);
      return op == 'is_checked' ? checked : !checked;

    case FieldKind.files:
      final files = _fileIdsOf(item, column!);
      return op == 'is_empty' ? files.isEmpty : files.isNotEmpty;
  }
}

(String, String)? _betweenBounds(Object? value) {
  if (value is List && value.length >= 2 && value[0] is String && value[1] is String) {
    return (value[0] as String, value[1] as String);
  }
  if (value is Map) {
    final from = value['from'];
    final to = value['to'];
    if (from is String && to is String) return (from, to);
  }
  return null;
}

/// True when [item] passes the saved filter group. Rules on unknown fields or
/// with invalid operators are ignored; a group with no usable rules passes
/// everything.
bool matchesFilters(BoardItem item, FilterGroup? filters, List<BoardColumn> columns, ViewContext ctx) {
  if (filters == null || filters.rules.isEmpty) return true;
  final usable = filters.rules.where((r) {
    final kind = fieldKindFor(r.field, columns);
    return kind != null && operatorsFor(kind).contains(r.operator);
  }).toList();
  if (usable.isEmpty) return true;
  return filters.conjunction == 'or'
      ? usable.any((r) => matchesRule(item, r, columns, ctx))
      : usable.every((r) => matchesRule(item, r, columns, ctx));
}

// ---------- Sorting ----------

/// Sort key for one rule, or null when the item has no value (sorts last).
Comparable<Object>? _sortKey(BoardItem item, String field, List<BoardColumn> columns, ViewContext ctx) {
  switch (field) {
    case 'name':
      return item.name.toLowerCase();
    case 'created_at':
      return _asDateTime(item.createdAt);
    case 'updated_at':
      return _asDateTime(item.updatedAt);
    case 'serial':
      return _asNum(item.serial);
  }
  final column = columns.where((c) => c.id == field).firstOrNull;
  if (column == null) return null;
  switch (column.type) {
    case 'status':
      final id = _choiceIdsOf(item, column).firstOrNull;
      if (id == null) return null;
      final index = column.statusLabels.indexWhere((l) => l.id == id);
      return index < 0 ? null : index;
    case 'dropdown':
    case 'tags':
      final id = _choiceIdsOf(item, column).firstOrNull;
      if (id == null) return null;
      final options = (column.settings['options'] as List<dynamic>? ?? const []);
      final index = options.indexWhere((o) => o is Map && o['id'] == id);
      return index < 0 ? null : index;
    case 'people':
    case 'vote':
      final id = _userIdsOf(item, column).firstOrNull;
      return id == null ? null : (ctx.memberNames[id] ?? id).toLowerCase();
    case 'checkbox':
      return _isChecked(item, column) ? 0 : 1;
    case 'files':
      final files = _fileIdsOf(item, column);
      return files.isEmpty ? null : files.length;
    case 'date':
      final cell = _cell(item, column.id);
      final date = _dateOf(item, column);
      if (date == null) return null;
      final time = cell?['time'];
      return time is String && time.isNotEmpty ? '$date $time' : date;
    case 'timeline':
    case 'creation_log':
    case 'last_updated':
      return _dateOf(item, column);
    case 'number':
    case 'rating':
    case 'item_id':
    case 'auto_number':
      return _numberOf(item, column, ctx);
    default:
      return _textOf(item, column)?.toLowerCase();
  }
}

/// Contract sort: rules in order, missing values last in both directions,
/// then board position (then id, so the order is total).
int compareItems(BoardItem a, BoardItem b, List<SortRule> sort, List<BoardColumn> columns, ViewContext ctx) {
  for (final rule in sort) {
    final ka = _sortKey(a, rule.field, columns, ctx);
    final kb = _sortKey(b, rule.field, columns, ctx);
    if (ka == null && kb == null) continue;
    if (ka == null) return 1;
    if (kb == null) return -1;
    final cmp = _compareKeys(ka, kb);
    if (cmp != 0) return rule.isDescending ? -cmp : cmp;
  }
  final byPosition = a.position.compareTo(b.position);
  return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
}

int _compareKeys(Comparable<Object> a, Comparable<Object> b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  return a.toString().compareTo(b.toString());
}

// ---------- Applying a view ----------

/// Filters (saved rules, then [extraFilter] — the quick filters) and sorts
/// each group's top-level items. Subitems ride with their parent untouched.
/// Groups that end up empty are kept; the caller decides whether to show them.
/// Inputs are never mutated.
List<BoardGroup> applyView(
  BoardDetail board,
  ViewConfig config,
  ViewContext ctx, {
  bool Function(BoardItem)? extraFilter,
}) {
  final columns = board.columns;
  return [
    for (final group in board.groups)
      group.copyWith(items: _applyToItems(group.items, config, columns, ctx, extraFilter)),
  ];
}

List<BoardItem> _applyToItems(
  List<BoardItem> items,
  ViewConfig config,
  List<BoardColumn> columns,
  ViewContext ctx,
  bool Function(BoardItem)? extraFilter,
) {
  final kept = [
    for (final item in items)
      if (matchesFilters(item, config.filters, columns, ctx) && (extraFilter == null || extraFilter(item))) item,
  ];
  if (config.sort.isNotEmpty) {
    kept.sort((a, b) => compareItems(a, b, config.sort, columns, ctx));
  }
  return kept;
}

/// Columns of [scope] that are not hidden, in the view's order: ids listed in
/// `columnOrder` first (in that order), then the rest in board order.
List<BoardColumn> visibleColumns(List<BoardColumn> columns, ViewConfig config, {String scope = 'items'}) {
  final hidden = config.hiddenColumnIds.toSet();
  final candidates = [
    for (final c in columns)
      if (_scopeOf(c) == scope && !hidden.contains(c.id)) c,
  ];
  if (config.columnOrder.isEmpty) return candidates;
  final byId = {for (final c in candidates) c.id: c};
  final ordered = <BoardColumn>[];
  for (final id in config.columnOrder) {
    final column = byId.remove(id);
    if (column != null) ordered.add(column);
  }
  ordered.addAll(candidates.where((c) => byId.containsKey(c.id)));
  return ordered;
}

// ---------- Conditional colors ----------

/// Colour token for one cell: the first `applyTo: cell` rule on this column
/// that matches, or null.
String? cellColorFor(
  BoardItem item,
  BoardColumn column,
  ViewConfig config,
  List<BoardColumn> columns,
  ViewContext ctx,
) {
  for (final rule in config.conditionalColors) {
    if (rule.applyTo != 'cell' || rule.field != column.id) continue;
    if (matchesRule(item, rule.asRule, columns, ctx)) return rule.color;
  }
  return null;
}

/// Colour token for the row background: the first `applyTo: row` rule that
/// matches, or null. The caller tints at 12% alpha.
String? rowColorFor(BoardItem item, ViewConfig config, List<BoardColumn> columns, ViewContext ctx) {
  for (final rule in config.conditionalColors) {
    if (rule.applyTo != 'row') continue;
    if (matchesRule(item, rule.asRule, columns, ctx)) return rule.color;
  }
  return null;
}

// ---------- Column summaries ----------

sealed class ColumnSummary {
  const ColumnSummary();
}

/// Number column footer. [mode] is `sum|avg|min|max|count`; [formatted] is
/// ready to display (unit and decimals applied except for `count`).
class NumberSummary extends ColumnSummary {
  const NumberSummary({required this.value, required this.mode, required this.formatted});
  final num value;
  final String mode;
  final String formatted;
}

class RatingSummary extends ColumnSummary {
  const RatingSummary({required this.average, required this.formatted});
  final double average;

  /// e.g. `★ 4.2`
  final String formatted;
}

class StatusSummary extends ColumnSummary {
  const StatusSummary({required this.counts, required this.total});

  /// labelId → count, in label order, labels with zero items omitted.
  final Map<String, int> counts;

  /// Items in the group (so the battery can show the unlabelled remainder).
  final int total;
}

class CheckboxSummary extends ColumnSummary {
  const CheckboxSummary({required this.checked, required this.total});
  final int checked;
  final int total;
  String get formatted => '$checked/$total';
}

class PeopleSummary extends ColumnSummary {
  const PeopleSummary({required this.distinct});
  final int distinct;
}

class DateRangeSummary extends ColumnSummary {
  const DateRangeSummary({required this.from, required this.to, required this.formatted});

  /// `YYYY-MM-DD`
  final String from;
  final String to;

  /// e.g. `Jan 3 – Mar 9`, or a single day when from == to.
  final String formatted;
}

/// Footer summary for [column] over [items], or null when the type has no
/// summary, `settings.summary` is `none`, or there is nothing to summarise.
ColumnSummary? summarize(BoardColumn column, List<BoardItem> items) {
  if (column.settings['summary'] == 'none') return null;
  switch (column.type) {
    case 'number':
      final values = [for (final i in items) ?_asNum(_cell(i, column.id)?['number'])];
      if (values.isEmpty) return null;
      final mode = column.settings['summary'] as String? ?? 'sum';
      final num value = switch (mode) {
        'avg' => values.fold<num>(0, (s, v) => s + v) / values.length,
        'min' => values.reduce((a, b) => a < b ? a : b),
        'max' => values.reduce((a, b) => a > b ? a : b),
        'count' => values.length,
        _ => values.fold<num>(0, (s, v) => s + v),
      };
      final formatted = mode == 'count' ? NumberFormat.decimalPattern().format(value) : formatNumberCell(column, value);
      return NumberSummary(value: value, mode: mode == 'count' ? 'count' : _numberMode(mode), formatted: formatted);

    case 'rating':
      final values = [for (final i in items) ?_asNum(_cell(i, column.id)?['rating'])];
      if (values.isEmpty) return null;
      final average = values.fold<num>(0, (s, v) => s + v) / values.length;
      return RatingSummary(average: average, formatted: '★ ${average.toStringAsFixed(1)}');

    case 'status':
      if (items.isEmpty) return null;
      final counts = <String, int>{};
      for (final item in items) {
        final id = _choiceIdsOf(item, column).firstOrNull;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      final ordered = <String, int>{};
      for (final label in column.statusLabels) {
        final count = counts.remove(label.id);
        if (count != null) ordered[label.id] = count;
      }
      ordered.addAll(counts); // labels no longer in settings keep their count
      return StatusSummary(counts: ordered, total: items.length);

    case 'checkbox':
      if (items.isEmpty) return null;
      return CheckboxSummary(checked: items.where((i) => _isChecked(i, column)).length, total: items.length);

    case 'people':
      final distinct = {for (final i in items) ..._userIdsOf(i, column)};
      return distinct.isEmpty ? null : PeopleSummary(distinct: distinct.length);

    case 'date':
      final dates = [for (final i in items) ?_dateOf(i, column)]..sort();
      return dates.isEmpty ? null : _dateRange(dates.first, dates.last);

    case 'timeline':
      final froms = <String>[];
      final tos = <String>[];
      for (final item in items) {
        final cell = _cell(item, column.id);
        final from = cell?['from'];
        final to = cell?['to'];
        if (from is String && from.isNotEmpty) froms.add(from);
        if (to is String && to.isNotEmpty) tos.add(to);
      }
      if (froms.isEmpty && tos.isEmpty) return null;
      froms.sort();
      tos.sort();
      final from = froms.isEmpty ? tos.first : froms.first;
      final to = tos.isEmpty ? froms.last : tos.last;
      return _dateRange(from, to);

    default:
      return null;
  }
}

String _numberMode(String mode) => const {'sum', 'avg', 'min', 'max'}.contains(mode) ? mode : 'sum';

DateRangeSummary _dateRange(String from, String to) {
  String label(String ymd) {
    final parsed = DateTime.tryParse(ymd);
    return parsed == null ? ymd : DateFormat.MMMd().format(parsed);
  }
  return DateRangeSummary(from: from, to: to, formatted: from == to ? label(from) : '${label(from)} – ${label(to)}');
}

/// Formats a number cell per the column's `unit`, `unitPosition` and
/// `decimals` settings. Without `decimals`, integers print without a fraction
/// and other values with up to two decimals. A one-character suffix unit
/// (`%`, `h`) is glued to the number; longer units get a space.
String formatNumberCell(BoardColumn column, num value) {
  final decimals = _asNum(column.settings['decimals'])?.toInt();
  final format = NumberFormat.decimalPattern();
  if (decimals != null) {
    format.minimumFractionDigits = decimals.clamp(0, 6);
    format.maximumFractionDigits = decimals.clamp(0, 6);
  } else if (value is int || value == value.roundToDouble()) {
    format.maximumFractionDigits = 0;
  } else {
    format.maximumFractionDigits = 2;
  }
  final number = format.format(value);
  final unit = column.settings['unit'] as String?;
  if (unit == null || unit.isEmpty) return number;
  final position = column.settings['unitPosition'] as String? ?? 'suffix';
  if (position == 'prefix') return '$unit$number';
  return unit.length == 1 ? '$number$unit' : '$number $unit';
}
