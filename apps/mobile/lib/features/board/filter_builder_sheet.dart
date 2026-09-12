import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/widgets/df_button.dart';
import 'batch_bar.dart' show showPeoplePicker;
import 'cell_editors.dart' show promptForText;
import 'columns_sheet.dart' show columnTypeIcon;
import 'view_engine.dart';

// ------------------------------------------------------------------ fields

/// A filterable field: `name`, `group` or an item column.
class RuleField {
  const RuleField({required this.id, required this.label, required this.icon, required this.kind});

  final String id;
  final String label;
  final IconData icon;
  final FieldKind kind;
}

/// Name, Group, then the board's item columns that have a filter kind.
List<RuleField> filterableFields(BoardDetail board) => [
      const RuleField(id: 'name', label: 'Name', icon: Icons.title_rounded, kind: FieldKind.text),
      const RuleField(id: 'group', label: 'Group', icon: Icons.folder_outlined, kind: FieldKind.group),
      for (final column in board.itemColumns)
        if (fieldKindForType(column.type) case final kind?)
          RuleField(id: column.id, label: column.title, icon: columnTypeIcon(column.type), kind: kind),
    ];

RuleField? fieldById(List<RuleField> fields, String id) => fields.where((f) => f.id == id).firstOrNull;

/// A fresh rule on the first field with its first operator.
FilterRule newFilterRule(List<RuleField> fields) {
  final field = fields.first;
  return FilterRule(id: _newId(), field: field.id, operator: operatorsFor(field.kind).first);
}

String _newId() => 'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Human label of a rule's value for the chip; "value" when it is still unset.
String ruleValueLabel(BoardDetail board, List<BoardMember> members, FilterRule rule) {
  if (!operatorNeedsValue(rule.operator)) return '';
  final kind = fieldKindFor(rule.field, board.columns);
  final value = rule.value;
  if (value == null || (value is List && value.isEmpty) || (value is String && value.isEmpty)) return 'value';
  final column = board.columns.where((c) => c.id == rule.field).firstOrNull;
  switch (kind) {
    case FieldKind.choice:
      final ids = _asList(value);
      final names = ids.map((id) => _choiceLabel(column, id)).toList();
      return _joinNames(names);
    case FieldKind.people:
      final names = _asList(value)
          .map((id) => id == 'me' ? 'Me' : members.where((m) => m.userId == id).firstOrNull?.fullName ?? 'Someone')
          .toList();
      return _joinNames(names);
    case FieldKind.group:
      final names = _asList(value).map((id) => board.groups.where((g) => g.id == id).firstOrNull?.title ?? '?').toList();
      return _joinNames(names);
    case FieldKind.date:
      if (rule.operator == 'is_between' && value is List && value.length >= 2) {
        return '${_dateLabel(value[0].toString())} – ${_dateLabel(value[1].toString())}';
      }
      final text = value.toString();
      return datePresets.contains(text) ? datePresetLabel(text) : _dateLabel(text);
    default:
      return value.toString();
  }
}

String _joinNames(List<String> names) {
  if (names.isEmpty) return 'value';
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

String _choiceLabel(BoardColumn? column, String id) {
  if (column == null) return id;
  if (column.type == 'status') return column.statusLabels.where((l) => l.id == id).firstOrNull?.label ?? id;
  return column.options.where((o) => o['id'] == id).firstOrNull?['label']?.toString() ?? id;
}

String _dateLabel(String ymd) {
  final parsed = DateTime.tryParse(ymd);
  return parsed == null ? ymd : DateFormat.MMMd().format(parsed);
}

List<String> _asList(Object? value) {
  if (value is List) return [for (final v in value) if (v != null) v.toString()];
  if (value is String && value.isNotEmpty) return [value];
  return const [];
}

// ------------------------------------------------------------------- sheet

/// "Where `field` `operator` `value`" rows with add/remove and an And/Or
/// toggle. Returns the edited group (possibly with no rules) or null when
/// dismissed without applying.
Future<FilterGroup?> showFilterBuilderSheet(
  BuildContext context, {
  required BoardDetail board,
  required List<BoardMember> members,
  FilterGroup? initial,
}) {
  return showModalBottomSheet<FilterGroup>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) => _FilterBuilderSheet(
        board: board,
        members: members,
        initial: initial ?? const FilterGroup(),
        scrollController: scrollController,
      ),
    ),
  );
}

class _FilterBuilderSheet extends StatefulWidget {
  const _FilterBuilderSheet({
    required this.board,
    required this.members,
    required this.initial,
    required this.scrollController,
  });

