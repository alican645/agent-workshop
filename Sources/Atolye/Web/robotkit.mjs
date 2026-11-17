// Robotları kuran three.js kodu: hazır robotları RobotExpressive'den giydirir, kendi .glb robotlarını
// normalleştirir, her robot için klon + animasyon hazırlar ve eksik animasyonlara yedek hareket verir.
import * as THREE from 'three';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';
import { matchClips } from './robots.mjs';

/** Modeli ilk klibin (tercihen Idle) ilk karesinde ölçer: animasyon iskeleti başka bir duruşa sokabiliyor. */
function measure(root, clips, idleName) {
  const mixer = new THREE.AnimationMixer(root);
  const clip = clips.find((c) => c.name === idleName) || clips[0];
  if (clip) { mixer.clipAction(clip).play(); mixer.update(0); }
  root.updateMatrixWorld(true);
  const bb = new THREE.Box3().setFromObject(root);
  mixer.stopAllAction(); mixer.uncacheRoot(root);
  return bb;
}

function std(color, def, extra = {}) {
  return new THREE.MeshStandardMaterial({ color, metalness: def.material.metalness, roughness: def.material.roughness, ...extra });
}

// Takılar RobotExpressive'in Head kemiğinin yerel uzayında kurulur (y yukarı, +z ön yüz).
// O uzayda kafa: x ±0.0132, y −0.0021…0.0208, z −0.0129…0.0143 (önizleme ile ölçüldü).
const HEAD = { top: 0.0208, bottom: -0.0021, half: 0.0132, front: 0.0143, back: -0.0129, mid: 0.0094 };

function accessory(name, def) {
  const g = new THREE.Group();
  const second = std(def.colors.second, def);
  const dark = new THREE.MeshStandardMaterial({ color: '#2b2926', roughness: 0.6 });
  const glow = (op = 1) => new THREE.MeshStandardMaterial({ color: def.colors.second, emissive: def.colors.second, emissiveIntensity: 0.9, roughness: 0.2, transparent: op < 1, opacity: op });
  const add = (geo, mat, x, y, z, rx = 0, ry = 0, rz = 0) => {
    const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.set(rx, ry, rz); m.castShadow = true; g.add(m); return m;
  };
  switch (name) {
    case 'helmet': // baret / kask: tepede kubbe + siper
      add(new THREE.SphereGeometry(0.0148, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), second, 0, HEAD.top - 0.0045, 0.001);
      add(new THREE.CylinderGeometry(0.0172, 0.0172, 0.0013, 28), second, 0, HEAD.top - 0.0045, 0.0025);
      break;
    case 'headlamp': // baretin önünde parlayan lamba
      add(new THREE.CylinderGeometry(0.003, 0.003, 0.003, 16), dark, 0, HEAD.top + 0.002, 0.0145, Math.PI / 2, 0, 0);
      add(new THREE.CylinderGeometry(0.0024, 0.0024, 0.0008, 16), new THREE.MeshStandardMaterial({ color: '#fff6cf', emissive: '#fff2a8', emissiveIntensity: 1.6 }),
        0, HEAD.top + 0.002, 0.0162, Math.PI / 2, 0, 0);
      break;
    case 'propeller': // pervaneli bere
      add(new THREE.SphereGeometry(0.0105, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2), second, 0, HEAD.top - 0.002, 0);
      add(new THREE.CylinderGeometry(0.0007, 0.0007, 0.006, 8), dark, 0, HEAD.top + 0.0095, 0);
      for (const r of [0, Math.PI]) {
        const bl = add(new THREE.BoxGeometry(0.011, 0.0008, 0.0032), new THREE.MeshStandardMaterial({ color: '#ff8c2e', roughness: 0.5 }), 0, HEAD.top + 0.0125, 0, 0, r, 0.18);
        bl.geometry.translate(0.0055, 0, 0);
      }
      add(new THREE.SphereGeometry(0.0013, 10, 8), dark, 0, HEAD.top + 0.0128, 0);
      break;
    case 'visor': // göz hizasında yarı saydam ışıklı bant
      add(new THREE.BoxGeometry(0.03, 0.0075, 0.0015), glow(0.55), 0, HEAD.mid, HEAD.front + 0.004);
      break;
    case 'twinAntenna':
      for (const x of [-1, 1]) {
        add(new THREE.CylinderGeometry(0.0008, 0.0008, 0.013, 8), dark, x * 0.008, HEAD.top + 0.004, 0, 0, 0, -x * 0.35);
        add(new THREE.SphereGeometry(0.0022, 12, 8), glow(), x * 0.0105, HEAD.top + 0.0098, 0);
      }
      break;
    case 'antenna':
      add(new THREE.CylinderGeometry(0.0009, 0.0009, 0.02, 8), dark, 0, HEAD.top + 0.0085, 0);
      add(new THREE.SphereGeometry(0.0032, 14, 10), glow(), 0, HEAD.top + 0.019, 0);
      break;
    case 'headphones': // kafanın üstünden geçen bant + kulaklar
      add(new THREE.TorusGeometry(0.0158, 0.0016, 8, 28, Math.PI), dark, 0, HEAD.mid, 0);
      for (const x of [-1, 1]) add(new THREE.CylinderGeometry(0.0062, 0.0062, 0.005, 20), second, x * (HEAD.half + 0.002), HEAD.mid, 0, 0, 0, Math.PI / 2);
      break;
    case 'monoVisor': // iki gözün önünde tek, iri, kırmızı göz
      add(new THREE.CylinderGeometry(0.0068, 0.0068, 0.002, 24), glow(), 0, HEAD.mid, HEAD.front + 0.0045, Math.PI / 2, 0, 0);
      add(new THREE.BoxGeometry(0.03, 0.0035, 0.0015), dark, 0, HEAD.mid, HEAD.front + 0.0035);
      break;
  }
  return g;
}

