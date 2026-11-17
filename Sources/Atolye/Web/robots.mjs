// Robot havuzunun saf mantığı: hazır robot kataloğu, rastgele seçim ve animasyon ad eşleme.
// three.js'e bağımlı değil; Tests/web altında node --test ile sınanır.

/**
 * Hazır robotlar: her biri ayrı bir model (Quaternius, CC0 — models/LICENSE.txt).
 * hide: gizlenecek parça adları; clips: ad eşlemenin yanlış seçeceği hareketler için elle seçilen klip.
 */
export const BUILTINS = [
  { id: 'george', name: 'George', role: 'main', url: './models/George.glb' },
  { id: 'mike', name: 'Mike', role: 'main', url: './models/Mike.glb' },
  { id: 'stan', name: 'Stan', role: 'main', url: './models/Stan.glb' },
  { id: 'leela', name: 'Leela', role: 'sub', url: './models/Leela.glb' },
  { id: 'android', name: 'Android', role: 'sub', url: './models/Android.glb',
    hide: ['Sword'], clips: { idle: 'Idle_Neutral', work: 'Interact' } },
  { id: 'usta', name: 'Usta', role: 'sub', url: './models/RobotExpressive.glb' },
];

export const DEFAULTS = { main: 'mike', sub: 'usta' };

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
 * Model kliplerini hareketlere eşler. Önce `overrides` (modelde varsa), sonra tam ad, sonra içerme
 * (3 harf ve altı anahtarlar yalnız baştan eşleşir: "sit" "position"a takılmasın). Bulunamayan hareket null.
 */
export function matchClips(names, overrides = {}) {
  const list = names.map((n) => [n, norm(n)]);
  const out = {};
  for (const [motion, keys] of Object.entries(MOTIONS)) {
    let hit = names.includes(overrides[motion]) ? overrides[motion] : null;
    if (!hit) for (const k of keys) { const f = list.find(([, n]) => n === k); if (f) { hit = f[0]; break; } }
    if (!hit) for (const k of keys) {
      if (k.length <= 2) continue; // "hi" yalnız tam ad: "HitReact" el sallama değil
      const f = list.find(([, n]) => (k.length <= 3 ? n.startsWith(k) : n.includes(k)));
      if (f) { hit = f[0]; break; }
    }
    out[motion] = hit;
  }
  return out;
}
