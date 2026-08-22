import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';

/// Result of an editor: the new cell value, or null to clear the cell.
typedef CellValue = Map<String, dynamic>?;

/// Opens the right editor for [column] and returns the chosen value.
/// Returns `(false, null)` when the user dismisses without choosing.
Future<({bool changed, CellValue value})> editCell({
  required BuildContext context,
  required BoardColumn column,
  required BoardItem item,
  required List<BoardMember> members,
}) async {
  final current = item.values[column.id] as Map<String, dynamic>?;

  switch (column.type) {
    case 'status':
      final picked = await _showSheet<_Choice<String?>>(
        context,
        title: column.title,
        builder: (context) => _StatusPicker(column: column, current: current?['labelId'] as String?),
      );
      if (picked == null) return (changed: false, value: null);
      return (changed: true, value: picked.value == null ? null : {'labelId': picked.value});

    case 'people':
      final currentIds = ((current?['userIds'] as List<dynamic>?) ?? const []).cast<String>();
      final picked = await _showSheet<_Choice<List<String>>>(
        context,
        title: column.title,
        builder: (context) => _PeoplePicker(members: members, selected: currentIds),
      );
      if (picked == null) return (changed: false, value: null);
      return (changed: true, value: picked.value.isEmpty ? null : {'userIds': picked.value});

    case 'date':
      final existing = current?['date'] as String?;
      final initial = existing != null ? DateTime.tryParse(existing) : null;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Select ${column.title.toLowerCase()}',
      );
      if (picked == null) return (changed: false, value: null);
      return (changed: true, value: {'date': DateFormat('yyyy-MM-dd').format(picked)});

    case 'checkbox':
      final checked = current?['checked'] == true;
      return (changed: true, value: checked ? null : {'checked': true});

    case 'text':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['text'] as String? ?? '',
      );
      if (value == null) return (changed: false, value: null);
      return (changed: true, value: value.isEmpty ? null : {'text': value});

    case 'number':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['number']?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        validator: (raw) => raw.isEmpty || double.tryParse(raw) != null ? null : 'Enter a number',
      );
      if (value == null) return (changed: false, value: null);
      if (value.isEmpty) return (changed: true, value: null);
      return (changed: true, value: {'number': double.parse(value)});

    case 'link':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['url'] as String? ?? '',
        hint: 'https://example.com',
        keyboardType: TextInputType.url,
        validator: (raw) {
          if (raw.isEmpty) return null;
          final uri = Uri.tryParse(raw);
          return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty
              ? null
              : 'Enter a full http(s) URL';
        },
      );
      if (value == null) return (changed: false, value: null);
      return (changed: true, value: value.isEmpty ? null : {'url': value});

    case 'location':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['address'] as String? ?? '',
        hint: 'Address or place',
      );
      if (value == null) return (changed: false, value: null);
      return (changed: true, value: value.isEmpty ? null : {'address': value});

    case 'tags':
    case 'dropdown':
      final options = (column.settings['options'] as List<dynamic>? ?? const [])
          .map((o) => o as Map<String, dynamic>)
          .toList();
      if (options.isEmpty) {
        showDfToast(context, 'Add options to this column first', icon: Icons.info_outline_rounded);
        return (changed: false, value: null);
      }
      final currentIds = ((current?['optionIds'] as List<dynamic>?) ?? const []).cast<String>();
      final picked = await _showSheet<_Choice<List<String>>>(
        context,
        title: column.title,
        builder: (context) => _OptionPicker(
          options: options,
          selected: currentIds,
          multiSelect: column.type == 'tags',
        ),
      );
      if (picked == null) return (changed: false, value: null);
      return (changed: true, value: picked.value.isEmpty ? null : {'optionIds': picked.value});

    default:
      showDfToast(context, '${column.title} cannot be edited yet', icon: Icons.info_outline_rounded);
      return (changed: false, value: null);
  }
}

/// Wraps a chosen value so `null` stays distinguishable from "dismissed".
class _Choice<T> {
  const _Choice(this.value);
  final T value;
}

Future<T?> _showSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: DfSpacing.sm),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: DfSpacing.sm),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: DfColors.borderStrong, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          Flexible(child: builder(sheetContext)),
        ]),
      ),
    ),
  );
}

