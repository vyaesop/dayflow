import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_avatar.dart';
import '../../ui/widgets/df_button.dart';
import '../../ui/widgets/df_misc.dart';
import '../../ui/widgets/df_text_field.dart';
import '../item/item_repository.dart';
import 'view_engine.dart' show formatNumberCell;

/// Result of an editor: the new cell value, or null to clear the cell.
typedef CellValue = Map<String, dynamic>?;

/// `refresh` asks the caller to re-read the item/board because the server
/// changed the cell itself (Files column uploads/removals).
typedef CellEditResult = ({bool changed, CellValue value, bool refresh});

const CellEditResult _dismissed = (changed: false, value: null, refresh: false);

CellEditResult _set(CellValue value) => (changed: true, value: value, refresh: false);

// ---------------------------------------------------------------- validators

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _phonePattern = RegExp(r'^[+()\-\s\d]{3,32}$');

/// Null when [raw] is empty (clear) or a plausible address ≤254 chars.
String? validateEmail(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (value.length > 254) return 'Email is too long';
  return _emailPattern.hasMatch(value) ? null : 'Enter a valid email address';
}

/// Null when [raw] is empty (clear) or matches the contract's phone shape.
String? validatePhone(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!_phonePattern.hasMatch(value)) return 'Enter a valid phone number';
  return RegExp(r'\d').hasMatch(value) ? null : 'Enter a valid phone number';
}

/// "Jan 3 – Mar 9"; falls back to the raw strings when they do not parse.
String formatTimelineLabel(String from, String to) {
  final a = DateTime.tryParse(from);
  final b = DateTime.tryParse(to);
  if (a == null || b == null) return '$from – $to';
  return '${DateFormat.MMMd().format(a)} – ${DateFormat.MMMd().format(b)}';
}

/// "★★★☆☆" — [rating] filled stars out of [max].
String ratingLabel(int rating, int max) {
  final total = max.clamp(1, 10);
  final filled = rating.clamp(0, total);
  return '${'★' * filled}${'☆' * (total - filled)}';
}

// ------------------------------------------------------------------- editors

