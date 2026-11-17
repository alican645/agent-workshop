import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BUILTINS, pick, matchClips, hashId } from '../../Sources/Atolye/Web/robots.mjs';

const pool = BUILTINS.map((b) => ({ id: b.id, role: b.role, builtin: true }));
const RE = ['Dance', 'Death', 'Idle', 'Jump', 'No', 'Punch', 'Running', 'Sitting', 'Standing', 'ThumbsUp', 'Walking', 'WalkJump', 'Wave', 'Yes'];

test('6 hazır robot: 3 ana, 3 alt, renkleri farklı', () => {
  assert.deepEqual(BUILTINS.map((b) => b.id), ['usta', 'muhendis', 'kasif', 'kivilcim', 'pit', 'vida']);
  assert.equal(BUILTINS.filter((b) => b.role === 'main').length, 3);
  assert.equal(BUILTINS.filter((b) => b.role === 'sub').length, 3);
  assert.equal(new Set(BUILTINS.map((b) => b.colors.main)).size, 6);
});

test('hashId kararlı', () => {
  assert.equal(hashId('abc'), hashId('abc'));
  assert.notEqual(hashId('abc'), hashId('abd'));
});

test('pick aynı oturuma aynı robotu verir', () => {
  assert.equal(pick(pool, 'main', new Map(), 's1'), pick(pool, 'main', new Map(), 's1'));
});

test('pick kullanılmayanı tercih eder', () => {
  assert.equal(pick(pool, 'main', new Map([['usta', 1], ['muhendis', 1]]), 'x'), 'kasif');
  assert.equal(pick(pool, 'sub', new Map([['pit', 2], ['vida', 1]]), 'x'), 'kivilcim');
});

test('pick yüklenemeyeni atlar, aday yoksa varsayılan', () => {
  const p = [{ id: 'muhendis', role: 'main', failed: true }];
  assert.equal(pick(p, 'main', new Map(), 'x'), 'usta');
  assert.equal(pick([], 'sub', new Map(), 'x'), 'pit');
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
