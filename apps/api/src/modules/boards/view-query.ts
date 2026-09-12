import { BadRequestException } from '@nestjs/common';
import { z } from 'zod';

/**
 * The saved-view query engine: filters, sorting, column visibility and
 * conditional colours over the board payload (contract §3).
 *
 * Everything here is pure. `now` and the current user come in through
 * `QueryContext` so the same code runs identically in tests, in the CSV
 * export and (mirrored in Dart) on the client.
 *
 * Decisions the contract leaves open, resolved here:
 * - Negative operators (`not_contains`, `is_not`, `neq`, `is_none_of`) are
 *   true for an empty cell — an empty cell is "not X". Positive comparisons
 *   are false for an empty cell.
 * - `auto_number` is positional. `applyView` stamps `item.autoNumber` (the
 *   1-based index in board order, before filtering) so it can be filtered and
 *   sorted like a number; outside `applyView` the cell is missing.
 * - `creation_log`/`last_updated` compare on the item's timestamp reduced to
 *   the local calendar day, like every other date.
 * - Filtering a `link` matches the url, `location` the address.
 * - Unknown ids in `hiddenColumnIds`/`columnOrder` are dropped silently by
 *   `validateViewConfig` rather than rejected, because a column deletion must
 *   not make every saved view on the board unsaveable.
 * - Group filter values are checked against the board's group ids; label,
 *   option and user ids are not (they simply never match once removed).
 */

export type FieldKind = 'text' | 'choice' | 'people' | 'date' | 'number' | 'checkbox' | 'group' | 'files';

export interface FilterRule {
  id: string;
  field: string;
  operator: string;
  value?: unknown;
}

export interface SortRule {
  field: string;
  direction: 'asc' | 'desc';
}

export interface ConditionalColor {
  id: string;
  field: string;
  operator: string;
  value?: unknown;
  color: string;
  applyTo: 'cell' | 'row';
}

export interface ViewFilters {
  conjunction: 'and' | 'or';
  rules: FilterRule[];
}

export interface ViewConfig {
  filters?: ViewFilters;
  sort?: SortRule[];
  hiddenColumnIds?: string[];
  columnOrder?: string[];
  conditionalColors?: ConditionalColor[];
  laneColumnId?: string;
  dateColumnId?: string;
}

export interface QueryColumn {
  id: string;
  type: string;
  title: string;
  settings: unknown;
  position: number;
  scope?: string;
}

export interface QueryItem {
  id: string;
  name: string;
  position: number;
  values: Record<string, unknown>;
  serial?: number;
  createdAt?: string;
  updatedAt?: string;
  groupId?: string;
  /** 1-based index in board order; stamped by `applyView`. */
  autoNumber?: number;
}

export interface QueryGroup {
  id: string;
  title: string;
  position: number;
  items: QueryItem[];
}

export interface QueryContext {
  userId: string | null;
  now: Date;
  memberNames?: Record<string, string>;
}

export const COLOR_PALETTE = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo', 'grey'] as const;

export const DATE_PRESETS = [
  'today',
  'yesterday',
  'tomorrow',
  'this_week',
  'last_week',
  'next_week',
  'this_month',
  'last_month',
  'next_month',
  'past',
  'future',
] as const;
export type DatePreset = (typeof DATE_PRESETS)[number];

export const SORT_META_FIELDS = ['name', 'created_at', 'updated_at', 'serial'] as const;

const KIND_BY_TYPE: Record<string, FieldKind> = {
  text: 'text',
  long_text: 'text',
  email: 'text',
  phone: 'text',
  link: 'text',
  location: 'text',
  status: 'choice',
  dropdown: 'choice',
  tags: 'choice',
  people: 'people',
  vote: 'people',
  date: 'date',
  timeline: 'date',
  creation_log: 'date',
  last_updated: 'date',
  number: 'number',
  rating: 'number',
  item_id: 'number',
  auto_number: 'number',
  checkbox: 'checkbox',
  files: 'files',
};