/// Opens the right editor for [column] and returns the chosen value.
/// Returns `(changed: false, value: null, refresh: false)` when the user
/// dismisses without choosing.
Future<CellEditResult> editCell({
  required BuildContext context,
  required BoardColumn column,
  required BoardItem item,
  required List<BoardMember> members,
  String? meUserId,
  ItemRepository? files,
}) async {
  final current = item.values[column.id] as Map<String, dynamic>?;

  if (column.isReadOnly) {
    showDfToast(context, '${column.title} is set automatically', icon: Icons.info_outline_rounded);
    return _dismissed;
  }

  switch (column.type) {
    case 'status':
      final picked = await _showSheet<_Choice<String?>>(
        context,
        title: column.title,
        builder: (context) => _StatusPicker(column: column, current: current?['labelId'] as String?),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value == null ? null : {'labelId': picked.value});

    case 'people':
      final currentIds = ((current?['userIds'] as List<dynamic>?) ?? const []).cast<String>();
      final picked = await _showSheet<_Choice<List<String>>>(
        context,
        title: column.title,
        builder: (context) => _PeoplePicker(members: members, selected: currentIds),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value.isEmpty ? null : {'userIds': picked.value});

    case 'date':
      final existing = current?['date'] as String?;
      final existingTime = current?['time'] as String?;
      final initial = existing != null ? DateTime.tryParse(existing) : null;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Select ${column.title.toLowerCase()}',
      );
      if (picked == null || !context.mounted) return _dismissed;
      final date = DateFormat('yyyy-MM-dd').format(picked);
      // Optional time step. Swiping the sheet away keeps the date just picked
      // (and any time it already had) so the quick path stays one tap.
      final timeChoice = await _showSheet<_Choice<String?>>(
        context,
        title: DateFormat.yMMMd().format(picked),
        builder: (context) => _DateTimeStep(initialTime: existingTime),
      );
      final time = timeChoice == null ? existingTime : timeChoice.value;
      return _set({'date': date, 'time': ?time});

    case 'checkbox':
      final checked = current?['checked'] == true;
      return _set(checked ? null : {'checked': true});

    case 'text':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['text'] as String? ?? '',
      );
      if (value == null) return _dismissed;
      return _set(value.isEmpty ? null : {'text': value});

    case 'long_text':
      final picked = await _showSheet<_Choice<String>>(
        context,
        title: column.title,
        builder: (context) => _LongTextEditor(initial: current?['text'] as String? ?? ''),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value.isEmpty ? null : {'text': picked.value});

    case 'number':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['number']?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        validator: (raw) => raw.isEmpty || double.tryParse(raw) != null ? null : 'Enter a number',
      );
      if (value == null) return _dismissed;
      if (value.isEmpty) return _set(null);
      return _set({'number': double.parse(value)});

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
      if (value == null) return _dismissed;
      return _set(value.isEmpty ? null : {'url': value});

    case 'email':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['email'] as String? ?? '',
        hint: 'name@example.com',
        keyboardType: TextInputType.emailAddress,
        validator: validateEmail,
      );
      if (value == null) return _dismissed;
      if (value.isEmpty) return _set(null);
      final label = current?['label'] as String?;
      return _set({'email': value, if (label != null && label.isNotEmpty) 'label': label});

    case 'phone':
      final picked = await _showSheet<_Choice<Map<String, dynamic>?>>(
        context,
        title: column.title,
        builder: (context) => _PhoneEditor(
          initialPhone: current?['phone'] as String? ?? '',
          initialCountryCode: current?['countryCode'] as String? ?? '',
        ),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value);

    case 'location':
      final value = await promptForText(
        context,
        title: column.title,
        initial: current?['address'] as String? ?? '',
        hint: 'Address or place',
      );
      if (value == null) return _dismissed;
      return _set(value.isEmpty ? null : {'address': value});

    case 'tags':
    case 'dropdown':
      final options = column.options;
      if (options.isEmpty) {
        showDfToast(context, 'Add options to this column first', icon: Icons.info_outline_rounded);
        return _dismissed;
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
      if (picked == null) return _dismissed;
      return _set(picked.value.isEmpty ? null : {'optionIds': picked.value});

    case 'rating':
      final picked = await _showSheet<_Choice<int?>>(
        context,
        title: column.title,
        builder: (context) => _RatingPicker(
          max: column.ratingMax,
          current: (current?['rating'] as num?)?.toInt() ?? 0,
        ),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value == null ? null : {'rating': picked.value});

    case 'vote':
      if (meUserId == null) {
        showDfToast(context, 'Sign in to vote', icon: Icons.info_outline_rounded);
        return _dismissed;
      }
      final ids = ((current?['userIds'] as List<dynamic>?) ?? const []).cast<String>().toList();
      if (ids.contains(meUserId)) {
        ids.remove(meUserId);
      } else {
        ids.add(meUserId);
      }
      return _set(ids.isEmpty ? null : {'userIds': ids});

    case 'timeline':
      final picked = await _showSheet<_Choice<Map<String, dynamic>?>>(
        context,
        title: column.title,
        builder: (context) => _TimelineEditor(
          initialFrom: current?['from'] as String?,
          initialTo: current?['to'] as String?,
        ),
      );
      if (picked == null) return _dismissed;
      return _set(picked.value);

    case 'files':
      if (files == null) {
        showDfToast(context, 'Open the item to manage its files', icon: Icons.info_outline_rounded);
        return _dismissed;
      }
      final session = _FilesSession(
        ids: ((current?['fileIds'] as List<dynamic>?) ?? const []).cast<String>().toSet(),
      );
      await _showSheet<void>(
        context,
        title: column.title,
        builder: (context) => _FilesEditor(column: column, item: item, files: files, session: session),
      );
      return (changed: false, value: null, refresh: session.dirty);

    default:
      showDfToast(context, '${column.title} cannot be edited yet', icon: Icons.info_outline_rounded);
      return _dismissed;
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
        padding: EdgeInsets.only(bottom: DfSpacing.sm + MediaQuery.viewInsetsOf(sheetContext).bottom),
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

/// Save / Clear pair used at the bottom of value editor sheets.
class _SheetActions extends StatelessWidget {
  const _SheetActions({required this.onSave, required this.onClear});

  final VoidCallback onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DfButton(label: 'Save', onPressed: onSave),
        const SizedBox(height: DfSpacing.xxs),
        DfButton(label: 'Clear', variant: DfButtonVariant.text, onPressed: onClear),
      ]),
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

