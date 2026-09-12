import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_misc.dart';
import '../board/cell_editors.dart';

const _faqs = <({String question, String answer})>[
  (
    question: 'How do I invite my team?',
    answer:
        'Open More → Members & invitations and enter their email. They get an invite link by email; '
        'opening it on a phone with Dayflow installed joins them straight into your account.',
  ),
  (
    question: 'What is the difference between board types?',
    answer:
        'Main boards are visible to everyone in the account. Private and shareable boards are visible '
        'only to their board members and account admins.',
  ),
  (
    question: 'Where do my notifications come from?',
    answer:
        'You are notified when someone @mentions you, replies to your update, or assigns you to an item. '
        'Email delivery for these can be turned off under Settings → Notifications.',
  ),
  (
    question: 'How does My Work decide its buckets?',
    answer:
        'My Work gathers every item assigned to you through a People column across all boards you can see, '
        'grouped by the item\'s date: overdue, today, this week, later, or without a date.',
  ),
  (
    question: 'Can I use Dayflow offline?',
    answer:
        'Dayflow needs a connection to load and save work. If the live-updates link drops, boards fall back '
        'to refreshing automatically every half minute until it recovers.',
  ),
  (
    question: 'How do I export a board?',
    answer: 'Open the board, tap the ⋮ menu, and choose “Export to CSV”. The file includes every group, item, and column.',
  ),
];

/// Support center: answers to the questions people actually hit, plus a
/// direct line to send feedback (delivered to the product team).
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  Future<void> _sendFeedback(BuildContext context) async {
    final message = await promptForText(context, title: 'Contact us', hint: 'Tell us what happened or what you need');
    if (message == null || message.isEmpty) return;
    try {
      await ApiClient.instance.post('/me/feedback', body: {'message': message});
      if (context.mounted) showDfToast(context, 'Thanks — your message was sent');
    } on ApiException catch (e) {
      if (context.mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & support'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DfSpacing.md),
        children: [
          Text('Frequently asked', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          DfCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (index, faq) in _faqs.indexed) ...[
                if (index > 0) const Divider(height: 1),
                ExpansionTile(
                  title: Text(faq.question, style: text.titleSmall),
                  tilePadding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
                  childrenPadding: const EdgeInsets.fromLTRB(DfSpacing.md, 0, DfSpacing.md, DfSpacing.sm),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  children: [Text(faq.answer, style: text.bodySmall)],
                ),
              ],
            ]),
          ),
          const SizedBox(height: DfSpacing.md),
          Text('Still stuck?', style: text.labelMedium),
          const SizedBox(height: DfSpacing.xs),
          DfCard(
            onTap: () => _sendFeedback(context),
            child: Row(children: [
              const Icon(Icons.support_agent_rounded, color: DfColors.primary),
              const SizedBox(width: DfSpacing.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Contact us', style: text.titleMedium),
                  Text('Report a problem or ask a question — it lands with the team.', style: text.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: DfColors.textTertiary),
            ]),
          ),
        ],
      ),
    );
  }
}