  final BoardDetail board;
  final List<BoardMember> members;
  final FilterGroup initial;
  final ScrollController scrollController;

  @override
  State<_FilterBuilderSheet> createState() => _FilterBuilderSheetState();
}

class _FilterBuilderSheetState extends State<_FilterBuilderSheet> {
  late FilterGroup _group = widget.initial;
  late final List<RuleField> _fields = filterableFields(widget.board);

  void _update(int index, FilterRule rule) => setState(() {
        final rules = [..._group.rules];
        rules[index] = rule;
        _group = _group.copyWith(rules: rules);
      });

  void _remove(int index) => setState(() {
        final rules = [..._group.rules]..removeAt(index);
        _group = _group.copyWith(rules: rules);
      });

  void _add() => setState(() => _group = _group.copyWith(rules: [..._group.rules, newFilterRule(_fields)]));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rules = _group.rules;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(DfSpacing.md, DfSpacing.md, DfSpacing.md, DfSpacing.xs),
        child: Row(children: [
          Expanded(child: Text('Filters', style: text.titleLarge)),
          if (rules.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _group = _group.copyWith(rules: const [])),
              child: const Text('Clear all'),
            ),
        ]),
      ),
      if (rules.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md),
          child: Row(children: [
            Text('Show items that match', style: text.bodySmall),
            const SizedBox(width: DfSpacing.xs),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 'and', label: Text('All')),
                ButtonSegment(value: 'or', label: Text('Any')),
              ],
              selected: {_group.conjunction},
              onSelectionChanged: (selection) =>
                  setState(() => _group = _group.copyWith(conjunction: selection.first)),
            ),
          ]),
        ),
      Expanded(
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: DfSpacing.md, vertical: DfSpacing.xs),
          children: [
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DfSpacing.lg),
                child: Text(
                  'No filters yet. Add one to narrow down what this view shows.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            for (final (index, rule) in rules.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: DfSpacing.xs),
                child: RuleEditorRow(
                  prefix: index == 0 ? 'Where' : (_group.conjunction == 'or' ? 'Or' : 'And'),
                  rule: rule,
                  board: widget.board,
                  members: widget.members,
                  fields: _fields,
                  onChanged: (next) => _update(index, next),
                  onDelete: () => _remove(index),
                ),
              ),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(rules.isEmpty ? 'Add filter' : 'Add another filter'),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: DfButton(label: 'Apply', onPressed: () => Navigator.pop(context, _group)),
      ),
    ]);
  }
}

// -------------------------------------------------------------- rule row

/// One rule: prefix · field chip · operator chip · value chip · delete. Shared
/// by the filter builder and the conditional-colors sheet.
class RuleEditorRow extends StatelessWidget {
  const RuleEditorRow({
    super.key,
    required this.prefix,
    required this.rule,
    required this.board,
    required this.members,
    required this.fields,
    required this.onChanged,
    required this.onDelete,
    this.trailing,
  });

  final String prefix;
  final FilterRule rule;
  final BoardDetail board;
  final List<BoardMember> members;
  final List<RuleField> fields;
  final ValueChanged<FilterRule> onChanged;
  final VoidCallback onDelete;

  /// Extra controls rendered after the rule (e.g. a colour swatch).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final field = fieldById(fields, rule.field);
    final kind = field?.kind;
    final needsValue = operatorNeedsValue(rule.operator);

    return Container(
      padding: const EdgeInsets.fromLTRB(DfSpacing.sm, DfSpacing.xs, DfSpacing.xxs, DfSpacing.xs),
      decoration: BoxDecoration(
        color: isDark ? DfColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(DfRadius.md),
        border: Border.all(color: isDark ? DfColors.borderDark : DfColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(width: 44, child: Text(prefix, style: text.labelMedium)),
        ),
        Expanded(
          child: Wrap(spacing: DfSpacing.xxs, runSpacing: DfSpacing.xxs, children: [
            RulePill(
              icon: field?.icon,
              label: field?.label ?? 'Deleted column',
              onTap: () async {
                final picked = await pickRuleField(context, fields, current: rule.field);
                if (picked == null || picked.id == rule.field) return;
                onChanged(rule.copyWith(
                  field: picked.id,
                  operator: operatorsFor(picked.kind).first,
                  value: () => null,
                ));
              },
            ),
            RulePill(
              label: operatorLabel(rule.operator),
              onTap: kind == null
                  ? null
                  : () async {
                      final picked = await pickOperator(context, kind, current: rule.operator);
                      if (picked == null || picked == rule.operator) return;
                      final keepValue = operatorNeedsValue(picked) &&
                          (picked == 'is_between') == (rule.operator == 'is_between');
                      onChanged(rule.copyWith(operator: picked, value: keepValue ? null : () => null));
                    },
            ),
            if (needsValue && kind != null)
              RulePill(
                label: ruleValueLabel(board, members, rule),
                emphasized: rule.value != null,
                onTap: () async {
                  final result = await editRuleValue(
                    context,
                    board: board,
                    members: members,
                    field: rule.field,
                    operator: rule.operator,
                    current: rule.value,
                  );
                  if (result == null) return;
                  onChanged(rule.copyWith(value: () => result.value));
                },
              ),
            ?trailing,
          ]),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 18, color: DfColors.textTertiary),
          tooltip: 'Remove',
          onPressed: onDelete,
        ),
      ]),
    );
  }
}

