import { describe, expect, it } from 'vitest';
import { firstNameOf, slugify } from './auth.service';

describe('firstNameOf', () => {
  it('takes the first whitespace-separated token', () => {
    expect(firstNameOf('Robin Vega')).toBe('Robin');
    expect(firstNameOf('Robin')).toBe('Robin');
  });

  it('ignores surrounding and repeated whitespace', () => {
    expect(firstNameOf('   Robin   Vega  ')).toBe('Robin');
    expect(firstNameOf('Robin\t\tVega')).toBe('Robin');
  });

  it('falls back to "My" for an empty name so the account is still nameable', () => {
    expect(firstNameOf('')).toBe('My');
    expect(firstNameOf('    ')).toBe('My');
  });
});

describe('slugify', () => {
  it('lowercases and hyphenates, then appends a uniqueness suffix', () => {
    expect(slugify("Robin's team")).toMatch(/^robin-s-team-[0-9a-f]{6}$/);
  });

  it('collapses runs of punctuation into a single hyphen', () => {
    expect(slugify('Acme  &&  Co.')).toMatch(/^acme-co-[0-9a-f]{6}$/);
  });

  it('does not leave leading or trailing hyphens on the base', () => {
    expect(slugify('  !!Hello!!  ')).toMatch(/^hello-[0-9a-f]{6}$/);
  });

  it('produces a different slug for the same name each time', () => {
    const a = slugify("Robin's team");
    const b = slugify("Robin's team");
    expect(a).not.toBe(b);
  });

  it('still yields a usable slug when the name has no alphanumerics', () => {
    // Base collapses to empty, leaving just the random suffix — never a bare '-'.
    expect(slugify('!!!')).toMatch(/^-[0-9a-f]{6}$/);
  });
});
