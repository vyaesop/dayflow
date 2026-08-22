import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../home/home_providers.dart';

/// Whether completed items are shown ("Hide done items" chip toggles this).
final myWorkShowDoneProvider = StateProvider<bool>((ref) => false);

/// Board ids hidden from My Work; empty set means every board is visible.
final myWorkHiddenBoardsProvider = StateProvider<Set<String>>((ref) => {});

final myWorkProvider = FutureProvider.autoDispose<MyWork>((ref) async {
  final includeDone = ref.watch(myWorkShowDoneProvider);
  return MyWork.fromJson(
    await ApiClient.instance.get('/my-work', query: {'includeDone': '$includeDone'}),
  );
});

/// Everything assigned to me across every board, bucketed by due date, with
/// the design's "Hide done items" and visible-boards filters.
class MyWorkScreen extends ConsumerWidget {
  const MyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myWorkProvider);
    final showDone = ref.watch(myWorkShowDoneProvider);
    final hiddenBoards = ref.watch(myWorkHiddenBoardsProvider);
    final text = Theme.of(context).textTheme;

    List<MyWorkItem> visible(List<MyWorkItem> bucket) =>
        bucket.where((i) => !hiddenBoards.contains(i.boardId)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My work'),
        centerTitle: false,
        titleSpacing: DfSpacing.md,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: DfSpacing.xs, bottom: DfSpacing.xs),
                  child: _ToggleChip(
                    label: showDone ? 'Showing done items' : 'Hide done items',
                    selected: !showDone,
                    onTap: () => ref.read(myWorkShowDoneProvider.notifier).state = !showDone,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: DfSpacing.xs, bottom: DfSpacing.xs),
                  child: _ToggleChip(
                    label: hiddenBoards.isEmpty ? 'Boards' : 'Boards (filtered)',
                    selected: hiddenBoards.isNotEmpty,
                    icon: Icons.grid_view_rounded,
                    onTap: () => _pickVisibleBoards(context, ref),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(DfSpacing.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 30, color: DfColors.textTertiary),
              const SizedBox(height: DfSpacing.sm),
              Text('$error', textAlign: TextAlign.center, style: text.bodySmall),
              const SizedBox(height: DfSpacing.md),
              DfButton(
                label: 'Try again',
                variant: DfButtonVariant.tonal,
                expand: false,
                onPressed: () => ref.invalidate(myWorkProvider),
              ),
            ]),
          ),
        ),
        data: (work) {
          final buckets = [
            (title: 'Overdue', items: visible(work.overdue), accent: DfColors.danger),
            (title: 'Today', items: visible(work.today), accent: DfColors.primary),
            (title: 'This week', items: visible(work.thisWeek), accent: DfColors.accentBlue),
            (title: 'Later', items: visible(work.later), accent: DfColors.textSecondary),
            (title: 'No date', items: visible(work.noDate), accent: DfColors.textTertiary),
            if (showDone) (title: 'Done', items: visible(work.done), accent: DfColors.success),
          ];
          final isEmpty = buckets.every((b) => b.items.isEmpty);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myWorkProvider);
              await ref.read(myWorkProvider.future);
            },
            child: isEmpty
                ? _EmptyMyWork(doneCount: work.doneCount, filtered: hiddenBoards.isNotEmpty)
                : ListView(
                    padding: const EdgeInsets.only(bottom: DfSpacing.xxl),
                    children: [
                      for (final bucket in buckets)
                        _Bucket(title: bucket.title, items: bucket.items, accent: bucket.accent),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _pickVisibleBoards(BuildContext context, WidgetRef ref) async {
    final workspaces = await ref.read(workspacesProvider.future).catchError((Object _) => <WorkspaceSummary>[]);
    if (!context.mounted) return;
    final boards = workspaces.expand((w) => w.boards).toList();
    final hidden = {...ref.read(myWorkHiddenBoardsProvider)};

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(DfSpacing.md),
              child: Row(children: [
                Text('Visible boards', style: Theme.of(sheetContext).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ref.read(myWorkHiddenBoardsProvider.notifier).state = hidden;
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final board in boards)
                    CheckboxListTile(
                      value: !hidden.contains(board.id),
                      onChanged: (checked) => setSheetState(() {
                        if (checked == false) {
                          hidden.add(board.id);
                        } else {
                          hidden.remove(board.id);
                        }
                      }),
                      title: Text(board.name),
                      subtitle: Text(board.workspaceName),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
            const SizedBox(height: DfSpacing.sm),
          ]),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.selected, required this.onTap, this.icon});

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

class _Bucket extends StatelessWidget {
  const _Bucket({required this.title, required this.items, required this.accent});

  final String title;
  final List<MyWorkItem> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          const SizedBox(width: DfSpacing.xs),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: DfSpacing.xs),
          Text('${items.length}', style: Theme.of(context).textTheme.labelSmall),
        ]),
        const SizedBox(height: DfSpacing.xs),
        for (final (index, item) in items.indexed)
          _MyWorkTile(item: item)
              .animate(delay: DfMotion.staggerStep * (index.clamp(0, 8)))
              .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
              .slideY(begin: 0.06, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
      ]),
    );
  }
}

class _MyWorkTile extends StatelessWidget {
  const _MyWorkTile({required this.item});

  final MyWorkItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        onTap: () => context.push('/items/${item.id}'),
        child: Row(children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: DfSpacing.xs),
            decoration: BoxDecoration(
              color: DfColors.token(item.groupColor),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              const SizedBox(height: 2),
              Text('${item.boardName} · ${item.groupTitle}', style: text.labelSmall),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (item.statusLabel != null)
              DfStatusPill(label: item.statusLabel!, colorToken: item.statusColor ?? 'grey', height: 22),
            if (item.date != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(DateFormat.MMMd().format(item.date!), style: text.labelSmall),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _EmptyMyWork extends StatelessWidget {
  const _EmptyMyWork({required this.doneCount, required this.filtered});

  final int doneCount;
  final bool filtered;

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
                  filtered ? Icons.filter_alt_off_outlined : Icons.thumb_up_alt_outlined,
                  size: 34,
                  color: DfColors.primary,
                ),
              ),
              const SizedBox(height: DfSpacing.md),
              Text(
                filtered ? 'Nothing on the visible boards' : 'Well done!\nYou don\'t have any items here.',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: DfSpacing.xxs),
              Text(
                filtered
                    ? 'Adjust the boards filter to see more.'
                    : doneCount > 0
                        ? "You've completed $doneCount item(s).\nFor items to appear here, you need a People column\nin the relevant boards."
                        : 'For items to appear in My Work, you need a People\ncolumn in the relevant boards.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ])
                .animate()
                .fadeIn(duration: DfMotion.expressiveLong, curve: DfMotion.enter)
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1, 1),
                  duration: DfMotion.expressiveLong,
                  curve: DfMotion.emphasize,
                ),
          ),
        ),
      ],
    );
  }
}
