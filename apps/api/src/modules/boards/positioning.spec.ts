import { describe, expect, it } from 'vitest';
import {
  needsRebalance,
  neighboursFor,
  positionAtEnd,
  positionAtStart,
  positionBetween,
  rebalanced,
} from './positioning';

describe('positionAtEnd', () => {
  it('starts at the step for an empty list', () => {
    expect(positionAtEnd([])).toBe(1);
  });

  it('goes one step past the current maximum, not the array order', () => {
    expect(positionAtEnd([3, 1, 2])).toBe(4);
  });
});

describe('positionAtStart', () => {
  it('halves the smallest position', () => {
    expect(positionAtStart([2, 4])).toBe(1);
  });

  it('starts at the step for an empty list', () => {
    expect(positionAtStart([])).toBe(1);
  });
});

describe('positionBetween', () => {
  it('takes the midpoint of two neighbours', () => {
    expect(positionBetween(1, 2)).toBe(1.5);
  });

  it('appends past the last row', () => {
    expect(positionBetween(7, null)).toBe(8);
  });

  it('halves down when inserting at the top', () => {
    expect(positionBetween(null, 4)).toBe(2);
  });

  it('starts at the step for an empty list', () => {
    expect(positionBetween(null, null)).toBe(1);
  });

  it('keeps the result strictly between its neighbours', () => {
    let before = 1;
    const after = 2;
    for (let i = 0; i < 20; i++) {
      const mid = positionBetween(before, after);
      expect(mid).toBeGreaterThan(before);
      expect(mid).toBeLessThan(after);
      before = mid;
    }
  });
});

describe('needsRebalance', () => {
  it('is false at the ends of a list', () => {
    expect(needsRebalance(null, 1)).toBe(false);
    expect(needsRebalance(1, null)).toBe(false);
  });

  it('is false for a healthy gap', () => {
    expect(needsRebalance(1, 2)).toBe(false);
  });

  it('becomes true once repeated midpoints collapse the gap', () => {
    let before = 1;
    const after = 2;
    let iterations = 0;
    while (!needsRebalance(before, after) && iterations < 100) {
      before = positionBetween(before, after);
      iterations++;
    }
    expect(needsRebalance(before, after)).toBe(true);
    // Should survive a realistic number of inserts before renumbering.
    expect(iterations).toBeGreaterThan(15);
  });
});

describe('neighboursFor', () => {
  const ordered = [
    { id: 'a', position: 1 },
    { id: 'b', position: 2 },
    { id: 'c', position: 3 },
  ];

  it('returns the head when inserting at the top', () => {
    expect(neighboursFor(ordered, null)).toEqual({ before: null, after: 1 });
  });

  it('brackets the anchor and its follower', () => {
    expect(neighboursFor(ordered, 'a')).toEqual({ before: 1, after: 2 });
  });

  it('reports an open end when anchored to the last row', () => {
    expect(neighboursFor(ordered, 'c')).toEqual({ before: 3, after: null });
  });

  it('ignores the row being moved so it cannot anchor to itself', () => {
    expect(neighboursFor(ordered, 'a', 'b')).toEqual({ before: 1, after: 3 });
  });

  it('appends when the anchor is unknown', () => {
    expect(neighboursFor(ordered, 'missing')).toEqual({ before: 3, after: null });
  });

  it('handles an empty list', () => {
    expect(neighboursFor([], null)).toEqual({ before: null, after: null });
    expect(neighboursFor([], 'x')).toEqual({ before: null, after: null });
  });

  it('moving the only row leaves no neighbours', () => {
    expect(neighboursFor([{ id: 'a', position: 1 }], null, 'a')).toEqual({ before: null, after: null });
  });
});

describe('rebalanced', () => {
  it('produces evenly spaced 1-based positions', () => {
    expect(rebalanced(4)).toEqual([1, 2, 3, 4]);
    expect(rebalanced(0)).toEqual([]);
  });
});
