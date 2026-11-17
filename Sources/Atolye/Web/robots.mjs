// Robot havuzunun saf mantığı: hazır robot kataloğu, rastgele seçim ve animasyon ad eşleme.
// three.js'e bağımlı değil; Tests/web altında node --test ile sınanır.

/**
 * Hazır robotlar. Hepsi RobotExpressive iskeletinden giydirilir:
 * colors.main gövdenin renkli parçaları, colors.second takılar; bones kemik ölçekleri; scale genel boy.
 */
export const BUILTINS = [
  { id: 'usta', name: 'Usta', role: 'main', scale: 1,
    colors: { main: '#e8772e', second: '#ffcf3a' }, material: { metalness: 0.05, roughness: 0.8 },
    bones: {}, accessories: ['helmet', 'headlamp'] },
  { id: 'muhendis', name: 'Mühendis', role: 'main', scale: 1.06,
    colors: { main: '#2f4f8f', second: '#9fd8ff' }, material: { metalness: 0.35, roughness: 0.35 },
    bones: { 'UpperLeg.L': 1.3, 'UpperLeg.R': 1.3, Head: 0.9 }, accessories: ['visor', 'twinAntenna'] },
  { id: 'kasif', name: 'Kâşif', role: 'main', scale: 0.95,
    colors: { main: '#6f8a3a', second: '#3b3530' }, material: { metalness: 0.1, roughness: 0.75 },
    bones: { Head: 1.35, Torso: 1.1, 'UpperLeg.L': 0.75, 'UpperLeg.R': 0.75 }, accessories: ['headphones'] },
  { id: 'kivilcim', name: 'Kıvılcım', role: 'sub', scale: 1,
    colors: { main: '#f2c230', second: '#ff6a3d' }, material: { metalness: 0.2, roughness: 0.25 },
    bones: { Head: 0.8, 'UpperLeg.L': 1.15, 'UpperLeg.R': 1.15 }, accessories: ['antenna'] },
  { id: 'pit', name: 'Pıt', role: 'sub', scale: 0.95,
    colors: { main: '#8f7be0', second: '#f6f1e8' }, material: { metalness: 0.05, roughness: 0.6 },
    bones: { Head: 1.6, 'UpperLeg.L': 0.8, 'UpperLeg.R': 0.8 }, accessories: ['propeller'] },
  { id: 'vida', name: 'Vida', role: 'sub', scale: 1,
    colors: { main: '#9aa3ad', second: '#ff3b3b' }, material: { metalness: 0.3, roughness: 0.4 },
    bones: { 'Shoulder.L': 1.45, 'Shoulder.R': 1.45, Torso: 1.1 }, accessories: ['helmet', 'monoVisor'] },
];

export const DEFAULTS = { main: 'usta', sub: 'pit' };

/** 32 bit kararlı özet (FNV-1a). */
export function hashId(id) {
  let h = 0x811c9dc5;
  for (let i = 0; i < id.length; i++) { h ^= id.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return h >>> 0;
}

/**
 * Yeni bir robot için havuzdan kostüm seçer: rolü uyan, yüklenebilen robotlar arasından
 * atölyede en az kullanılanı; eşitlikte oturum kimliğinden türetilen sırayla.
 */
export function pick(pool, role, inUse, sessionId) {
  const cands = pool.filter((p) => !p.failed && (p.role === role || p.role === 'both'));
  if (!cands.length) return DEFAULTS[role];
  const min = Math.min(...cands.map((p) => inUse.get(p.id) || 0));
  const least = cands.filter((p) => (inUse.get(p.id) || 0) === min);
  return least[hashId(sessionId) % least.length].id;
}

/** Atölyenin hareketleri ve onları karşılayabilecek klip adları (öncelik sırasıyla). */
export const MOTIONS = {
  idle: ['idle', 'stand', 'breath'],
  walk: ['walking', 'walk', 'run', 'jog'],
  wave: ['wave', 'hello', 'greet', 'hi'],
  sit: ['sitting', 'sit'],
  yes: ['yes', 'nod', 'thumbsup'],
  work: ['punch', 'attack', 'work', 'hammer', 'interact'],
  thumbs: ['thumbsup', 'yes'],
};

const norm = (n) => n.split('|').pop().toLowerCase().replace(/[^a-z0-9]/g, '');

/**
 * Model kliplerini hareketlere eşler. Önce tam ad, sonra içerme (3 harf ve altı anahtarlar
 * yalnız baştan eşleşir: "sit" "position"a takılmasın). Bulunamayan hareket null.
 */
export function matchClips(names) {
  const list = names.map((n) => [n, norm(n)]);
  const out = {};
  for (const [motion, keys] of Object.entries(MOTIONS)) {
    let hit = null;
    for (const k of keys) { const f = list.find(([, n]) => n === k); if (f) { hit = f[0]; break; } }
    if (!hit) for (const k of keys) {
      const f = list.find(([, n]) => (k.length <= 3 ? n.startsWith(k) : n.includes(k)));
      if (f) { hit = f[0]; break; }
    }
    out[motion] = hit;
  }
  return out;
}
