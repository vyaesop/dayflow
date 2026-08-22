import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import 'home_providers.dart';

/// Home tab: greeting, setup progress, favorites, recently visited, workspaces.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final me = auth is SignedIn ? auth.me : null;
    final overview = ref.watch(homeOverviewProvider);
    final workspaces = ref.watch(workspacesProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: DfSpacing.md,
        centerTitle: false,
        title: Row(children: [
          if (me != null)
            GestureDetector(
              onTap: () => _showAccountSwitcher(context, ref, me),
              child: DfAvatar(name: me.account.name, seed: me.account.id, size: 32),
            ),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_greeting(), style: Theme.of(context).textTheme.labelMedium),
                Text(
                  me?.firstName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeOverviewProvider);
          ref.invalidate(workspacesProvider);
          await Future.wait([
            ref.read(homeOverviewProvider.future),
            ref.read(workspacesProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            overview.when(
              loading: () => const _HomeSkeleton(),
              error: (error, _) => _ErrorTile(
                message: '$error',
                onRetry: () => ref.invalidate(homeOverviewProvider),
              ),
              // Sections cascade in with the Vibe expressive enter, the way
              // the monday app greets a fresh Home.
              data: (data) => Column(children: [
                if (data.setupPercent < 100)
                  _SetupCard(overview: data)
                      .animate()
                      .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                      .slideY(begin: 0.05, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                _FavoritesSection(favorites: data.favorites)
                    .animate(delay: DfMotion.staggerStep * 2)
                    .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                    .slideY(begin: 0.05, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                if (data.recentlyVisited.isNotEmpty)
                  _RecentSection(boards: data.recentlyVisited)
                      .animate(delay: DfMotion.staggerStep * 4)
                      .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter)
                      .slideY(begin: 0.05, end: 0, duration: DfMotion.expressiveShort, curve: DfMotion.enter),
              ]),
            ),
            workspaces.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (list) => _WorkspacesSection(workspaces: list),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  void _showAccountSwitcher(BuildContext context, WidgetRef ref, Me me) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: DfSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: DfSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Your accounts', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          const SizedBox(height: DfSpacing.xs),
          for (final account in me.accounts)
            ListTile(
              leading: DfAvatar(name: account.name, seed: account.id, size: 36),
              title: Text(account.name),
              subtitle: Text(account.role),
              trailing: account.id == me.account.id
                  ? const Icon(Icons.check_circle_rounded, color: DfColors.primary)
                  : null,
                  onTap: account.id == me.account.id
                  ? () => Navigator.pop(sheetContext)
                  : () async {
                      Navigator.pop(sheetContext);
                      await ref.read(authControllerProvider.notifier).switchAccount(account.id);
                      ref.invalidate(homeOverviewProvider);
                      ref.invalidate(workspacesProvider);
                    },
            ),
          const SizedBox(height: DfSpacing.sm),
        ]),
      ),
    );
  }
}

class _SetupCard extends ConsumerWidget {
  const _SetupCard({required this.overview});

