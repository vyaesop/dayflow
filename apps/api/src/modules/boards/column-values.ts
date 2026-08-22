import { BadRequestException } from '@nestjs/common';

/**
 * The column-type registry: each column type owns the shape of its cell value.
 *
 * Values arrive as untrusted JSON, so every type normalises to a canonical shape
 * and rejects anything else. `null` always means "clear the cell" and is stored
 * as SQL NULL rather than an empty object, so readers can rely on a missing
 * value being absent rather than a differently-shaped empty.
 */

export interface StatusLabel {
  id: string;
  label: string;
  color: string;
  isDone: boolean;
}

export interface DropdownOption {
  id: string;
  label: string;
  color?: string;
}

/** Column settings as stored in `columns.settings`. */
export interface ColumnSettings {
  labels?: StatusLabel[];
  options?: DropdownOption[];
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const HH_MM = /^([01]\d|2[0-3]):[0-5]\d$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function asRecord(value: unknown, columnType: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new BadRequestException(`A ${columnType} value must be an object`);
  }
  return value as Record<string, unknown>;
}

function asString(value: unknown, field: string, maxLength = 2000): string {
  if (typeof value !== 'string') throw new BadRequestException(`${field} must be a string`);
  if (value.length > maxLength) throw new BadRequestException(`${field} must be at most ${maxLength} characters`);
  return value;
}

function asStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) throw new BadRequestException(`${field} must be an array`);
  return value.map((v, i) => asString(v, `${field}[${i}]`, 200));
}

/** True when a value should clear the cell rather than set it. */
function isEmpty(value: unknown): boolean {
  return value === null || value === undefined;
}

/**
 * True when `YYYY-MM-DD` names a real calendar day.
 *
 * `Date.parse` is no help here: it rolls overflow forward, so '2026-02-31'
 * silently becomes March 3rd. Comparing the parsed components back against the
 * input is what actually rejects it.
 */
function isRealDate(value: string): boolean {
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
  );
}

/**
 * Validates and canonicalises a cell value for `columnType`.
 * Returns `null` to clear the cell.
 */
