import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import 'cell_editors.dart' show cellChip;

/// "N subitems · M done" toggle shown on a parent row.
class SubitemToggleChip extends StatelessWidget {
  const SubitemToggleChip({
    super.key,
    required this.count,
    required this.done,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final int done;
  final bool expanded;
  final VoidCallback onTap;

  /// Label text, shared with tests.
  static String label(int count, int done) => '$count ${count == 1 ? 'subitem' : 'subitems'} · $done done';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 24,
        padding: const EdgeInsets.fromLTRB(2, 0, DfSpacing.xs, 0),
        decoration: BoxDecoration(
          color: expanded
              ? (isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle)
              : (isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedRotation(
            turns: expanded ? 0 : -0.25,
            duration: DfMotion.productiveLong,
            child: Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: expanded ? DfColors.primary : DfColors.textSecondary,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label(count, done),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: expanded ? DfColors.primary : null),
          ),
        ]),
      ),
    );
  }
}

/// One cell chip: the value, or a dotted "+ Column" placeholder. Status chips
/// replay a small celebration when their label changes (Vibe emphasize curve,
/// plus a shimmer when the new label counts as done). [tint] wraps the chip in
/// a tinted container for conditional cell colours.
class DfCellChip extends StatelessWidget {
  const DfCellChip({
    super.key,
    required this.column,
    required this.item,
    required this.members,
    required this.enabled,
    required this.onEdit,
    this.autoNumber,
    this.tint,
  });

  final BoardColumn column;
  final BoardItem item;
  final List<BoardMember> members;
  final bool enabled;
  final VoidCallback onEdit;
  final int? autoNumber;

  /// Colour token from a matching conditional-colour rule.
  final String? tint;

  @override
  Widget build(BuildContext context) {
    var chip = cellChip(context, column, item, members, autoNumber: autoNumber);

    if (chip != null && column.type == 'status') {
      final cell = item.values[column.id];
      final labelId = cell is Map<String, dynamic> ? cell['labelId'] as String? : null;
      final isDone = column.statusLabels.any((l) => l.id == labelId && l.isDone);
      chip = Animate(
        // Re-keying restarts the effects each time the label changes.
        key: ValueKey('${column.id}:$labelId'),
        effects: [
          ScaleEffect(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: DfMotion.expressiveShort,
            curve: DfMotion.emphasize,
          ),
          if (isDone)
            ShimmerEffect(
              delay: DfMotion.productiveMedium,
              duration: DfMotion.expressiveLong,
              color: Colors.white.withValues(alpha: 0.6),
            ),
        ],
        child: chip,
      );
    }

    if (chip != null && tint != null) {
      chip = Container(
        key: ValueKey('cell-tint:${item.id}:${column.id}'),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: DfColors.token(tint!).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
        ),
        child: chip,
      );
    }

    return InkWell(
      onTap: enabled ? onEdit : null,
      borderRadius: BorderRadius.circular(6),
      child: chip ??
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark ? DfColors.borderDark : DfColors.border,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, size: 12, color: DfColors.textTertiary),
              const SizedBox(width: 2),
              Text(column.title, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
    );
  }
}

/// Indented list of a parent's subitems: name + chips over the board's
/// subitem columns. The parent screen owns navigation, editing and menus.
class SubitemRows extends StatelessWidget {
  const SubitemRows({
    super.key,
    required this.parent,
    required this.columns,
    required this.members,
    required this.accent,
    required this.canEdit,
    required this.onEditCell,
    required this.onOpen,
    required this.onMenu,
    this.onAdd,
  });

  final BoardItem parent;

  /// The board's subitem-scoped columns.
  final List<BoardColumn> columns;
  final List<BoardMember> members;
  final Color accent;
  final bool canEdit;
  final void Function(BoardItem subitem, BoardColumn column) onEditCell;
  final ValueChanged<BoardItem> onOpen;
  final ValueChanged<BoardItem> onMenu;

  /// "Add subitem" affordance; hidden when null.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(DfSpacing.lg, 0, DfSpacing.sm, DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
        borderRadius: BorderRadius.circular(DfRadius.sm),
        border: Border(left: BorderSide(color: accent.withValues(alpha: 0.5), width: 2)),
      ),
      child: Column(children: [
        for (final (index, sub) in parent.subitems.indexed) ...[
          if (index > 0) const Divider(height: 1),
          InkWell(
            key: ValueKey('subitem:${sub.id}'),
            onTap: () => onOpen(sub),
            onLongPress: canEdit ? () => onMenu(sub) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3, right: DfSpacing.xs),
                  child: Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: DfColors.textTertiary),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sub.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                    if (columns.isNotEmpty) ...[
                      const SizedBox(height: DfSpacing.xxs),
                      Wrap(spacing: DfSpacing.xxs, runSpacing: DfSpacing.xxs, children: [
                        for (final column in columns)
                          DfCellChip(
                            column: column,
                            item: sub,
                            members: members,
                            enabled: canEdit,
                            onEdit: () => onEditCell(sub, column),
                          ),
                      ]),
                    ],
                  ]),
                ),
                if (canEdit)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz_rounded, size: 18, color: DfColors.textTertiary),
                    onPressed: () => onMenu(sub),
                  ),
              ]),
            ),
          ),
        ],
        if (onAdd != null) ...[
          if (parent.subitems.isNotEmpty) const Divider(height: 1),
          InkWell(
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
              child: Row(children: [
                const Icon(Icons.add_rounded, size: 16, color: DfColors.textTertiary),
                const SizedBox(width: DfSpacing.xs),
                Text('Add subitem', style: text.bodySmall),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
