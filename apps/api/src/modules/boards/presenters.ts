import type { columns, groups, items } from '../../db/schema';

/** Shape of one item in board payloads and realtime events. */
export interface ItemPayload {
  id: string;
  name: string;
  groupId: string;
  position: number;
  updatesCount: number;
  values: Record<string, unknown>;
  serial: number;
  createdAt: string;
  createdByUserId: string | null;
  updatedAt: string;
  updatedByUserId: string | null;
  parentItemId: string | null;
  /** Only populated on top-level items. */
  subitems: ItemPayload[];
}

export interface ColumnPayload {
  id: string;
  type: string;
  scope: string;
  title: string;
  settings: unknown;
  position: number;
  width: number | null;
}

export interface GroupPayload {
  id: string;
  title: string;
  color: string;
  position: number;
  collapsed: boolean;
  items: ItemPayload[];
}

export function presentItem(
  row: typeof items.$inferSelect,
  values: Record<string, unknown>,
  updatesCount: number,
  subitems: ItemPayload[] = [],
): ItemPayload {
  return {
    id: row.id,
    name: row.name,
    groupId: row.groupId,
    position: row.position,
    updatesCount,
    values,
    serial: row.serial,
    createdAt: row.createdAt.toISOString(),
    createdByUserId: row.createdByUserId,
    updatedAt: row.updatedAt.toISOString(),
    updatedByUserId: row.updatedByUserId,
    parentItemId: row.parentItemId,
    subitems,
  };
}

export function presentColumn(column: typeof columns.$inferSelect): ColumnPayload {
  return {
    id: column.id,
    type: column.type,
    scope: column.scope,
    title: column.title,
    settings: column.settings,
    position: column.position,
    width: column.width,
  };
}

export function presentGroup(group: typeof groups.$inferSelect, groupItems: ItemPayload[] = []): GroupPayload {
  return {
    id: group.id,
    title: group.title,
    color: group.color,
    position: group.position,
    collapsed: group.collapsed,
    items: groupItems,
  };
}
