import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'board_controller.dart';
import 'dashboard_data.dart';
import 'view_engine.dart' show ViewConfig, ViewContext, applyView;

/// Dashboard view: at-a-glance widgets computed from the live board —
/// counts, status battery, items per group, number totals, upcoming dates.
///
/// With a [viewId] the saved view's filters narrow what is charted.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.boardId, this.viewId});

  final String boardId;
  final String? viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(boardControllerProvider(boardId));
    final auth = ref.watch(authControllerProvider);
    final meUserId = auth is SignedIn ? auth.me.id : null;
    final text = Theme.of(context).textTheme;
    final view = state.value?.views.where((v) => v.id == viewId).firstOrNull;

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
              Text(view?.name ?? 'Dashboard', style: text.labelSmall),
            ],
          ),
          orElse: () => const Text('Dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_rows_outlined),
            tooltip: 'Table view',
            onPressed: () => context.pushReplacement('/boards/$boardId'),
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
              onPressed: () => ref.invalidate(boardControllerProvider(boardId)),
            ),
          ]),
        ),
        data: (board) {
          // Top-level items only (subitems stay nested); the view's filters apply.
          final config = view == null ? const ViewConfig.empty() : ViewConfig.fromJson(view.config);
          final scoped = config.hasFilters
              ? board.copyWith(groups: applyView(board, config, ViewContext.forBoard(board, meUserId: meUserId)))
              : board;
          final data = computeDashboard(scoped);
          if (data.itemCount == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(DfSpacing.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.insert_chart_outlined_rounded, size: 40, color: DfColors.textTertiary),
                  const SizedBox(height: DfSpacing.sm),
                  Text('Nothing to chart yet', style: text.titleMedium),
                  const SizedBox(height: DfSpacing.xxs),
                  Text('Add items to the board and this dashboard fills itself in.',
                      style: text.bodySmall, textAlign: TextAlign.center),
                ]),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(DfSpacing.md),
            children: [
              _StatRow(data: data),
              if (data.statusSlices.isNotEmpty) ...[
                const SizedBox(height: DfSpacing.md),
                _StatusBattery(data: data),
              ],
              if (data.groupSlices.length > 1) ...[
                const SizedBox(height: DfSpacing.md),
                _GroupChart(slices: data.groupSlices),
              ],
              if (data.numberSummaries.isNotEmpty) ...[
                const SizedBox(height: DfSpacing.md),
                _NumbersCard(summaries: data.numberSummaries),
              ],
              const SizedBox(height: DfSpacing.md),
              _UpcomingCard(upcoming: data.upcoming),
              const SizedBox(height: DfSpacing.lg),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _StatTile(label: 'Items', value: '${data.itemCount}')),
      const SizedBox(width: DfSpacing.xs),
      Expanded(
        child: _StatTile(
          label: 'Done',
          value: '${(data.donePercent * 100).round()}%',
          caption: '${data.doneCount} of ${data.itemCount}',
        ),
      ),
      const SizedBox(width: DfSpacing.xs),
      Expanded(
        child: _StatTile(
          label: 'Overdue',
          value: '${data.overdueCount}',
          emphasize: data.overdueCount > 0,
        ),
      ),
    ]);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.caption, this.emphasize = false});

  final String label;
  final String value;
  final String? caption;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: text.labelSmall),
        const SizedBox(height: DfSpacing.xxs),
        Text(
          value,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasize ? DfColors.token('red') : null,
          ),
        ),
        if (caption != null) Text(caption!, style: text.labelSmall),
      ]),
    );
  }
}

class _StatusBattery extends StatelessWidget {
  const _StatusBattery({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Status', style: text.titleSmall),
        const SizedBox(height: DfSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(children: [
              for (final slice in data.statusSlices)
                Expanded(
                  flex: slice.count,
                  child: Container(color: DfColors.token(slice.colorToken)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: DfSpacing.sm),
        Wrap(
          spacing: DfSpacing.sm,
          runSpacing: DfSpacing.xxs,
          children: [
            for (final slice in data.statusSlices)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: DfColors.token(slice.colorToken),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: DfSpacing.xxs),
                Text('${slice.label} · ${slice.count}', style: text.labelSmall),
              ]),
          ],
        ),
      ]),
    );
  }
}

class _GroupChart extends StatelessWidget {
  const _GroupChart({required this.slices});

  final List<GroupSlice> slices;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final max = slices.fold<int>(1, (m, s) => s.count > m ? s.count : m);
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Items per group', style: text.titleSmall),
        const SizedBox(height: DfSpacing.sm),
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: DfSpacing.xs),
            child: Row(children: [
              SizedBox(
                width: 110,
                child: Text(slice.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              ),
              const SizedBox(width: DfSpacing.xs),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: slice.count / max,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: DfColors.token(slice.colorToken),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: DfSpacing.xs),
              SizedBox(
                width: 28,
                child: Text('${slice.count}', textAlign: TextAlign.end, style: text.labelSmall),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({required this.summaries});

  final List<NumberSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final format = NumberFormat.decimalPattern();
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Numbers', style: text.titleSmall),
        const SizedBox(height: DfSpacing.sm),
        for (final summary in summaries)
          Padding(
            padding: const EdgeInsets.only(bottom: DfSpacing.xs),
            child: Row(children: [
              Expanded(child: Text(summary.title, style: text.bodyMedium)),
              Text('Σ ${format.format(summary.sum)}', style: text.titleSmall),
              const SizedBox(width: DfSpacing.sm),
              Text(
                summary.count == 0 ? '—' : 'avg ${format.format(double.parse(summary.average.toStringAsFixed(1)))}',
                style: text.labelSmall,
              ),
            ]),
          ),
      ]),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.upcoming});

  final List<UpcomingItem> upcoming;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DfCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Coming up', style: text.titleSmall),
        const SizedBox(height: DfSpacing.sm),
        if (upcoming.isEmpty)
          Text('Nothing scheduled — items with a date land here.', style: text.bodySmall)
        else
          for (final entry in upcoming)
            InkWell(
              onTap: () => context.push('/items/${entry.itemId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: DfSpacing.xxs),
                child: Row(children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: DfColors.token(entry.groupColorToken),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: DfSpacing.sm),
                  Expanded(
                    child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                  ),
                  Text(DateFormat.MMMd().format(entry.date), style: text.labelSmall),
                ]),
              ),
            ),
      ]),
    );
  }
}
