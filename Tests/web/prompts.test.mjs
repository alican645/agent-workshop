import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DETAIL_MAX, waitingPrompts, balloonHtml, answerMessage, isPlaceholder, menuKey, dropFocus } from '../../Sources/Atolye/Web/prompts.mjs';
import { makeT } from '../../Sources/Atolye/Web/i18n.mjs';

const t = makeT(null);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const opts = { t, esc, compact: false };

const prompt = (o = {}) => ({
  kind: 'permission', question: 'Do you want to proceed?',
  options: [{ label: 'Yes', freeText: false }, { label: 'No', freeText: false }],
  multi: false, answerable: true, sent: false, failed: false, ...o,
});
const item = (p, o = {}) => ({ robot: 'r1', label: 'claude', color: '#f00', prompt: p, ...o });
const html = (p, o = {}, ui = {}) => balloonHtml([item(p, o)], { ...opts, ...ui });

test('stacksOnePerWaitingRobot', () => {
  const zone = { id: 'z', name: 'Z', color: '#0f0', robots: [
    { id: 'a', label: 'A', state: 'waiting', prompt: prompt() },
    { id: 'b', label: 'B', state: 'busy' },
    { id: 'c', label: 'C', state: 'waiting', prompt: prompt({ kind: 'question' }), terminal: 't3' },
  ] };
  const w = waitingPrompts(zone);
  assert.equal(w.length, 2);
  assert.deepEqual(w.map((x) => x.robot), ['a', 'c']);
  assert.equal(w[1].color, '#0f0');
  assert.equal(w[1].terminal, 't3');
  assert.equal(w[0].label, 'A');
});

test('numbersOptions', () => {
  const h = html(prompt());
  assert.ok(h.includes('[1]'));
  assert.ok(h.includes('[2]'));
});

test('notAnswerableIsDimmed', () => {
  const h = html(prompt({ answerable: false }));
  assert.ok(h.includes('class="pq off"'));
  assert.ok(h.includes('terminalinden cevapla'));
  const buttons = [...h.matchAll(/<button[^>]*class="po[^"]*"[^>]*>/g)].map((m) => m[0]);
  assert.equal(buttons.length, 2);
  for (const b of buttons) assert.ok(b.includes('disabled'), b);
});

test('answerableIsNotDimmed', () => {
  const h = html(prompt());
  assert.ok(h.includes('class="pq"'));
  assert.ok(!h.includes('disabled'));
  assert.ok(!h.includes('terminalinden cevapla'));
});

test('sentShowsSending', () => {
  const h = html(prompt({ sent: true }));
  assert.ok(h.includes('gönderildi…'));
  assert.ok(h.includes('disabled'));
});

test('localPendingDisablesButtons', () => {
  const h = html(prompt(), {}, { pending: new Set(['r1']) });
  assert.ok(h.includes('disabled'));
});

test('failedShowsOpenTerminal', () => {
  const h = html(prompt({ failed: true }), { terminal: 't1' });
  assert.ok(h.includes('gitmedi — terminali aç'));
  assert.ok(h.includes('data-term="t1"'));
  assert.ok(!h.includes('disabled')); // yeniden denenebilir
});

test('detailIsTruncated', () => {
  const detail = 'x'.repeat(500);
  const h = html(prompt({ detail }));
  const m = h.match(/<div class="pd" title="([^"]*)">([^<]*)<\/div>/);
  assert.ok(m, h);
  assert.equal(m[1], detail);
  assert.ok(m[2].length <= DETAIL_MAX + 1);
  assert.ok(m[2].endsWith('…'));
  assert.equal(DETAIL_MAX, 160);
});

test('pagesShown', () => {
  const h = html(prompt({ kind: 'question', page: 0, pages: 3 }));
  assert.ok(h.includes('1/3'));
});

test('planHasOpenLink', () => {
  const h = html(prompt({ kind: 'plan', planPath: '/tmp/p.md' }));
  assert.ok(h.includes('Planı aç'));
  assert.ok(h.includes('data-act="plan"'));
});

test('emptyPlanShowsDefaultTitleAndNote', () => {
  const h = html(prompt({ kind: 'plan', question: '', options: [], planPath: '/tmp/p.md' }));
  assert.ok(h.includes('Plan onayı bekliyor'));
  assert.ok(h.includes('Planı aç'));
  assert.ok(h.includes('terminalinden cevapla'));
  assert.ok(h.includes('class="pq off"'));
});

test('emptyQuestionDefaultTitleByKind', () => {
  assert.ok(html(prompt({ question: '' })).includes('İzin bekliyor'));
  assert.ok(html(prompt({ kind: 'question', question: '' })).includes('Soru soruyor'));
});

