import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import 'view_engine.dart';

/// Footer under a group's items: one compact line per visible column that
/// has something to summarise (number sum, rating average, status battery,
/// checkbox count, distinct people, date range).
class SummaryFooter extends StatelessWidget {
  const SummaryFooter({super.key, required this.columns, required this.items});

  final List<BoardColumn> columns;
  final List<BoardItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final column in columns) {
      final summary = summarize(column, items);
      if (summary == null) continue;
      rows.add(_SummaryRow(column: column, summary: summary));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
        border: Border(top: BorderSide(color: isDark ? DfColors.borderDark : DfColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.column, required this.summary});

  final BoardColumn column;
  final ColumnSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelSmall;
    final Widget value = switch (summary) {
      NumberSummary(:final formatted, :final mode) => Text(
          '${_modeLabel(mode)} $formatted',
          style: text?.copyWith(fontWeight: FontWeight.w600),
        ),
      RatingSummary(:final formatted) => Text(formatted, style: text?.copyWith(fontWeight: FontWeight.w600)),
      CheckboxSummary(:final formatted) => Text(formatted, style: text?.copyWith(fontWeight: FontWeight.w600)),
      PeopleSummary(:final distinct) =>
        Text(distinct == 1 ? '1 person' : '$distinct people', style: text?.copyWith(fontWeight: FontWeight.w600)),
      DateRangeSummary(:final formatted) => Text(formatted, style: text?.copyWith(fontWeight: FontWeight.w600)),
      StatusSummary() => StatusBattery(column: column, summary: summary as StatusSummary),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(column.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
        ),
        const SizedBox(width: DfSpacing.xs),
        Expanded(
          child: summary is StatusSummary ? value : Align(alignment: Alignment.centerLeft, child: value),
        ),
      ]),
    );
  }

  String _modeLabel(String mode) => switch (mode) {
        'avg' => 'avg',
        'min' => 'min',
        'max' => 'max',
        'count' => '#',
        _ => 'Σ',
      };
}

/// Thin bar of label colours proportional to counts, with the done count.
class StatusBattery extends StatelessWidget {
  const StatusBattery({super.key, required this.column, required this.summary});

  final BoardColumn column;
  final StatusSummary summary;

  @override
  Widget build(BuildContext context) {
    final labels = column.statusLabels;
    final labelled = summary.counts.values.fold<int>(0, (s, c) => s + c);
    final unlabelled = summary.total - labelled;
    final done = summary.counts.entries
        .where((e) => labels.any((l) => l.id == e.key && l.isDone))
        .fold<int>(0, (s, e) => s + e.value);
    final text = Theme.of(context).textTheme.labelSmall;

    return Tooltip(
      message: [
        for (final entry in summary.counts.entries)
          '${labels.where((l) => l.id == entry.key).firstOrNull?.label ?? entry.key}: ${entry.value}',
        if (unlabelled > 0) 'No status: $unlabelled',
      ].join('\n'),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                for (final entry in summary.counts.entries)
                  Expanded(
                    flex: entry.value,
                    child: Container(
                      color: DfColors.token(labels.where((l) => l.id == entry.key).firstOrNull?.color ?? 'grey'),
                    ),
                  ),
                if (unlabelled > 0)
                  Expanded(
                    flex: unlabelled,
                    child: Container(color: DfColors.statusGrey.withValues(alpha: 0.5)),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: DfSpacing.xs),
        Text('$done/${summary.total} done', style: text?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