/// Second step of the date editor: optionally attach an `HH:mm` time.
class _DateTimeStep extends StatefulWidget {
  const _DateTimeStep({required this.initialTime});

  final String? initialTime;

  @override
  State<_DateTimeStep> createState() => _DateTimeStepState();
}

class _DateTimeStepState extends State<_DateTimeStep> {
  late String? _time = widget.initialTime;

  Future<void> _pickTime() async {
    final parts = _time?.split(':');
    final initial = parts != null && parts.length == 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() => _time = _formatTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        leading: const Icon(Icons.schedule_rounded, color: DfColors.textSecondary),
        title: Text(_time == null ? 'Add time' : 'Time: $_time'),
        subtitle: _time == null ? const Text('Optional') : null,
        trailing: _time == null
            ? const Icon(Icons.chevron_right_rounded, color: DfColors.textTertiary)
            : IconButton(
                tooltip: 'Remove time',
                icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.textTertiary),
                onPressed: () => setState(() => _time = null),
              ),
        onTap: _pickTime,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
        child: DfButton(label: 'Save', onPressed: () => Navigator.pop(context, _Choice<String?>(_time))),
      ),
    ]);
  }
}

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _LongTextEditor extends StatefulWidget {
  const _LongTextEditor({required this.initial});

  final String initial;

  @override
  State<_LongTextEditor> createState() => _LongTextEditorState();
}

class _LongTextEditorState extends State<_LongTextEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.length > 20000) {
      setState(() => _error = 'Keep it under 20 000 characters');
      return;
    }
    Navigator.pop(context, _Choice<String>(text));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
        // DfTextField is single-line; the theme's InputDecoration keeps the look.
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(hintText: 'Write something…', errorText: _error, alignLabelWithHint: true),
          onChanged: (_) => _error == null ? null : setState(() => _error = null),
        ),
      ),
      const SizedBox(height: DfSpacing.sm),
      _SheetActions(
        onSave: _save,
        onClear: () => Navigator.pop(context, const _Choice<String>('')),
      ),
    ]);
  }
}

class _PhoneEditor extends StatefulWidget {
  const _PhoneEditor({required this.initialPhone, required this.initialCountryCode});

  final String initialPhone;
  final String initialCountryCode;

  @override
  State<_PhoneEditor> createState() => _PhoneEditorState();
}

class _PhoneEditorState extends State<_PhoneEditor> {
  late final TextEditingController _phone = TextEditingController(text: widget.initialPhone);
  late final TextEditingController _country = TextEditingController(text: widget.initialCountryCode);
  String? _phoneError;
  String? _countryError;

  @override
  void dispose() {
    _phone.dispose();
    _country.dispose();
    super.dispose();
  }