/// Compact pill button used for the field / operator / value parts of a rule.
class RulePill extends StatelessWidget {
  const RulePill({super.key, required this.label, this.icon, this.onTap, this.emphasized = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DfRadius.pill),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: DfSpacing.xs),
        decoration: BoxDecoration(
          color: emphasized
              ? (isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle)
              : (isDark ? DfColors.surfaceAltDark : DfColors.surfaceAlt),
          borderRadius: BorderRadius.circular(DfRadius.pill),
          border: Border.all(color: emphasized ? DfColors.primaryBorder : (isDark ? DfColors.borderDark : DfColors.border)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: emphasized ? DfColors.primary : DfColors.textSecondary),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(
                color: emphasized ? DfColors.primary : (isDark ? DfColors.textPrimaryDark : DfColors.textPrimary),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- pickers

Future<RuleField?> pickRuleField(BuildContext context, List<RuleField> fields, {String? current}) {
  return showModalBottomSheet<RuleField>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (draggableContext, scrollController) => ListView(
        controller: scrollController,
        children: [
          Padding(
            padding: const EdgeInsets.all(DfSpacing.md),
            child: Text('Field', style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          for (final field in fields)
            ListTile(
              leading: Icon(field.icon, size: 20, color: DfColors.primary),
              title: Text(field.label),
              trailing: field.id == current ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
              onTap: () => Navigator.pop(sheetContext, field),
            ),
        ],
      ),
    ),
  );
}

Future<String?> pickOperator(BuildContext context, FieldKind kind, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.all(DfSpacing.md),
          child: Text('Condition', style: Theme.of(sheetContext).textTheme.titleMedium),
        ),
        for (final op in operatorsFor(kind))
          ListTile(
            title: Text(operatorLabel(op)),
            trailing: op == current ? const Icon(Icons.check_rounded, color: DfColors.primary) : null,
            onTap: () => Navigator.pop(sheetContext, op),
          ),
      ]),
    ),
  );
}

/// Opens the right value editor for the field's kind. Returns null when
/// dismissed; otherwise a record whose `value` may itself be null (cleared).
Future<({Object? value})?> editRuleValue(
  BuildContext context, {
  required BoardDetail board,
  required List<BoardMember> members,
  required String field,
  required String operator,
  Object? current,
}) async {
  final kind = fieldKindFor(field, board.columns);
  final column = board.columns.where((c) => c.id == field).firstOrNull;
  switch (kind) {
    case FieldKind.text:
      final value = await promptForText(context, title: 'Value', initial: current?.toString() ?? '');
      if (value == null) return null;
      return (value: value.isEmpty ? null : value);

    case FieldKind.number:
      final value = await promptForText(
        context,
        title: 'Value',
        initial: current?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        validator: (raw) => raw.isEmpty || num.tryParse(raw) != null ? null : 'Enter a number',
      );
      if (value == null) return null;
      return (value: value.isEmpty ? null : num.parse(value));

    case FieldKind.choice:
      if (column == null) return null;
      final options = column.type == 'status'
          ? [for (final l in column.statusLabels) (id: l.id, label: l.label, color: l.color)]
          : [
              for (final o in column.options)
                (id: o['id'] as String, label: o['label']?.toString() ?? '', color: o['color']?.toString()),
            ];
      final picked = await _pickMany(
        context,
        title: column.title,
        options: options,
        selected: _asList(current),
      );
      if (picked == null) return null;
      return (value: picked.isEmpty ? null : picked);

    case FieldKind.people:
      final picked = await showPeoplePicker(
        context,
        members: members,
        selected: _asList(current),
        includeMe: true,
        title: column?.title ?? 'People',
      );
      if (picked == null) return null;
      return (value: picked.isEmpty ? null : picked);

    case FieldKind.group:
      final picked = await _pickMany(
        context,
        title: 'Groups',
        options: [for (final g in board.groups) (id: g.id, label: g.title, color: g.color)],
        selected: _asList(current),
      );
      if (picked == null) return null;
      return (value: picked.isEmpty ? null : picked);

    case FieldKind.date:
      if (operator == 'is_between') {
        final bounds = current is List && current.length >= 2 ? current : null;
        final picked = await showModalBottomSheet<List<String>>(
          context: context,
          builder: (sheetContext) => _BetweenEditor(
            from: bounds?[0]?.toString(),
            to: bounds?[1]?.toString(),
          ),
        );
        if (picked == null) return null;
        return (value: picked);
      }
      final picked = await showModalBottomSheet<({String? value})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => _DateValueEditor(current: current?.toString()),
      );
      if (picked == null) return null;
      return (value: picked.value);

    case FieldKind.checkbox:
    case FieldKind.files:
    case null:
      return null;
  }
}

