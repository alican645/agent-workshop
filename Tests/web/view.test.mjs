import { test } from 'node:test';
import assert from 'node:assert/strict';
import { homeDistance, ZONE_W, ZONE_D, ELEV } from '../../Sources/Atolye/Web/view.mjs';

const base = { gapX: 16, gapZ: 14, fov: 45, aspect: 16 / 10 };

// Sığdırma: verilen uzaklıkta bütün platformların genişliği ve derinliği görüş açısına girer.
function fits(d, { cols, rows, gapX, gapZ, fov, aspect }) {
  const v = Math.tan((fov * Math.PI) / 360), h = v * aspect;
  const w = (cols - 1) * gapX + ZONE_W, dep = (rows - 1) * gapZ + ZONE_D;
  return w / 2 <= d * h && (dep * Math.sin(ELEV)) / 2 <= d * v;
}

test('bütün platformlar sığar', () => {
  for (const [cols, rows] of [[1, 1], [2, 1], [2, 2], [3, 3], [4, 4], [5, 4]]) {
    for (const aspect of [1.0, 1.6, 2.2]) {
      const o = { ...base, cols, rows, aspect };
      assert.ok(fits(homeDistance(o), o), `${cols}x${rows} @${aspect}`);
    }
  }
});

test('proje arttıkça uzaklaşır', () => {
  const d1 = homeDistance({ ...base, cols: 1, rows: 1 });
  const d4 = homeDistance({ ...base, cols: 2, rows: 2 });
  const d9 = homeDistance({ ...base, cols: 3, rows: 3 });
  assert.ok(d1 < d4 && d4 < d9);
});

test('dar pencerede daha uzak', () => {
  const wide = homeDistance({ ...base, cols: 3, rows: 2, aspect: 2 });
  const narrow = homeDistance({ ...base, cols: 3, rows: 2, aspect: 1 });
  assert.ok(narrow > wide);
});

test('tek projede çok uzaklaşmaz', () => {
  const d = homeDistance({ ...base, cols: 1, rows: 1 });
  assert.ok(d >= 14 && d <= 26, String(d));
});
