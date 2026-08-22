import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../item/update_card.dart' show relativeTime;

class NotificationFeed {
  const NotificationFeed({required this.items, required this.unreadCount});

  final List<AppNotification> items;
  final int unreadCount;
}

final notificationsProvider = FutureProvider.autoDispose<NotificationFeed>((ref) async {
  final json = await ApiClient.instance.get('/notifications');
  return NotificationFeed(
    items: (json['notifications'] as List<dynamic>? ?? const [])
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList(),
    unreadCount: json['unreadCount'] as int? ?? 0,
  );
});

enum _Filter {
  all('All'),
  unread('Unread'),
  mentioned('I was mentioned'),
  assigned('Assigned to me');

  const _Filter(this.label);
  final String label;

  bool matches(AppNotification notification) => switch (this) {
        _Filter.all => true,
        _Filter.unread => !notification.isRead,
        _Filter.mentioned => notification.type == 'mention' || notification.type == 'reply',
        _Filter.assigned => notification.type == 'assigned',
      };
}

/// Notification center with the design's filter tabs and in-feed search.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<AppNotification> _visible(List<AppNotification> items) {
    final query = _query.text.trim().toLowerCase();
    return items.where((n) {
      if (!_filter.matches(n)) return false;
      if (query.isEmpty) return true;
      return n.headline.toLowerCase().contains(query) ||
          (n.snippet?.toLowerCase().contains(query) ?? false) ||
          n.boardName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: DfSpacing.md,
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search notifications',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              )
            : const Text('Notifications'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Stop searching' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            }),
          ),
          ...state.maybeWhen(
            data: (feed) => feed.unreadCount == 0
                ? const <Widget>[]
                : [
                    TextButton(
                      onPressed: () async {
                        try {
                          await ApiClient.instance.post('/notifications/read-all');
                          ref.invalidate(notificationsProvider);
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            showDfToast(context, e.message, icon: Icons.error_outline_rounded);
                          }
                        }
                      },
                      child: const Text('Mark all read'),
                    ),
                  ],
            orElse: () => const <Widget>[],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
              child: Row(children: [
                for (final filter in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: DfSpacing.xs, bottom: DfSpacing.xs),
                    child: _FilterChip(
                      label: filter.label,
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
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
                onPressed: () => ref.invalidate(notificationsProvider),
              ),
            ]),
          ),
        ),
        data: (feed) {
          final visible = _visible(feed.items);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              await ref.read(notificationsProvider.future);
            },
            child: visible.isEmpty
                ? _EmptyFeed(filtered: feed.items.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: DfSpacing.xs),
                    itemCount: visible.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) => _NotificationTile(
                      notification: visible[index],
                      onTap: () async {
                        final notification = visible[index];
                        if (!notification.isRead) {
                          try {
                            await ApiClient.instance.post('/notifications/${notification.id}/read');
                            ref.invalidate(notificationsProvider);
                          } on ApiException {
                            // Navigation matters more than the read receipt.
                          }
                        }
                        if (!context.mounted) return;
                        final itemId = notification.itemId;
                        final boardId = notification.boardId;
                        if (itemId != null) {
                          context.push('/items/$itemId');
                        } else if (boardId != null) {
                          context.push('/boards/$boardId');
                        }
                      },
                    )
                        .animate(delay: DfMotion.staggerStep * (index.clamp(0, 8)))
                        .fadeIn(duration: DfMotion.expressiveShort, curve: DfMotion.enter),
                  ),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? DfColors.primary : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: notification.isRead
          ? Colors.transparent
          : (isDark ? DfColors.primary.withValues(alpha: 0.10) : DfColors.primarySubtle),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
          child: Row(children: [
            DfAvatar(
              name: notification.actorName ?? '?',
              seed: notification.actorName ?? notification.id,
              imageUrl: notification.actorAvatarUrl,
              size: 36,
            ),
            const SizedBox(width: DfSpacing.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(notification.headline, style: text.bodyMedium),
                if (notification.snippet != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      notification.snippet!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${notification.boardName} · ${relativeTime(notification.createdAt)}',
                  style: text.labelSmall,
                ),
              ]),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: DfColors.primary, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.filtered});

  /// True when notifications exist but the current filter/search hides them.
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
                  filtered ? Icons.filter_alt_off_outlined : Icons.notifications_rounded,
                  size: 34,
                  color: DfColors.primary,
                ),
              ),
              const SizedBox(height: DfSpacing.md),
              Text(
                filtered ? 'Nothing matches' : 'Ready, set, get notified!',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: DfSpacing.xxs),
              Text(
                filtered
                    ? 'Try a different filter or search term.'
                    : "Here's where you'll get notified every time\nsomething important happens.",
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
