import { describe, expect, it } from 'vitest';
import { planColumnMapping, remapCellValue, type TransferColumn } from './board-transfer';

const col = (id: string, type: string, title: string, scope = 'items', settings: unknown = {}): TransferColumn => ({
  id,
  type,
  title,
  scope,
  settings,
});

describe('planColumnMapping', () => {
  it('pairs columns by scope, type and case-insensitive title', () => {
    const plan = planColumnMapping(
      [col('s1', 'status', 'Status'), col('s2', 'people', 'owner'), col('s3', 'text', 'Notes')],
      [col('t1', 'people', 'Owner'), col('t2', 'status', 'STATUS'), col('t3', 'number', 'Notes')],
    );
    expect(plan.mapping.map((m) => [m.sourceColumnId, m.targetColumnId])).toEqual([
      ['s1', 't2'],
      ['s2', 't1'],
      ['s3', null],
    ]);
    expect(plan.dropped).toEqual([{ columnId: 's3', title: 'Notes', type: 'text' }]);
  });

  it('never reuses a target column and keeps scopes apart', () => {
    const plan = planColumnMapping(
      [col('a', 'date', 'Date'), col('b', 'date', 'Date'), col('c', 'date', 'Date', 'subitems')],
      [col('x', 'date', 'Date'), col('y', 'date', 'Date', 'subitems')],
    );
    expect(plan.mapping.map((m) => m.targetColumnId)).toEqual(['x', null, 'y']);
  });

  it('skips read-only metadata columns entirely', () => {
    const plan = planColumnMapping([col('a', 'item_id', 'ID'), col('b', 'auto_number', '#')], []);
    expect(plan.mapping).toEqual([]);
    expect(plan.dropped).toEqual([]);
  });
});

describe('remapCellValue', () => {
  const sourceStatus = { labels: [{ id: 'w', label: 'Working on it' }, { id: 'd', label: 'Done' }] };
  const targetStatus = { labels: [{ id: 'done_x', label: 'done' }, { id: 'stuck', label: 'Stuck' }] };

  it('maps status labels by text and drops unmatched ones', () => {
    expect(remapCellValue('status', { labelId: 'd' }, sourceStatus, targetStatus)).toEqual({ labelId: 'done_x' });
    expect(remapCellValue('status', { labelId: 'w' }, sourceStatus, targetStatus)).toBeNull();
    expect(remapCellValue('status', { labelId: 'zzz' }, sourceStatus, targetStatus)).toBeNull();
  });

  it('maps dropdown/tags options by text, de-duplicated', () => {
    const source = { options: [{ id: 'a', label: 'Blog' }, { id: 'b', label: 'Social' }] };
    const target = { options: [{ id: 'x', label: 'blog' }, { id: 'y', label: 'Email' }] };
    expect(remapCellValue('tags', { optionIds: ['a', 'b', 'a'] }, source, target)).toEqual({ optionIds: ['x'] });
    expect(remapCellValue('dropdown', { optionIds: ['b'] }, source, target)).toBeNull();
  });

  it('clamps ratings to the target scale', () => {
    expect(remapCellValue('rating', { rating: 8 }, { max: 10 }, { max: 5 })).toEqual({ rating: 5 });
    expect(remapCellValue('rating', { rating: 3 }, {}, {})).toEqual({ rating: 3 });
  });

  it('copies every other type verbatim and passes null through', () => {
    expect(remapCellValue('text', { text: 'hi' }, {}, {})).toEqual({ text: 'hi' });
    expect(remapCellValue('people', { userIds: ['u1'] }, {}, {})).toEqual({ userIds: ['u1'] });
    expect(remapCellValue('date', null, {}, {})).toBeNull();
  });
});
