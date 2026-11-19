import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

// Sayfadaki betiklerde sözdizimi hatası (ör. aynı adla iki değişken) sahneyi tümden durdurur.
test('index.html betikleri derlenir', () => {
  const html = readFileSync(new URL('../../Sources/Atolye/Web/index.html', import.meta.url), 'utf8');
  const scripts = [...html.matchAll(/<script( type="module")?>([\s\S]*?)<\/script>/g)];
  assert.ok(scripts.length >= 2);
  const dir = mkdtempSync(join(tmpdir(), 'page-'));
  scripts.forEach(([, mod, code], i) => {
    const file = join(dir, `s${i}.${mod ? 'mjs' : 'cjs'}`);
    writeFileSync(file, code);
    const r = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
  });
});

// Panelde kart satırı terminal satırı (.mach) seçicisine takılmamalı: yoksa tıklama terminal açmaya döner.
test('kart satırları terminal satırı sayılmaz', () => {
  const html = readFileSync(new URL('../../Sources/Atolye/Web/index.html', import.meta.url), 'utf8');
  const row = html.match(/class="([^"]*)" data-card=/);
  assert.ok(row, 'kart satırı bulunamadı');
  assert.ok(!row[1].split(/\s+/).includes('mach'), row[1]);
});
