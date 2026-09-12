import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../board/board_controller.dart';
import '../item/update_card.dart' show relativeTime;
import '../members/members_providers.dart';

/// Loads one page of a board's activity. Indirection so tests can feed pages
/// without an API client.
typedef ActivityLoader = Future<ActivityPage> Function(String boardId, {String? actorId, String? cursor});

final activityLoaderProvider = Provider<ActivityLoader>((ref) {
  final repo = ref.read(boardRepositoryProvider);
  return (boardId, {actorId, cursor}) => repo.activity(boardId, actorId: actorId, cursor: cursor);
});

final activityUndoProvider = Provider<Future<void> Function(String entryId)>(
  (ref) => ref.read(boardRepositoryProvider).undoActivity,
);

/// Client-side event groups for the filter bar.
enum ActivityGroup {
  all('All'),
  items('Items'),
  cells('Values'),
  structure('Structure'),
  board('Board');

  const ActivityGroup(this.label);
  final String label;

  bool matches(ActivityEntry entry) {
    final event = entry.event;
    return switch (this) {
      ActivityGroup.all => true,
      ActivityGroup.items => event.startsWith('item_'),
      ActivityGroup.cells => event == 'column_value_changed',
      ActivityGroup.structure =>
        event.startsWith('group_') || (event.startsWith('column_') && event != 'column_value_changed'),
      ActivityGroup.board =>
        event.startsWith('board_') || event.startsWith('member_') || event == 'activity_undone',
    };
  }
}

/// Paged board activity log with event-group and person filters, and undo
/// for reversible entries.
class BoardActivityScreen extends ConsumerStatefulWidget {
  const BoardActivityScreen({super.key, required this.boardId});

  final String boardId;

  @override
  ConsumerState<BoardActivityScreen> createState() => _BoardActivityScreenState();
}

class _BoardActivityScreenState extends ConsumerState<BoardActivityScreen> {
  final _scroll = ScrollController();
  final _entries = <ActivityEntry>[];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _initial = true;
  String? _error;
  ActivityGroup _group = ActivityGroup.all;
  BoardMember? _actor;

  /// Generation counter so a stale page from before a filter reset is dropped.
  int _generation = 0;

  static const _pageThreshold = 400.0;
  static const _minVisible = 15;
  static const _maxAutoPages = 3;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - _pageThreshold) _load();
  }

  List<ActivityEntry> get _visible => _entries.where(_group.matches).toList();

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _cursor = null;
        _hasMore = true;
      }
    });
    try {
      final page = await ref.read(activityLoaderProvider)(
        widget.boardId,
        actorId: _actor?.userId,
        cursor: reset ? null : _cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) _entries.clear();
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null && page.entries.isNotEmpty;
        _loading = false;
        _initial = false;
      });
      await _ensureFilled();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _initial = false;
        _error = e.message;
      });
    }
  }

  /// A narrow group filter can hide a whole page; pull a few more so the list
  /// is not misleadingly empty. Bounded so a filter that matches nothing does
  /// not walk the entire log.
  Future<void> _ensureFilled() async {
    var pulled = 0;
    while (mounted && _hasMore && !_loading && _visible.length < _minVisible && pulled < _maxAutoPages) {
      pulled++;
      await _load();
    }
  }

  void _setGroup(ActivityGroup group) {
    if (group == _group) return;
    setState(() => _group = group);
    _ensureFilled();
  }

  Future<void> _pickActor() async {
    final members = await ref.read(assignableMembersProvider.future).catchError((Object _) => <BoardMember>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<_ActorChoice>(
      context: context,
      builder: (sheetContext) => _ActorSheet(members: members, selected: _actor),
    );
    if (picked == null || !mounted) return;
    setState(() => _actor = picked.member);
    await _load(reset: true);
  }

  Future<void> _undo(ActivityEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Undo this change?', style: Theme.of(dialogContext).textTheme.titleMedium),
        content: Text(
          'This reverts "${entry.actorName ?? 'Someone'} ${entry.boardDescription}". The undo is logged too.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Undo')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(activityUndoProvider)(entry.id);
      ref.invalidate(boardControllerProvider(widget.boardId));
      if (!mounted) return;
      showDfToast(context, 'Change undone');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        leading: BackButton(onPressed: () => context.pop()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
              child: Row(children: [
                for (final group in ActivityGroup.values)
                  Padding(
                    padding: const EdgeInsets.only(right: DfSpacing.xs, bottom: DfSpacing.xs),
                    child: _FilterChip(
                      label: group.label,
                      selected: _group == group,
                      onTap: () => _setGroup(group),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: DfSpacing.xs, bottom: DfSpacing.xs),
                  child: _FilterChip(
                    label: _actor?.fullName ?? 'Person',
                    icon: Icons.person_outline_rounded,
                    selected: _actor != null,
                    onTap: _pickActor,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      body: Builder(builder: (context) {
        if (_initial && _loading) return const Center(child: CircularProgressIndicator());
        if (_entries.isEmpty && _error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DfSpacing.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
                const SizedBox(height: DfSpacing.sm),
                Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
                const SizedBox(height: DfSpacing.md),
                DfButton(
                  label: 'Try again',
                  variant: DfButtonVariant.tonal,
                  expand: false,
                  onPressed: () => _load(reset: true),
                ),
              ]),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: visible.isEmpty
              ? _EmptyActivity(
                  filtered: _entries.isNotEmpty || _actor != null,
                  hasMore: _hasMore,
                  loading: _loading,
                  onLoadMore: _load,
                )
              : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.only(top: DfSpacing.xs, bottom: DfSpacing.xxl),
                  itemCount: visible.length + 1,
                  separatorBuilder: (context, index) =>
                      index < visible.length - 1 ? const Divider(height: 1) : const SizedBox.shrink(),
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return _Footer(hasMore: _hasMore, loading: _loading, error: _error, onLoadMore: _load);
                    }
                    final entry = visible[index];
                    return _ActivityRow(
                      entry: entry,
                      onUndo: entry.undoable && !entry.isUndone ? () => _undo(entry) : null,
                    ).animate(delay: DfMotion.staggerStep * (index.clamp(0, 8))).fadeIn(
                          duration: DfMotion.expressiveShort,
                          curve: DfMotion.enter,
                        );
                  },
                ),
        );
      }),
    );
  }
}

