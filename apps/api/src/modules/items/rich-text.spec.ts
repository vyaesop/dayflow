import { BadRequestException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import {
  docToPlainText,
  legacyDoc,
  MAX_BODY_LENGTH,
  mentionsIn,
  normalizeStoredDoc,
  parseMarkdownLite,
  serializeDoc,
  type Doc,
  type Inline,
} from './rich-text';

const ANN = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';

const t = (text: string, ...marks: Array<'bold' | 'italic' | 'strike' | 'code'>): Inline =>
  marks.length ? { type: 'text', text, marks } : { type: 'text', text };
const link = (href: string, text = href): Inline => ({ type: 'link', href, text });
const user = (label: string, userId: string): Inline => ({ type: 'mention', label, userId });
const everyone: Inline = { type: 'mention', label: 'Everyone on this board', scope: 'board' };

/** The inline content of the first paragraph. */
function inline(input: string): Inline[] {
  const doc = parseMarkdownLite(input);
  expect(doc.content).toHaveLength(1);
  const block = doc.content[0];
  expect(block.type).toBe('paragraph');
  return block.type === 'paragraph' ? block.content : [];
}

describe('parseMarkdownLite — each inline construct alone', () => {
  it('plain text', () => {
    expect(inline('just words')).toEqual([t('just words')]);
  });

  it('bold', () => {
    expect(inline('a **b** c')).toEqual([t('a '), t('b', 'bold'), t(' c')]);
  });

  it('italic', () => {
    expect(inline('a _b_ c')).toEqual([t('a '), t('b', 'italic'), t(' c')]);
    expect(inline('_b_')).toEqual([t('b', 'italic')]);
    expect(inline('(_b_), _c_.')).toEqual([t('('), t('b', 'italic'), t('), '), t('c', 'italic'), t('.')]);
  });

  it('strike', () => {
    expect(inline('a ~~b~~ c')).toEqual([t('a '), t('b', 'strike'), t(' c')]);
  });

  it('code', () => {
    expect(inline('run `npm test` now')).toEqual([t('run '), t('npm test', 'code'), t(' now')]);
  });

  it('link', () => {
    expect(inline('see [docs](https://example.com/a?b=1) now')).toEqual([
      t('see '),
      link('https://example.com/a?b=1', 'docs'),
      t(' now'),
    ]);
    expect(inline('[x](http://h)')).toEqual([link('http://h', 'x')]);
  });

  it('bare url', () => {
    expect(inline('go to https://example.com/p/1 now')).toEqual([t('go to '), link('https://example.com/p/1'), t(' now')]);
    expect(inline('http://a.b')).toEqual([link('http://a.b')]);
  });

  it('user mention (id lower-cased)', () => {
    expect(inline(`hi @[Ann Lee](user:${ANN.toUpperCase()})!`)).toEqual([t('hi '), user('Ann Lee', ANN), t('!')]);
  });

  it('board mention', () => {
    expect(inline('@[Everyone on this board](board) ship it')).toEqual([everyone, t(' ship it')]);
  });
});

describe('parseMarkdownLite — combinations', () => {
  it('nests marks', () => {
    expect(inline('**bold _both_ bold**')).toEqual([t('bold ', 'bold'), t('both', 'bold', 'italic'), t(' bold', 'bold')]);
    expect(inline('**_~~`all`~~_**')).toEqual([t('all', 'bold', 'italic', 'strike', 'code')]);
    expect(inline('~~**x**~~')).toEqual([t('x', 'bold', 'strike')]);
  });

  it('does not parse inside code', () => {
    expect(inline('`**not bold** _nor italic_ @[x](board)`')).toEqual([t('**not bold** _nor italic_ @[x](board)', 'code')]);
  });

  it('keeps mentions and links inside marked spans, dropping the mark', () => {
    expect(inline(`**ask @[Bob](user:${BOB})**`)).toEqual([t('ask ', 'bold'), user('Bob', BOB)]);
    expect(inline('~~[old](https://old.example)~~')).toEqual([link('https://old.example', 'old')]);
  });

  it('mixes everything in one line', () => {
    expect(inline(`@[Ann](user:${ANN}) see **[the doc](https://d.example)** or https://x.example/y, then \`git push\`.`)).toEqual([
      user('Ann', ANN),
      t(' see '),
      link('https://d.example', 'the doc'),
      t(' or '),
      link('https://x.example/y'),
      t(', then '),
      t('git push', 'code'),
      t('.'),
    ]);
  });

  it('merges adjacent runs with identical marks', () => {
    expect(inline('**a****b**')).toEqual([t('ab', 'bold')]);
    expect(inline('a`b`c')).toEqual([t('a'), t('b', 'code'), t('c')]);
  });

  it('prefers mention over link over the rest at the same position', () => {
    expect(inline('@[x](user:not-a-uuid)')).toEqual([t('@[x](user:not-a-uuid)')]);
    expect(inline('[x](ftp://nope)')).toEqual([t('[x](ftp://nope)')]);
    expect(inline('[**x**](https://h)')).toEqual([link('https://h', '**x**')]);
  });
});

describe('parseMarkdownLite — literal fallbacks', () => {
  it('unbalanced markers stay literal', () => {
    expect(inline('**open')).toEqual([t('**open')]);
    expect(inline('close**')).toEqual([t('close**')]);
    expect(inline('~~half')).toEqual([t('~~half')]);
    expect(inline('`tick')).toEqual([t('`tick')]);
    expect(inline('_lonely')).toEqual([t('_lonely')]);
    expect(inline('****')).toEqual([t('****')]);
    expect(inline('~~~~')).toEqual([t('~~~~')]);
    expect(inline('``')).toEqual([t('``')]);
    expect(inline('a * b * c')).toEqual([t('a * b * c')]);
  });

  it('snake_case is not italic', () => {
    expect(inline('my_var_name here')).toEqual([t('my_var_name here')]);
    expect(inline('foo_bar _baz_ qux_')).toEqual([t('foo_bar '), t('baz', 'italic'), t(' qux_')]);
    expect(inline('_bar_baz_')).toEqual([t('bar_baz', 'italic')]);
    expect(inline('_ spaced _')).toEqual([t('_ spaced _')]);
    expect(inline('__')).toEqual([t('__')]);
  });

  it('bare urls exclude trailing punctuation', () => {
    expect(inline('see https://example.com/a.')).toEqual([t('see '), link('https://example.com/a'), t('.')]);
    expect(inline('(https://example.com/a), ok')).toEqual([t('('), link('https://example.com/a'), t('), ok')]);
    expect(inline('https://example.com/a?q=1!?')).toEqual([link('https://example.com/a?q=1'), t('!?')]);
    expect(inline('https://example.com/a.b')).toEqual([link('https://example.com/a.b')]);
    expect(inline('https://.')).toEqual([t('https://.')]);
    expect(inline('https:// nope')).toEqual([t('https:// nope')]);
    expect(inline('http is a protocol')).toEqual([t('http is a protocol')]);
  });
});

describe('parseMarkdownLite — blocks', () => {
  it('groups consecutive bullets of either marker into one list', () => {
    expect(parseMarkdownLite('- one\n* two\n- **three**')).toEqual({
      type: 'doc',
      content: [{ type: 'bulletList', items: [[t('one')], [t('two')], [t('three', 'bold')]] }],
    });
  });

  it('groups ordered items regardless of their numbers', () => {
    expect(parseMarkdownLite('3. a\n1. b\n42. c')).toEqual({
      type: 'doc',
      content: [{ type: 'orderedList', items: [[t('a')], [t('b')], [t('c')]] }],
    });
  });

  it('starts a new list when the type changes and after a paragraph', () => {
    expect(parseMarkdownLite('- a\n1. b\n- c\npara\n- d').content.map((b) => b.type)).toEqual([
      'bulletList',
      'orderedList',
      'bulletList',
      'paragraph',
      'bulletList',
    ]);
  });

  it('drops blank lines (they do not break a list), trims right, tolerates CRLF', () => {
    expect(parseMarkdownLite('  \n- a  \r\n\n- b\r\n\n\npara   \n')).toEqual({
      type: 'doc',
      content: [
        { type: 'bulletList', items: [[t('a')], [t('b')]] },
        { type: 'paragraph', content: [t('para')] },
      ],
    });
    expect(parseMarkdownLite('')).toEqual({ type: 'doc', content: [] });
    expect(parseMarkdownLite('\n\n  \n')).toEqual({ type: 'doc', content: [] });
  });

  it('needs a space after the marker and content after it', () => {
    expect(parseMarkdownLite('-nope\n1.nope\n- \n-').content.map((b) => b.type)).toEqual([
      'paragraph',
      'paragraph',
      'paragraph',
      'paragraph',
    ]);
    expect(parseMarkdownLite('1.5 is a number').content[0].type).toBe('paragraph');
  });
});

describe('serializeDoc round trip', () => {
  const canonical = [
    'Hello **world**',
    '- one\n- two\n1. three\n2. four\nend',
    `Ping @[Ann Lee](user:${ANN}) and @[Everyone on this board](board)`,
    'See [docs](https://example.com/a) or https://example.com/b',
    '**_~~`all`~~_**',
    'snake_case stays plus _italic_ words',
    'Unbalanced **bold and `code stay literal',
    'mixed ~~old~~ and **new** in one line, `x` too.',
    `- item with **bold** and @[Bob](user:${BOB})\n- (https://example.com/p).`,
    'a **b _c_ d** e',
    '1. first\n2. second\n- then a bullet\nparagraph\n1. restart',
    '_a**b**_ and ~~c**d**~~ and **e**_f_',
  ];

  it.each(canonical)('is stable for canonical input %#', (input) => {
    expect(serializeDoc(parseMarkdownLite(input))).toBe(input);
  });

  const nonCanonical: Array<[string, string]> = [
    ['* star bullet\n* another', '- star bullet\n- another'],
    ['3. x\n7. y', '1. x\n2. y'],
    ['\n\npara one  \n\n\npara two\n', 'para one\npara two'],
    ['**a****b**', '**ab**'],
    ['- a\n\n- b', '- a\n- b'],
    ['~~**x**~~', '**~~x~~**'],
    ['**b ****_c_**** d**', '**b _c_ d**'],
    ['[https://h.example](https://h.example)', 'https://h.example'],
    [`@[Ann](user:${ANN.toUpperCase()})`, `@[Ann](user:${ANN})`],
  ];

  it.each(nonCanonical)('normalizes %j to %j and is then idempotent', (input, expected) => {
    const once = serializeDoc(parseMarkdownLite(input));
    expect(once).toBe(expected);
    expect(serializeDoc(parseMarkdownLite(once))).toBe(once);
    expect(parseMarkdownLite(once)).toEqual(parseMarkdownLite(input));
  });

  it('serializes a hand-built doc with every node type', () => {
    const doc: Doc = {
      type: 'doc',
      content: [
        { type: 'paragraph', content: [t('a ', 'bold'), t('b', 'italic', 'code'), link('https://l', 'L'), link('https://bare'), user('U', ANN), everyone] },
        { type: 'orderedList', items: [[t('x')], [t('y', 'strike')]] },
        { type: 'bulletList', items: [[t('z')]] },
      ],
    };
    expect(serializeDoc(doc)).toBe(`**a **_\`b\`_[L](https://l)https://bare@[U](user:${ANN})@[Everyone on this board](board)\n1. x\n2. ~~y~~\n- z`);
  });
});

describe('docToPlainText', () => {
  it('flattens marks, mentions, links and lists', () => {
    const doc = parseMarkdownLite(
      `**Hey** @[Ann](user:${ANN}) and @[Everyone on this board](board), see [the doc](https://d.example) at https://x.example\n- _one_\n- two\n1. three\n2. four`,
    );
    expect(docToPlainText(doc)).toBe(
      'Hey @Ann and @Everyone on this board, see the doc at https://x.example\n• one\n• two\n1. three\n2. four',
    );
  });

  it('is empty for an empty doc', () => {
    expect(docToPlainText({ type: 'doc', content: [] })).toBe('');
  });
});

describe('mentionsIn', () => {
  it('collects distinct user ids in order and flags the board mention', () => {
    const doc = parseMarkdownLite(`@[Bob](user:${BOB}) @[Ann](user:${ANN}) again @[Bob](user:${BOB})\n- @[Everyone on this board](board) **@[Ann](user:${ANN})**`);
    expect(mentionsIn(doc)).toEqual({ userIds: [BOB, ANN], everyone: true });
  });

  it('is empty without mentions', () => {
    expect(mentionsIn(parseMarkdownLite('nothing @here or @[bad](user:x)'))).toEqual({ userIds: [], everyone: false });
    expect(mentionsIn(parseMarkdownLite(`\`@[Ann](user:${ANN})\``))).toEqual({ userIds: [], everyone: false });
  });
});

describe('legacyDoc', () => {
  it('wraps each non-blank line as a plain paragraph without inline parsing', () => {
    expect(legacyDoc('**not bold**\n\n  @[x](board)  \n')).toEqual({
      type: 'doc',
      content: [
        { type: 'paragraph', content: [t('**not bold**')] },
        { type: 'paragraph', content: [t('  @[x](board)')] },
      ],
    });
    expect(legacyDoc('')).toEqual({ type: 'doc', content: [] });
  });
});

describe('normalizeStoredDoc', () => {
  it('accepts the old paragraph-with-text shape', () => {
    expect(
      normalizeStoredDoc({ type: 'doc', content: [{ type: 'paragraph', text: 'hello\nworld' }, { type: 'paragraph', text: '' }] }),
    ).toEqual({
      type: 'doc',
      content: [
        { type: 'paragraph', content: [t('hello')] },
        { type: 'paragraph', content: [t('world')] },
      ],
    });
  });

  it('passes a current doc through unchanged', () => {
    const doc = parseMarkdownLite(`**a** _b_ [c](https://c) @[D](user:${ANN}) @[E](board)\n- x\n1. y`);
    expect(normalizeStoredDoc(JSON.parse(JSON.stringify(doc)))).toEqual(doc);
  });

  it('treats a string as legacy plain text', () => {
    expect(normalizeStoredDoc('plain **text**')).toEqual(legacyDoc('plain **text**'));
  });

  it('returns an empty doc for garbage', () => {
    for (const garbage of [null, undefined, 42, true, [], {}, { type: 'doc' }, { type: 'doc', content: 'x' }, { content: [1, 'a', null] }]) {
      expect(normalizeStoredDoc(garbage)).toEqual({ type: 'doc', content: [] });
    }
  });

  it('drops invalid nodes and repairs partial ones', () => {
    const out = normalizeStoredDoc({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            { type: 'text', text: 'a', marks: ['code', 'bold', 'nope', 7] },
            { type: 'text', text: '' },
            { type: 'text', text: 42 },
            { type: 'link', href: 'https://h' },
            { type: 'link', text: 'no href' },
            { type: 'mention', label: 'Board', scope: 'board' },
            { type: 'mention', label: 'Ann', userId: ANN, scope: 'weird' },
            { type: 'mention', label: 'nobody' },
            { type: 'image', src: 'x' },
            'junk',
            { type: 'text', text: 'b' },
            { type: 'text', text: 'c' },
          ],
        },
        { type: 'paragraph', content: [{ type: 'text', text: '' }] },
        { type: 'paragraph' },
        { type: 'bulletList', items: [[{ type: 'text', text: 'ok' }], [], 'junk', [{ type: 'bogus' }]] },
        { type: 'orderedList', items: [[{ type: 'bogus' }]] },
        { type: 'orderedList' },
        { type: 'heading', content: [] },
        7,
      ],
    });
    expect(out).toEqual({
      type: 'doc',
      content: [
        {
          type: 'paragraph',
          content: [
            t('a', 'bold', 'code'),
            link('https://h'),
            { type: 'mention', label: 'Board', scope: 'board' },
            user('Ann', ANN),
            t('bc'),
          ],
        },
        { type: 'bulletList', items: [[t('ok')]] },
      ],
    });
    expect(serializeDoc(out)).toBe(`**\`a\`**https://h@[Board](board)@[Ann](user:${ANN})bc\n- ok`);
  });
});

describe('length limit', () => {
  it('accepts exactly the maximum and rejects one more', () => {
    expect(parseMarkdownLite('x'.repeat(MAX_BODY_LENGTH)).content).toHaveLength(1);
    expect(() => parseMarkdownLite('x'.repeat(MAX_BODY_LENGTH + 1))).toThrow(BadRequestException);
    expect(() => parseMarkdownLite('x'.repeat(MAX_BODY_LENGTH + 1))).toThrow(/10000 characters/);
  });
});
