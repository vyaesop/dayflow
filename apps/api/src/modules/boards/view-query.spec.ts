import { BadRequestException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import {
  applyView,
  cellColorFor,
  compareItems,
  DATE_PRESETS,
  displayValue,
  fieldKind,
  matchesFilters,
  matchesRule,
  operatorsFor,
  resolveDateRange,
  rowColorFor,
  validateViewConfig,
  visibleColumns,
  type FieldKind,
  type QueryColumn,
  type QueryContext,
  type QueryGroup,
  type QueryItem,
  type SortRule,
  type ViewConfig,
} from './view-query';

const USER_A = '11111111-1111-4111-8111-111111111111';
const USER_B = '22222222-2222-4222-8222-222222222222';
const USER_C = '33333333-3333-4333-8333-333333333333';

function col(id: string, type: string, settings: unknown = {}, position = 0, scope?: string): QueryColumn {
  return { id, type, title: id, settings, position, ...(scope ? { scope } : {}) };
}

const columns: QueryColumn[] = [
  col('status', 'status', {
    labels: [
      { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
      { id: 'done', label: 'Done', color: 'green', isDone: true },
      { id: 'stuck', label: 'Stuck', color: 'red', isDone: false },
    ],
  }, 1),
  col('owner', 'people', {}, 2),
  col('due', 'date', {}, 3),
  col('span', 'timeline', {}, 4),
  col('notes', 'text', {}, 5),
  col('body', 'long_text', {}, 6),
  col('amount', 'number', { unit: '$' }, 7),
  col('flag', 'checkbox', {}, 8),
  col('cat', 'dropdown', { options: [{ id: 'blog', label: 'Blog' }, { id: 'social', label: 'Social' }] }, 9),
  col('tags', 'tags', { options: [{ id: 'a', label: 'Alpha' }, { id: 'b', label: 'Beta' }, { id: 'c', label: 'Gamma' }] }, 10),
  col('site', 'link', {}, 11),
  col('mail', 'email', {}, 12),
  col('tel', 'phone', {}, 13),
  col('where', 'location', {}, 14),
  col('docs', 'files', {}, 15),
  col('stars', 'rating', { max: 5 }, 16),
  col('votes', 'vote', {}, 17),
  col('sid', 'item_id', {}, 18),
  col('created', 'creation_log', {}, 19),
  col('updated', 'last_updated', {}, 20),
  col('auto', 'auto_number', {}, 21),
  col('mystery', 'hologram', {}, 22),
  col('sub_status', 'status', { labels: [] }, 1, 'subitems'),
];

/** Saturday 12 September 2026, local midnight. */
const SATURDAY = new Date(2026, 8, 12);
const MONDAY = new Date(2026, 8, 7);
const SUNDAY = new Date(2026, 8, 13);

const ctx: QueryContext = {
  userId: USER_A,
  now: SATURDAY,
  memberNames: { [USER_A]: 'Zoe', [USER_B]: 'Adam', [USER_C]: 'Mia' },
};

/** Local noon on a September 2026 day as ISO, so the local calendar day is stable in every TZ. */
function sep(day: number): string {
  return new Date(2026, 8, day, 12).toISOString();
}

let seq = 0;
function item(values: Record<string, unknown>, extra: Partial<QueryItem> = {}): QueryItem {
  seq += 1;
  return { id: `item-${seq}`, name: `Item ${seq}`, position: seq, values, ...extra };
}

const rule = (field: string, operator: string, value?: unknown) => ({ id: 'r', field, operator, value });

// ---------------------------------------------------------------------------

describe('fieldKind', () => {
  it('maps the meta fields', () => {
    expect(fieldKind('name', columns)).toBe('text');
    expect(fieldKind('group', columns)).toBe('group');
  });

  it('maps every column type to its kind', () => {
    const expected: Record<string, FieldKind> = {
      status: 'choice',
      owner: 'people',
      due: 'date',
      span: 'date',
      notes: 'text',
      body: 'text',
      amount: 'number',
      flag: 'checkbox',
      cat: 'choice',
      tags: 'choice',
      site: 'text',
      mail: 'text',
      tel: 'text',
      where: 'text',
      docs: 'files',
      stars: 'number',
      votes: 'people',
      sid: 'number',
      created: 'date',
      updated: 'date',
      auto: 'number',
    };
    for (const [id, kind] of Object.entries(expected)) expect(fieldKind(id, columns), id).toBe(kind);
  });

  it('is null for unknown columns and unknown column types', () => {
    expect(fieldKind('nope', columns)).toBeNull();
    expect(fieldKind('mystery', columns)).toBeNull();
  });
});

describe('operatorsFor', () => {
  it('lists the contract operators per kind', () => {
    expect(operatorsFor('text')).toEqual(['contains', 'not_contains', 'is', 'is_not', 'is_empty', 'is_not_empty']);
    expect(operatorsFor('choice')).toEqual(['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty']);
    expect(operatorsFor('people')).toEqual(['is_any_of', 'is_none_of', 'is_empty', 'is_not_empty']);
    expect(operatorsFor('date')).toEqual(['is', 'is_before', 'is_after', 'is_between', 'is_empty', 'is_not_empty']);
    expect(operatorsFor('number')).toEqual(['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'is_empty', 'is_not_empty']);
    expect(operatorsFor('checkbox')).toEqual(['is_checked', 'is_not_checked']);
    expect(operatorsFor('group')).toEqual(['is_any_of', 'is_none_of']);
    expect(operatorsFor('files')).toEqual(['is_empty', 'is_not_empty']);
  });

  it('returns a copy', () => {
    operatorsFor('text').push('evil');
    expect(operatorsFor('text')).not.toContain('evil');
  });
});

// ---------------------------------------------------------------------------

describe('resolveDateRange', () => {
  it('covers every preset from a Saturday', () => {
    const expected: Record<string, [string, string]> = {
      today: ['2026-09-12', '2026-09-12'],
      yesterday: ['2026-09-11', '2026-09-11'],
      tomorrow: ['2026-09-13', '2026-09-13'],
      this_week: ['2026-09-07', '2026-09-13'],
      last_week: ['2026-08-31', '2026-09-06'],
      next_week: ['2026-09-14', '2026-09-20'],
      this_month: ['2026-09-01', '2026-09-30'],
      last_month: ['2026-08-01', '2026-08-31'],
      next_month: ['2026-10-01', '2026-10-31'],
      past: ['0001-01-01', '2026-09-11'],
      future: ['2026-09-13', '9999-12-31'],
    };
    expect(Object.keys(expected).sort()).toEqual([...DATE_PRESETS].sort());
    for (const preset of DATE_PRESETS) {
      const [from, to] = expected[preset];
      expect(resolveDateRange(preset, SATURDAY), preset).toEqual({ from, to });
    }
  });

  it('starts weeks on Monday', () => {
    expect(resolveDateRange('this_week', MONDAY)).toEqual({ from: '2026-09-07', to: '2026-09-13' });
    expect(resolveDateRange('last_week', MONDAY)).toEqual({ from: '2026-08-31', to: '2026-09-06' });
    expect(resolveDateRange('next_week', MONDAY)).toEqual({ from: '2026-09-14', to: '2026-09-20' });
    // Sunday still belongs to the week that started the previous Monday.
    expect(resolveDateRange('this_week', SUNDAY)).toEqual({ from: '2026-09-07', to: '2026-09-13' });
  });

  it('crosses year boundaries for months', () => {
    expect(resolveDateRange('last_month', new Date(2026, 0, 15))).toEqual({ from: '2025-12-01', to: '2025-12-31' });
    expect(resolveDateRange('next_month', new Date(2025, 11, 15))).toEqual({ from: '2026-01-01', to: '2026-01-31' });
    expect(resolveDateRange('this_month', new Date(2026, 1, 3))).toEqual({ from: '2026-02-01', to: '2026-02-28' });
  });

  it('ignores the time of day', () => {
    expect(resolveDateRange('today', new Date(2026, 8, 12, 23, 59))).toEqual({ from: '2026-09-12', to: '2026-09-12' });
  });

  it('throws on an unknown preset', () => {
    expect(() => resolveDateRange('someday', SATURDAY)).toThrow(/Unknown date preset/);
  });
});

// ---------------------------------------------------------------------------

describe('matchesRule — text', () => {
  const hello = item({ notes: { text: 'Hello World' } }, { name: 'Launch Plan' });
  const blank = item({ notes: { text: '' } });
  const missing = item({});

  it('handles every operator on the item name (case-insensitive)', () => {
    expect(matchesRule(hello, rule('name', 'contains', 'launch'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('name', 'contains', 'nope'), columns, ctx)).toBe(false);
    expect(matchesRule(hello, rule('name', 'not_contains', 'nope'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('name', 'is', 'launch plan'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('name', 'is', 'launch'), columns, ctx)).toBe(false);
    expect(matchesRule(hello, rule('name', 'is_not', 'launch'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('name', 'is_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(hello, rule('name', 'is_not_empty'), columns, ctx)).toBe(true);
  });

  it('handles every operator on a text column', () => {
    expect(matchesRule(hello, rule('notes', 'contains', 'WORLD'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('notes', 'not_contains', 'WORLD'), columns, ctx)).toBe(false);
    expect(matchesRule(hello, rule('notes', 'is', 'hello world'), columns, ctx)).toBe(true);
    expect(matchesRule(hello, rule('notes', 'is_not', 'hello world'), columns, ctx)).toBe(false);
  });

  it('treats a missing cell and an empty string as empty', () => {
    for (const it_ of [blank, missing]) {
      expect(matchesRule(it_, rule('notes', 'is_empty'), columns, ctx)).toBe(true);
      expect(matchesRule(it_, rule('notes', 'is_not_empty'), columns, ctx)).toBe(false);
      expect(matchesRule(it_, rule('notes', 'contains', 'x'), columns, ctx)).toBe(false);
      expect(matchesRule(it_, rule('notes', 'not_contains', 'x'), columns, ctx)).toBe(true);
      expect(matchesRule(it_, rule('notes', 'is', 'x'), columns, ctx)).toBe(false);
      expect(matchesRule(it_, rule('notes', 'is_not', 'x'), columns, ctx)).toBe(true);
    }
  });

  it('reads the text-ish column types from their own keys', () => {
    const it_ = item({
      body: { text: 'long body' },
      site: { url: 'https://example.com/docs', label: 'Handbook' },
      mail: { email: 'ann@example.com' },
      tel: { phone: '+1 555 0100' },
      where: { address: 'Berlin, Germany' },
    });
    expect(matchesRule(it_, rule('body', 'contains', 'body'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('site', 'contains', 'example.com'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('site', 'contains', 'Handbook'), columns, ctx)).toBe(false); // url, not label
    expect(matchesRule(it_, rule('mail', 'is', 'ANN@example.com'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('tel', 'contains', '555'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('where', 'contains', 'berlin'), columns, ctx)).toBe(true);
  });

  it('is false when the value is not a string', () => {
    expect(matchesRule(hello, rule('notes', 'contains', 42), columns, ctx)).toBe(false);
    expect(matchesRule(hello, rule('notes', 'is_not', ['x']), columns, ctx)).toBe(false);
  });
});

describe('matchesRule — choice', () => {
  const done = item({ status: { labelId: 'done' }, cat: { optionIds: ['blog'] }, tags: { optionIds: ['a', 'b'] } });
  const bare = item({ tags: { optionIds: [] } });

  it('matches status labels with is_any_of / is_none_of', () => {
    expect(matchesRule(done, rule('status', 'is_any_of', ['done', 'stuck']), columns, ctx)).toBe(true);
    expect(matchesRule(done, rule('status', 'is_any_of', ['working']), columns, ctx)).toBe(false);
    expect(matchesRule(done, rule('status', 'is_none_of', ['working']), columns, ctx)).toBe(true);
    expect(matchesRule(done, rule('status', 'is_none_of', ['done']), columns, ctx)).toBe(false);
  });

  it('matches tags on any overlap', () => {
    expect(matchesRule(done, rule('tags', 'is_any_of', ['b', 'c']), columns, ctx)).toBe(true);
    expect(matchesRule(done, rule('tags', 'is_any_of', ['c']), columns, ctx)).toBe(false);
    expect(matchesRule(done, rule('tags', 'is_none_of', ['c']), columns, ctx)).toBe(true);
    expect(matchesRule(done, rule('tags', 'is_none_of', ['a']), columns, ctx)).toBe(false);
  });

  it('matches a dropdown', () => {
    expect(matchesRule(done, rule('cat', 'is_any_of', ['blog']), columns, ctx)).toBe(true);
    expect(matchesRule(done, rule('cat', 'is_none_of', ['blog']), columns, ctx)).toBe(false);
  });

  it('never matches unknown label ids', () => {
    expect(matchesRule(done, rule('status', 'is_any_of', ['ghost']), columns, ctx)).toBe(false);
    expect(matchesRule(done, rule('status', 'is_none_of', ['ghost']), columns, ctx)).toBe(true);
  });

  it('treats a missing cell or an empty array as empty', () => {
    expect(matchesRule(bare, rule('status', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(bare, rule('tags', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(bare, rule('tags', 'is_not_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(done, rule('status', 'is_not_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(bare, rule('status', 'is_any_of', ['done']), columns, ctx)).toBe(false);
    expect(matchesRule(bare, rule('status', 'is_none_of', ['done']), columns, ctx)).toBe(true);
  });

  it('is false when the value is not an array', () => {
    expect(matchesRule(done, rule('status', 'is_any_of', 'done'), columns, ctx)).toBe(false);
  });
});

describe('matchesRule — people', () => {
  const mine = item({ owner: { userIds: [USER_A, USER_B] }, votes: { userIds: [USER_C] } });
  const nobody = item({ owner: { userIds: [] } });

  it('resolves "me" to the current user', () => {
    expect(matchesRule(mine, rule('owner', 'is_any_of', ['me']), columns, ctx)).toBe(true);
    expect(matchesRule(mine, rule('owner', 'is_none_of', ['me']), columns, ctx)).toBe(false);
    expect(matchesRule(mine, rule('votes', 'is_any_of', ['me']), columns, ctx)).toBe(false);
    expect(matchesRule(mine, rule('votes', 'is_none_of', ['me']), columns, ctx)).toBe(true);
  });

  it('matches explicit ids', () => {
    expect(matchesRule(mine, rule('owner', 'is_any_of', [USER_C, USER_B]), columns, ctx)).toBe(true);
    expect(matchesRule(mine, rule('owner', 'is_none_of', [USER_C]), columns, ctx)).toBe(true);
    expect(matchesRule(mine, rule('votes', 'is_any_of', [USER_C]), columns, ctx)).toBe(true);
  });

  it('"me" matches nothing for an anonymous context', () => {
    const anon: QueryContext = { userId: null, now: SATURDAY };
    expect(matchesRule(mine, rule('owner', 'is_any_of', ['me']), columns, anon)).toBe(false);
    expect(matchesRule(mine, rule('owner', 'is_none_of', ['me']), columns, anon)).toBe(true);
  });

  it('treats an empty list as empty', () => {
    expect(matchesRule(nobody, rule('owner', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(nobody, rule('votes', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(mine, rule('owner', 'is_not_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(nobody, rule('owner', 'is_not_empty'), columns, ctx)).toBe(false);
  });
});

describe('matchesRule — date', () => {
  const sat = item({ due: { date: '2026-09-12', time: '10:00' }, span: { from: '2026-09-01', to: '2026-09-20' } });
  const lastMonth = item({ due: { date: '2026-08-20' } });
  const nextYear = item({ due: { date: '2027-01-01' } });
  const missing = item({});

  it('"is" with a literal date and with presets means inside the range', () => {
    expect(matchesRule(sat, rule('due', 'is', '2026-09-12'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is', '2026-09-11'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is', 'today'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is', 'this_week'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is', 'this_month'), columns, ctx)).toBe(true);
    expect(matchesRule(lastMonth, rule('due', 'is', 'last_month'), columns, ctx)).toBe(true);
    expect(matchesRule(lastMonth, rule('due', 'is', 'this_month'), columns, ctx)).toBe(false);
    expect(matchesRule(lastMonth, rule('due', 'is', 'past'), columns, ctx)).toBe(true);
    expect(matchesRule(nextYear, rule('due', 'is', 'future'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is', 'future'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is', 'past'), columns, ctx)).toBe(false);
  });

  it('"is_before" compares to the range start, "is_after" to the range end', () => {
    // this_week = Sep 7..13
    expect(matchesRule(lastMonth, rule('due', 'is_before', 'this_week'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_before', 'this_week'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is_after', 'this_week'), columns, ctx)).toBe(false);
    expect(matchesRule(nextYear, rule('due', 'is_after', 'this_week'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_after', 'yesterday'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_before', 'tomorrow'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_before', '2026-09-12'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is_before', '2026-09-13'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_after', '2026-09-11'), columns, ctx)).toBe(true);
  });

  it('"is_between" is inclusive on both ends', () => {
    expect(matchesRule(sat, rule('due', 'is_between', ['2026-09-12', '2026-09-30']), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_between', ['2026-09-01', '2026-09-12']), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('due', 'is_between', ['2026-09-13', '2026-09-30']), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is_between', ['2026-09-12']), columns, ctx)).toBe(false);
  });

  it('uses the timeline start', () => {
    expect(matchesRule(sat, rule('span', 'is', '2026-09-01'), columns, ctx)).toBe(true);
    expect(matchesRule(sat, rule('span', 'is', '2026-09-20'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('span', 'is_before', 'this_week'), columns, ctx)).toBe(true);
  });

  it('reads creation_log and last_updated from the item timestamps', () => {
    const it_ = item({}, { createdAt: sep(3), updatedAt: sep(12) });
    expect(matchesRule(it_, rule('created', 'is', 'last_week'), columns, ctx)).toBe(true); // Sep 3 is in Aug 31..Sep 6
    expect(matchesRule(it_, rule('created', 'is', 'this_week'), columns, ctx)).toBe(false);
    expect(matchesRule(it_, rule('created', 'is', 'this_month'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('created', 'is', '2026-09-03'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('updated', 'is', 'today'), columns, ctx)).toBe(true);
    expect(matchesRule(it_, rule('updated', 'is_not_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(item({}), rule('created', 'is_empty'), columns, ctx)).toBe(true);
  });

  it('an empty cell fails every comparison and only passes is_empty', () => {
    for (const op of ['is', 'is_before', 'is_after']) {
      expect(matchesRule(missing, rule('due', op, 'today'), columns, ctx), op).toBe(false);
    }
    expect(matchesRule(missing, rule('due', 'is_between', ['2026-01-01', '2026-12-31']), columns, ctx)).toBe(false);
    expect(matchesRule(missing, rule('due', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(missing, rule('due', 'is_not_empty'), columns, ctx)).toBe(false);
  });

  it('is false for a value that is neither a preset nor a date', () => {
    expect(matchesRule(sat, rule('due', 'is', 'whenever'), columns, ctx)).toBe(false);
    expect(matchesRule(sat, rule('due', 'is', 42), columns, ctx)).toBe(false);
  });
});

describe('matchesRule — number', () => {
  const ten = item({ amount: { number: 10 }, stars: { rating: 4 } }, { serial: 7 });
  const missing = item({});

  it('handles every comparison', () => {
    expect(matchesRule(ten, rule('amount', 'eq', 10), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'eq', 11), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'neq', 11), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'neq', 10), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'gt', 9), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'gt', 10), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'gte', 10), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'lt', 10), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'lt', 11), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'lte', 10), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('amount', 'is_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'is_not_empty'), columns, ctx)).toBe(true);
  });

  it('reads rating and item_id (serial)', () => {
    expect(matchesRule(ten, rule('stars', 'gte', 4), columns, ctx)).toBe(true);
    expect(matchesRule(ten, rule('sid', 'eq', 7), columns, ctx)).toBe(true);
    expect(matchesRule(item({}), rule('sid', 'is_empty'), columns, ctx)).toBe(true);
  });

  it('an empty cell only passes neq and is_empty', () => {
    for (const op of ['eq', 'gt', 'gte', 'lt', 'lte']) {
      expect(matchesRule(missing, rule('amount', op, 0), columns, ctx), op).toBe(false);
    }
    expect(matchesRule(missing, rule('amount', 'neq', 0), columns, ctx)).toBe(true);
    expect(matchesRule(missing, rule('amount', 'is_empty'), columns, ctx)).toBe(true);
  });

  it('auto_number is missing until applyView numbers the items', () => {
    expect(matchesRule(ten, rule('auto', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule({ ...ten, autoNumber: 3 }, rule('auto', 'eq', 3), columns, ctx)).toBe(true);
  });

  it('is false for a non-numeric value', () => {
    expect(matchesRule(ten, rule('amount', 'eq', '10'), columns, ctx)).toBe(false);
    expect(matchesRule(ten, rule('amount', 'gt', Number.NaN), columns, ctx)).toBe(false);
  });
});

describe('matchesRule — checkbox, group, files', () => {
  const checked = item({ flag: { checked: true }, docs: { fileIds: [USER_A] } }, { groupId: 'g1' });
  const unchecked = item({ docs: { fileIds: [] } }, { groupId: 'g2' });

  it('checkbox', () => {
    expect(matchesRule(checked, rule('flag', 'is_checked'), columns, ctx)).toBe(true);
    expect(matchesRule(checked, rule('flag', 'is_not_checked'), columns, ctx)).toBe(false);
    expect(matchesRule(unchecked, rule('flag', 'is_checked'), columns, ctx)).toBe(false);
    expect(matchesRule(unchecked, rule('flag', 'is_not_checked'), columns, ctx)).toBe(true);
  });

  it('group', () => {
    expect(matchesRule(checked, rule('group', 'is_any_of', ['g1', 'g3']), columns, ctx)).toBe(true);
    expect(matchesRule(checked, rule('group', 'is_none_of', ['g1']), columns, ctx)).toBe(false);
    expect(matchesRule(unchecked, rule('group', 'is_any_of', ['g1']), columns, ctx)).toBe(false);
    expect(matchesRule(unchecked, rule('group', 'is_none_of', ['g1']), columns, ctx)).toBe(true);
    expect(matchesRule(item({}), rule('group', 'is_any_of', ['g1']), columns, ctx)).toBe(false);
  });

  it('files only know emptiness', () => {
    expect(matchesRule(checked, rule('docs', 'is_not_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(unchecked, rule('docs', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(item({}), rule('docs', 'is_empty'), columns, ctx)).toBe(true);
    expect(matchesRule(checked, rule('docs', 'contains', 'x'), columns, ctx)).toBe(false);
  });

  it('is false for unknown fields and operators invalid for the kind', () => {
    expect(matchesRule(checked, rule('ghost', 'is_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(checked, rule('mystery', 'is_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(checked, rule('flag', 'is_empty'), columns, ctx)).toBe(false);
    expect(matchesRule(checked, rule('name', 'gt', 1), columns, ctx)).toBe(false);
    expect(matchesRule(checked, rule('group', 'is_empty'), columns, ctx)).toBe(false);
  });
});

describe('matchesFilters', () => {
  const it_ = item({ status: { labelId: 'done' }, amount: { number: 5 } });

  it('passes everything with no filters or no rules', () => {
    expect(matchesFilters(it_, undefined, columns, ctx)).toBe(true);
    expect(matchesFilters(it_, { conjunction: 'and', rules: [] }, columns, ctx)).toBe(true);
    expect(matchesFilters(it_, { conjunction: 'or', rules: [] }, columns, ctx)).toBe(true);
  });

  it('applies and / or', () => {
    const yes = rule('status', 'is_any_of', ['done']);
    const no = rule('amount', 'gt', 100);
    expect(matchesFilters(it_, { conjunction: 'and', rules: [yes, no] }, columns, ctx)).toBe(false);
    expect(matchesFilters(it_, { conjunction: 'or', rules: [yes, no] }, columns, ctx)).toBe(true);
    expect(matchesFilters(it_, { conjunction: 'or', rules: [no, no] }, columns, ctx)).toBe(false);
    expect(matchesFilters(it_, { conjunction: 'and', rules: [yes, yes] }, columns, ctx)).toBe(true);
  });
});

// ---------------------------------------------------------------------------

function sortIds(items: QueryItem[], sort: SortRule[]): string[] {
  return [...items].sort((a, b) => compareItems(a, b, sort, columns, ctx)).map((i) => i.id);
}

function pair(field: string): [SortRule[], SortRule[]] {
  return [[{ field, direction: 'asc' }], [{ field, direction: 'desc' }]];
}

describe('compareItems', () => {
  it('status sorts by label index, missing last both ways', () => {
    const stuck = item({ status: { labelId: 'stuck' } });
    const none = item({});
    const working = item({ status: { labelId: 'working' } });
    const ghost = item({ status: { labelId: 'ghost' } });
    const [asc, desc] = pair('status');
    expect(sortIds([stuck, none, working, ghost], asc)).toEqual([working.id, stuck.id, ghost.id, none.id]);
    expect(sortIds([stuck, none, working, ghost], desc)).toEqual([ghost.id, stuck.id, working.id, none.id]);
  });

  it('dropdown and tags sort by the first selected option index', () => {
    const social = item({ tags: { optionIds: ['c', 'a'] }, cat: { optionIds: ['social'] } });
    const alpha = item({ tags: { optionIds: ['a', 'c'] }, cat: { optionIds: ['blog'] } });
    const none = item({ tags: { optionIds: [] } });
    const [asc, desc] = pair('tags');
    expect(sortIds([social, none, alpha], asc)).toEqual([alpha.id, social.id, none.id]);
    expect(sortIds([social, none, alpha], desc)).toEqual([social.id, alpha.id, none.id]);
    expect(sortIds([social, none, alpha], pair('cat')[0])).toEqual([alpha.id, social.id, none.id]);
  });

  it('people sort by the first assignee display name', () => {
    const zoe = item({ owner: { userIds: [USER_A, USER_B] } });
    const adam = item({ owner: { userIds: [USER_B] } });
    const mia = item({ votes: { userIds: [USER_C] }, owner: { userIds: [USER_C] } });
    const none = item({});
    const [asc, desc] = pair('owner');
    expect(sortIds([zoe, none, adam, mia], asc)).toEqual([adam.id, mia.id, zoe.id, none.id]);
    expect(sortIds([zoe, none, adam, mia], desc)).toEqual([zoe.id, mia.id, adam.id, none.id]);
    // Without a name map the id is used.
    const noNames: QueryContext = { userId: null, now: SATURDAY };
    expect(
      [zoe, adam].sort((a, b) => compareItems(a, b, asc, columns, noNames)).map((i) => i.id),
    ).toEqual([zoe.id, adam.id]);
  });

  it('text sorts case-insensitively', () => {
    const b = item({ notes: { text: 'banana' } });
    const a = item({ notes: { text: 'Apple' } });
    const none = item({ notes: { text: '' } });
    const c = item({ notes: { text: 'cherry' } });
    const [asc, desc] = pair('notes');
    expect(sortIds([b, none, a, c], asc)).toEqual([a.id, b.id, c.id, none.id]);
    expect(sortIds([b, none, a, c], desc)).toEqual([c.id, b.id, a.id, none.id]);
  });

  it('name sorts case-insensitively', () => {
    const b = item({}, { name: 'beta' });
    const a = item({}, { name: 'Alpha' });
    const [asc, desc] = pair('name');
    expect(sortIds([b, a], asc)).toEqual([a.id, b.id]);
    expect(sortIds([b, a], desc)).toEqual([b.id, a.id]);
  });

  it('date and timeline sort by date string', () => {
    const late = item({ due: { date: '2026-12-01' }, span: { from: '2026-12-01', to: '2026-12-02' } });
    const none = item({});
    const early = item({ due: { date: '2026-01-01' }, span: { from: '2026-01-01', to: '2026-12-31' } });
    const [asc, desc] = pair('due');
    expect(sortIds([late, none, early], asc)).toEqual([early.id, late.id, none.id]);
    expect(sortIds([late, none, early], desc)).toEqual([late.id, early.id, none.id]);
    expect(sortIds([late, none, early], pair('span')[0])).toEqual([early.id, late.id, none.id]);
  });

  it('creation_log / last_updated / created_at / updated_at / serial', () => {
    const old = item({}, { createdAt: sep(1), updatedAt: sep(11), serial: 1 });
    const none = item({});
    const recent = item({}, { createdAt: sep(10), updatedAt: sep(2), serial: 2 });
    expect(sortIds([recent, none, old], pair('created')[0])).toEqual([old.id, recent.id, none.id]);
    expect(sortIds([recent, none, old], pair('updated')[0])).toEqual([recent.id, old.id, none.id]);
    expect(sortIds([recent, none, old], pair('created_at')[1])).toEqual([recent.id, old.id, none.id]);
    expect(sortIds([recent, none, old], pair('updated_at')[0])).toEqual([recent.id, old.id, none.id]);
    expect(sortIds([recent, none, old], pair('serial')[1])).toEqual([recent.id, old.id, none.id]);
    expect(sortIds([recent, none, old], pair('sid')[0])).toEqual([old.id, recent.id, none.id]);
  });

  it('number and rating sort numerically', () => {
    const big = item({ amount: { number: 100 }, stars: { rating: 5 } });
    const none = item({});
    const small = item({ amount: { number: 9 }, stars: { rating: 1 } });
    const [asc, desc] = pair('amount');
    expect(sortIds([big, none, small], asc)).toEqual([small.id, big.id, none.id]);
    expect(sortIds([big, none, small], desc)).toEqual([big.id, small.id, none.id]);
    expect(sortIds([big, none, small], pair('stars')[1])).toEqual([big.id, small.id, none.id]);
  });

  it('checkbox: checked first on asc, unchecked first on desc', () => {
    const off = item({});
    const on = item({ flag: { checked: true } });
    const [asc, desc] = pair('flag');
    expect(sortIds([off, on], asc)).toEqual([on.id, off.id]);
    expect(sortIds([off, on], desc)).toEqual([off.id, on.id]);
  });

  it('files sort by count with empty last', () => {
    const two = item({ docs: { fileIds: [USER_A, USER_B] } });
    const none = item({ docs: { fileIds: [] } });
    const one = item({ docs: { fileIds: [USER_A] } });
    expect(sortIds([two, none, one], pair('docs')[0])).toEqual([one.id, two.id, none.id]);
    expect(sortIds([two, none, one], pair('docs')[1])).toEqual([two.id, one.id, none.id]);
  });

  it('breaks ties on board position and chains rules', () => {
    const second = item({ status: { labelId: 'done' }, amount: { number: 2 } }, { position: 20 });
    const first = item({ status: { labelId: 'done' }, amount: { number: 1 } }, { position: 10 });
    const tied = item({ status: { labelId: 'done' }, amount: { number: 1 } }, { position: 5 });
    expect(sortIds([second, first, tied], pair('status')[0])).toEqual([tied.id, first.id, second.id]);
    expect(
      sortIds([second, first, tied], [{ field: 'status', direction: 'asc' }, { field: 'amount', direction: 'desc' }]),
    ).toEqual([second.id, tied.id, first.id]);
    expect(sortIds([second, first, tied], [])).toEqual([tied.id, first.id, second.id]);
  });

  it('unknown fields and unknown column types are treated as missing', () => {
    const a = item({ mystery: { x: 1 } }, { position: 2 });
    const b = item({}, { position: 1 });
    expect(sortIds([a, b], pair('ghost')[0])).toEqual([b.id, a.id]);
    expect(sortIds([a, b], pair('mystery')[0])).toEqual([b.id, a.id]);
  });
});

// ---------------------------------------------------------------------------

describe('applyView', () => {
  const groups: QueryGroup[] = [
    {
      id: 'g1',
      title: 'Todo',
      position: 1,
      items: [
        item({ status: { labelId: 'done' }, amount: { number: 3 } }, { id: 'a', position: 2, groupId: 'g1' }),
        item({ status: { labelId: 'working' }, amount: { number: 9 } }, { id: 'b', position: 1, groupId: 'g1' }),
        item({ status: { labelId: 'done' } }, { id: 'c', position: 3, groupId: 'g1' }),
      ],
    },
    { id: 'g2', title: 'Later', position: 2, items: [item({ status: { labelId: 'stuck' } }, { id: 'd', position: 1, groupId: 'g2' })] },
    { id: 'g3', title: 'Empty', position: 3, items: [] },
  ];

  it('filters within each group, sorts, and keeps empty groups', () => {
    const config: ViewConfig = {
      filters: { conjunction: 'and', rules: [rule('status', 'is_any_of', ['done'])] },
      sort: [{ field: 'amount', direction: 'desc' }],
    };
    const out = applyView(groups, config, columns, ctx);
    expect(out.map((g) => g.id)).toEqual(['g1', 'g2', 'g3']);
    expect(out[0].items.map((i) => i.id)).toEqual(['a', 'c']);
    expect(out[1].items).toEqual([]);
    expect(out[2].items).toEqual([]);
  });

  it('keeps board order without sort rules and stamps auto numbers across groups', () => {
    const out = applyView(groups, {}, columns, ctx);
    expect(out[0].items.map((i) => [i.id, i.autoNumber])).toEqual([['b', 1], ['a', 2], ['c', 3]]);
    expect(out[1].items.map((i) => [i.id, i.autoNumber])).toEqual([['d', 4]]);
  });

  it('numbers before filtering so auto_number filters see board positions', () => {
    const config: ViewConfig = { filters: { conjunction: 'and', rules: [rule('auto', 'gte', 3)] } };
    const out = applyView(groups, config, columns, ctx);
    expect(out[0].items.map((i) => i.id)).toEqual(['c']);
    expect(out[1].items.map((i) => i.id)).toEqual(['d']);
  });

  it('does not mutate the input', () => {
    const before = JSON.stringify(groups);
    applyView(groups, { sort: [{ field: 'name', direction: 'desc' }] }, columns, ctx);
    expect(JSON.stringify(groups)).toBe(before);
  });

  it('applies "or" filters with a "me" rule end to end', () => {
    const mine: QueryGroup[] = [
      {
        id: 'g',
        title: 'G',
        position: 1,
        items: [
          item({ owner: { userIds: [USER_B] } }, { id: 'x', position: 1 }),
          item({ owner: { userIds: [USER_A] } }, { id: 'y', position: 2 }),
          item({ status: { labelId: 'stuck' } }, { id: 'z', position: 3 }),
        ],
      },
    ];
    const config: ViewConfig = {
      filters: { conjunction: 'or', rules: [rule('owner', 'is_any_of', ['me']), rule('status', 'is_any_of', ['stuck'])] },
    };
    expect(applyView(mine, config, columns, ctx)[0].items.map((i) => i.id)).toEqual(['y', 'z']);
  });
});

describe('visibleColumns', () => {
  const small: QueryColumn[] = [
    col('c', 'text', {}, 3),
    col('a', 'text', {}, 1),
    col('b', 'text', {}, 2),
    col('s', 'status', {}, 1, 'subitems'),
  ];

  it('returns item-scope columns in board order by default', () => {
    expect(visibleColumns(small, {}).map((c) => c.id)).toEqual(['a', 'b', 'c']);
  });

  it('removes hidden columns', () => {
    expect(visibleColumns(small, { hiddenColumnIds: ['b', 'ghost'] }).map((c) => c.id)).toEqual(['a', 'c']);
  });

  it('applies columnOrder, appending unlisted columns in board order', () => {
    expect(visibleColumns(small, { columnOrder: ['c', 'a'] }).map((c) => c.id)).toEqual(['c', 'a', 'b']);
    expect(visibleColumns(small, { columnOrder: ['ghost', 'b', 'b'] }).map((c) => c.id)).toEqual(['b', 'a', 'c']);
  });

  it('hidden wins over an explicit order', () => {
    expect(visibleColumns(small, { columnOrder: ['c', 'a'], hiddenColumnIds: ['c'] }).map((c) => c.id)).toEqual(['a', 'b']);
  });

  it('can select the subitem scope', () => {
    expect(visibleColumns(small, {}, 'subitems').map((c) => c.id)).toEqual(['s']);
  });
});

describe('conditional colours', () => {
  const config: ViewConfig = {
    conditionalColors: [
      { id: '1', field: 'status', operator: 'is_any_of', value: ['stuck'], color: 'red', applyTo: 'cell' },
      { id: '2', field: 'status', operator: 'is_not_empty', color: 'grey', applyTo: 'cell' },
      { id: '3', field: 'amount', operator: 'gt', value: 100, color: 'amber', applyTo: 'row' },
      { id: '4', field: 'owner', operator: 'is_any_of', value: ['me'], color: 'teal', applyTo: 'row' },
    ],
  };
  const statusCol = columns.find((c) => c.id === 'status')!;
  const amountCol = columns.find((c) => c.id === 'amount')!;

  it('first matching cell rule wins', () => {
    const stuck = item({ status: { labelId: 'stuck' } });
    const done = item({ status: { labelId: 'done' } });
    const none = item({});
    expect(cellColorFor(stuck, statusCol, config, columns, ctx)).toBe('red');
    expect(cellColorFor(done, statusCol, config, columns, ctx)).toBe('grey');
    expect(cellColorFor(none, statusCol, config, columns, ctx)).toBeNull();
  });

  it('cell rules only colour their own column and row rules never colour cells', () => {
    const rich = item({ status: { labelId: 'stuck' }, amount: { number: 500 } });
    expect(cellColorFor(rich, amountCol, config, columns, ctx)).toBeNull();
  });

  it('row rules apply in order and ignore cell rules', () => {
    const rich = item({ status: { labelId: 'stuck' }, amount: { number: 500 }, owner: { userIds: [USER_A] } });
    const mine = item({ owner: { userIds: [USER_A] } });
    const plain = item({ status: { labelId: 'stuck' } });
    expect(rowColorFor(rich, config, columns, ctx)).toBe('amber');
    expect(rowColorFor(mine, config, columns, ctx)).toBe('teal');
    expect(rowColorFor(plain, config, columns, ctx)).toBeNull();
    expect(rowColorFor(plain, {}, columns, ctx)).toBeNull();
  });
});

// ---------------------------------------------------------------------------

describe('validateViewConfig', () => {
  const groupIds = ['g1', 'g2'];

  it('accepts a full config, strips unknown keys and value-less operators', () => {
    const out = validateViewConfig(
      {
        filters: {
          conjunction: 'and',
          rules: [
            { id: 'a', field: 'status', operator: 'is_any_of', value: ['done'] },
            { id: 'b', field: 'notes', operator: 'is_empty', value: 'ignored' },
            { id: 'c', field: 'due', operator: 'is_before', value: 'next_week' },
            { id: 'd', field: 'due', operator: 'is_between', value: ['2026-01-01', '2026-02-01'] },
            { id: 'e', field: 'amount', operator: 'gte', value: 3 },
            { id: 'f', field: 'group', operator: 'is_any_of', value: ['g1'] },
            { id: 'g', field: 'flag', operator: 'is_checked' },
            { id: 'h', field: 'owner', operator: 'is_any_of', value: ['me'] },
            { id: 'i', field: 'name', operator: 'contains', value: 'x' },
            { id: 'j', field: 'docs', operator: 'is_not_empty' },
          ],
        },
        sort: [{ field: 'name', direction: 'asc' }, { field: 'amount', direction: 'desc' }, { field: 'serial', direction: 'asc' }],
        hiddenColumnIds: ['notes'],
        columnOrder: ['amount', 'status'],
        conditionalColors: [{ id: 'x', field: 'status', operator: 'is_any_of', value: ['stuck'], color: 'red', applyTo: 'row' }],
        laneColumnId: 'status',
        dateColumnId: 'due',
        somethingElse: true,
      },
      columns,
      groupIds,
    );
    expect(out).toEqual({
      filters: {
        conjunction: 'and',
        rules: [
          { id: 'a', field: 'status', operator: 'is_any_of', value: ['done'] },
          { id: 'b', field: 'notes', operator: 'is_empty' },
          { id: 'c', field: 'due', operator: 'is_before', value: 'next_week' },
          { id: 'd', field: 'due', operator: 'is_between', value: ['2026-01-01', '2026-02-01'] },
          { id: 'e', field: 'amount', operator: 'gte', value: 3 },
          { id: 'f', field: 'group', operator: 'is_any_of', value: ['g1'] },
          { id: 'g', field: 'flag', operator: 'is_checked' },
          { id: 'h', field: 'owner', operator: 'is_any_of', value: ['me'] },
          { id: 'i', field: 'name', operator: 'contains', value: 'x' },
          { id: 'j', field: 'docs', operator: 'is_not_empty' },
        ],
      },
      sort: [{ field: 'name', direction: 'asc' }, { field: 'amount', direction: 'desc' }, { field: 'serial', direction: 'asc' }],
      hiddenColumnIds: ['notes'],
      columnOrder: ['amount', 'status'],
      conditionalColors: [{ id: 'x', field: 'status', operator: 'is_any_of', value: ['stuck'], color: 'red', applyTo: 'row' }],
      laneColumnId: 'status',
      dateColumnId: 'due',
    });
  });

  it('accepts an empty, null or undefined config', () => {
    expect(validateViewConfig({}, columns, groupIds)).toEqual({});
    expect(validateViewConfig(null, columns, groupIds)).toEqual({});
    expect(validateViewConfig(undefined, columns, groupIds)).toEqual({});
  });

  it('accepts a dropdown lane and a timeline date column', () => {
    expect(validateViewConfig({ laneColumnId: 'cat', dateColumnId: 'span' }, columns, groupIds)).toEqual({
      laneColumnId: 'cat',
      dateColumnId: 'span',
    });
  });

  it('drops unknown ids from hiddenColumnIds and columnOrder, de-duplicating', () => {
    expect(
      validateViewConfig({ hiddenColumnIds: ['notes', 'ghost', 'notes'], columnOrder: ['ghost', 'amount'] }, columns, groupIds),
    ).toEqual({ hiddenColumnIds: ['notes'], columnOrder: ['amount'] });
  });

  const filters = (r: Record<string, unknown>) => ({ filters: { conjunction: 'and', rules: [{ id: 'r', ...r }] } });

  it('rejects a non-object config and malformed shapes', () => {
    expect(() => validateViewConfig('nope', columns, groupIds)).toThrow(BadRequestException);
    expect(() => validateViewConfig([], columns, groupIds)).toThrow(BadRequestException);
    expect(() => validateViewConfig({ filters: { conjunction: 'xor', rules: [] } }, columns, groupIds)).toThrow(/conjunction/);
    expect(() => validateViewConfig({ sort: [{ field: 'name', direction: 'up' }] }, columns, groupIds)).toThrow(/direction/);
    expect(() => validateViewConfig({ hiddenColumnIds: 'notes' }, columns, groupIds)).toThrow(BadRequestException);
    expect(() => validateViewConfig(filters({ field: 'name', operator: 'contains', value: 'x', id: undefined }), columns, groupIds)).toThrow(
      BadRequestException,
    );
  });

  it('rejects unknown fields', () => {
    expect(() => validateViewConfig(filters({ field: 'ghost', operator: 'is_empty' }), columns, groupIds)).toThrow(/unknown field "ghost"/);
    expect(() => validateViewConfig(filters({ field: 'mystery', operator: 'is_empty' }), columns, groupIds)).toThrow(/unknown field/);
    expect(() => validateViewConfig({ sort: [{ field: 'ghost', direction: 'asc' }] }, columns, groupIds)).toThrow(/Sort: unknown field/);
  });

  it('rejects an operator that does not fit the field kind', () => {
    expect(() => validateViewConfig(filters({ field: 'amount', operator: 'contains', value: 'x' }), columns, groupIds)).toThrow(
      /not valid for a number field/,
    );
    expect(() => validateViewConfig(filters({ field: 'flag', operator: 'is_empty' }), columns, groupIds)).toThrow(/not valid for a checkbox/);
    expect(() => validateViewConfig(filters({ field: 'group', operator: 'is_empty' }), columns, groupIds)).toThrow(/not valid for a group/);
    expect(() => validateViewConfig(filters({ field: 'docs', operator: 'is', value: 'x' }), columns, groupIds)).toThrow(/not valid for a files/);
  });

  it('rejects value shapes that do not fit the operator', () => {
    expect(() => validateViewConfig(filters({ field: 'name', operator: 'contains', value: 3 }), columns, groupIds)).toThrow(/must be a string/);
    expect(() => validateViewConfig(filters({ field: 'name', operator: 'is' }), columns, groupIds)).toThrow(/must be a string/);
    expect(() => validateViewConfig(filters({ field: 'status', operator: 'is_any_of', value: 'done' }), columns, groupIds)).toThrow(
      /list of ids/,
    );
    expect(() => validateViewConfig(filters({ field: 'owner', operator: 'is_none_of', value: [1] }), columns, groupIds)).toThrow(/list of ids/);
    expect(() => validateViewConfig(filters({ field: 'due', operator: 'is', value: 'whenever' }), columns, groupIds)).toThrow(/date preset/);
    expect(() => validateViewConfig(filters({ field: 'due', operator: 'is_after', value: '12/09/2026' }), columns, groupIds)).toThrow(
      /date preset/,
    );
    expect(() => validateViewConfig(filters({ field: 'due', operator: 'is_between', value: ['2026-01-01'] }), columns, groupIds)).toThrow(
      /\[from, to\]/,
    );
    expect(() => validateViewConfig(filters({ field: 'due', operator: 'is_between', value: ['today', 'tomorrow'] }), columns, groupIds)).toThrow(
      /\[from, to\]/,
    );
    expect(() => validateViewConfig(filters({ field: 'amount', operator: 'gt', value: '3' }), columns, groupIds)).toThrow(/must be a number/);
    expect(() => validateViewConfig(filters({ field: 'amount', operator: 'eq', value: Number.NaN }), columns, groupIds)).toThrow(
      /must be a number/,
    );
  });

  it('rejects unknown group ids', () => {
    expect(() => validateViewConfig(filters({ field: 'group', operator: 'is_any_of', value: ['g9'] }), columns, groupIds)).toThrow(
      /unknown group "g9"/,
    );
  });

  it('rejects colours outside the palette and bad applyTo', () => {
    const color = (c: Record<string, unknown>) => ({
      conditionalColors: [{ id: 'c', field: 'status', operator: 'is_not_empty', color: 'red', applyTo: 'cell', ...c }],
    });
    expect(() => validateViewConfig(color({ color: 'magenta' }), columns, groupIds)).toThrow(/color/);
    expect(() => validateViewConfig(color({ applyTo: 'column' }), columns, groupIds)).toThrow(/applyTo/);
    expect(() => validateViewConfig(color({ field: 'ghost' }), columns, groupIds)).toThrow(/Conditional colour #1: unknown field/);
    expect(() => validateViewConfig(color({ operator: 'gt', value: 1 }), columns, groupIds)).toThrow(/not valid for a choice/);
  });

  it('rejects lane and date columns of the wrong type or unknown', () => {
    expect(() => validateViewConfig({ laneColumnId: 'notes' }, columns, groupIds)).toThrow(/laneColumnId/);
    expect(() => validateViewConfig({ laneColumnId: 'ghost' }, columns, groupIds)).toThrow(/laneColumnId/);
    expect(() => validateViewConfig({ laneColumnId: 'tags' }, columns, groupIds)).toThrow(/laneColumnId/);
    expect(() => validateViewConfig({ dateColumnId: 'notes' }, columns, groupIds)).toThrow(/dateColumnId/);
    expect(() => validateViewConfig({ dateColumnId: 'created' }, columns, groupIds)).toThrow(/dateColumnId/);
    expect(() => validateViewConfig({ dateColumnId: 'ghost' }, columns, groupIds)).toThrow(/dateColumnId/);
  });
});

// ---------------------------------------------------------------------------

describe('displayValue', () => {
  const byId = (id: string) => columns.find((c) => c.id === id)!;
  const full = item(
    {
      status: { labelId: 'done' },
      owner: { userIds: [USER_B, USER_A] },
      due: { date: '2026-09-12', time: '09:30' },
      span: { from: '2026-09-01', to: '2026-09-30' },
      notes: { text: 'hello' },
      body: { text: 'line one\nline two' },
      amount: { number: 12.5 },
      flag: { checked: true },
      cat: { optionIds: ['blog'] },
      tags: { optionIds: ['a', 'zzz'] },
      site: { url: 'https://example.com', label: 'Example' },
      mail: { email: 'ann@example.com', label: 'Ann' },
      tel: { phone: '+49 30 1234', countryCode: 'DE' },
      where: { address: 'Berlin', lat: 52.5, lng: 13.4 },
      docs: { fileIds: [USER_A, USER_B, USER_C] },
      stars: { rating: 4 },
      votes: { userIds: [USER_A] },
    },
    { serial: 42, createdAt: sep(3), updatedAt: sep(12), autoNumber: 7 },
  );

  it('flattens every column type', () => {
    expect(displayValue(byId('status'), full, ctx)).toBe('Done');
    expect(displayValue(byId('owner'), full, ctx)).toBe('Adam; Zoe');
    expect(displayValue(byId('due'), full, ctx)).toBe('2026-09-12 09:30');
    expect(displayValue(byId('span'), full, ctx)).toBe('2026-09-01 → 2026-09-30');
    expect(displayValue(byId('notes'), full, ctx)).toBe('hello');
    expect(displayValue(byId('body'), full, ctx)).toBe('line one\nline two');
    expect(displayValue(byId('amount'), full, ctx)).toBe('12.5');
    expect(displayValue(byId('flag'), full, ctx)).toBe('Yes');
    expect(displayValue(byId('cat'), full, ctx)).toBe('Blog');
    expect(displayValue(byId('tags'), full, ctx)).toBe('Alpha; zzz');
    expect(displayValue(byId('site'), full, ctx)).toBe('https://example.com');
    expect(displayValue(byId('mail'), full, ctx)).toBe('ann@example.com');
    expect(displayValue(byId('tel'), full, ctx)).toBe('+49 30 1234');
    expect(displayValue(byId('where'), full, ctx)).toBe('Berlin');
    expect(displayValue(byId('docs'), full, ctx)).toBe('3 file(s)');
    expect(displayValue(byId('stars'), full, ctx)).toBe('4/5');
    expect(displayValue(byId('votes'), full, ctx)).toBe('1 vote(s)');
    expect(displayValue(byId('sid'), full, ctx)).toBe('#42');
    expect(displayValue(byId('created'), full, ctx)).toBe('2026-09-03');
    expect(displayValue(byId('updated'), full, ctx)).toBe('2026-09-12');
    expect(displayValue(byId('auto'), full, ctx)).toBe('');
  });

  it('falls back to a count for people without a name map, and to ids for unknown names', () => {
    const noNames: QueryContext = { userId: null, now: SATURDAY };
    expect(displayValue(byId('owner'), full, noNames)).toBe('2 assigned');
    expect(displayValue(byId('owner'), full, { ...ctx, memberNames: { [USER_B]: 'Adam' } })).toBe(`Adam; ${USER_A}`);
  });

  it('uses the rating max from settings', () => {
    expect(displayValue(col('r', 'rating', { max: 10 }), item({ r: { rating: 7 } }), ctx)).toBe('7/10');
  });

  it('renders empty cells as the empty string', () => {
    const empty = item({});
    for (const c of columns) expect(displayValue(c, empty, ctx), c.id).toBe('');
    expect(displayValue(byId('status'), item({ status: { labelId: 'ghost' } }), ctx)).toBe('');
    expect(displayValue(byId('span'), item({ span: { from: '2026-01-01' } }), ctx)).toBe('');
  });
});