  final HomeOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.xs, DfSpacing.md, DfSpacing.md),
      child: DfCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DfProgressRing(percent: overview.setupPercent),
            const SizedBox(width: DfSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finish setting up', style: text.titleMedium),
                Text('A few steps to get the most out of Dayflow', style: text.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: DfSpacing.md),
          for (final step in overview.setupSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: DfSpacing.xs),
              child: Row(children: [
                Icon(
                  step.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: step.done ? DfColors.success : DfColors.textTertiary,
                ),
                const SizedBox(width: DfSpacing.xs),
                Expanded(
                  child: Text(
                    step.label,
                    style: step.done
                        ? text.bodyMedium?.copyWith(
                            color: DfColors.textTertiary,
                            decoration: TextDecoration.lineThrough,
                          )
                        : text.bodyMedium,
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection({required this.favorites});

  final List<BoardSummary> favorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.star_rounded, size: 20, color: DfColors.accentAmber),
          const SizedBox(width: DfSpacing.xxs),
          Text('Favorites', style: text.titleMedium),
        ]),
        const SizedBox(height: DfSpacing.xs),
        if (favorites.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: DfSpacing.xl, horizontal: DfSpacing.md),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DfColors.heroGradientStart, DfColors.heroGradientEnd],
              ),
              borderRadius: BorderRadius.circular(DfRadius.lg),
            ),
            child: Column(children: [
              const Icon(Icons.star_border_rounded, color: Colors.white, size: 30),
              const SizedBox(height: DfSpacing.xs),
              Text(
                'Star the boards you use most',
                style: text.titleMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: DfSpacing.xxs),
              Text(
                'They will show up right here for quick access',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Colors.white70),
              ),
            ]),
          )
        else
          for (final board in favorites) _BoardTile(board: board),
      ]),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.boards});

  final List<BoardSummary> boards;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history_rounded, size: 20, color: DfColors.textSecondary),
          const SizedBox(width: DfSpacing.xxs),
          Text('Recently visited', style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: DfSpacing.xs),
        for (final board in boards) _BoardTile(board: board),
      ]),
    );
  }
}

class _WorkspacesSection extends StatelessWidget {
  const _WorkspacesSection({required this.workspaces});

  final List<WorkspaceSummary> workspaces;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspaces_outlined, size: 20, color: DfColors.textSecondary),
          const SizedBox(width: DfSpacing.xxs),
          Text('Workspaces', style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: DfSpacing.xs),
        for (final workspace in workspaces) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DfSpacing.xxs),
            child: Text(workspace.name, style: Theme.of(context).textTheme.labelMedium),
          ),
          for (final board in workspace.boards) _BoardTile(board: board),
        ],
      ]),
    );
  }
}

class _BoardTile extends ConsumerStatefulWidget {
  const _BoardTile({required this.board});

  final BoardSummary board;

  @override
  ConsumerState<_BoardTile> createState() => _BoardTileState();
}

class _BoardTileState extends ConsumerState<_BoardTile> {
  late bool _favorite = widget.board.isFavorite;

  @override
  void didUpdateWidget(covariant _BoardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.board.isFavorite != oldWidget.board.isFavorite) {
      _favorite = widget.board.isFavorite;
    }
  }

  Future<void> _toggle() async {
    setState(() => _favorite = !_favorite);
    try {
      final result = await toggleBoardFavorite(widget.board.id);
      if (mounted) setState(() => _favorite = result);
      ref.invalidate(homeOverviewProvider);
      ref.invalidate(workspacesProvider);
    } catch (_) {
      if (mounted) setState(() => _favorite = !_favorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DfSpacing.xs),
      child: DfCard(
        padding: const EdgeInsets.all(DfSpacing.sm),
        onTap: () => context.push('/boards/${widget.board.id}'),
        child: Row(children: [
          const DfBoardGlyph(),
          const SizedBox(width: DfSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                widget.board.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.board.workspaceName.isNotEmpty)
                Text(widget.board.workspaceName, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _favorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _favorite ? DfColors.accentAmber : DfColors.textTertiary,
              size: 22,
            ),
            tooltip: _favorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: _toggle,
          ),
        ]),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(DfSpacing.md),
      child: Column(
        children: List.generate(
          4,
          (i) => Container(
            height: i == 0 ? 150 : 64,
            margin: const EdgeInsets.only(bottom: DfSpacing.sm),
            decoration: BoxDecoration(
              color: isDark ? DfColors.surfaceDark : DfColors.surfaceAlt,
              borderRadius: BorderRadius.circular(DfRadius.lg),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DfSpacing.md),
      child: DfCard(
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded, color: DfColors.textTertiary, size: 28),
          const SizedBox(height: DfSpacing.xs),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: DfSpacing.sm),
          DfButton(label: 'Try again', variant: DfButtonVariant.tonal, expand: false, onPressed: onRetry),
        ]),
      ),
    );
  }
}
