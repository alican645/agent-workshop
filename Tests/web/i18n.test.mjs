import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeT } from '../../Sources/Atolye/Web/i18n.mjs';

test('sözlükte varsa İngilizcesini verir, yer tutucuları doldurur', () => {
  const t = makeT({ '{0} yardımcı': '{0} helpers', 'dal değişti: {0} → {1}': 'branch changed: {0} → {1}' });
  assert.equal(t('{0} yardımcı', 3), '3 helpers');
  assert.equal(t('dal değişti: {0} → {1}', 'a', '<b>b</b>'), 'branch changed: a → <b>b</b>');
});

test('sözlük yoksa ya da anahtar eksikse Türkçe kalır', () => {
  assert.equal(makeT(undefined)('{0} yardımcı', 2), '2 yardımcı');
  assert.equal(makeT({})('bitti'), 'bitti');
});

test('aynı yer tutucu iki kez geçebilir', () => {
  assert.equal(makeT({})('{0}/{0}', 'x'), 'x/x');
});
