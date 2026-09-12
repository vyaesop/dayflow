import { BadRequestException } from '@nestjs/common';

/**
 * Markdown-lite for update bodies (contract §10).
 *
 * The client sends a string; the server stores a `Doc` and hands the canonical
 * serialization back for editing. The grammar is deliberately tiny:
 *
 *   blocks   — one per line; `- `/`* ` bullet items, `1. ` ordered items
 *              (consecutive items form one list), everything else a paragraph;
 *              blank lines are dropped and never break a list.
 *   inline   — `@[label](user:uuid)` / `@[label](board)` mentions,
 *              `[label](https://…)` links, `` `code` ``, `**bold**`,
 *              `~~strike~~`, `_italic_` (only at word boundaries, so
 *              snake_case survives), bare `https?://` autolinks with trailing
 *              punctuation left outside the link.
 *
 * Unbalanced markers are literal text. Marks nest (`**_x_**`) except inside
 * code, whose content is always literal. Links and mentions inside a marked
 * span keep their own type and drop the mark — a mention is worth more than
 * its bold.
 */

export type Mark = 'bold' | 'italic' | 'strike' | 'code';

export interface TextInline {
  type: 'text';
  text: string;
  marks?: Mark[];
}

export interface LinkInline {
  type: 'link';
  href: string;
  text: string;
}

export interface MentionInline {
  type: 'mention';
  label: string;
  userId?: string;
  scope?: 'board';
}

export type Inline = TextInline | LinkInline | MentionInline;

export interface ParagraphBlock {
  type: 'paragraph';
  content: Inline[];
}

export interface ListBlock {
  type: 'bulletList' | 'orderedList';
  items: Inline[][];
}

export type Block = ParagraphBlock | ListBlock;

export interface Doc {
  type: 'doc';
  content: Block[];
}

export const MAX_BODY_LENGTH = 10_000;

/** Canonical nesting order, outermost first: `**_~~`x`~~_**`. */
const MARK_ORDER: Mark[] = ['bold', 'italic', 'strike', 'code'];

// Sticky regexes: set lastIndex and exec to match exactly at a position.
const MENTION = /@\[([^\]\n]+)\]\((?:user:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})|board)\)/y;
const LINK = /\[([^\]\n]+)\]\((https?:\/\/[^\s)]+)\)/y;
const BARE_URL = /https?:\/\/[^\s]+/y;
const TRAILING_PUNCTUATION = /[.,;:!?)]+$/;
const WORD_CHAR = /[A-Za-z0-9]/;
const BULLET_ITEM = /^[-*] (.+)$/;
const ORDERED_ITEM = /^\d+\. (.+)$/;

function execAt(re: RegExp, s: string, at: number): RegExpExecArray | null {
  re.lastIndex = at;
  return re.exec(s);
}

function sortMarks(marks: Iterable<Mark>): Mark[] {
  const set = new Set(marks);
  return MARK_ORDER.filter((m) => set.has(m));
}

function textNode(text: string, marks: Mark[]): TextInline {
  return marks.length ? { type: 'text', text, marks: sortMarks(marks) } : { type: 'text', text };
}

function sameMarks(a: Mark[] | undefined, b: Mark[] | undefined): boolean {
  const x = a ?? [];
  const y = b ?? [];
  return x.length === y.length && x.every((m, i) => m === y[i]);
}

/** Merges adjacent text runs that carry identical marks. */
function mergeRuns(nodes: Inline[]): Inline[] {
  const out: Inline[] = [];
  for (const node of nodes) {
    const last = out[out.length - 1];
    if (node.type === 'text' && last && last.type === 'text' && sameMarks(last.marks, node.marks)) {
      last.text += node.text;
    } else {
      out.push(node.type === 'text' ? { ...node } : node);
    }
  }
  return out;
}

function withMark(marks: Mark[], mark: Mark): Mark[] {
  return marks.includes(mark) ? marks : [...marks, mark];
}

function isWhitespace(ch: string | undefined): boolean {
  return ch !== undefined && /\s/.test(ch);
}

/** `_` opens italic only at a word boundary and when followed by content. */
function opensItalic(s: string, i: number): boolean {
  if (i > 0 && WORD_CHAR.test(s[i - 1])) return false;
  const next = s[i + 1];
  return next !== undefined && !isWhitespace(next) && next !== '_';
}

/** The index of the `_` that closes an italic opened at `open`, or -1. */
function findItalicClose(s: string, open: number): number {
  for (let j = open + 2; j < s.length; j++) {
    if (s[j] !== '_') continue;
    if (isWhitespace(s[j - 1])) continue;
    const after = s[j + 1];
    if (after === undefined || !WORD_CHAR.test(after)) return j;
  }
  return -1;
}

/**
 * Single left-to-right scan. `marks` are the marks inherited from enclosing
 * spans, so nested markers compose.
 */