  void _save() {
    final phone = _phone.text.trim();
    final country = _country.text.trim().toUpperCase();
    final phoneError = validatePhone(phone);
    final countryError =
        country.isEmpty || RegExp(r'^[A-Z]{2}$').hasMatch(country) ? null : 'Use a 2-letter code (e.g. US)';
    if (phoneError != null || countryError != null) {
      setState(() {
        _phoneError = phoneError;
        _countryError = countryError;
      });
      return;
    }
    if (phone.isEmpty) {
      Navigator.pop(context, const _Choice<Map<String, dynamic>?>(null));
      return;
    }
    Navigator.pop(context, _Choice<Map<String, dynamic>?>({'phone': phone, if (country.isNotEmpty) 'countryCode': country}));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 92,
            child: DfTextField(
              controller: _country,
              label: 'Country',
              hint: 'US',
              errorText: _countryError,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _countryError == null ? null : setState(() => _countryError = null),
            ),
          ),
          const SizedBox(width: DfSpacing.xs),
          Expanded(
            child: DfTextField(
              controller: _phone,
              label: 'Phone',
              hint: '+1 555 010 2030',
              autofocus: true,
              keyboardType: TextInputType.phone,
              errorText: _phoneError,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _phoneError == null ? null : setState(() => _phoneError = null),
              onSubmitted: (_) => _save(),
            ),
          ),
        ]),
      ),
      const SizedBox(height: DfSpacing.sm),
      _SheetActions(
        onSave: _save,
        onClear: () => Navigator.pop(context, const _Choice<Map<String, dynamic>?>(null)),
      ),
    ]);
  }
}

class _RatingPicker extends StatefulWidget {
  const _RatingPicker({required this.max, required this.current});

  final int max;
  final int current;

  @override
  State<_RatingPicker> createState() => _RatingPickerState();
}

class _RatingPickerState extends State<_RatingPicker> {
  @override
  Widget build(BuildContext context) {
    final size = widget.max > 7 ? 30.0 : 36.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (var i = 1; i <= widget.max; i++)
              IconButton(
                tooltip: '$i of ${widget.max}',
                iconSize: size,
                icon: Icon(
                  i <= widget.current ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: i <= widget.current ? DfColors.accentAmber : DfColors.textTertiary,
                ),
                // Tapping the current value again clears the rating.
                onPressed: () => Navigator.pop(context, _Choice<int?>(i == widget.current ? null : i)),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(DfSpacing.xs),
        child: Text(
          widget.current == 0 ? 'Tap a star to rate' : '${widget.current} of ${widget.max} — tap again to clear',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      DfButton(
        label: 'Clear',
        variant: DfButtonVariant.text,
        onPressed: () => Navigator.pop(context, const _Choice<int?>(null)),
      ),
    ]);
  }
}

class _TimelineEditor extends StatefulWidget {
  const _TimelineEditor({required this.initialFrom, required this.initialTo});

  final String? initialFrom;
  final String? initialTo;

  @override
  State<_TimelineEditor> createState() => _TimelineEditorState();
}

class _TimelineEditorState extends State<_TimelineEditor> {
  late DateTime? _from = widget.initialFrom != null ? DateTime.tryParse(widget.initialFrom!) : null;
  late DateTime? _to = widget.initialTo != null ? DateTime.tryParse(widget.initialTo!) : null;
  String? _error;

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _from : (_to ?? _from)) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Select start' : 'Select end',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      if (start) {
        _from = picked;
        // End defaults to Start (and follows it when it would fall before).
        if (_to == null || _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _save() {
    final from = _from;
    final to = _to ?? from;
    if (from == null || to == null) {
      setState(() => _error = 'Pick a start date');
      return;
    }
    if (to.isBefore(from)) {
      setState(() => _error = 'End must be on or after start');
      return;
    }
    final f = DateFormat('yyyy-MM-dd');
    Navigator.pop(context, _Choice<Map<String, dynamic>?>({'from': f.format(from), 'to': f.format(to)}));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String label, DateTime? value, bool start) => ListTile(
          leading: Icon(start ? Icons.play_arrow_rounded : Icons.stop_rounded, color: DfColors.textSecondary),
          title: Text(label),
          trailing: Text(
            value == null ? 'Pick a date' : DateFormat.yMMMd().format(value),
            style: text.bodyMedium?.copyWith(color: value == null ? DfColors.textTertiary : DfColors.primary),
          ),
          onTap: () => _pick(start: start),
        );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      row('Start', _from, true),
      row('End', _to ?? _from, false),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xxs),
          child: Text(_error!, style: text.bodySmall?.copyWith(color: DfColors.danger)),
        ),
      const SizedBox(height: DfSpacing.xs),
      _SheetActions(
        onSave: _save,
        onClear: () => Navigator.pop(context, const _Choice<Map<String, dynamic>?>(null)),
      ),
    ]);
  }
}