/// Single-field text prompt. Returns null when cancelled, the trimmed text
/// otherwise (possibly empty, which callers treat as "clear").
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  TextInputType? keyboardType,
  String? Function(String)? validator,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextPromptDialog(
      title: title,
      controller: controller,
      hint: hint,
      keyboardType: keyboardType,
      validator: validator,
    ),
  ).whenComplete(controller.dispose);
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.validator,
  });

  final String title;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String)? validator;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  String? _error;

  void _submit() {
    final raw = widget.controller.text.trim();
    final error = widget.validator?.call(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      content: DfTextField(
        controller: widget.controller,
        hint: widget.hint,
        autofocus: true,
        keyboardType: widget.keyboardType,
        errorText: _error,
        textInputAction: TextInputAction.done,
        onChanged: (_) => _error == null ? null : setState(() => _error = null),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _StatusPicker extends StatelessWidget {
  const _StatusPicker({required this.column, required this.current});

  final BoardColumn column;
  final String? current;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
      children: [
        for (final label in column.statusLabels)
          Padding(
            padding: const EdgeInsets.only(bottom: DfSpacing.xs),
            child: InkWell(
              borderRadius: BorderRadius.circular(DfRadius.sm),
              onTap: () => Navigator.pop(context, _Choice<String?>(label.id)),
              child: Row(children: [
                Expanded(child: DfStatusPill(label: label.label, colorToken: label.color, height: 40)),
                if (label.id == current)
                  const Padding(
                    padding: EdgeInsets.only(left: DfSpacing.xs),
                    child: Icon(Icons.check_rounded, color: DfColors.primary),
                  ),
              ]),
            ),
          ),
        const Divider(height: DfSpacing.lg),
        DfButton(
          label: 'Clear',
          variant: DfButtonVariant.text,
          onPressed: () => Navigator.pop(context, const _Choice<String?>(null)),
        ),
      ],
    );
  }
}

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.members, required this.selected});

  final List<BoardMember> members;
  final List<String> selected;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (widget.members.isEmpty)
              const Padding(
                padding: EdgeInsets.all(DfSpacing.md),
                child: Text('No one has been added to this board yet.'),
              ),
            for (final member in widget.members)
              CheckboxListTile(
                value: _selected.contains(member.userId),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selected.add(member.userId);
                  } else {
                    _selected.remove(member.userId);
                  }
                }),
                title: Text(member.fullName),
                secondary: DfAvatar(name: member.fullName, seed: member.userId, imageUrl: member.avatarUrl),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
        child: DfButton(
          label: 'Done',
          onPressed: () => Navigator.pop(context, _Choice<List<String>>(_selected.toList())),
        ),
      ),
    ]);
  }
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({required this.options, required this.selected, required this.multiSelect});

  final List<Map<String, dynamic>> options;
  final List<String> selected;
  final bool multiSelect;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in widget.options)
              ListTile(
                title: Text(option['label'] as String? ?? ''),
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: DfColors.token(option['color'] as String? ?? 'grey'),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                trailing: _selected.contains(option['id'])
                    ? const Icon(Icons.check_rounded, color: DfColors.primary)
                    : null,
                onTap: () {
                  final id = option['id'] as String;
                  if (widget.multiSelect) {
                    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
                  } else {
                    Navigator.pop(context, _Choice<List<String>>(_selected.contains(id) ? [] : [id]));
                  }
                },
              ),
          ],
        ),
      ),
      if (widget.multiSelect)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
          child: DfButton(
            label: 'Done',
            onPressed: () => Navigator.pop(context, _Choice<List<String>>(_selected.toList())),
          ),
        ),
    ]);
  }
}

/// Renders a cell's current value as a compact chip. Returns null when unset.
Widget? cellChip(BuildContext context, BoardColumn column, BoardItem item, List<BoardMember> members) {
  final value = item.values[column.id] as Map<String, dynamic>?;

  switch (column.type) {
    case 'status':
      final label = column.statusLabels.where((l) => l.id == value?['labelId']).firstOrNull;
      if (label == null) return null;
      return DfStatusPill(label: label.label, colorToken: label.color, height: 24);

    case 'people':
      final ids = ((value?['userIds'] as List<dynamic>?) ?? const []).cast<String>();
      if (ids.isEmpty) return null;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (final id in ids.take(3))
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: DfAvatar(
              name: members.where((m) => m.userId == id).firstOrNull?.fullName ?? '?',
              seed: id,
              imageUrl: members.where((m) => m.userId == id).firstOrNull?.avatarUrl,
              size: 22,
            ),
          ),
        if (ids.length > 3)
          Text('+${ids.length - 3}', style: Theme.of(context).textTheme.labelSmall),
      ]);

    case 'date':
      final raw = value?['date'] as String?;
      final date = raw != null ? DateTime.tryParse(raw) : null;
      if (date == null) return null;
      final time = value?['time'] as String?;
      return _MetaChip(
        icon: Icons.event_rounded,
        label: time == null ? DateFormat.MMMd().format(date) : '${DateFormat.MMMd().format(date)} $time',
      );

    case 'timeline':
      final from = value?['from'] as String?;
      final to = value?['to'] as String?;
      if (from == null || to == null) return null;
      final a = DateTime.tryParse(from);
      final b = DateTime.tryParse(to);
      if (a == null || b == null) return null;
      return _MetaChip(
        icon: Icons.date_range_rounded,
        label: '${DateFormat.MMMd().format(a)} – ${DateFormat.MMMd().format(b)}',
      );

    case 'checkbox':
      if (value?['checked'] != true) return null;
      return const _MetaChip(icon: Icons.check_box_rounded, label: 'Done');

    case 'text':
      final text = value?['text'] as String?;
      if (text == null || text.isEmpty) return null;
      return _MetaChip(icon: Icons.notes_rounded, label: text);

    case 'number':
      final number = value?['number'];
      if (number == null) return null;
      return _MetaChip(icon: Icons.numbers_rounded, label: _formatNumber(number));

    case 'link':
      final url = value?['url'] as String?;
      if (url == null) return null;
      return _MetaChip(icon: Icons.link_rounded, label: value?['label'] as String? ?? Uri.parse(url).host);

    case 'location':
      final address = value?['address'] as String?;
      if (address == null) return null;
      return _MetaChip(icon: Icons.place_outlined, label: address);

    case 'tags':
    case 'dropdown':
      final ids = ((value?['optionIds'] as List<dynamic>?) ?? const []).cast<String>();
      if (ids.isEmpty) return null;
      final options = (column.settings['options'] as List<dynamic>? ?? const [])
          .map((o) => o as Map<String, dynamic>)
          .toList();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: DfStatusPill(
                label: options.where((o) => o['id'] == id).firstOrNull?['label'] as String? ?? id,
                colorToken: options.where((o) => o['id'] == id).firstOrNull?['color'] as String? ?? 'grey',
                height: 24,
              ),
            ),
        ],
      );

    default:
      return null;
  }
}

String _formatNumber(Object number) {
  if (number is num && number == number.roundToDouble()) {
    return NumberFormat.decimalPattern().format(number.round());
  }
  return NumberFormat.decimalPattern().format(number);
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: DfColors.textSecondary),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ]),
    );
  }
}