export function normalizeColumnValue(
  columnType: string,
  settings: ColumnSettings,
  raw: unknown,
): Record<string, unknown> | null {
  if (isEmpty(raw)) return null;

  switch (columnType) {
    case 'status': {
      const value = asRecord(raw, 'status');
      if (isEmpty(value.labelId)) return null;
      const labelId = asString(value.labelId, 'labelId', 80);
      const labels = settings.labels ?? [];
      if (!labels.some((l) => l.id === labelId)) {
        throw new BadRequestException(`Unknown status label "${labelId}" for this column`);
      }
      return { labelId };
    }

    case 'people': {
      const value = asRecord(raw, 'people');
      const userIds = asStringArray(value.userIds ?? [], 'userIds');
      for (const id of userIds) {
        if (!UUID.test(id)) throw new BadRequestException(`"${id}" is not a valid user id`);
      }
      // De-duplicate while preserving assignment order.
      const unique = [...new Set(userIds)];
      return unique.length ? { userIds: unique } : null;
    }

    case 'date': {
      const value = asRecord(raw, 'date');
      if (isEmpty(value.date)) return null;
      const date = asString(value.date, 'date', 10);
      if (!ISO_DATE.test(date)) throw new BadRequestException('date must be formatted YYYY-MM-DD');
      if (!isRealDate(date)) throw new BadRequestException(`"${date}" is not a real date`);
      if (isEmpty(value.time)) return { date };
      const time = asString(value.time, 'time', 5);
      if (!HH_MM.test(time)) throw new BadRequestException('time must be formatted HH:mm');
      return { date, time };
    }

    case 'timeline': {
      const value = asRecord(raw, 'timeline');
      if (isEmpty(value.from) && isEmpty(value.to)) return null;
      const from = asString(value.from, 'from', 10);
      const to = asString(value.to, 'to', 10);
      if (!ISO_DATE.test(from) || !ISO_DATE.test(to)) {
        throw new BadRequestException('timeline from/to must be formatted YYYY-MM-DD');
      }
      if (from > to) throw new BadRequestException('timeline from must not be after to');
      return { from, to };
    }

    case 'text': {
      const value = asRecord(raw, 'text');
      if (isEmpty(value.text)) return null;
      const text = asString(value.text, 'text', 5000);
      return text.length ? { text } : null;
    }

    case 'number': {
      const value = asRecord(raw, 'number');
      if (isEmpty(value.number)) return null;
      const n = value.number;
      if (typeof n !== 'number' || !Number.isFinite(n)) {
        throw new BadRequestException('number must be a finite number');
      }
      return { number: n };
    }

    case 'checkbox': {
      const value = asRecord(raw, 'checkbox');
      if (isEmpty(value.checked)) return null;
      if (typeof value.checked !== 'boolean') throw new BadRequestException('checked must be a boolean');
      // An unchecked box is the default, so store nothing.
      return value.checked ? { checked: true } : null;
    }

    case 'tags':
    case 'dropdown': {
      const value = asRecord(raw, columnType);
      const optionIds = asStringArray(value.optionIds ?? [], 'optionIds');
      const options = settings.options ?? [];
      for (const id of optionIds) {
        if (!options.some((o) => o.id === id)) {
          throw new BadRequestException(`Unknown option "${id}" for this column`);
        }
      }
      const unique = [...new Set(optionIds)];
      return unique.length ? { optionIds: unique } : null;
    }

    case 'link': {
      const value = asRecord(raw, 'link');
      if (isEmpty(value.url)) return null;
      const url = asString(value.url, 'url', 2048);
      let parsed: URL;
      try {
        parsed = new URL(url);
      } catch {
        throw new BadRequestException('url must be an absolute URL');
      }
      if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
        throw new BadRequestException('url must use http or https');
      }
      return isEmpty(value.label) ? { url } : { url, label: asString(value.label, 'label', 200) };
    }

    case 'location': {
      const value = asRecord(raw, 'location');
      if (isEmpty(value.address)) return null;
      const address = asString(value.address, 'address', 500);
      const out: Record<string, unknown> = { address };
      if (!isEmpty(value.lat) && !isEmpty(value.lng)) {
        const lat = value.lat;
        const lng = value.lng;
        if (typeof lat !== 'number' || typeof lng !== 'number') {
          throw new BadRequestException('lat/lng must be numbers');
        }
        if (lat < -90 || lat > 90) throw new BadRequestException('lat must be between -90 and 90');
        if (lng < -180 || lng > 180) throw new BadRequestException('lng must be between -180 and 180');
        out.lat = lat;
        out.lng = lng;
      }
      return out;
    }

    case 'vote': {
      const value = asRecord(raw, 'vote');
      const userIds = asStringArray(value.userIds ?? [], 'userIds');
      const unique = [...new Set(userIds)];
      return unique.length ? { userIds: unique } : null;
    }

    default:
      throw new BadRequestException(`Column type "${columnType}" cannot be edited yet`);
  }
}

/** The user ids a value assigns, for notification fan-out. */
export function assignedUserIds(columnType: string, value: Record<string, unknown> | null): string[] {
  if (columnType !== 'people' || !value) return [];
  const ids = value.userIds;
  return Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string') : [];
}

/** Default settings for a newly created column. */
export function defaultSettingsFor(columnType: string): ColumnSettings {
  switch (columnType) {
    case 'status':
      return {
        labels: [
          { id: 'working', label: 'Working on it', color: 'amber', isDone: false },
          { id: 'done', label: 'Done', color: 'green', isDone: true },
          { id: 'stuck', label: 'Stuck', color: 'red', isDone: false },
        ],
      };
    case 'tags':
    case 'dropdown':
      return { options: [] };
    default:
      return {};
  }
}
