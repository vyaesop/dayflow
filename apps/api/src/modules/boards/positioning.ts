/**
 * Fractional indexing for drag-reorder.
 *
 * Rows carry a float `position`; inserting between two neighbours takes their
 * midpoint, so a move rewrites exactly one row instead of renumbering the list.
 *
 * Repeated midpoints do eventually exhaust float precision (~50 inserts into the
 * same gap). `needsRebalance` detects that so the caller can renumber the list.
 */

export const POSITION_STEP = 1;

/** Smallest gap we trust before a list should be renumbered. */
const MIN_GAP = 1e-6;

/** Position for an item appended to the end of `positions`. */
export function positionAtEnd(positions: number[]): number {
  if (positions.length === 0) return POSITION_STEP;
  return Math.max(...positions) + POSITION_STEP;
}

/** Position for an item placed at the very start of `positions`. */
export function positionAtStart(positions: number[]): number {
  if (positions.length === 0) return POSITION_STEP;
  return Math.min(...positions) / 2;
}

/**
 * Position that places a row between `before` and `after`.
 * Pass `null` for either end of the list.
 */
export function positionBetween(before: number | null, after: number | null): number {
  if (before === null && after === null) return POSITION_STEP;
  if (before === null) return after! / 2;
  if (after === null) return before + POSITION_STEP;
  return (before + after) / 2;
}

/** True when the gap between neighbours has collapsed and the list needs renumbering. */
export function needsRebalance(before: number | null, after: number | null): boolean {
  if (before === null || after === null) return false;
  return Math.abs(after - before) < MIN_GAP;
}

/**
 * Given an ordered list and the id to insert after, returns the neighbouring
 * positions. `afterId === null` means "insert at the top".
 */
export function neighboursFor<T extends { id: string; position: number }>(
  ordered: T[],
  afterId: string | null,
  excludeId?: string,
): { before: number | null; after: number | null } {
  const list = excludeId ? ordered.filter((r) => r.id !== excludeId) : ordered;

  if (afterId === null) {
    return { before: null, after: list.length ? list[0].position : null };
  }
  const index = list.findIndex((r) => r.id === afterId);
  if (index === -1) {
    // Unknown anchor — fall back to appending.
    return { before: list.length ? list[list.length - 1].position : null, after: null };
  }
  return {
    before: list[index].position,
    after: index + 1 < list.length ? list[index + 1].position : null,
  };
}

/** Evenly spaced positions for renumbering a list, 1-based. */
export function rebalanced(count: number): number[] {
  return Array.from({ length: count }, (_, i) => (i + 1) * POSITION_STEP);
}
