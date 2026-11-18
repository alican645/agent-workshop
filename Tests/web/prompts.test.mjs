import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DETAIL_MAX, DETAIL_COMPACT, waitingPrompts, balloonHtml, answerMessage, isPlaceholder, isCheckable, menuKey, dropFocus } from '../../Sources/Atolye/Web/prompts.mjs';
import { makeT } from '../../Sources/Atolye/Web/i18n.mjs';

const t = makeT(null);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const opts = { t, esc, compact: false };

const prompt = (o = {}) => ({
  kind: 'permission', question: 'Do you want to proceed?',
  options: [{ label: 'Yes', freeText: false }, { label: 'No', freeText: false }],
  multi: false, answerable: true, sent: false, failed: false, menuId: 'm1', ...o,
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
  // Bulgu 5: yeniden deneme yok; seçenekler kapalı, "terminali aç" bağlantısı açık.
  const buttons = [...h.matchAll(/<button[^>]*class="po[^"]*"[^>]*>/g)].map((m) => m[0]);
  assert.equal(buttons.length, 2);
  for (const b of buttons) assert.ok(b.includes('disabled'), b);
});

// Bulgu 5: Swift eski sürümde sent ile failed'ı birlikte yollayabilir; "gitmedi" öncelikli.
test('failedWinsOverSent', () => {
  const h = html(prompt({ sent: true, failed: true }), { terminal: 't1' });
  assert.ok(h.includes('gitmedi — terminali aç'));
  assert.ok(!h.includes('gönderildi…'));
  assert.ok(h.includes('data-term="t1"'));
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
  assert.ok(isPlaceholder({ label: 'Type something.', freeText: true }, 'question'));
  assert.ok(!isPlaceholder({ label: 'hello', freeText: true }, 'question'));
  assert.ok(!isPlaceholder({ label: 'Type something.', freeText: false }, 'question'));
});

// Bulgu 1: plan/izin menüsünde serbest satır sıradan seçenektir (tıkla = seç + Enter, yazı kutusu yok).
test('placeholderOnlyInQuestions', () => {
  assert.ok(!isPlaceholder({ label: 'Tell Claude what to change', freeText: true }, 'plan'));
  assert.ok(!isPlaceholder({ label: 'No, and tell Claude what to do differently', freeText: true }, 'permission'));
  assert.ok(!isPlaceholder({ label: 'Type something.', freeText: true }));
});

// Bulgu 2: çoklu seçimde kutusuz satır ("Chat about this") işaretlenemez: kutu yok, düğme kapalı.
test('multiRowWithoutCheckboxIsDisabled', () => {
  const p = prompt({ kind: 'question', multi: true, options: [
    { label: 'Apple', freeText: false, checked: false }, { label: 'Chat about this', freeText: false }] });
  assert.ok(isCheckable(p, 0));
  assert.ok(!isCheckable(p, 1));
  assert.ok(!isCheckable(p, 5));
  const h = html(p);
  const buttons = [...h.matchAll(/<button[^>]*class="po[^"]*"[^>]*>.*?<\/button>/g)].map((m) => m[0]);
  assert.ok(!buttons[0].includes('disabled') && buttons[0].includes('☐'));
  assert.ok(buttons[1].includes('disabled'), buttons[1]);
  assert.ok(!buttons[1].includes('☐') && !buttons[1].includes('☑'));
  // Tek seçimde "Chat about this" sıradan seçenektir.
  assert.ok(isCheckable(prompt(), 0) === false);
});

test('answerMessageCarriesLabels', () => {
  const p = prompt();
  const m = answerMessage('r1', p, { option: 1 });
  assert.deepEqual(m, { type: 'answer', robot: 'r1', labels: ['Yes', 'No'], menuId: 'm1', option: 1 });
});

// Bulgu 4: cevap gösterilen menünün kimliğini taşır; kimlik yoksa alan yazılmaz (Swift mesajı reddeder).
test('answerMessageEchoesMenuId', () => {
  assert.equal(answerMessage('r1', prompt({ menuId: 'x' }), { option: 0 }).menuId, 'x');
  assert.ok(!('menuId' in answerMessage('r1', prompt({ menuId: undefined }), { option: 0 })));
  assert.ok(!('menuId' in answerMessage('r1', prompt({ menuId: 5 }), { option: 0 })));
  assert.notEqual(menuKey(prompt({ menuId: 'a' })), menuKey(prompt({ menuId: 'b' })));
});

test('answerMessageMultiSendsChecksOnly', () => {
  const p = prompt({ multi: true, options: [{ label: 'A', freeText: false, checked: false }, { label: 'B', freeText: false, checked: true }] });
  const m = answerMessage('r1', p, { option: 0, checks: [1, 0] });
  assert.deepEqual(m, { type: 'answer', robot: 'r1', labels: ['A', 'B'], menuId: 'm1', checks: [0, 1] });
});

test('answerMessageOmitsEmptyText', () => {
  const p = prompt({ options: [{ label: 'Type something.', freeText: true }] });
  assert.ok(!('text' in answerMessage('r1', p, { option: 0, text: '' })));
  assert.ok(!('text' in answerMessage('r1', p, { option: 0, text: null })));
  assert.equal(answerMessage('r1', p, { option: 0, text: 'hi' }).text, 'hi');
  const json = JSON.parse(JSON.stringify(answerMessage('r1', p, { option: 0 })));
  assert.deepEqual(Object.keys(json).sort(), ['labels', 'menuId', 'option', 'robot', 'type']);
});

test('escapesHtml', () => {
  const h = html(prompt({ question: '<i>q</i>', options: [{ label: '<b>', freeText: false }] }), { label: '<s>' });
  assert.ok(h.includes('&lt;b&gt;'));
  assert.ok(!h.includes('<b>'));
  assert.ok(!h.includes('<i>'));
  assert.ok(!h.includes('<s>'));
});

test('compactHidesDescriptions', () => {
  const p = prompt({ kind: 'question', options: [{ label: 'Yes', description: 'desc here', freeText: false }] });
  const h = balloonHtml([item(p)], { ...opts, compact: true });
  assert.ok(!h.includes('desc here'));
  assert.ok(h.includes('[1]'));
});

// Bulgu 9: küçük görünümde de izin komutu (kısaltılmış) görünür: "Yes" görülmemiş bir komutu onaylamasın.
test('compactShowsClippedPermissionDetail', () => {
  const detail = 'rm -rf build; ' + 'x'.repeat(200);
  const h = balloonHtml([item(prompt({ detail }))], { ...opts, compact: true });
  const m = h.match(/<div class="pd" title="([^"]*)">([^<]*)<\/div>/);
  assert.ok(m, h);
  assert.equal(m[1], detail);
  assert.ok(m[2].startsWith('rm -rf build'));
  assert.ok(m[2].length <= DETAIL_COMPACT && m[2].endsWith('…'));
  assert.equal(DETAIL_COMPACT, 60);
  assert.ok(balloonHtml([item(prompt({ detail: 'ls' }))], { ...opts, compact: true }).includes('>ls</div>'));
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
