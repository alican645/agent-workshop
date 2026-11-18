// Sahnenin dil desteği. Uygulama İngilizce seçiliyse `window.I18N` sözlüğünü (i18n/en.json) verir;
// anahtar Türkçe metindir, `{0}`, `{1}`… argümanlarla doldurulur.
export function makeT(table) {
  return (key, ...args) => {
    let s = (table && table[key]) ?? key;
    args.forEach((a, i) => { s = s.split(`{${i}}`).join(String(a)); });
    return s;
  };
}

export const t = makeT(globalThis.I18N);
export const LOCALE = globalThis.LANG === 'en' ? 'en-US' : 'tr-TR';
