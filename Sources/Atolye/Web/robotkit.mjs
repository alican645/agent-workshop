// Robotları kuran three.js kodu: hazır ve kendi .glb robotlarını normalleştirir, her robot için klon + animasyon hazırlar ve eksik animasyonlara yedek hareket verir.
import * as THREE from 'three';
import * as SkeletonUtils from 'three/addons/utils/SkeletonUtils.js';
import { matchClips } from './robots.mjs';
import { t } from './i18n.mjs';

/** Modeli Idle'ın ilk karesinde ölçer (animasyon iskeleti başka bir duruşa sokabiliyor); Idle yoksa duruş olduğu gibi. */
function measure(root, clips, idleName) {
  const mixer = new THREE.AnimationMixer(root);
  const clip = idleName ? clips.find((c) => c.name === idleName) : null;
  if (clip) { mixer.clipAction(clip).play(); mixer.update(0); }
  root.updateMatrixWorld(true);
  const bb = new THREE.Box3().setFromObject(root);
  mixer.stopAllAction(); mixer.uncacheRoot(root);
  return bb;
}

/**
 * Bir robot modeli (hazır ya da kendi .glb'si): sınır kutusuyla ortalanır, ayakları zemine oturtulur.
 * opts.hide: gizlenecek parça adları (ör. android'in kılıcı); opts.clips: elle seçilen klipler.
 */
export function modelKind(id, gltf, { flipped = false, hide = [], clips: overrides = {}, builtin = false } = {}) {
  const tpl = gltf.scene;
  tpl.traverse((o) => {
    if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; }
  });
  for (const n of hide) { const o = tpl.getObjectByName(n); if (o) o.removeFromParent(); }
  const clips = gltf.animations || [];
  const names = matchClips(clips.map((c) => c.name), overrides);
  const bb = measure(tpl, clips, names.idle);
  const H = bb.max.y - bb.min.y;
  if (bb.isEmpty() || !Number.isFinite(H) || H < 1e-6) throw new Error(t('modelde görünür parça yok'));
  const c = bb.getCenter(new THREE.Vector3());
  return { id, builtin, template: tpl, clips, names, H, offset: new THREE.Vector3(-c.x, -bb.min.y, -c.z), flipped };
}

/** Kendi .glb robotu. */
export const customKind = (id, gltf, flipped) => modelKind(id, gltf, { flipped });

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
  const actions = {};
  for (const [motion, name] of Object.entries(kind.names)) {
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
    case 'sit': { const k = Math.min(1, t * 3); inner.scale.y = 1 - 0.18 * k; inner.scale.x = inner.scale.z = 1 + 0.06 * k; break; } // çömel, zemine gömülme
    case 'yes': case 'thumbs': inner.rotation.x = 0.25 * Math.max(0, Math.sin(t * 7)); break;
    case 'work': inner.position.y = Math.max(0, Math.sin(t * 12)) * 0.05 * h; break;
  }
}
