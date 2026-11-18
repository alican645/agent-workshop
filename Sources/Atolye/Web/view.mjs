// Atölyenin genel görünümü: kameranın bütün platformları gösterecek uzaklığı.

/** Bir platformun genişliği (x) ve derinliği (z). */
export const ZONE_W = 12, ZONE_D = 9;
/** Platformdaki en yüksek şeyler (tabela, tahta). */
const ZONE_H = 4.6;
/** Kameranın yere bakış açısı (yataydan). */
export const ELEV = Math.atan2(0.36, 0.5);
/** Kenarlarda HUD kartlarına (karşılama, akış, panel) pay. */
const MARGIN = 1.2;
const MIN = 15;

/**
 * `cols × rows` ızgaradaki platformların hepsinin ekrana sığdığı kamera uzaklığı.
 * `fov` dikey görüş açısı (derece), `aspect` genişlik/yükseklik.
 */
export function homeDistance({ cols, rows, gapX, gapZ, fov, aspect }) {
  const v = Math.tan((fov * Math.PI) / 360), h = v * aspect;
  const w = (Math.max(1, cols) - 1) * gapX + ZONE_W;
  const d = (Math.max(1, rows) - 1) * gapZ + ZONE_D;
  // Yatay: genişlik görüş açısına girsin. Dikey: eğik bakıldığı için derinlik kısalır, yükseklik eklenir.
  const byW = w / 2 / h;
  const byD = (d * Math.sin(ELEV) + ZONE_H * Math.cos(ELEV)) / 2 / v;
  return Math.max(MIN, Math.max(byW, byD) * MARGIN);
}

/** Uzaklıktan kamera konumu (hedef: orijin). */
export function homePosition(dist) {
  return [0, dist * Math.sin(ELEV), dist * Math.cos(ELEV)];
}