/**
 * Hazır robot kostümü: RobotExpressive'in bir kopyasını renk, malzeme, kemik oranı ve takılarla giydirir.
 * Dönen `kind` her robot için `instantiate` ile klonlanır.
 */
// GLTFLoader aynı adlı düğümleri tekilleştirir ("Torso" kemiği "Torso_1" olabilir): sondaki _N'yi at.
const baseName = (n) => n.replace(/_\d+$/, '');

export function builtinKind(def, base) {
  const tpl = SkeletonUtils.clone(base.scene);
  tpl.traverse((o) => {
    if (o.isBone && def.bones[baseName(o.name)]) o.scale.multiplyScalar(def.bones[baseName(o.name)]);
    if (!o.isMesh) return;
    o.castShadow = true; o.receiveShadow = true;
    const mats = (Array.isArray(o.material) ? o.material : [o.material]).map((m) => {
      const c = m.clone();
      if (m.name === 'Main') c.color.set(def.colors.main);
      if (def.colors.joint && m.name === 'Grey') c.color.set(def.colors.joint);
      if (c.isMeshStandardMaterial && m.name !== 'Black') { c.metalness = def.material.metalness; c.roughness = def.material.roughness; }
      return c;
    });
    o.material = Array.isArray(o.material) ? mats : mats[0];
  });
  let head = null;
  tpl.traverse((o) => { if (!head && o.isBone && baseName(o.name) === 'Head') head = o; });
  if (head) for (const a of def.accessories) head.add(accessory(a, def));
  const bb = measure(tpl, base.clips, 'Idle');
  return { id: def.id, builtin: true, def, template: tpl, clips: base.clips, H: bb.max.y - bb.min.y, offset: new THREE.Vector3(), flipped: false };
}

/** Kendi .glb robotu: sınır kutusuyla ortalanır, ayakları zemine oturtulur. */
export function customKind(id, gltf, flipped) {
  const tpl = gltf.scene;
  tpl.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  const clips = gltf.animations || [];
  const names = matchClips(clips.map((c) => c.name));
  const bb = measure(tpl, clips, names.idle);
  const H = Math.max(bb.max.y - bb.min.y, 1e-6);
  const c = bb.getCenter(new THREE.Vector3());
  return { id, builtin: false, template: tpl, clips, H, offset: new THREE.Vector3(-c.x, -bb.min.y, -c.z), flipped };
}

/**
 * Bir robot örneği: `root` sahneye eklenir (ölçek 1 = boy `height`), `inner` yedek hareketlerin oynattığı katman.
 * `actions[motion]` klip yoksa null.
 */
export function instantiate(kind, height) {
  const model = SkeletonUtils.clone(kind.template);
  model.traverse((o) => {
    if (!o.isMesh) return;
    o.material = Array.isArray(o.material) ? o.material.map((m) => m.clone()) : o.material.clone();
  });
  const inner = new THREE.Group(); inner.add(model);
  model.position.copy(kind.offset);
  if (kind.flipped) inner.rotation.y = Math.PI;
  const k = height / kind.H;
  const fit = new THREE.Group(); fit.scale.setScalar(k); fit.add(inner);
  const root = new THREE.Group(); root.add(fit);
  const mixer = new THREE.AnimationMixer(model);
  const names = matchClips(kind.clips.map((c) => c.name));
  const actions = {};
  for (const [motion, name] of Object.entries(names)) {
    const clip = name && kind.clips.find((c) => c.name === name);
    actions[motion] = clip ? mixer.clipAction(clip) : null;
  }
  return { root, inner, mixer, actions, kind };
}

/** Klibi olmayan hareketler için modelin kendisini oynatır. `h` iç katman biriminde boy. */
export function fallbackPose(inner, motion, t, h) {
  inner.position.set(0, 0, 0); inner.rotation.x = 0; inner.rotation.z = 0; inner.scale.set(1, 1, 1);
  switch (motion) {
    case 'idle': inner.scale.y = 1 + 0.02 * Math.sin(t * 2.2); break;
    case 'walk': inner.position.y = Math.abs(Math.sin(t * 9)) * 0.06 * h; inner.rotation.z = 0.08 * Math.sin(t * 9); break;
    case 'wave': inner.rotation.z = 0.15 * Math.sin(t * 6); break;
    case 'sit': inner.position.y = -0.35 * h * Math.min(1, t * 3); break;
    case 'yes': case 'thumbs': inner.rotation.x = 0.25 * Math.max(0, Math.sin(t * 7)); break;
    case 'work': inner.position.y = Math.max(0, Math.sin(t * 12)) * 0.05 * h; break;
  }
}
