import { describe, expect, it } from 'vitest';
import { describeNotification } from './notification-copy';

describe('describeNotification', () => {
  it('describes a mention with board and snippet context', () => {
    const copy = describeNotification('mention', 'Alex Smith', {
      itemName: 'Launch checklist',
      boardName: 'Marketing',
      snippet: 'can you review this?',
    });
    expect(copy?.subject).toBe('Alex Smith mentioned you on Launch checklist');
    expect(copy?.line).toContain('in Marketing');
    expect(copy?.line).toContain('can you review this?');
  });

  it('describes an assignment', () => {
    const copy = describeNotification('assigned', 'Dana', { itemName: 'Q3 report', boardName: 'Finance' });
    expect(copy?.subject).toBe('Dana assigned you to Q3 report');
    expect(copy?.line).toBe('Dana assigned you to “Q3 report” in Finance.');
  });

  it('describes a reply without a board name', () => {
    const copy = describeNotification('reply', 'Sam', { itemName: 'Bug triage', snippet: 'done!' });
    expect(copy?.subject).toBe('Sam replied to your update');
    expect(copy?.line).toContain('“Bug triage”');
  });

  it('describes being added to a board', () => {
    const copy = describeNotification('board_invite', 'Priya', { boardName: 'Roadmap' });
    expect(copy?.subject).toBe('Priya added you to Roadmap');
    expect(copy?.line).toContain('“Roadmap”');
  });

  it('falls back to neutral copy when names are missing', () => {
    const copy = describeNotification('mention', '', {});
    expect(copy?.subject).toBe('A teammate mentioned you on an item');
  });

  it('returns null for types that should stay in-app only', () => {
    expect(describeNotification('update_on_subscribed', 'Alex', {})).toBeNull();
    expect(describeNotification('unknown_type', 'Alex', {})).toBeNull();
  });
});