/// Mutable state shared between the Files sheet and its caller, so a swipe
/// dismissal still reports whether the server-side cell changed.
class _FilesSession {
  _FilesSession({required this.ids});

  final Set<String> ids;
  bool dirty = false;
}

class _FilesEditor extends StatefulWidget {
  const _FilesEditor({required this.column, required this.item, required this.files, required this.session});

  final BoardColumn column;
  final BoardItem item;
  final ItemRepository files;
  final _FilesSession session;

  @override
  State<_FilesEditor> createState() => _FilesEditorState();
}

class _FilesEditorState extends State<_FilesEditor> {
  List<AppFile>? _all;
  String? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.files.filesForItem(widget.item.id);
      if (mounted) setState(() => _all = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  List<AppFile> get _visible => (_all ?? const []).where((f) => widget.session.ids.contains(f.id)).toList();

  Future<void> _add() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final uploaded = await widget.files.uploadFile(
        bytes: file.bytes!,
        filename: file.name,
        itemId: widget.item.id,
        columnId: widget.column.id,
      );
      widget.session.dirty = true;
      widget.session.ids.add(uploaded.id);
      if (mounted) setState(() => _all = [...?_all, uploaded]);
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppFile file) async {
    setState(() => _busy = true);
    try {
      await widget.files.deleteFile(file.id);
      widget.session.dirty = true;
      widget.session.ids.remove(file.id);
      if (mounted) setState(() => _all = _all?.where((f) => f.id != file.id).toList());
    } on ApiException catch (e) {
      if (mounted) showDfToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final files = _visible;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(DfSpacing.md),
                child: Text(_loadError!, style: text.bodySmall?.copyWith(color: DfColors.danger)),
              )
            else if (_all == null)
              const Padding(
                padding: EdgeInsets.all(DfSpacing.lg),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
              )
            else if (files.isEmpty)
              Padding(
                padding: const EdgeInsets.all(DfSpacing.md),
                child: Text('No files yet.', style: text.bodySmall),
              ),
            for (final file in files)
              ListTile(
                leading: _FileThumb(file: file),
                title: Text(file.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(file.sizeLabel),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.textTertiary),
                  onPressed: _busy ? null : () => _remove(file),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
        child: DfButton(
          label: 'Add file',
          variant: DfButtonVariant.tonal,
          icon: const Icon(Icons.attach_file_rounded, size: 20),
          loading: _busy,
          onPressed: _all == null ? null : _add,
        ),
      ),
    ]);
  }
}

class _FileThumb extends StatelessWidget {
  const _FileThumb({required this.file});

  final AppFile file;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = resolveMediaUrl(file.url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(DfRadius.sm),
      child: Container(
        width: 40,
        height: 40,
        color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
        alignment: Alignment.center,
        child: file.isImage && url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 20, color: DfColors.textTertiary),
              )
            : const Icon(Icons.insert_drive_file_outlined, size: 20, color: DfColors.textSecondary),
      ),
    );
  }
}

// --------------------------------------------------------------------- chips

