import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GEAR_MAX, gearLayout, gearColor, gearSpeed, cardLabel } from '../../Sources/Atolye/Web/gears.mjs';

test('boş pano: çark yok', () => {
  assert.deepEqual(gearLayout(0), { slots: [], more: 0 });
});

test('dört kart: iki satır, üst satır üç çark', () => {
  const { slots, more } = gearLayout(4);
  assert.equal(slots.length, 4);
  assert.equal(more, 0);
  assert.equal(new Set(slots.map((s) => `${s.x},${s.y}`)).size, 4);
  assert.ok(slots[0].y === slots[1].y && slots[1].y === slots[2].y);
  assert.ok(slots[3].y < slots[0].y);
  assert.ok(slots[0].x < slots[1].x && slots[1].x < slots[2].x);
});

test('altıdan fazlası +N', () => {
  const { slots, more } = gearLayout(9);
  assert.equal(GEAR_MAX, 6);
  assert.equal(slots.length, 6);
  assert.equal(more, 3);
});

test('durum renkleri', () => {
  assert.equal(gearColor('idle'), 0x9aa0a6);
  assert.equal(gearColor('running'), 0xf08a24);
  assert.equal(gearColor('failed'), 0xd9534f);
  assert.equal(gearColor('ok', 0.5), 0x4cd28a);
  assert.equal(gearColor('ok', 3), 0x3aa57a);
});

test('yalnız çalışan çark döner', () => {
  assert.ok(gearSpeed('running') > 0);
  for (const s of ['idle', 'ok', 'failed']) assert.equal(gearSpeed(s), 0);
});

test('uzun kart adı kısalır', () => {
  const l = cardLabel('Çok uzun bir kart adı');
  assert.equal([...l].length, 14);
  assert.ok(l.endsWith('…'));
  assert.equal(cardLabel('Deploy'), 'Deploy');
});
