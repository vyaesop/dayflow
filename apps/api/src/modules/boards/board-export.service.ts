import { Injectable } from '@nestjs/common';
import type { AuthContext } from '../../common/auth-context';
import { BoardsService } from './boards.service';

/**
 * Board → CSV. One row per item, one column per board column, with the
 * group as the leading column. Values are flattened to display text the same
 * way the client renders chips.
 */
@Injectable()
export class BoardExportService {
  constructor(private readonly boards: BoardsService) {}

  async toCsv(auth: AuthContext, boardId: string): Promise<{ fileName: string; csv: string }> {
    const board = await this.boards.getBoard(auth, boardId);

    const header = ['Group', 'Item', ...board.columns.map((c) => c.title)];
    const lines = [header.map(escapeCsv).join(',')];

    for (const group of board.groups) {
      for (const item of group.items) {
        const cells = board.columns.map((column) =>
          flattenValue(column.type, column.settings, item.values[column.id]),
        );
        lines.push([group.title, item.name, ...cells].map(escapeCsv).join(','));
      }
    }

    const safeName = board.name.replace(/[^\w\d-]+/g, '_').slice(0, 60) || 'board';
    return { fileName: `${safeName}.csv`, csv: lines.join('\r\n') };
  }
}

function flattenValue(type: string, settings: unknown, raw: unknown): string {
  if (raw === null || raw === undefined) return '';
  const value = raw as Record<string, unknown>;

  switch (type) {
    case 'status': {
      const labels = (settings as { labels?: Array<{ id: string; label: string }> })?.labels ?? [];
      return labels.find((l) => l.id === value.labelId)?.label ?? '';
    }
    case 'people':
      return Array.isArray(value.userIds) ? `${value.userIds.length} assigned` : '';
    case 'date':
      return [value.date, value.time].filter(Boolean).join(' ');
    case 'timeline':
      return value.from && value.to ? `${value.from} → ${value.to}` : '';
    case 'text':
      return String(value.text ?? '');
    case 'number':
      return value.number === undefined ? '' : String(value.number);
    case 'checkbox':
      return value.checked === true ? 'Yes' : '';
    case 'link':
      return String(value.url ?? '');
    case 'location':
      return String(value.address ?? '');
    case 'tags':
    case 'dropdown': {
      const options = (settings as { options?: Array<{ id: string; label: string }> })?.options ?? [];
      const ids = Array.isArray(value.optionIds) ? (value.optionIds as string[]) : [];
      return ids.map((id) => options.find((o) => o.id === id)?.label ?? id).join('; ');
    }
    default:
      return '';
  }
}

function escapeCsv(field: string): string {
  if (/[",\r\n]/.test(field)) return `"${field.replace(/"/g, '""')}"`;
  return field;
}
