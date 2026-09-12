import { Injectable } from '@nestjs/common';
import type { AuthContext } from '../../common/auth-context';
import { ViewsService } from '../views/views.service';
import { BoardsService } from './boards.service';
import { applyView, displayValue, visibleColumns, type QueryColumn, type QueryContext, type ViewConfig } from './view-query';

/**
 * Board → CSV. One row per item (subitems indented under their parent), one
 * column per visible board column, with the group as the leading column.
 * Passing a view applies its filters, sort and hidden columns, so the export
 * matches what the viewer sees.
 */
@Injectable()
export class BoardExportService {
  constructor(
    private readonly boards: BoardsService,
    private readonly views: ViewsService,
  ) {}

  async toCsv(auth: AuthContext, boardId: string, viewId?: string): Promise<{ fileName: string; csv: string }> {
    const board = await this.boards.getBoard(auth, boardId);
    const config: ViewConfig = viewId ? await this.views.configFor(boardId, viewId) : {};

    const columns: QueryColumn[] = board.columns.map((c) => ({
      id: c.id,
      type: c.type,
      title: c.title,
      settings: c.settings,
      position: c.position,
      scope: c.scope,
    }));
    const ctx: QueryContext = {
      userId: auth.userId,
      now: new Date(),
      memberNames: Object.fromEntries(board.members.map((m) => [m.userId, m.fullName])),
    };

    const itemColumns = visibleColumns(columns, config, 'items');
    const subitemColumns = visibleColumns(columns, config, 'subitems');
    const groups = applyView(
      board.groups.map((g) => ({
        id: g.id,
        title: g.title,
        position: g.position,
        items: g.items.map((i) => ({
          id: i.id,
          name: i.name,
          position: i.position,
          values: i.values,
          serial: i.serial,
          createdAt: i.createdAt,
          updatedAt: i.updatedAt,
          groupId: g.id,
        })),
      })),
      config,
      columns,
      ctx,
    );
    const subitemsByParent = new Map(board.groups.flatMap((g) => g.items).map((i) => [i.id, i.subitems]));

    const header = ['Group', 'Item', ...itemColumns.map((c) => c.title)];
    const lines = [header.map(escapeCsv).join(',')];
    for (const group of groups) {
      for (const item of group.items) {
        lines.push(
          [group.title, item.name, ...itemColumns.map((column) => displayValue(column, item, ctx))].map(escapeCsv).join(','),
        );
        for (const sub of subitemsByParent.get(item.id) ?? []) {
          const subItem = {
            id: sub.id,
            name: sub.name,
            position: sub.position,
            values: sub.values,
            serial: sub.serial,
            createdAt: sub.createdAt,
            updatedAt: sub.updatedAt,
          };
          // Subitems carry their own column set; they are written under the
          // parent with their values flattened into one "Subitems" style cell
          // per parent column slot so the CSV stays rectangular.
          const detail = subitemColumns
            .map((column) => {
              const value = displayValue(column, subItem, ctx);
              return value ? `${column.title}: ${value}` : '';
            })
            .filter(Boolean)
            .join(' · ');
          lines.push([group.title, `  ↳ ${sub.name}`, detail, ...itemColumns.slice(1).map(() => '')].map(escapeCsv).join(','));
        }
      }
    }

    const safeName = board.name.replace(/[^\w\d-]+/g, '_').slice(0, 60) || 'board';
    return { fileName: `${safeName}.csv`, csv: lines.join('\r\n') };
  }
}

function escapeCsv(field: string): string {
  if (/[",\r\n]/.test(field)) return `"${field.replace(/"/g, '""')}"`;
  return field;
}