function scanInline(s: string, marks: Mark[]): Inline[] {
  const out: Inline[] = [];
  let buffer = '';
  const flush = () => {
    if (buffer) {
      out.push(textNode(buffer, marks));
      buffer = '';
    }
  };

  let i = 0;
  while (i < s.length) {
    const ch = s[i];

    if (ch === '@') {
      const m = execAt(MENTION, s, i);
      if (m) {
        flush();
        out.push(m[2] ? { type: 'mention', label: m[1], userId: m[2].toLowerCase() } : { type: 'mention', label: m[1], scope: 'board' });
        i += m[0].length;
        continue;
      }
    } else if (ch === '[') {
      const m = execAt(LINK, s, i);
      if (m) {
        flush();
        out.push({ type: 'link', href: m[2], text: m[1] });
        i += m[0].length;
        continue;
      }
    } else if (ch === '`') {
      const close = s.indexOf('`', i + 1);
      if (close > i + 1) {
        flush();
        out.push(textNode(s.slice(i + 1, close), withMark(marks, 'code')));
        i = close + 1;
        continue;
      }
    } else if (ch === '*' && s.startsWith('**', i)) {
      const close = s.indexOf('**', i + 2);
      if (close > i + 2) {
        flush();
        out.push(...scanInline(s.slice(i + 2, close), withMark(marks, 'bold')));
        i = close + 2;
        continue;
      }
    } else if (ch === '~' && s.startsWith('~~', i)) {
      const close = s.indexOf('~~', i + 2);
      if (close > i + 2) {
        flush();
        out.push(...scanInline(s.slice(i + 2, close), withMark(marks, 'strike')));
        i = close + 2;
        continue;
      }
    } else if (ch === '_' && opensItalic(s, i)) {
      const close = findItalicClose(s, i);
      if (close !== -1) {
        flush();
        out.push(...scanInline(s.slice(i + 1, close), withMark(marks, 'italic')));
        i = close + 1;
        continue;
      }
    } else if (ch === 'h') {
      const m = execAt(BARE_URL, s, i);
      if (m) {
        const href = m[0].replace(TRAILING_PUNCTUATION, '');
        if (href.length > href.indexOf('://') + 3) {
          flush();
          out.push({ type: 'link', href, text: href });
          i += href.length;
          continue;
        }
      }
    }

    buffer += ch;
    i += 1;
  }
  flush();
  return mergeRuns(out);
}

