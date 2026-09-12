import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';

/// Bottom action bar shown while rows are selected. Every action is a
/// callback; the screen owns the pickers and the batch request.
class BatchBar extends StatelessWidget {
  const BatchBar({
    super.key,
    required this.count,
    required this.onSetStatus,
    required this.onAssign,
    required this.onMoveToGroup,
    required this.onDuplicate,
    required this.onArchive,
    required this.onDelete,
    this.busy = false,
  });

  final int count;

  /// Null hides the action (e.g. no status/people column on the board).
  final VoidCallback? onSetStatus;
  final VoidCallback? onAssign;
  final VoidCallback? onMoveToGroup;
  final VoidCallback? onDuplicate;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = count > 0 && !busy;

    Widget action(String label, IconData icon, VoidCallback? onTap, {bool destructive = false}) {
      final color = destructive
          ? DfColors.danger
          : (isDark ? DfColors.textPrimaryDark : DfColors.textPrimary);
      return InkWell(
        onTap: enabled && onTap != null ? onTap : null,
        borderRadius: BorderRadius.circular(DfRadius.sm),
        child: Opacity(
          opacity: enabled && onTap != null ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DfSpacing.sm, vertical: DfSpacing.xs),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
            ]),
          ),
        ),
      );
    }

    return Material(
      color: isDark ? DfColors.surfaceDark : Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: isDark ? DfColors.borderDark : DfColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs, vertical: DfSpacing.xxs),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (onSetStatus != null) action('Set status', Icons.donut_large_rounded, onSetStatus),
                  if (onAssign != null) action('Assign', Icons.person_add_alt_rounded, onAssign),
                  action('Move', Icons.drive_file_move_outlined, onMoveToGroup),
                  action('Duplicate', Icons.copy_rounded, onDuplicate),
                  action('Archive', Icons.archive_outlined, onArchive),
                  action('Delete', Icons.delete_outline_rounded, onDelete, destructive: true),
                ]),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: DfSpacing.sm),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Multi-select of people. Returns the chosen user ids (possibly empty) or
/// null when dismissed. [includeMe] adds a "Me" entry whose id is `'me'`.
Future<List<String>?> showPeoplePicker(
  BuildContext context, {
  required List<BoardMember> members,
  List<String> selected = const [],
  bool includeMe = false,
  String title = 'People',
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _PeoplePickerSheet(
      members: members,
      selected: selected,
      includeMe: includeMe,
      title: title,
    ),
  );
}

class _PeoplePickerSheet extends StatefulWidget {
  const _PeoplePickerSheet({
    required this.members,
    required this.selected,
    required this.includeMe,
    required this.title,
  });

  final List<BoardMember> members;
  final List<String> selected;
  final bool includeMe;
  final String title;

  @override
  State<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends State<_PeoplePickerSheet> {
  late final Set<String> _selected = {...widget.selected};

  void _toggle(String id, bool? checked) => setState(() {
        if (checked == true) {
          _selected.add(id);
        } else {
          _selected.remove(id);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (widget.includeMe)
            CheckboxListTile(
              value: _selected.contains('me'),
              onChanged: (checked) => _toggle('me', checked),
              title: const Text('Me'),
              subtitle: const Text('Whoever is looking at the view'),
              secondary: const CircleAvatar(
                radius: 16,
                backgroundColor: DfColors.primarySubtle,
                child: Icon(Icons.person_rounded, size: 18, color: DfColors.primary),
              ),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          if (widget.members.isEmpty && !widget.includeMe)
            const Padding(
              padding: EdgeInsets.all(DfSpacing.md),
              child: Text('No one has been added to this board yet.'),
            ),
          for (final member in widget.members)
            CheckboxListTile(
              value: _selected.contains(member.userId),
              onChanged: (checked) => _toggle(member.userId, checked),
              title: Text(member.fullName),
              secondary: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
        child: DfButton(label: 'Done', onPressed: () => Navigator.pop(context, _selected.toList())),
      ),
    ]);
  }
}

/// Picks one label of a status column. Returns the label id, or null.
Future<String?> showStatusLabelPicker(BuildContext context, BoardColumn column) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: DfSpacing.sm),
            child: Text(column.title, style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final label in column.statusLabels)
            Padding(
              padding: const EdgeInsets.only(bottom: DfSpacing.xs),
              child: InkWell(
                borderRadius: BorderRadius.circular(DfRadius.sm),
                onTap: () => Navigator.pop(sheetContext, label.id),
                child: DfStatusPill(label: label.label, colorToken: label.color, height: 40),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Picks one of [columns]; skips the sheet when there is exactly one.
Future<BoardColumn?> pickColumn(BuildContext context, List<BoardColumn> columns, {required String title}) {
  if (columns.isEmpty) return Future.value(null);
  if (columns.length == 1) return Future.value(columns.first);
  return showModalBottomSheet<BoardColumn>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
        ),
        for (final column in columns)
          ListTile(title: Text(column.title), onTap: () => Navigator.pop(sheetContext, column)),
      ]),
    ),
  );
}