Future<List<String>?> _pickMany(
  BuildContext context, {
  required String title,
  required List<({String id, String label, String? color})> options,
  required List<String> selected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _MultiPickSheet(title: title, options: options, selected: selected),
  );
}

class _MultiPickSheet extends StatefulWidget {
  const _MultiPickSheet({required this.title, required this.options, required this.selected});

  final String title;
  final List<({String id, String label, String? color})> options;
  final List<String> selected;

  @override
  State<_MultiPickSheet> createState() => _MultiPickSheetState();
}

class _MultiPickSheetState extends State<_MultiPickSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (widget.options.isEmpty)
            const Padding(padding: EdgeInsets.all(DfSpacing.md), child: Text('Nothing to choose from yet.')),
          for (final option in widget.options)
            CheckboxListTile(
              value: _selected.contains(option.id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(option.id);
                } else {
                  _selected.remove(option.id);
                }
              }),
              title: Text(option.label),
              secondary: option.color == null
                  ? null
                  : Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: DfColors.token(option.color!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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

/// Preset chips or a specific day.
class _DateValueEditor extends StatelessWidget {
  const _DateValueEditor({this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSpecific = current != null && !datePresets.contains(current);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Date', style: text.titleMedium),
          const SizedBox(height: DfSpacing.sm),
          Wrap(spacing: DfSpacing.xs, runSpacing: DfSpacing.xs, children: [
            for (final preset in datePresets)
              ChoiceChip(
                label: Text(datePresetLabel(preset)),
                selected: current == preset,
                showCheckmark: false,
                shape: const StadiumBorder(),
                selectedColor: isDark ? DfColors.primary.withValues(alpha: 0.22) : DfColors.primarySubtle,
                onSelected: (_) => Navigator.pop(context, (value: preset)),
              ),
          ]),
          const SizedBox(height: DfSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded, color: DfColors.primary),
            title: Text(isSpecific ? _dateLabel(current!) : 'Pick a specific day'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: (isSpecific ? DateTime.tryParse(current!) : null) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null || !context.mounted) return;
              Navigator.pop(context, (value: formatYmd(picked)));
            },
          ),
          if (current != null)
            TextButton(onPressed: () => Navigator.pop(context, (value: null)), child: const Text('Clear')),
        ]),
      ),
    );
  }
}

/// Two day pickers for `is_between`.
class _BetweenEditor extends StatefulWidget {
  const _BetweenEditor({this.from, this.to});

  final String? from;
  final String? to;

  @override
  State<_BetweenEditor> createState() => _BetweenEditorState();
}

class _BetweenEditorState extends State<_BetweenEditor> {
  late String? _from = widget.from;
  late String? _to = widget.to;

  Future<void> _pick(bool isFrom) async {
    final existing = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: (existing == null ? null : DateTime.tryParse(existing)) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = formatYmd(picked);
      } else {
        _to = formatYmd(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final valid = _from != null && _to != null && _from!.compareTo(_to!) <= 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(DfSpacing.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Between', style: text.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.first_page_rounded, color: DfColors.primary),
            title: Text(_from == null ? 'From' : _dateLabel(_from!)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.last_page_rounded, color: DfColors.primary),
            title: Text(_to == null ? 'To' : _dateLabel(_to!)),
            onTap: () => _pick(false),
          ),
          if (_from != null && _to != null && !valid)
            Text('The end must not be before the start.', style: text.labelSmall?.copyWith(color: DfColors.danger)),
          const SizedBox(height: DfSpacing.sm),
          DfButton(label: 'Done', onPressed: valid ? () => Navigator.pop(context, [_from!, _to!]) : null),
        ]),
      ),
    );
  }
}