const OPERATORS: Record<FieldKind, string[]> = {
  text: ['contains', 'not_contains', 'is', 'is_not', 'is_empty', 'is_not_empty'],
  choice: ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty'],
  people: ['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty'],
  date: ['is', 'is_before', 'is_after', 'is_between', 'is_empty', 'is_not_empty'],
  number: ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty'],
  checkbox: ['is_checked', 'is_not_checked'],
  group: ['is_any_of', 'is_none_of'],
  files: ['is_empty', 'is_not_empty'],
};

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function columnById(field: string, columns: QueryColumn[]): QueryColumn | undefined {
  return columns.find((c) => c.id === field);
}

/** The filter/sort kind of a field (`name`, `group` or a column id); null when unknown. */
export function fieldKind(field: string, columns: QueryColumn[]): FieldKind | null {
  if (field === 'name') return 'text';
  if (field === 'group') return 'group';
  const column = columnById(field, columns);
  if (!column) return null;
  return KIND_BY_TYPE[column.type] ?? null;
}

export function operatorsFor(kind: FieldKind): string[] {
  return [...OPERATORS[kind]];
}

export function isDatePreset(value: unknown): value is DatePreset {
  return typeof value === 'string' && (DATE_PRESETS as readonly string[]).includes(value);
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** `YYYY-MM-DD` of a Date in the local calendar. */
export function formatLocalDay(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function localMidnight(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function addDays(d: Date, days: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
}

/** The Monday on or before `d`. */
function startOfWeek(d: Date): Date {
  const offset = (d.getDay() + 6) % 7; // Sunday=0 → 6, Monday=1 → 0
  return addDays(d, -offset);
}

/** Inclusive `YYYY-MM-DD` bounds for a preset, in the local calendar; weeks start Monday. */
export function resolveDateRange(preset: string, now: Date): { from: string; to: string } {
  const today = localMidnight(now);
  const year = today.getFullYear();
  const month = today.getMonth();
  const span = (from: Date, to: Date) => ({ from: formatLocalDay(from), to: formatLocalDay(to) });

  switch (preset) {
    case 'today':
      return span(today, today);
    case 'yesterday':
      return span(addDays(today, -1), addDays(today, -1));
    case 'tomorrow':
      return span(addDays(today, 1), addDays(today, 1));
    case 'this_week': {
      const monday = startOfWeek(today);
      return span(monday, addDays(monday, 6));
    }
    case 'last_week': {
      const monday = addDays(startOfWeek(today), -7);
      return span(monday, addDays(monday, 6));
    }
    case 'next_week': {
      const monday = addDays(startOfWeek(today), 7);
      return span(monday, addDays(monday, 6));
    }
    case 'this_month':
      return span(new Date(year, month, 1), new Date(year, month + 1, 0));
    case 'last_month':
      return span(new Date(year, month - 1, 1), new Date(year, month, 0));
    case 'next_month':
      return span(new Date(year, month + 1, 1), new Date(year, month + 2, 0));
    case 'past':
      return { from: '0001-01-01', to: formatLocalDay(addDays(today, -1)) };
    case 'future':
      return { from: formatLocalDay(addDays(today, 1)), to: '9999-12-31' };
    default:
      throw new Error(`Unknown date preset "${preset}"`);
  }
}

/** A preset or a literal `YYYY-MM-DD` as an inclusive range; null for anything else. */
function dateTarget(value: unknown, now: Date): { from: string; to: string } | null {
  if (isDatePreset(value)) return resolveDateRange(value, now);
  if (typeof value === 'string' && ISO_DATE.test(value)) return { from: value, to: value };
  return null;
}

/** Local calendar day of an ISO timestamp; null when absent or unparsable. */
function localDayOf(iso: string | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : formatLocalDay(d);
}

// ---------------------------------------------------------------------------
// Cell reading
// ---------------------------------------------------------------------------

type Cell = string | number | boolean | string[] | null;

function record(raw: unknown): Record<string, unknown> | null {
  return typeof raw === 'object' && raw !== null && !Array.isArray(raw) ? (raw as Record<string, unknown>) : null;
}

function str(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function strArray(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
}

/** The comparable value of a field on an item, normalised per kind. */
function cellValue(field: string, columns: QueryColumn[], item: QueryItem): Cell {
  if (field === 'name') return item.name;
  if (field === 'group') return item.groupId ? [item.groupId] : [];

  const column = columnById(field, columns);
  if (!column) return null;
  const cell = record(item.values[column.id]);

  switch (column.type) {
    case 'text':
    case 'long_text':
      return str(cell?.text);
    case 'email':
      return str(cell?.email);
    case 'phone':
      return str(cell?.phone);
    case 'link':
      return str(cell?.url);
    case 'location':
      return str(cell?.address);
    case 'status':
      return typeof cell?.labelId === 'string' ? [cell.labelId] : [];
    case 'dropdown':
    case 'tags':
      return strArray(cell?.optionIds);
    case 'people':
    case 'vote':
      return strArray(cell?.userIds);
    case 'files':
      return strArray(cell?.fileIds);
    case 'date':
      return str(cell?.date);
    case 'timeline':
      return str(cell?.from);
    case 'creation_log':
      return localDayOf(item.createdAt);
    case 'last_updated':
      return localDayOf(item.updatedAt);
    case 'number':
      return num(cell?.number);
    case 'rating':
      return num(cell?.rating);
    case 'item_id':
      return num(item.serial);
    case 'auto_number':
      return num(item.autoNumber);
    case 'checkbox':
      return cell?.checked === true;
    default:
      return null;
  }
}

function isEmptyCell(value: Cell): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value === 'string') return value === '';
  if (Array.isArray(value)) return value.length === 0;
  return false;
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

function resolvePeople(ids: string[], ctx: QueryContext): string[] {
  const out: string[] = [];
  for (const id of ids) {
    if (id === 'me') {
      if (ctx.userId) out.push(ctx.userId);
    } else {
      out.push(id);
    }
  }
  return out;
}

export function matchesRule(
  item: QueryItem,
  rule: Pick<FilterRule, 'field' | 'operator' | 'value'>,
  columns: QueryColumn[],
  ctx: QueryContext,
): boolean {
  const kind = fieldKind(rule.field, columns);
  if (!kind) return false;
  if (!OPERATORS[kind].includes(rule.operator)) return false;

  const value = cellValue(rule.field, columns, item);
  const empty = isEmptyCell(value);
  const op = rule.operator;

  if (op === 'is_empty') return empty;
  if (op === 'is_not_empty') return !empty;

  switch (kind) {
    case 'text': {
      const needle = typeof rule.value === 'string' ? rule.value.toLowerCase() : null;
      if (needle === null) return false;
      const hay = empty ? '' : String(value).toLowerCase();
      switch (op) {
        case 'contains':
          return !empty && hay.includes(needle);
        case 'not_contains':
          return empty || !hay.includes(needle);
        case 'is':
          return !empty && hay === needle;
        case 'is_not':
          return empty || hay !== needle;
        default:
          return false;
      }
    }

    case 'choice':
    case 'people':
    case 'group': {
      if (!Array.isArray(rule.value)) return false;
      const wanted = kind === 'people' ? resolvePeople(strArray(rule.value), ctx) : strArray(rule.value);
      const have = Array.isArray(value) ? value : [];
      const overlap = have.some((id) => wanted.includes(id));
      if (op === 'is_any_of') return overlap;
      if (op === 'is_none_of') return !overlap;
      return false;
    }

    case 'date': {
      if (empty || typeof value !== 'string') return false;
      if (op === 'is_between') {
        if (!Array.isArray(rule.value) || rule.value.length !== 2) return false;
        const [from, to] = rule.value;
        if (typeof from !== 'string' || typeof to !== 'string') return false;
        return value >= from && value <= to;
      }
      const target = dateTarget(rule.value, ctx.now);
      if (!target) return false;
      switch (op) {
        case 'is':
          return value >= target.from && value <= target.to;
        case 'is_before':
          return value < target.from;
        case 'is_after':
          return value > target.to;
        default:
          return false;
      }
    }

    case 'number': {
      const expected = num(rule.value);
      if (expected === null) return false;
      if (empty || typeof value !== 'number') return op === 'neq';
      switch (op) {
        case 'eq':
          return value === expected;
        case 'neq':
          return value !== expected;
        case 'gt':
          return value > expected;
        case 'gte':
          return value >= expected;
        case 'lt':
          return value < expected;
        case 'lte':
          return value <= expected;
        default:
          return false;
      }
    }

    case 'checkbox':
      if (op === 'is_checked') return value === true;
      if (op === 'is_not_checked') return value !== true;
      return false;

    case 'files':
      // Only the emptiness operators exist for files; handled above.
      return false;

    default:
      return false;
  }
}

export function matchesFilters(
  item: QueryItem,
  filters: ViewFilters | undefined,
  columns: QueryColumn[],
  ctx: QueryContext,
): boolean {
  if (!filters || filters.rules.length === 0) return true;
  if (filters.conjunction === 'or') return filters.rules.some((r) => matchesRule(item, r, columns, ctx));
  return filters.rules.every((r) => matchesRule(item, r, columns, ctx));
}

// ---------------------------------------------------------------------------
// Sorting
// ---------------------------------------------------------------------------

type SortKey = string | number | null;

function labelsOf(column: QueryColumn): Array<{ id: string }> {
  const labels = (column.settings as { labels?: unknown } | null)?.labels;
  return Array.isArray(labels) ? (labels as Array<{ id: string }>) : [];
}

function optionsOf(column: QueryColumn): Array<{ id: string; label?: string }> {
  const options = (column.settings as { options?: unknown } | null)?.options;
  return Array.isArray(options) ? (options as Array<{ id: string; label?: string }>) : [];
}

function sortKey(field: string, columns: QueryColumn[], item: QueryItem, ctx: QueryContext): SortKey {
  switch (field) {
    case 'name':
      return item.name.toLowerCase();
    case 'created_at':
      return item.createdAt ?? null;
    case 'updated_at':
      return item.updatedAt ?? null;
    case 'serial':
      return num(item.serial);
  }

  const column = columnById(field, columns);
  if (!column) return null;
  const kind = KIND_BY_TYPE[column.type];
  if (!kind) return null;
  const value = cellValue(field, columns, item);

  switch (column.type) {
    case 'status': {
      if (!Array.isArray(value) || value.length === 0) return null;
      const index = labelsOf(column).findIndex((l) => l.id === value[0]);
      // Unknown labels sort after every known label but before empty cells.
      return index === -1 ? labelsOf(column).length : index;
    }
    case 'dropdown':
    case 'tags': {
      if (!Array.isArray(value) || value.length === 0) return null;
      const index = optionsOf(column).findIndex((o) => o.id === value[0]);
      return index === -1 ? optionsOf(column).length : index;
    }
    case 'people':
    case 'vote': {
      if (!Array.isArray(value) || value.length === 0) return null;
      const first = value[0];
      return (ctx.memberNames?.[first] ?? first).toLowerCase();
    }
    case 'checkbox':
      // Unchecked is a value here, not a gap: checked first on asc, last on desc.
      return value === true ? 0 : 1;
    case 'files':
      return Array.isArray(value) && value.length > 0 ? value.length : null;
    default:
      break;
  }

  if (isEmptyCell(value)) return null;
  if (typeof value === 'string') return kind === 'text' ? value.toLowerCase() : value;
  if (typeof value === 'number') return value;
  return null;
}

export function compareItems(
  a: QueryItem,
  b: QueryItem,
  sort: SortRule[],
  columns: QueryColumn[],
  ctx: QueryContext,
): number {
  for (const rule of sort) {
    const ka = sortKey(rule.field, columns, a, ctx);
    const kb = sortKey(rule.field, columns, b, ctx);
    if (ka === null && kb === null) continue;
    // Missing values sort last regardless of direction.
    if (ka === null) return 1;
    if (kb === null) return -1;
    const cmp =
      typeof ka === 'number' && typeof kb === 'number' ? ka - kb : String(ka).localeCompare(String(kb));
    if (cmp !== 0) return rule.direction === 'desc' ? -cmp : cmp;
  }
  return a.position - b.position;
}

// ---------------------------------------------------------------------------
// The view
// ---------------------------------------------------------------------------

/**
 * Applies a view's filters and sort to every group. Groups are kept even when
 * they end up empty — hiding them is a presentation decision.
 */
export function applyView(
  groups: QueryGroup[],
  config: ViewConfig,
  columns: QueryColumn[],
  ctx: QueryContext,
): QueryGroup[] {
  let counter = 0;
  return groups.map((group) => {
    const numbered = [...group.items]
      .sort((a, b) => a.position - b.position)
      .map((item) => ({ ...item, autoNumber: ++counter }));
    const kept = numbered.filter((item) => matchesFilters(item, config.filters, columns, ctx));
    const sort = config.sort ?? [];
    if (sort.length) kept.sort((a, b) => compareItems(a, b, sort, columns, ctx));
    return { ...group, items: kept };
  });
}

/** Columns of one scope, minus hidden ones, in the view's order (unlisted columns follow in board order). */
export function visibleColumns(
  columns: QueryColumn[],
  config: ViewConfig,
  scope: 'items' | 'subitems' = 'items',
): QueryColumn[] {
  const hidden = new Set(config.hiddenColumnIds ?? []);
  const inScope = columns
    .filter((c) => (c.scope ?? 'items') === scope && !hidden.has(c.id))
    .sort((a, b) => a.position - b.position);
  const byId = new Map(inScope.map((c) => [c.id, c] as const));
  const used = new Set<string>();
  const ordered: QueryColumn[] = [];
  for (const id of config.columnOrder ?? []) {
    const column = byId.get(id);
    if (column && !used.has(id)) {
      ordered.push(column);
      used.add(id);
    }
  }
  for (const column of inScope) {
    if (!used.has(column.id)) ordered.push(column);
  }
  return ordered;
}

/** The first matching cell colour for `column`, or null. */
export function cellColorFor(
  item: QueryItem,
  column: QueryColumn,
  config: ViewConfig,
  columns: QueryColumn[],
  ctx: QueryContext,
): string | null {
  for (const rule of config.conditionalColors ?? []) {
    if (rule.applyTo !== 'cell' || rule.field !== column.id) continue;
    if (matchesRule(item, rule, columns, ctx)) return rule.color;
  }
  return null;
}

/** The first matching row colour, or null. */
export function rowColorFor(
  item: QueryItem,
  config: ViewConfig,
  columns: QueryColumn[],
  ctx: QueryContext,
): string | null {
  for (const rule of config.conditionalColors ?? []) {
    if (rule.applyTo !== 'row') continue;
    if (matchesRule(item, rule, columns, ctx)) return rule.color;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

const ruleSchema = z.object({
  id: z.string().min(1),
  field: z.string().min(1),
  operator: z.string().min(1),
  value: z.unknown().optional(),
});

const conditionalColorSchema = ruleSchema.extend({
  color: z.enum(COLOR_PALETTE),
  applyTo: z.enum(['cell', 'row']),
});

const viewConfigSchema = z.object({
  filters: z
    .object({
      conjunction: z.enum(['and', 'or']),
      rules: z.array(ruleSchema),
    })
    .optional(),
  sort: z.array(z.object({ field: z.string().min(1), direction: z.enum(['asc', 'desc']) })).optional(),
  hiddenColumnIds: z.array(z.string()).optional(),
  columnOrder: z.array(z.string()).optional(),
  conditionalColors: z.array(conditionalColorSchema).optional(),
  laneColumnId: z.string().min(1).optional(),
  dateColumnId: z.string().min(1).optional(),
});

function isDateValue(v: unknown): boolean {
  return isDatePreset(v) || (typeof v === 'string' && ISO_DATE.test(v));
}

/**
 * Checks a rule's value against its operator and returns the value to store.
 * Operators that take no value store none.
 */
function normalizeRuleValue(kind: FieldKind, rule: FilterRule, groupIds: string[], where: string): unknown {
  const fail = (what: string) => {
    throw new BadRequestException(`${where} "${rule.field}" ${rule.operator}: value must be ${what}`);
  };
  const v = rule.value;
  switch (rule.operator) {
    case 'is_empty':
    case 'is_not_empty':
    case 'is_checked':
    case 'is_not_checked':
      return undefined;
    case 'contains':
    case 'not_contains':
    case 'is_not':
      if (typeof v !== 'string') fail('a string');
      return v;
    case 'is':
      if (kind === 'date') {
        if (!isDateValue(v)) fail('a date preset or a YYYY-MM-DD date');
      } else if (typeof v !== 'string') {
        fail('a string');
      }
      return v;
    case 'is_before':
    case 'is_after':
      if (!isDateValue(v)) fail('a date preset or a YYYY-MM-DD date');
      return v;
    case 'is_between':
      if (
        !Array.isArray(v) ||
        v.length !== 2 ||
        !v.every((d) => typeof d === 'string' && ISO_DATE.test(d))
      ) {
        fail('a [from, to] pair of YYYY-MM-DD dates');
      }
      return v;
    case 'is_any_of':
    case 'is_none_of': {
      if (!Array.isArray(v) || !v.every((id) => typeof id === 'string')) fail('a list of ids');
      const ids = v as string[];
      if (kind === 'group') {
        const unknown = ids.find((id) => !groupIds.includes(id));
        if (unknown !== undefined) {
          throw new BadRequestException(`${where} "${rule.field}": unknown group "${unknown}"`);
        }
      }
      return ids;
    }
    case 'eq':
    case 'neq':
    case 'gt':
    case 'gte':
    case 'lt':
    case 'lte':
      if (typeof v !== 'number' || !Number.isFinite(v)) fail('a number');
      return v;
    default:
      return v;
  }
}

function validateRule<T extends FilterRule>(rule: T, columns: QueryColumn[], groupIds: string[], where: string): T {
  const kind = fieldKind(rule.field, columns);
  if (!kind) throw new BadRequestException(`${where}: unknown field "${rule.field}"`);
  if (!OPERATORS[kind].includes(rule.operator)) {
    throw new BadRequestException(
      `${where} "${rule.field}": operator "${rule.operator}" is not valid for a ${kind} field`,
    );
  }
  const value = normalizeRuleValue(kind, rule, groupIds, where);
  const out: T = { ...rule };
  if (value === undefined) delete out.value;
  else out.value = value;
  return out;
}

function knownColumnIds(ids: string[] | undefined, columns: QueryColumn[]): string[] | undefined {
  if (!ids) return undefined;
  const known = new Set(columns.map((c) => c.id));
  return [...new Set(ids.filter((id) => known.has(id)))];
}

/**
 * Validates an untrusted view config against the board and returns the
 * normalised config. Unknown top-level keys are stripped; unknown ids in
 * `hiddenColumnIds`/`columnOrder` are dropped.
 */
export function validateViewConfig(config: unknown, columns: QueryColumn[], groupIds: string[]): ViewConfig {
  const parsed = viewConfigSchema.safeParse(config ?? {});
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const path = issue.path.length ? `${issue.path.join('.')}: ` : '';
    throw new BadRequestException(`Invalid view config — ${path}${issue.message}`);
  }
  const raw = parsed.data;
  const out: ViewConfig = {};

  if (raw.filters) {
    out.filters = {
      conjunction: raw.filters.conjunction,
      rules: raw.filters.rules.map((r, i) => validateRule(r, columns, groupIds, `Filter #${i + 1}`)),
    };
  }

  if (raw.sort) {
    const sortable = new Set<string>([...SORT_META_FIELDS, ...columns.map((c) => c.id)]);
    for (const rule of raw.sort) {
      if (!sortable.has(rule.field)) throw new BadRequestException(`Sort: unknown field "${rule.field}"`);
    }
    out.sort = raw.sort.map((r) => ({ field: r.field, direction: r.direction }));
  }

  const hidden = knownColumnIds(raw.hiddenColumnIds, columns);
  if (hidden) out.hiddenColumnIds = hidden;
  const order = knownColumnIds(raw.columnOrder, columns);
  if (order) out.columnOrder = order;

  if (raw.conditionalColors) {
    out.conditionalColors = raw.conditionalColors.map((r, i) =>
      validateRule(r, columns, groupIds, `Conditional colour #${i + 1}`),
    );
  }

  if (raw.laneColumnId !== undefined) {
    const lane = columnById(raw.laneColumnId, columns);
    if (!lane || (lane.type !== 'status' && lane.type !== 'dropdown')) {
      throw new BadRequestException('laneColumnId must be a status or dropdown column of this board');
    }
    out.laneColumnId = raw.laneColumnId;
  }

  if (raw.dateColumnId !== undefined) {
    const date = columnById(raw.dateColumnId, columns);
    if (!date || (date.type !== 'date' && date.type !== 'timeline')) {
      throw new BadRequestException('dateColumnId must be a date or timeline column of this board');
    }
    out.dateColumnId = raw.dateColumnId;
  }

  return out;
}

// ---------------------------------------------------------------------------
// Display
// ---------------------------------------------------------------------------

/** A cell flattened to a single string for CSV/export. */
export function displayValue(column: QueryColumn, item: QueryItem, ctx: QueryContext): string {
  // Board-derived types render without a stored cell.
  switch (column.type) {
    case 'item_id':
      return typeof item.serial === 'number' ? `#${item.serial}` : '';
    case 'creation_log':
      return localDayOf(item.createdAt) ?? '';
    case 'last_updated':
      return localDayOf(item.updatedAt) ?? '';
    case 'auto_number':
      return '';
  }

  const value = record(item.values[column.id]);
  if (!value) return '';

  switch (column.type) {
    case 'status': {
      const labels = (column.settings as { labels?: Array<{ id: string; label: string }> } | null)?.labels ?? [];
      return labels.find((l) => l.id === value.labelId)?.label ?? '';
    }
    case 'people': {
      const ids = strArray(value.userIds);
      if (ctx.memberNames) return ids.map((id) => ctx.memberNames?.[id] ?? id).join('; ');
      return ids.length ? `${ids.length} assigned` : '';
    }
    case 'vote': {
      const n = strArray(value.userIds).length;
      return `${n} vote(s)`;
    }
    case 'files': {
      const n = strArray(value.fileIds).length;
      return `${n} file(s)`;
    }
    case 'date':
      return [value.date, value.time].filter(Boolean).join(' ');
    case 'timeline':
      return value.from && value.to ? `${value.from} → ${value.to}` : '';
    case 'text':
    case 'long_text':
      return String(value.text ?? '');
    case 'number':
      return value.number === undefined || value.number === null ? '' : String(value.number);
    case 'rating': {
      const max = num((column.settings as { max?: unknown } | null)?.max) ?? 5;
      return typeof value.rating === 'number' ? `${value.rating}/${max}` : '';
    }
    case 'checkbox':
      return value.checked === true ? 'Yes' : '';
    case 'link':
      return String(value.url ?? '');
    case 'email':
      return String(value.email ?? '');
    case 'phone':
      return String(value.phone ?? '');
    case 'location':
      return String(value.address ?? '');
    case 'tags':
    case 'dropdown': {
      const options = optionsOf(column);
      return strArray(value.optionIds)
        .map((id) => options.find((o) => o.id === id)?.label ?? id)
        .join('; ');
    }
    default:
      return '';
  }
}
