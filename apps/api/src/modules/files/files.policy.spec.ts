import { describe, expect, it } from 'vitest';
import { normalizeMime, planServing } from './files.policy';

describe('planServing', () => {
  it('renders allowlisted raster images inline with their own type', () => {
    expect(planServing('image/png')).toEqual({ contentType: 'image/png', disposition: 'inline' });
    expect(planServing('image/jpeg')).toEqual({ contentType: 'image/jpeg', disposition: 'inline' });
    expect(planServing('IMAGE/PNG')).toEqual({ contentType: 'image/png', disposition: 'inline' });
    expect(planServing('image/png; charset=binary')).toEqual({ contentType: 'image/png', disposition: 'inline' });
  });

  it('forces active content to download as an opaque attachment', () => {
    for (const dangerous of ['text/html', 'image/svg+xml', 'application/xhtml+xml', 'text/javascript']) {
      expect(planServing(dangerous)).toEqual({ contentType: 'application/octet-stream', disposition: 'attachment' });
    }
  });

  it('treats unknown, empty, and malformed types as attachments', () => {
    expect(planServing('application/pdf').disposition).toBe('attachment');
    expect(planServing('').disposition).toBe('attachment');
    expect(planServing('not-a-mime').disposition).toBe('attachment');
  });
});

describe('normalizeMime', () => {
  it('lowercases and strips parameters', () => {
    expect(normalizeMime('Image/PNG; charset=utf-8')).toBe('image/png');
    expect(normalizeMime(undefined)).toBe('');
    expect(normalizeMime(null)).toBe('');
  });
});