/** Parses a markdown-lite body into a Doc. Throws when the body is too long. */
export function parseMarkdownLite(input: string): Doc {
  if (input.length > MAX_BODY_LENGTH) {
    throw new BadRequestException(`Body must be at most ${MAX_BODY_LENGTH} characters`);
  }

  const content: Block[] = [];
  let list: ListBlock | null = null;

  for (const rawLine of input.split('\n')) {
    const line = rawLine.trimEnd();
    if (line.trim() === '') continue;

    const bullet = BULLET_ITEM.exec(line);
    const ordered = bullet ? null : ORDERED_ITEM.exec(line);
    const listType: ListBlock['type'] | null = bullet ? 'bulletList' : ordered ? 'orderedList' : null;
    const match = bullet ?? ordered;

    if (listType && match) {
      if (!list || list.type !== listType) {
        list = { type: listType, items: [] };
        content.push(list);
      }
      list.items.push(scanInline(match[1], []));
    } else {
      list = null;
      content.push({ type: 'paragraph', content: scanInline(line, []) });
    }
  }

  return { type: 'doc', content };
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

function markToken(mark: Mark): string {
  switch (mark) {
    case 'bold':
      return '**';
    case 'italic':
      return '_';
    case 'strike':
      return '~~';
    case 'code':
      return '`';
  }
}

function serializeAtom(node: LinkInline | MentionInline): string {
  if (node.type === 'link') return node.text === node.href ? node.href : `[${node.text}](${node.href})`;
  return node.scope === 'board' ? `@[${node.label}](board)` : `@[${node.label}](user:${node.userId})`;
}

/**
 * Serializes a run of inlines. Consecutive text runs that share a mark are
 * wrapped once (`**b _c_ d**`, not `**b **_**c**_** d**`), outermost mark
 * first per `MARK_ORDER`. `open` are the marks already wrapped around us.
 * Code is never grouped: its content is literal, so nothing may nest inside.
 */
function serializeInlines(nodes: Inline[], open: Mark[] = []): string {
  let out = '';
  let i = 0;
  while (i < nodes.length) {
    const node = nodes[i];
    if (node.type !== 'text') {
      out += serializeAtom(node);
      i += 1;
      continue;
    }
    const pending = (node.marks ?? []).filter((m) => !open.includes(m));
    if (pending.length === 0) {
      out += node.text;
      i += 1;
      continue;
    }
    const mark = MARK_ORDER.find((m) => pending.includes(m)) as Mark;
    let j = i + 1;
    if (mark !== 'code') {
      while (j < nodes.length) {
        const next = nodes[j];
        if (next.type !== 'text' || !(next.marks ?? []).includes(mark)) break;
        j += 1;
      }
    }
    const token = markToken(mark);
    out += `${token}${serializeInlines(nodes.slice(i, j), [...open, mark])}${token}`;
    i = j;
  }
  return out;
}

/** Canonical markdown-lite for a Doc; `parseMarkdownLite` of the result yields the same Doc. */
export function serializeDoc(doc: Doc): string {
  return doc.content
    .map((block) => {
      switch (block.type) {
        case 'paragraph':
          return serializeInlines(block.content);
        case 'bulletList':
          return block.items.map((item) => `- ${serializeInlines(item)}`).join('\n');
        case 'orderedList':
          return block.items.map((item, i) => `${i + 1}. ${serializeInlines(item)}`).join('\n');
      }
    })
    .join('\n');
}

function plainInline(node: Inline): string {
  switch (node.type) {
    case 'text':
      return node.text;
    case 'link':
      return node.text;
    case 'mention':
      return `@${node.label}`;
  }
}

function plainInlines(nodes: Inline[]): string {
  return nodes.map(plainInline).join('');
}

/** Plain text for search and notifications: mentions become `@Label`, links their text. */
export function docToPlainText(doc: Doc): string {
  return doc.content
    .map((block) => {
      switch (block.type) {
        case 'paragraph':
          return plainInlines(block.content);
        case 'bulletList':
          return block.items.map((item) => `• ${plainInlines(item)}`).join('\n');
        case 'orderedList':
          return block.items.map((item, i) => `${i + 1}. ${plainInlines(item)}`).join('\n');
      }
    })
    .join('\n');
}

function* inlinesOf(doc: Doc): Generator<Inline> {
  for (const block of doc.content) {
    if (block.type === 'paragraph') yield* block.content;
    else for (const item of block.items) yield* item;
  }
}

/** The distinct mentioned user ids (in order of first appearance) and whether the board was mentioned. */
export function mentionsIn(doc: Doc): { userIds: string[]; everyone: boolean } {
  const userIds: string[] = [];
  let everyone = false;
  for (const node of inlinesOf(doc)) {
    if (node.type !== 'mention') continue;
    if (node.scope === 'board') everyone = true;
    else if (node.userId && !userIds.includes(node.userId)) userIds.push(node.userId);
  }
  return { userIds, everyone };
}

// ---------------------------------------------------------------------------
// Legacy rows
// ---------------------------------------------------------------------------

/** Wraps plain text as one paragraph per non-blank line, with no inline parsing. */
export function legacyDoc(text: string): Doc {
  const content: Block[] = [];
  for (const rawLine of text.split('\n')) {
    const line = rawLine.trimEnd();
    if (line.trim() === '') continue;
    content.push({ type: 'paragraph', content: [{ type: 'text', text: line }] });
  }
  return { type: 'doc', content };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function sanitizeInline(raw: unknown): Inline | null {
  if (!isRecord(raw)) return null;
  switch (raw.type) {
    case 'text': {
      if (typeof raw.text !== 'string' || raw.text === '') return null;
      const marks = Array.isArray(raw.marks)
        ? sortMarks(raw.marks.filter((m): m is Mark => typeof m === 'string' && (MARK_ORDER as string[]).includes(m)))
        : [];
      return textNode(raw.text, marks);
    }
    case 'link': {
      if (typeof raw.href !== 'string' || raw.href === '') return null;
      const text = typeof raw.text === 'string' && raw.text !== '' ? raw.text : raw.href;
      return { type: 'link', href: raw.href, text };
    }
    case 'mention': {
      if (typeof raw.label !== 'string' || raw.label === '') return null;
      if (raw.scope === 'board') return { type: 'mention', label: raw.label, scope: 'board' };
      if (typeof raw.userId === 'string' && raw.userId !== '') return { type: 'mention', label: raw.label, userId: raw.userId };
      return null;
    }
    default:
      return null;
  }
}

function sanitizeInlines(raw: unknown): Inline[] {
  if (!Array.isArray(raw)) return [];
  const nodes: Inline[] = [];
  for (const entry of raw) {
    const node = sanitizeInline(entry);
    if (node) nodes.push(node);
  }
  return mergeRuns(nodes);
}

/**
 * Coerces whatever is in the `body` column into a valid Doc: the current
 * shape, the old `{type:'paragraph', text}` shape, a plain string (treated as
 * legacy text), or garbage (→ empty doc). Never throws.
 */
export function normalizeStoredDoc(raw: unknown): Doc {
  if (typeof raw === 'string') return legacyDoc(raw);
  if (!isRecord(raw) || !Array.isArray(raw.content)) return { type: 'doc', content: [] };

  const content: Block[] = [];
  for (const block of raw.content) {
    if (!isRecord(block)) continue;
    if (block.type === 'paragraph') {
      if (typeof block.text === 'string') {
        content.push(...legacyDoc(block.text).content);
      } else {
        const inlines = sanitizeInlines(block.content);
        if (inlines.length) content.push({ type: 'paragraph', content: inlines });
      }
    } else if ((block.type === 'bulletList' || block.type === 'orderedList') && Array.isArray(block.items)) {
      const items = block.items.map(sanitizeInlines).filter((item) => item.length > 0);
      if (items.length) content.push({ type: block.type, items });
    }
  }
  return { type: 'doc', content };
}
