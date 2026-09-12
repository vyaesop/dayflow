import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'board_controller.dart';
import 'view_engine.dart';

/// Month calendar over a board's date (or timeline) column.
///
/// With a [viewId] the saved view's filters apply and its `dateColumnId`
/// picks the column; changing the column is written back to the view.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, required this.boardId, this.viewId});

  final String boardId;
  final String? viewId;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  String? _dateColumnId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(boardControllerProvider(widget.boardId));
    final controller = ref.read(boardControllerProvider(widget.boardId).notifier);
    final auth = ref.watch(authControllerProvider);
    final meUserId = auth is SignedIn ? auth.me.id : null;
    final text = Theme.of(context).textTheme;

    final board = state.value;
    final view = board?.views.where((v) => v.id == widget.viewId).firstOrNull;
    final config = view == null ? const ViewConfig.empty() : ViewConfig.fromJson(view.config);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.pop()),
        centerTitle: false,
        titleSpacing: 0,
        title: state.maybeWhen(
          data: (board) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(board.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(view?.name ?? 'Calendar', style: text.labelSmall),
            ],
          ),
          orElse: () => const Text('Calendar'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_rows_outlined),
            tooltip: 'Table view',
            onPressed: () => context.pushReplacement('/boards/${widget.boardId}'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$error', style: text.bodySmall),
            const SizedBox(height: DfSpacing.md),
            DfButton(
              label: 'Try again',
              variant: DfButtonVariant.tonal,
              expand: false,
              onPressed: () => ref.invalidate(boardControllerProvider(widget.boardId)),
            ),
          ]),
        ),
        data: (board) {
          final dateColumns = board.itemColumns.where((c) => c.type == 'date' || c.type == 'timeline').toList();
          if (dateColumns.isEmpty) return _NoDateColumn(boardId: widget.boardId);
          final wantedId = _dateColumnId ?? config.dateColumnId;
          final dateColumn = dateColumns.firstWhere(
            (c) => c.id == wantedId,
            orElse: () => dateColumns.firstWhere((c) => c.type == 'date', orElse: () => dateColumns.first),
          );

          // date (yyyy-MM-dd) → items due that day, with their group color.
          // Subitems ride inside their parents and are not placed.
          final groups = applyView(board, config, ViewContext.forBoard(board, meUserId: meUserId));
          final byDay = <String, List<(BoardItem, String)>>{};
          for (final group in groups) {
            for (final item in group.items) {
              final cell = item.values[dateColumn.id];
              final raw = cell is Map<String, dynamic>
                  ? (dateColumn.type == 'timeline' ? cell['from'] : cell['date']) as String?
                  : null;
              if (raw == null) continue;
              byDay.putIfAbsent(raw, () => []).add((item, group.color));
            }
          }

          final selectedKey =
              _selectedDay == null ? null : DateFormat('yyyy-MM-dd').format(_selectedDay!);
          final dayItems = selectedKey == null ? const <(BoardItem, String)>[] : byDay[selectedKey] ?? const [];

          return Column(children: [
            if (dateColumns.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xs, DfSpacing.md, 0),
                child: Row(children: [
                  Text('Dates from', style: text.labelMedium),
                  const SizedBox(width: DfSpacing.xs),
                  DropdownButton<String>(
                    value: dateColumn.id,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final column in dateColumns)
                        DropdownMenuItem(value: column.id, child: Text(column.title)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _dateColumnId = value);
                      if (view != null && board.canEdit) {
                        _persist(controller, view, config.copyWith(dateColumnId: () => value));
                      }
                    },
                  ),
                ]),
              ),
            _MonthHeader(
              month: _month,
              onPrevious: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              onToday: () => setState(() {
                _month = DateTime(DateTime.now().year, DateTime.now().month);
                _selectedDay = DateTime.now();
              }),
            ),
            _MonthGrid(
              month: _month,
              byDay: byDay,
              selectedDay: _selectedDay,
              onSelect: (day) => setState(() => _selectedDay = day),
            ),
            const Divider(height: 1),
            Expanded(
              child: _selectedDay == null
                  ? Center(child: Text('Select a day to see its items', style: text.bodySmall))
                  : dayItems.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing due ${DateFormat.MMMd().format(_selectedDay!)}',
                            style: text.bodySmall,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(DfSpacing.md),
                          children: [
                            for (final (index, entry) in dayItems.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                                child: DfCard(
                                  padding: const EdgeInsets.all(DfSpacing.sm),
                                  onTap: () => context.push('/items/${entry.$1.id}'),
                                  child: Row(children: [
                                    Container(
                                      width: 3,
                                      height: 30,
                                      margin: const EdgeInsets.only(right: DfSpacing.xs),
                                      decoration: BoxDecoration(
                                        color: DfColors.token(entry.$2),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        entry.$1.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodyMedium,
                                      ),
                                    ),
                                  ]),
                                ),
                              )
                                  .animate(delay: DfMotion.staggerStep * index)
                                  .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                                  .slideY(
                                    begin: 0.08,
                                    end: 0,
                                    duration: DfMotion.expressiveShort,
                                    curve: DfMotion.enter,
                                  ),
                          ],
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _persist(BoardController controller, BoardView view, ViewConfig config) async {
    try {
      await controller.updateViewConfig(view.id, config.toJson());
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
      child: Row(children: [
        Text(DateFormat.yMMMM().format(month), style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton(onPressed: onToday, child: const Text('Today')),
        IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: onPrevious),
        IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: onNext),
      ]),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.byDay,
    required this.selectedDay,
    required this.onSelect,
  });

  final DateTime month;
  final Map<String, List<(BoardItem, String)>> byDay;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final firstDay = DateTime(month.year, month.month, 1);
    // Weeks start on Sunday, as in the design's calendar.
    final leading = firstDay.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm),
      child: Column(children: [
        Row(children: [
          for (final label in const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'])
            Expanded(child: Center(child: Text(label, style: text.labelSmall))),
        ]),
        const SizedBox(height: DfSpacing.xxs),
        for (var week = 0; week < ((leading + daysInMonth + 6) ~/ 7); week++)
          Row(children: [
            for (var weekday = 0; weekday < 7; weekday++)
              Expanded(
                child: Builder(builder: (context) {
                  final dayNumber = week * 7 + weekday - leading + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox(height: 44);
                  final day = DateTime(month.year, month.month, dayNumber);
                  final key = DateFormat('yyyy-MM-dd').format(day);
                  final entries = byDay[key] ?? const [];
                  final isToday =
                      day.year == today.year && day.month == today.month && day.day == today.day;
                  final isSelected = selectedDay != null &&
                      day.year == selectedDay!.year &&
                      day.month == selectedDay!.month &&
                      day.day == selectedDay!.day;

                  return InkWell(
                    onTap: () => onSelect(day),
                    borderRadius: BorderRadius.circular(DfRadius.sm),
                    child: AnimatedContainer(
                      duration: DfMotion.productiveLong,
                      curve: DfMotion.transition,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected ? DfColors.primary.withValues(alpha: 0.15) : null,
                        borderRadius: BorderRadius.circular(DfRadius.sm),
                        border: isToday ? Border.all(color: DfColors.primary) : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(
                          '$dayNumber',
                          style: text.bodySmall?.copyWith(
                            fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected ? DfColors.primary : null,
                          ),
                        ),
                        SizedBox(
                          height: 6,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (final entry in entries.take(3))
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: DfColors.token(entry.$2),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
          ]),
        const SizedBox(height: DfSpacing.xs),
      ]),
    );
  }
}

class _NoDateColumn extends StatelessWidget {
  const _NoDateColumn({required this.boardId});

  final String boardId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_month_outlined, size: 34, color: DfColors.textTertiary),
          const SizedBox(height: DfSpacing.sm),
          Text('No date column', style: text.titleMedium),
          const SizedBox(height: DfSpacing.xxs),
          Text(
            'The calendar places items by their date column.\nAdd one on the table view to use this.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: DfSpacing.md),
          DfButton(
            label: 'Back to table',
            variant: DfButtonVariant.tonal,
            expand: false,
            onPressed: () => context.pushReplacement('/boards/$boardId'),
          ),
        ]),
      ),
    );
  }
}