class _ActorChoice {
  const _ActorChoice(this.member);

  /// Null clears the filter ("Anyone").
  final BoardMember? member;
}

class _ActorSheet extends StatelessWidget {
  const _ActorSheet({required this.members, required this.selected});

  final List<BoardMember> members;
  final BoardMember? selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Align(alignment: Alignment.centerLeft, child: Text('Filter by person', style: text.titleMedium)),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.people_outline_rounded),
                title: const Text('Anyone'),
                trailing: selected == null ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
                onTap: () => Navigator.pop(context, const _ActorChoice(null)),
              ),
              for (final member in members)
                ListTile(
                  leading: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 32),
                  title: Text(member.fullName),
                  trailing: selected?.userId == member.userId
                      ? const Icon(Icons.check_rounded, color: DfColors.primary)
                      : null,
                  onTap: () => Navigator.pop(context, _ActorChoice(member)),
                ),
            ],
          ),
        ),
        const SizedBox(height: DfSpacing.sm),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: DfMotion.productiveLong,
      curve: DfMotion.transition,
      decoration: BoxDecoration(
        color: selected
            ? (isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DfRadius.pill),
        border: Border.all(
          color: selected ? DfColors.primary : (isDark ? DfColors.borderDark : DfColors.border),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DfRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? DfColors.primary : DfColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? DfColors.primary : null,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Events whose `from`/`to` payload is worth spelling out under the sentence.
bool _showsDiff(ActivityEntry entry) =>
    entry.event == 'column_value_changed' || entry.event.endsWith('_renamed') || entry.event == 'item_moved';

/// Renders a payload value compactly: primitives as-is, cell maps by their
/// most telling key, collections as counts.
String describeActivityValue(Object? value) {
  switch (value) {
    case null:
      return '—';
    case String s:
      return s.isEmpty ? '—' : s;
    case num n:
      return n is double && n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
    case bool b:
      return b ? 'Yes' : 'No';
    case List l:
      return l.isEmpty ? '—' : '${l.length} value${l.length == 1 ? '' : 's'}';
    case Map m:
      if (m.isEmpty) return '—';
      if (m['labelId'] != null) return '${m['labelId']}';
      if (m['text'] != null) return describeActivityValue(m['text']);
      if (m['number'] != null) return describeActivityValue(m['number']);
      if (m['date'] != null) {
        final time = m['time'];
        return time is String && time.isNotEmpty ? '${m['date']} $time' : '${m['date']}';
      }
      if (m['from'] != null || m['to'] != null) return '${m['from'] ?? '…'} – ${m['to'] ?? '…'}';
      if (m['url'] != null) return describeActivityValue(m['label'] ?? m['url']);
      if (m['address'] != null) return describeActivityValue(m['address']);
      if (m['email'] != null) return describeActivityValue(m['email']);
      if (m['phone'] != null) return describeActivityValue(m['phone']);
      if (m['rating'] != null) return '★ ${m['rating']}';
      if (m['checked'] != null) return m['checked'] == true ? 'Checked' : 'Unchecked';
      if (m['userIds'] is List) {
        final n = (m['userIds'] as List).length;
        return '$n ${n == 1 ? 'person' : 'people'}';
      }
      if (m['optionIds'] is List) {
        final n = (m['optionIds'] as List).length;
        return '$n tag${n == 1 ? '' : 's'}';
      }
      if (m['fileIds'] is List) {
        final n = (m['fileIds'] as List).length;
        return '$n file${n == 1 ? '' : 's'}';
      }
      return describeActivityValue(m.values.first);
    default:
      return value.toString();
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.onUndo});

  final ActivityEntry entry;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actor = entry.actorName ?? 'Someone';
    final hasDiff = _showsDiff(entry) && (entry.payload.containsKey('from') || entry.payload.containsKey('to'));

    return Opacity(
      opacity: entry.isUndone ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DfAvatar(name: actor, seed: entry.actorId ?? actor, imageUrl: entry.actorAvatarUrl, size: 36),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: actor, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' ${entry.boardDescription}'),
                ]),
                style: text.bodyMedium,
              ),
              if (hasDiff)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${describeActivityValue(entry.payload['from'])} → ${describeActivityValue(entry.payload['to'])}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(fontFamily: 'Inter'),
                  ),
                ),
              const SizedBox(height: DfSpacing.xxs),
              Wrap(
                spacing: DfSpacing.xs,
                runSpacing: DfSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(relativeTime(entry.createdAt), style: text.labelSmall),
                  if (entry.columnTitle != null)
                    _Tag(
                      label: entry.columnTitle!,
                      color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
                      textColor: isDark ? DfColors.textSecondaryDark : DfColors.textSecondary,
                    ),
                  if (entry.isUndone)
                    _Tag(
                      label: 'Undone',
                      color: DfColors.statusAmber.withValues(alpha: 0.15),
                      textColor: DfColors.statusAmber,
                    ),
                ],
              ),
            ]),
          ),
          if (onUndo != null)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Undo'),
            ),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.hasMore, required this.loading, required this.error, required this.onLoadMore});

  final bool hasMore;
  final bool loading;
  final String? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: DfSpacing.xs),
          Text('Loading…', style: text.labelMedium),
        ]),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(children: [
          Text(error!, textAlign: TextAlign.center, style: text.bodySmall),
          TextButton(onPressed: onLoadMore, child: const Text('Try again')),
        ]),
      );
    }
    if (hasMore) {
      return Center(child: TextButton(onPressed: onLoadMore, child: const Text('Load more')));
    }
    return Padding(
      padding: const EdgeInsets.all(DfSpacing.md),
      child: Text('Beginning of the log', textAlign: TextAlign.center, style: text.labelSmall),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({
    required this.filtered,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  final bool filtered;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.xl),
            child: Column(children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: isDark ? DfColors.surfaceAltDark : DfColors.primarySubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  filtered ? Icons.filter_alt_off_outlined : Icons.history_rounded,
                  size: 34,
                  color: DfColors.primary,
                ),
              ),
              const SizedBox(height: DfSpacing.md),
              Text(
                filtered ? 'Nothing matches this filter' : 'No activity yet',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: DfSpacing.xxs),
              Text(
                filtered
                    ? 'Try another group or person.'
                    : 'Every change on this board is recorded here,\nand recent ones can be undone.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              if (hasMore) ...[
                const SizedBox(height: DfSpacing.sm),
                if (loading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  TextButton(onPressed: onLoadMore, child: const Text('Load older activity')),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}
