// Makine panosu: çalıştırma kartlarının çarkları. Saf hesaplar (yerleşim, renk, hız); çizim index.html'de.

/** Panoda görünen en çok çark (2 satır × 3 sütun). */
export const GEAR_MAX = 6;
const COLS = 3;
/** Pano yüzü yerel koordinatı: sütun aralığı, satır yükseklikleri (üst satır önce). */
const DX = 0.72, ROW_Y = [2.8, 2.02];

/** `n` kartın çark yerleri, satır satır soldan sağa; sığmayanlar `more`. */
export function gearLayout(n) {
  const shown = Math.max(0, Math.min(n, GEAR_MAX));
  const slots = [];
  for (let i = 0; i < shown; i++) {
    const col = i % COLS, row = Math.floor(i / COLS);
    slots.push({ x: (col - 1) * DX, y: ROW_Y[row] });
  }
  return { slots, more: Math.max(0, n - GEAR_MAX) };
}

/** Durumun rengi. Başarıdan sonraki ilk 2 sn parlak yeşil, sonra sakin yeşil. */
export function gearColor(state, sinceOkSec = Infinity) {
  switch (state) {
    case 'running': return 0xf08a24;
    case 'failed': return 0xd9534f;
    case 'ok': return sinceOkSec < 2 ? 0x4cd28a : 0x3aa57a;
    default: return 0x9aa0a6;
  }
}

/** Dönüş hızı (rad/sn): yalnız çalışan kart döner. */
export function gearSpeed(state) {
  return state === 'running' ? 2.4 : 0;
}

/** Çarkın altındaki ad; uzunsa `…` ile kısaltılır (harf sayısı `max`). */
export function cardLabel(name, max = 14) {
  const chars = [...(name || '')];
  return chars.length <= max ? chars.join('') : chars.slice(0, max - 1).join('') + '…';
}
