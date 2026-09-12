/**
 * Pure helpers for moving an item between boards: which source columns land
 * on which target columns, and how a cell value is translated across two
 * columns' settings. Kept free of I/O so the rules are unit-testable.
 */

export interface TransferColumn {
  id: string;
  type: string;
  scope: string;
  title: string;
  settings: unknown;
}

export interface ColumnMapping {
  sourceColumnId: string;
  sourceTitle: string;
  sourceType: string;
  targetColumnId: string | null;
  targetTitle: string | null;
}

export interface TransferPlan {
  mapping: ColumnMapping[];
  dropped: Array<{ columnId: string; title: string; type: string }>;
}

/** Read-only columns carry no stored values, so they never need mapping. */
const UNMAPPED_TYPES = new Set(['item_id', 'creation_log', 'last_updated', 'auto_number']);

/**
 * Pairs source columns with target columns of the same scope and type whose
 * titles match case-insensitively. Each target column is used at most once;
 * ties resolve in source order.
 */
export function planColumnMapping(source: TransferColumn[], target: TransferColumn[]): TransferPlan {
  const used = new Set<string>();
  const mapping: ColumnMapping[] = [];
  const dropped: TransferPlan['dropped'] = [];

  for (const column of source) {
    if (UNMAPPED_TYPES.has(column.type)) continue;
    const match = target.find(
      (t) =>
        !used.has(t.id) &&
        t.scope === column.scope &&
        t.type === column.type &&
        t.title.trim().toLowerCase() === column.title.trim().toLowerCase(),
    );
    if (match) used.add(match.id);
    mapping.push({
      sourceColumnId: column.id,
      sourceTitle: column.title,
      sourceType: column.type,
      targetColumnId: match?.id ?? null,
      targetTitle: match?.title ?? null,
    });
    if (!match) dropped.push({ columnId: column.id, title: column.title, type: column.type });
  }
  return { mapping, dropped };
}

interface LabelLike {
  id: string;
  label: string;
}

function labelsOf(settings: unknown, key: 'labels' | 'options'): LabelLike[] {
  const list = (settings as Record<string, unknown> | null | undefined)?.[key];
  return Array.isArray(list) ? (list as LabelLike[]) : [];
}

/**
 * Translates a stored cell value so it is valid on the target column.
 * Status labels and dropdown/tags options are matched by text; anything that
 * cannot be matched is dropped (null when nothing survives). Other types copy
 * verbatim.
 */
export function remapCellValue(
  type: string,
  value: Record<string, unknown> | null,
  sourceSettings: unknown,
  targetSettings: unknown,
): Record<string, unknown> | null {
  if (!value) return null;

  if (type === 'status') {
    const sourceLabel = labelsOf(sourceSettings, 'labels').find((l) => l.id === value.labelId);
    if (!sourceLabel) return null;
    const target = labelsOf(targetSettings, 'labels').find(
      (l) => l.label.trim().toLowerCase() === sourceLabel.label.trim().toLowerCase(),
    );
    return target ? { labelId: target.id } : null;
  }

  if (type === 'dropdown' || type === 'tags') {
    const sourceOptions = labelsOf(sourceSettings, 'options');
    const targetOptions = labelsOf(targetSettings, 'options');
    const ids = Array.isArray(value.optionIds) ? (value.optionIds as string[]) : [];
    const mapped = ids
      .map((id) => sourceOptions.find((o) => o.id === id))
      .filter((o): o is LabelLike => !!o)
      .map((o) => targetOptions.find((t) => t.label.trim().toLowerCase() === o.label.trim().toLowerCase()))
      .filter((o): o is LabelLike => !!o)
      .map((o) => o.id);
    const unique = [...new Set(mapped)];
    return unique.length ? { optionIds: unique } : null;
  }

  if (type === 'rating') {
    const max = ratingMaxOf(targetSettings);
    const rating = typeof value.rating === 'number' ? Math.min(value.rating, max) : null;
    return rating && rating >= 1 ? { rating } : null;
  }

  return value;
}

function ratingMaxOf(settings: unknown): number {
  const max = (settings as Record<string, unknown> | null | undefined)?.max;
  return typeof max === 'number' && max >= 1 && max <= 10 ? Math.floor(max) : 5;
}
