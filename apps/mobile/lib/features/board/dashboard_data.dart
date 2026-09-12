import '../../core/models/models.dart';

/// Pure aggregations behind the board Dashboard view (unit-tested; no widgets).

class StatusSlice {
  const StatusSlice({required this.label, required this.colorToken, required this.count, required this.isDone});

  final String label;
  final String colorToken;
  final int count;
  final bool isDone;
}

class NumberSummary {
  const NumberSummary({required this.columnId, required this.title, required this.sum, required this.count});

  final String columnId;
  final String title;
  final double sum;

  /// Items with a value in this column (average denominator).
  final int count;

  double get average => count == 0 ? 0 : sum / count;
}

class GroupSlice {
  const GroupSlice({required this.title, required this.colorToken, required this.count});

  final String title;
  final String colorToken;
  final int count;
}

class UpcomingItem {
  const UpcomingItem({required this.itemId, required this.name, required this.date, required this.groupColorToken});

  final String itemId;
  final String name;
  final DateTime date;
  final String groupColorToken;
}

class DashboardData {
  const DashboardData({
    required this.itemCount,
    required this.doneCount,
    required this.overdueCount,
    required this.statusSlices,
    required this.groupSlices,
    required this.numberSummaries,
    required this.upcoming,
  });

  final int itemCount;
  final int doneCount;
  final int overdueCount;

  /// Status distribution, largest first, with a trailing "No status" bucket.
  final List<StatusSlice> statusSlices;

  /// Items per group, in board order.
  final List<GroupSlice> groupSlices;

  /// One summary per number column, in column order.
  final List<NumberSummary> numberSummaries;

  /// Not-done items dated today or later, soonest first.
  final List<UpcomingItem> upcoming;

  double get donePercent => itemCount == 0 ? 0 : doneCount / itemCount;
}

DashboardData computeDashboard(BoardDetail board, {DateTime? now, int upcomingLimit = 6}) {
  final today = _dateOnly(now ?? DateTime.now());

  final statusColumn = board.columns.where((c) => c.type == 'status').firstOrNull;
  final dateColumn = board.columns.where((c) => c.type == 'date').firstOrNull;
  final numberColumns = board.columns.where((c) => c.type == 'number').toList();

  final labels = statusColumn?.statusLabels ?? const <StatusLabel>[];
  final doneLabelIds = labels.where((l) => l.isDone).map((l) => l.id).toSet();
  final countsByLabel = <String, int>{};

  var itemCount = 0;
  var doneCount = 0;
  var overdueCount = 0;
  var unlabeled = 0;
  final sums = {for (final c in numberColumns) c.id: 0.0};
  final valueCounts = {for (final c in numberColumns) c.id: 0};
  final upcoming = <UpcomingItem>[];

  for (final group in board.groups) {
    for (final item in group.items) {
      itemCount += 1;

      String? labelId;
      if (statusColumn != null) {
        final cell = item.values[statusColumn.id];
        labelId = cell is Map<String, dynamic> ? cell['labelId'] as String? : null;
      }
      final isDone = labelId != null && doneLabelIds.contains(labelId);
      if (isDone) doneCount += 1;
      if (labelId != null) {
        countsByLabel[labelId] = (countsByLabel[labelId] ?? 0) + 1;
      } else if (statusColumn != null) {
        unlabeled += 1;
      }

      for (final column in numberColumns) {
        final cell = item.values[column.id];
        final number = cell is Map<String, dynamic> ? cell['number'] : null;
        if (number is num) {
          sums[column.id] = sums[column.id]! + number.toDouble();
          valueCounts[column.id] = valueCounts[column.id]! + 1;
        }
      }

      if (dateColumn != null && !isDone) {
        final cell = item.values[dateColumn.id];
        final raw = cell is Map<String, dynamic> ? cell['date'] as String? : null;
        final due = raw == null ? null : DateTime.tryParse(raw);
        if (due != null) {
          final day = _dateOnly(due);
          if (day.isBefore(today)) {
            overdueCount += 1;
          } else {
            upcoming.add(UpcomingItem(
              itemId: item.id,
              name: item.name,
              date: day,
              groupColorToken: group.color,
            ));
          }
        }
      }
    }
  }

  final statusSlices = <StatusSlice>[
    for (final label in labels)
      if ((countsByLabel[label.id] ?? 0) > 0)
        StatusSlice(
          label: label.label,
          colorToken: label.color,
          count: countsByLabel[label.id]!,
          isDone: label.isDone,
        ),
  ]..sort((a, b) => b.count.compareTo(a.count));
  if (unlabeled > 0) {
    statusSlices.add(StatusSlice(label: 'No status', colorToken: 'grey', count: unlabeled, isDone: false));
  }

  upcoming.sort((a, b) => a.date.compareTo(b.date));

  return DashboardData(
    itemCount: itemCount,
    doneCount: doneCount,
    overdueCount: overdueCount,
    statusSlices: statusSlices,
    groupSlices: [
      for (final group in board.groups)
        GroupSlice(title: group.title, colorToken: group.color, count: group.items.length),
    ],
    numberSummaries: [
      for (final column in numberColumns)
        NumberSummary(
          columnId: column.id,
          title: column.title,
          sum: sums[column.id]!,
          count: valueCounts[column.id]!,
        ),
    ],
    upcoming: upcoming.take(upcomingLimit).toList(),
  );
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
