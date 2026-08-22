import { BadRequestException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { assignedUserIds, defaultSettingsFor, normalizeColumnValue, type ColumnSettings } from './column-values';

const statusSettings: ColumnSettings = {
  labels: [
    { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
    { id: 'done', label: 'Done', color: 'green', isDone: true },
  ],
};

const dropdownSettings: ColumnSettings = {
  options: [
    { id: 'blog', label: 'Blog' },
    { id: 'social', label: 'Social' },
  ],
};

const USER_A = '11111111-1111-4111-8111-111111111111';
const USER_B = '22222222-2222-4222-8222-222222222222';

describe('normalizeColumnValue — clearing', () => {
  it('treats null and undefined as "clear the cell" for every type', () => {
    for (const type of ['status', 'people', 'date', 'text', 'number', 'checkbox']) {
      expect(normalizeColumnValue(type, statusSettings, null)).toBeNull();
      expect(normalizeColumnValue(type, statusSettings, undefined)).toBeNull();
    }
  });

  it('rejects non-object values', () => {
    expect(() => normalizeColumnValue('text', {}, 'plain string')).toThrow(BadRequestException);
    expect(() => normalizeColumnValue('text', {}, 42)).toThrow(BadRequestException);
    expect(() => normalizeColumnValue('text', {}, ['a'])).toThrow(BadRequestException);
  });

  it('rejects a type that is not editable', () => {
    expect(() => normalizeColumnValue('mystery', {}, { x: 1 })).toThrow(/cannot be edited/);
  });
});

describe('normalizeColumnValue — status', () => {
  it('accepts a label defined on the column', () => {
    expect(normalizeColumnValue('status', statusSettings, { labelId: 'done' })).toEqual({ labelId: 'done' });
  });

  it('rejects a label the column does not define', () => {
    expect(() => normalizeColumnValue('status', statusSettings, { labelId: 'nope' })).toThrow(/Unknown status label/);
  });

  it('rejects any label when the column has no labels configured', () => {
    expect(() => normalizeColumnValue('status', {}, { labelId: 'done' })).toThrow(/Unknown status label/);
  });

  it('clears when labelId is null', () => {
    expect(normalizeColumnValue('status', statusSettings, { labelId: null })).toBeNull();
  });

  it('drops unrecognised extra keys', () => {
    expect(normalizeColumnValue('status', statusSettings, { labelId: 'done', evil: true })).toEqual({
      labelId: 'done',
    });
  });
});

describe('normalizeColumnValue — people', () => {
  it('accepts and de-duplicates user ids, preserving order', () => {
    expect(normalizeColumnValue('people', {}, { userIds: [USER_B, USER_A, USER_B] })).toEqual({
      userIds: [USER_B, USER_A],
    });
  });

  it('clears on an empty list', () => {
    expect(normalizeColumnValue('people', {}, { userIds: [] })).toBeNull();
    expect(normalizeColumnValue('people', {}, {})).toBeNull();
  });

  it('rejects ids that are not uuids', () => {
    expect(() => normalizeColumnValue('people', {}, { userIds: ['not-a-uuid'] })).toThrow(/not a valid user id/);
  });

  it('rejects a non-array', () => {
    expect(() => normalizeColumnValue('people', {}, { userIds: USER_A })).toThrow(/must be an array/);
  });
});

describe('normalizeColumnValue — date', () => {
  it('accepts an ISO date, with or without a time', () => {
    expect(normalizeColumnValue('date', {}, { date: '2026-08-15' })).toEqual({ date: '2026-08-15' });
    expect(normalizeColumnValue('date', {}, { date: '2026-08-15', time: '09:30' })).toEqual({
      date: '2026-08-15',
      time: '09:30',
    });
  });

  it('rejects other date formats', () => {
    expect(() => normalizeColumnValue('date', {}, { date: '15/08/2026' })).toThrow(/YYYY-MM-DD/);
  });

  it('rejects an impossible date that still matches the pattern', () => {
    expect(() => normalizeColumnValue('date', {}, { date: '2026-02-31' })).toThrow(/not a real date/);
  });

  it('rejects a malformed time', () => {
    expect(() => normalizeColumnValue('date', {}, { date: '2026-08-15', time: '25:00' })).toThrow(/HH:mm/);
    expect(() => normalizeColumnValue('date', {}, { date: '2026-08-15', time: '9:30' })).toThrow(/HH:mm/);
  });
});

describe('normalizeColumnValue — timeline', () => {
  it('accepts a forward range', () => {
    expect(normalizeColumnValue('timeline', {}, { from: '2026-08-01', to: '2026-08-31' })).toEqual({
      from: '2026-08-01',
      to: '2026-08-31',
    });
  });

  it('rejects a reversed range', () => {
    expect(() => normalizeColumnValue('timeline', {}, { from: '2026-09-01', to: '2026-08-01' })).toThrow(
      /must not be after/,
    );
  });

  it('clears when both ends are absent', () => {
    expect(normalizeColumnValue('timeline', {}, {})).toBeNull();
  });
});

describe('normalizeColumnValue — text and number', () => {
  it('keeps text and clears the empty string', () => {
    expect(normalizeColumnValue('text', {}, { text: 'hello' })).toEqual({ text: 'hello' });
    expect(normalizeColumnValue('text', {}, { text: '' })).toBeNull();
  });

  it('rejects text past the length cap', () => {
    expect(() => normalizeColumnValue('text', {}, { text: 'x'.repeat(5001) })).toThrow(/at most 5000/);
  });

  it('accepts finite numbers including zero and negatives', () => {
    expect(normalizeColumnValue('number', {}, { number: 0 })).toEqual({ number: 0 });
    expect(normalizeColumnValue('number', {}, { number: -12.5 })).toEqual({ number: -12.5 });
  });

  it('rejects non-finite and non-numeric values', () => {
    expect(() => normalizeColumnValue('number', {}, { number: Number.POSITIVE_INFINITY })).toThrow(/finite/);
    expect(() => normalizeColumnValue('number', {}, { number: '12' })).toThrow(/finite/);
  });
});

describe('normalizeColumnValue — checkbox', () => {
  it('stores only the checked state', () => {
    expect(normalizeColumnValue('checkbox', {}, { checked: true })).toEqual({ checked: true });
  });

  it('treats unchecked as empty so the default is absence', () => {
    expect(normalizeColumnValue('checkbox', {}, { checked: false })).toBeNull();
  });

  it('rejects a non-boolean', () => {
    expect(() => normalizeColumnValue('checkbox', {}, { checked: 'yes' })).toThrow(/boolean/);
  });
});

describe('normalizeColumnValue — dropdown and tags', () => {
  it('accepts options the column defines', () => {
    expect(normalizeColumnValue('dropdown', dropdownSettings, { optionIds: ['blog'] })).toEqual({
      optionIds: ['blog'],
    });
  });

  it('rejects unknown options', () => {
    expect(() => normalizeColumnValue('tags', dropdownSettings, { optionIds: ['nope'] })).toThrow(/Unknown option/);
  });

  it('clears on an empty selection', () => {
    expect(normalizeColumnValue('dropdown', dropdownSettings, { optionIds: [] })).toBeNull();
  });
});

describe('normalizeColumnValue — link', () => {
  it('accepts http and https, with an optional label', () => {
    expect(normalizeColumnValue('link', {}, { url: 'https://example.com' })).toEqual({
      url: 'https://example.com',
    });
    expect(normalizeColumnValue('link', {}, { url: 'http://example.com', label: 'Brief' })).toEqual({
      url: 'http://example.com',
      label: 'Brief',
    });
  });

  it('rejects a relative url', () => {
    expect(() => normalizeColumnValue('link', {}, { url: '/docs' })).toThrow(/absolute URL/);
  });

  it('rejects dangerous schemes', () => {
    expect(() => normalizeColumnValue('link', {}, { url: 'javascript:alert(1)' })).toThrow(/http or https/);
    expect(() => normalizeColumnValue('link', {}, { url: 'file:///etc/passwd' })).toThrow(/http or https/);
  });
});

describe('normalizeColumnValue — location', () => {
  it('keeps the address alone when coordinates are absent', () => {
    expect(normalizeColumnValue('location', {}, { address: 'Berlin' })).toEqual({ address: 'Berlin' });
  });

  it('keeps valid coordinates', () => {
    expect(normalizeColumnValue('location', {}, { address: 'Berlin', lat: 52.52, lng: 13.405 })).toEqual({
      address: 'Berlin',
      lat: 52.52,
      lng: 13.405,
    });
  });

  it('rejects out-of-range coordinates', () => {
    expect(() => normalizeColumnValue('location', {}, { address: 'X', lat: 91, lng: 0 })).toThrow(/-90 and 90/);
    expect(() => normalizeColumnValue('location', {}, { address: 'X', lat: 0, lng: 181 })).toThrow(/-180 and 180/);
  });
});

describe('assignedUserIds', () => {
  it('extracts ids from a people value', () => {
    expect(assignedUserIds('people', { userIds: [USER_A, USER_B] })).toEqual([USER_A, USER_B]);
  });

  it('is empty for other column types or a cleared cell', () => {
    expect(assignedUserIds('status', { labelId: 'done' })).toEqual([]);
    expect(assignedUserIds('people', null)).toEqual([]);
  });

  it('ignores non-string entries defensively', () => {
    expect(assignedUserIds('people', { userIds: [USER_A, 7] })).toEqual([USER_A]);
  });
});

describe('defaultSettingsFor', () => {
  it('gives status columns a usable label set with one done state', () => {
    const settings = defaultSettingsFor('status');
    expect(settings.labels).toHaveLength(3);
    expect(settings.labels!.filter((l) => l.isDone)).toHaveLength(1);
  });

  it('gives choice columns an empty option list', () => {
    expect(defaultSettingsFor('dropdown')).toEqual({ options: [] });
    expect(defaultSettingsFor('tags')).toEqual({ options: [] });
  });

  it('gives plain columns no settings', () => {
    expect(defaultSettingsFor('text')).toEqual({});
  });
});
