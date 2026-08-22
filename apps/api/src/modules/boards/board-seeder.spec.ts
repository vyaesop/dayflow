import { describe, expect, it } from 'vitest';
import { DEFAULT_STATUS_LABELS } from './board-seeder.service';

describe('DEFAULT_STATUS_LABELS', () => {
  it('has unique label ids so cell values resolve unambiguously', () => {
    const ids = DEFAULT_STATUS_LABELS.map((l) => l.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('marks exactly one label as the done state', () => {
    expect(DEFAULT_STATUS_LABELS.filter((l) => l.isDone)).toHaveLength(1);
    expect(DEFAULT_STATUS_LABELS.find((l) => l.isDone)?.id).toBe('done');
  });

  it('gives every label a colour token the client can resolve', () => {
    // Kept in sync with DfColors.token() in apps/mobile/lib/core/theme/tokens.dart.
    const clientTokens = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo', 'grey'];
    for (const label of DEFAULT_STATUS_LABELS) {
      expect(clientTokens).toContain(label.color);
    }
  });

  it('gives every label a non-empty display name', () => {
    for (const label of DEFAULT_STATUS_LABELS) {
      expect(label.label.trim()).not.toBe('');
    }
  });
});
