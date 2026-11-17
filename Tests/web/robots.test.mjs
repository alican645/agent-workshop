import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BUILTINS, DEFAULTS, pick, matchClips, hashId } from '../../Sources/Atolye/Web/robots.mjs';

const pool = BUILTINS.map((b) => ({ id: b.id, role: b.role, builtin: true }));
const RE = ['Dance', 'Death', 'Idle', 'Jump', 'No', 'Punch', 'Running', 'Sitting', 'Standing', 'ThumbsUp', 'Walking', 'WalkJump', 'Wave', 'Yes'];

test('6 hazır robot: 3 ana, 3 alt, her biri ayrı model', () => {
  assert.deepEqual(BUILTINS.map((b) => b.id), ['george', 'mike', 'stan', 'leela', 'android', 'usta']);
  assert.deepEqual(BUILTINS.filter((b) => b.role === 'main').map((b) => b.id), ['george', 'mike', 'stan']);
  assert.equal(BUILTINS.filter((b) => b.role === 'sub').length, 3);
  assert.equal(new Set(BUILTINS.map((b) => b.url)).size, 6);
  assert.ok(BUILTINS.every((b) => b.url.startsWith('./models/') && b.url.endsWith('.glb')));
  assert.deepEqual(DEFAULTS, { main: 'mike', sub: 'usta' });
});

test('android: kılıç gizli, bekleme ve çalışma klipleri elle seçili', () => {
  const a = BUILTINS.find((b) => b.id === 'android');
  assert.deepEqual(a.hide, ['Sword']);
  const names = ['Idle_Gun_Pointing', 'Idle_Neutral', 'Idle_Sword', 'Interact', 'Punch_Left', 'Walk', 'Wave'];
  const m = matchClips(names, a.clips);
  assert.equal(m.idle, 'Idle_Neutral');
  assert.equal(m.work, 'Interact');
  assert.equal(m.wave, 'Wave');
});

test('matchClips: mech adları (Hello el sallama)', () => {
  const m = matchClips(['Dance', 'Hello', 'Idle', 'Punch', 'Walk', 'Yes', 'Run']);
  assert.deepEqual([m.idle, m.walk, m.wave, m.yes, m.sit], ['Idle', 'Walk', 'Hello', 'Yes', null]);
});

test('hashId kararlı', () => {
  assert.equal(hashId('abc'), hashId('abc'));
  assert.notEqual(hashId('abc'), hashId('abd'));
});

test('pick aynı oturuma aynı robotu verir', () => {
  assert.equal(pick(pool, 'main', new Map(), 's1'), pick(pool, 'main', new Map(), 's1'));
});

test('pick kullanılmayanı tercih eder', () => {
  assert.equal(pick(pool, 'main', new Map([['george', 1], ['mike', 1]]), 'x'), 'stan');
  assert.equal(pick(pool, 'sub', new Map([['usta', 2], ['android', 1]]), 'x'), 'leela');
});

test('pick yüklenemeyeni atlar, aday yoksa varsayılan', () => {
  const p = [{ id: 'george', role: 'main', failed: true }];
  assert.equal(pick(p, 'main', new Map(), 'x'), 'mike');
  assert.equal(pick([], 'sub', new Map(), 'x'), 'usta');
});

test('pick both rollü robotu iki rolde de sayar', () => {
  const p = [{ id: 'benim', role: 'both' }];
  assert.equal(pick(p, 'main', new Map(), 'x'), 'benim');
  assert.equal(pick(p, 'sub', new Map(), 'x'), 'benim');
});

test('matchClips RobotExpressive adlarını eşler', () => {
  assert.deepEqual(matchClips(RE), { idle: 'Idle', walk: 'Walking', wave: 'Wave', sit: 'Sitting', yes: 'Yes', work: 'Punch', thumbs: 'ThumbsUp' });
});

test('matchClips farklı adlar ve eksikler', () => {
  const m = matchClips(['Armature|run_cycle', 'HELLO']);
  assert.equal(m.walk, 'Armature|run_cycle');
  assert.equal(m.wave, 'HELLO');
  assert.equal(m.idle, null);
});

test('matchClips boş', () => {
  assert.ok(Object.values(matchClips([])).every((v) => v === null));
});

test('matchClips iki harfli anahtarı yalnız tam ad olarak eşler', () => {
  assert.equal(matchClips(['HitReact']).wave, null);
  assert.equal(matchClips(['Hi']).wave, 'Hi');
});
