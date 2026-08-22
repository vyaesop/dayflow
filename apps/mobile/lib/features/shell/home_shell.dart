import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';

/// Bottom-tab shell: Home · My Work · Notifications · More, with the global FAB.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: navigationShell,
      floatingActionButton: navigationShell.currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => _showCreateSheet(context),
              backgroundColor: DfColors.primary,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? DfColors.surfaceDark : Colors.white,
          border: Border(top: BorderSide(color: isDark ? DfColors.borderDark : DfColors.border)),
        ),
        child: NavigationBar(
          height: 64,
          backgroundColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          selectedIndex: navigationShell.currentIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: DfColors.primary),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.work_outline_rounded),
              selectedIcon: Icon(Icons.work_rounded, color: DfColors.primary),
              label: 'My work',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded, color: DfColors.primary),
              label: 'Notifications',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.more_horiz_rounded, color: DfColors.primary),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DfSpacing.sm),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: DfSpacing.sm),
              decoration: BoxDecoration(
                color: DfColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined, color: DfColors.primary),
              title: const Text('New board'),
              subtitle: const Text('Start from scratch or use a template'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/boards-new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded, color: DfColors.primary),
              title: const Text('Search'),
              subtitle: const Text('Find a board or item by name'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/search');
              },
            ),
          ]),
        ),
      ),
    );
  }
}