/// Renders a cell's current value as a compact chip. Returns null when unset.
///
/// [autoNumber] is the item's 1-based index in the current board order, used
/// by `auto_number` columns; when omitted that chip renders nothing.
Widget? cellChip(
  BuildContext context,
  BoardColumn column,
  BoardItem item,
  List<BoardMember> members, {
  int? autoNumber,
}) {
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
      if (DateTime.tryParse(from) == null || DateTime.tryParse(to) == null) return null;
      return _MetaChip(icon: Icons.date_range_rounded, label: formatTimelineLabel(from, to));

    case 'checkbox':
      if (value?['checked'] != true) return null;
      return const _MetaChip(icon: Icons.check_box_rounded, label: 'Done');

    case 'text':
      final text = value?['text'] as String?;
      if (text == null || text.isEmpty) return null;
      return _MetaChip(icon: Icons.notes_rounded, label: text);

    case 'long_text':
      final text = (value?['text'] as String?)?.trim();
      if (text == null || text.isEmpty) return null;
      final firstLine = text.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => text);
      return _MetaChip(icon: Icons.subject_rounded, label: firstLine.trim());

    case 'number':
      final number = value?['number'];
      if (number is! num) return null;
      return _MetaChip(icon: Icons.numbers_rounded, label: formatNumberCell(column, number));

    case 'link':
      final url = value?['url'] as String?;
      if (url == null) return null;
      return _MetaChip(icon: Icons.link_rounded, label: value?['label'] as String? ?? Uri.parse(url).host);

    case 'email':
      final email = value?['email'] as String?;
      if (email == null || email.isEmpty) return null;
      return _MetaChip(icon: Icons.mail_outline_rounded, label: email);

    case 'phone':
      final phone = value?['phone'] as String?;
      if (phone == null || phone.isEmpty) return null;
      return _MetaChip(icon: Icons.phone_outlined, label: phone);

    case 'location':
      final address = value?['address'] as String?;
      if (address == null) return null;
      return _MetaChip(icon: Icons.place_outlined, label: address);

    case 'tags':
    case 'dropdown':
      final ids = ((value?['optionIds'] as List<dynamic>?) ?? const []).cast<String>();
      if (ids.isEmpty) return null;
      final options = column.options;
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

    case 'rating':
      final rating = (value?['rating'] as num?)?.toInt();
      if (rating == null || rating <= 0) return null;
      return _MetaChip(label: ratingLabel(rating, column.ratingMax), tint: DfColors.accentAmber);

    case 'vote':
      final ids = ((value?['userIds'] as List<dynamic>?) ?? const []).cast<String>();
      if (ids.isEmpty) return null;
      return _MetaChip(icon: Icons.thumb_up_alt_outlined, label: '${ids.length}');

    case 'files':
      final ids = ((value?['fileIds'] as List<dynamic>?) ?? const []).cast<String>();
      if (ids.isEmpty) return null;
      return _MetaChip(icon: Icons.attach_file_rounded, label: ids.length == 1 ? '1 file' : '${ids.length} files');

    case 'item_id':
      if (item.serial <= 0) return null;
      return _MetaChip(icon: Icons.tag_rounded, label: '#${item.serial}', mono: true);

    case 'creation_log':
      return _logChip(item.createdAt, item.createdByUserId, members, Icons.add_circle_outline_rounded);

    case 'last_updated':
      return _logChip(item.updatedAt, item.updatedByUserId, members, Icons.history_rounded);

    case 'auto_number':
      if (autoNumber == null) return null;
      return _MetaChip(icon: Icons.format_list_numbered_rounded, label: '$autoNumber', mono: true);

    default:
      return null;
  }
}

Widget? _logChip(DateTime? at, String? userId, List<BoardMember> members, IconData icon) {
  if (at == null) return null;
  final name = members.where((m) => m.userId == userId).firstOrNull?.fullName ?? 'Someone';
  return _MetaChip(icon: icon, label: '${DateFormat.MMMd().format(at.toLocal())} · $name');
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({this.icon, required this.label, this.mono = false, this.tint});

  final IconData? icon;
  final String label;

  /// Tabular figures for ids and counters.
  final bool mono;

  /// Overrides the label colour (e.g. amber stars).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.labelSmall;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: DfColors.textSecondary),
          const SizedBox(width: 3),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base?.copyWith(
              color: tint,
              fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
              letterSpacing: mono ? 0.2 : null,
            ),
          ),
        ),
      ]),
    );
  }
}
