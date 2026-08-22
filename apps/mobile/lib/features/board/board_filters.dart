import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';

/// Active filters on a board's item list (Quick Find + quick filters).
class BoardFilter {
  const BoardFilter({this.query = '', this.personId, this.statusLabelId, this.statusColumnId});

  final String query;
  final String? personId;
  final String? statusLabelId;

  /// Which status column [statusLabelId] belongs to.
  final String? statusColumnId;

  bool get isActive => query.isNotEmpty || personId != null || statusLabelId != null;

  BoardFilter copyWith({
    String? query,
    String? Function()? personId,
    String? Function()? statusLabelId,
    String? Function()? statusColumnId,
  }) =>
      BoardFilter(
        query: query ?? this.query,
        personId: personId != null ? personId() : this.personId,
        statusLabelId: statusLabelId != null ? statusLabelId() : this.statusLabelId,
        statusColumnId: statusColumnId != null ? statusColumnId() : this.statusColumnId,
      );

  /// True when [item] survives this filter.
  bool matches(BoardItem item, List<BoardColumn> columns) {
    if (query.isNotEmpty && !item.name.toLowerCase().contains(query.toLowerCase())) {
      return false;
    }
    if (personId != null) {
      final assigned = columns.where((c) => c.type == 'people').any((column) {
        final cell = item.values[column.id];
        final ids = cell is Map<String, dynamic> ? (cell['userIds'] as List<dynamic>? ?? const []) : const [];
        return ids.contains(personId);
      });
      if (!assigned) return false;
    }
    if (statusLabelId != null && statusColumnId != null) {
      final cell = item.values[statusColumnId!];
      final current = cell is Map<String, dynamic> ? cell['labelId'] as String? : null;
      if (current != statusLabelId) return false;
    }
    return true;
  }
}

final boardFilterProvider =
    StateProvider.autoDispose.family<BoardFilter, String>((ref, boardId) => const BoardFilter());

/// Quick-filter sheet: person and status label chips, mirroring the design's
/// quick filters row.
Future<void> showBoardFilterSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String boardId,
  required BoardDetail board,
  required List<BoardMember> members,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _FilterSheet(boardId: boardId, board: board, members: members),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.boardId, required this.board, required this.members});

  final String boardId;
  final BoardDetail board;
  final List<BoardMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(boardFilterProvider(boardId));
    final notifier = ref.read(boardFilterProvider(boardId).notifier);
    final text = Theme.of(context).textTheme;
    final statusColumns = board.columns.where((c) => c.type == 'status').toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Quick filters', style: text.titleMedium),
            const Spacer(),
            if (filter.isActive)
              TextButton(
                onPressed: () {
                  notifier.state = BoardFilter(query: filter.query);
                  Navigator.pop(context);
                },
                child: const Text('Clear'),
              ),
          ]),
          if (members.isNotEmpty) ...[
            const SizedBox(height: DfSpacing.xs),
            Text('Person', style: text.labelMedium),
            const SizedBox(height: DfSpacing.xs),
            Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xs, children: [
              for (final member in members)
                _PersonChip(
                  member: member,
                  selected: filter.personId == member.userId,
                  onTap: () => notifier.state = filter.copyWith(
                    personId: () => filter.personId == member.userId ? null : member.userId,
                  ),
                ),
            ]),
          ],
          for (final column in statusColumns) ...[
            const SizedBox(height: DfSpacing.md),
            Text(column.title, style: text.labelMedium),
            const SizedBox(height: DfSpacing.xs),
            Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xs, children: [
              for (final label in column.statusLabels)
                GestureDetector(
                  onTap: () {
                    final selected =
                        filter.statusLabelId == label.id && filter.statusColumnId == column.id;
                    notifier.state = filter.copyWith(
                      statusLabelId: () => selected ? null : label.id,
                      statusColumnId: () => selected ? null : column.id,
                    );
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 100),
                    opacity: filter.statusLabelId == null ||
                            (filter.statusLabelId == label.id && filter.statusColumnId == column.id)
                        ? 1
                        : 0.4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: 8),
                      decoration: BoxDecoration(
                        color: DfColors.token(label.color),
                        borderRadius: BorderRadius.circular(DfRadius.sm),
                        border: filter.statusLabelId == label.id && filter.statusColumnId == column.id
                            ? Border.all(color: DfColors.textPrimary, width: 2)
                            : null,
                      ),
                      child: Text(
                        label.label,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontVariations: [FontVariation('wght', 600)],
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: DfSpacing.md),
          DfButton(label: 'Done', onPressed: () => Navigator.pop(context)),
        ]),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.member, required this.selected, required this.onTap});

  final BoardMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DfRadius.pill),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, DfSpacing.sm, 4),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DfRadius.pill),
          border: Border.all(
            color: selected ? DfColors.primary : (isDark ? DfColors.borderDark : DfColors.border),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 24),
          const SizedBox(width: DfSpacing.xs),
          Text(
            member.fullName,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? DfColors.primary : null,
                ),
          ),
        ]),
      ),
    );
  }
}