test('multiShowsChecksAndSend', () => {
  const p = prompt({ kind: 'question', multi: true, options: [
    { label: 'Apple', freeText: false, checked: true }, { label: 'Pear', freeText: false, checked: false }] });
  const h = html(p);
  assert.ok(h.includes('☑'));
  assert.ok(h.includes('☐'));
  assert.ok(h.includes('Gönder'));
  // yerel seçim, snapshot'taki işaretin yerine geçer
  const h2 = html(p, {}, { checks: new Map([['r1', new Set([1])]]) });
  assert.ok(h2.indexOf('☐') < h2.indexOf('☑'));
});

test('freeTextEditShowsInput', () => {
  const p = prompt({ kind: 'question', options: [{ label: 'Red', freeText: false }, { label: 'Type something.', freeText: true }] });
  assert.ok(!html(p).includes('<input'));
  const h = html(p, {}, { edit: new Map([['r1', 1]]) });
  assert.ok(h.includes('<input'));
  assert.ok(h.includes('Gönder'));
});

test('placeholderOnlyForUntypedFreeText', () => {
  assert.ok(isPlaceholder({ label: 'Type something.', freeText: true }));
  assert.ok(isPlaceholder({ label: 'Tell Claude what to change', freeText: true }));
  assert.ok(!isPlaceholder({ label: 'hello', freeText: true }));
  assert.ok(!isPlaceholder({ label: 'Type something.', freeText: false }));
});

test('answerMessageCarriesLabels', () => {
  const p = prompt();
  const m = answerMessage('r1', p, { option: 1 });
  assert.deepEqual(m, { type: 'answer', robot: 'r1', labels: ['Yes', 'No'], option: 1 });
});

test('answerMessageMultiSendsChecksOnly', () => {
  const p = prompt({ multi: true, options: [{ label: 'A', freeText: false, checked: false }, { label: 'B', freeText: false, checked: true }] });
  const m = answerMessage('r1', p, { option: 0, checks: [1, 0] });
  assert.deepEqual(m, { type: 'answer', robot: 'r1', labels: ['A', 'B'], checks: [0, 1] });
});

test('answerMessageOmitsEmptyText', () => {
  const p = prompt({ options: [{ label: 'Type something.', freeText: true }] });
  assert.ok(!('text' in answerMessage('r1', p, { option: 0, text: '' })));
  assert.ok(!('text' in answerMessage('r1', p, { option: 0, text: null })));
  assert.equal(answerMessage('r1', p, { option: 0, text: 'hi' }).text, 'hi');
  const json = JSON.parse(JSON.stringify(answerMessage('r1', p, { option: 0 })));
  assert.deepEqual(Object.keys(json).sort(), ['labels', 'option', 'robot', 'type']);
});

test('escapesHtml', () => {
  const h = html(prompt({ question: '<i>q</i>', options: [{ label: '<b>', freeText: false }] }), { label: '<s>' });
  assert.ok(h.includes('&lt;b&gt;'));
  assert.ok(!h.includes('<b>'));
  assert.ok(!h.includes('<i>'));
  assert.ok(!h.includes('<s>'));
});

test('compactHidesDetailAndDescriptions', () => {
  const p = prompt({ detail: 'rm -rf build', options: [{ label: 'Yes', description: 'desc here', freeText: false }] });
  const h = balloonHtml([item(p)], { ...opts, compact: true });
  assert.ok(!h.includes('rm -rf build'));
  assert.ok(!h.includes('desc here'));
  assert.ok(h.includes('[1]'));
});

// Yeni menü (aynı etiketli yeni bir izin bile) eski odağı devralmaz: rakam görülmemiş soruyu cevaplamasın.
test('menuKeyIgnoresSendStateButNotMenu', () => {
  const p = prompt();
  assert.equal(menuKey(p), menuKey({ ...p, sent: true, failed: true }));
  assert.notEqual(menuKey(p), menuKey({ ...p, question: 'Run rm?' }));
  assert.notEqual(menuKey(p), menuKey({ ...p, detail: 'rm -rf /' }));
});

test('focusDroppedWhenItsMenuChanges', () => {
  const f = { zone: 'z', robot: 'a' };
  assert.equal(dropFocus(f, new Set(['a'])), null);
  assert.equal(dropFocus(f, new Set(['b'])), f);
  assert.equal(dropFocus(null, new Set(['a'])), null);
});

test('emptyItemsGiveEmptyHtml', () => {
  assert.equal(balloonHtml([], opts), '');
});
