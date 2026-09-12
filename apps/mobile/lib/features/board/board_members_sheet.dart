import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_misc.dart';
import '../members/members_providers.dart';
import 'board_controller.dart';

const _boardRoles = <({String key, String label, String description})>[
  (key: 'owner', label: 'Owner', description: 'Manages members, settings, and the board type'),
  (key: 'member', label: 'Member', description: 'Edits everything on the board'),
  (key: 'viewer', label: 'Viewer', description: 'Read-only on this board'),
];

/// Board members sheet, monday-style: owners (crowned) and subscribers with a
/// role each. Owners and account admins invite teammates, change roles, and
/// remove people; anyone can leave.
Future<void> showBoardMembersSheet(BuildContext context, WidgetRef ref, {required String boardId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) =>
          _BoardMembersSheet(boardId: boardId, scrollController: scrollController),
    ),
  );
}

class _BoardMembersSheet extends ConsumerStatefulWidget {
  const _BoardMembersSheet({required this.boardId, required this.scrollController});

  final String boardId;
  final ScrollController scrollController;

  @override
  ConsumerState<_BoardMembersSheet> createState() => _BoardMembersSheetState();
}

class _BoardMembersSheetState extends ConsumerState<_BoardMembersSheet> {
  BoardMemberList? _list;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(boardRepositoryProvider).boardMembers(widget.boardId);
      if (mounted) setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<BoardMemberList> Function() op, {String? leftBoard}) async {
    setState(() => _busy = true);
    try {
      final list = await op();
      if (!mounted) return;
      if (leftBoard != null) {
        Navigator.pop(context);
        showDfToast(context, leftBoard);
        return;
      }
      setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMember() async {
    final list = _list;
    if (list == null) return;
    final directory = await ref.read(memberDirectoryProvider.future);
    if (!mounted) return;
    final onBoard = list.members.map((m) => m.userId).toSet();
    final candidates = directory.members.where((m) => !onBoard.contains(m.userId)).toList();

    if (candidates.isEmpty) {
      showDfToast(context, 'Everyone in the account is already on this board');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (pickerContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text('Add to board', style: Theme.of(pickerContext).textTheme.titleMedium),
          ),
          for (final member in candidates)
            ListTile(
              leading: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl, size: 36),
              title: Text(member.fullName),
              subtitle: Text(member.email),
              onTap: () => Navigator.pop(pickerContext, member.userId),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    await _run(() => ref
        .read(boardRepositoryProvider)
        .addBoardMember(boardId: widget.boardId, userId: picked));
  }

  Future<void> _editMember(BoardMemberEntry member) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (menuContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(member.fullName, style: Theme.of(menuContext).textTheme.titleMedium),
          ),
          for (final role in _boardRoles)
            ListTile(
              leading: Icon(
                role.key == 'owner' ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                size: 20,
                color: role.key == 'owner' && !member.canBeOwner ? DfColors.textTertiary : DfColors.primary,
              ),
              title: Text(role.label),
              subtitle: Text(
                role.key == 'owner' && !member.canBeOwner
                    ? 'Account viewers and guests cannot own boards'
                    : role.description,
              ),
              trailing: member.role == role.key
                  ? const Icon(Icons.check_rounded, color: DfColors.primary)
                  : null,
              enabled: role.key != 'owner' || member.canBeOwner,
              onTap: () => Navigator.pop(menuContext, role.key),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined, size: 20, color: DfColors.danger),
            title: Text(
              member.isYou ? 'Leave board' : 'Remove from board',
              style: const TextStyle(color: DfColors.danger),
            ),
            onTap: () => Navigator.pop(menuContext, 'remove'),
          ),
        ]),
      ),
    );
    if (action == null || action == member.role) return;

    if (action == 'remove') {
      await _run(
        () => ref
            .read(boardRepositoryProvider)
            .removeBoardMember(boardId: widget.boardId, userId: member.userId),
        leftBoard: member.isYou ? 'You left the board' : null,
      );
    } else {
      await _run(() => ref
          .read(boardRepositoryProvider)
          .changeBoardMemberRole(boardId: widget.boardId, userId: member.userId, role: action));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = _list;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Board members', style: text.titleLarge)),
          if (_busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (list?.canManage ?? false)
            IconButton(
              icon: const Icon(Icons.person_add_alt_rounded, color: DfColors.primary),
              tooltip: 'Add someone',
              onPressed: _addMember,
            ),
        ]),
      ),
      if (list != null && !list.canManage)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Only board owners and account admins can change this list.', style: text.labelSmall),
          ),
        ),
      Expanded(
        child: _error != null
            ? Center(child: Text(_error!, style: text.bodySmall))
            : list == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.all(DfSpacing.xs),
                    children: [
                      for (final member in list.members)
                        ListTile(
                          leading: DfAvatar(
                            name: member.fullName,
                            seed: member.userId,
                            imageUrl: member.avatarUrl,
                            size: 40,
                          ),
                          title: Row(children: [
                            Flexible(
                              child: Text(
                                member.isYou ? '${member.fullName} (you)' : member.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (member.role == 'owner') ...[
                              const SizedBox(width: DfSpacing.xxs),
                              const Icon(Icons.workspace_premium_rounded,
                                  size: 16, color: DfColors.accentAmber),
                            ],
                          ]),
                          subtitle: Text(member.email),
                          trailing: DfStatusPill(
                            label: member.role,
                            colorToken: switch (member.role) {
                              'owner' => 'amber',
                              'viewer' => 'grey',
                              _ => 'blue',
                            },
                            height: 22,
                          ),
                          onTap: (list.canManage || member.isYou) && !_busy
                              ? () => _editMember(member)
                              : null,
                        ),
                    ],
                  ),
      ),
    ]);
  }
}
