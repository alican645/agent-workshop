// Platform balonu: bekleyen ajanların seçenek menüleri (saf; DOM'a dokunmaz, node:test ile sınanır).
// Snapshot alanları Swift'teki PromptInfo ile sözleşme; isteğe bağlı alanlar yoksa hiç gelmez.

/** Ayrıntı (komut, dosya yolu…) balonda en fazla bu kadar karakter; tamamı `title` içinde. */
export const DETAIL_MAX = 160;
/** Küçük görünümde izin ayrıntısı (komut) bu kadar karakter: "Yes" görülmemiş bir komutu onaylamasın. */
export const DETAIL_COMPACT = 60;

/** Serbest metin satırının henüz yazılmamış hâli (Swift: PromptParser.freeTextPrefixes). */
export const FREE_TEXT_PREFIXES = ['Type something', 'Tell Claude what to change', 'No, and tell Claude'];

/**
 * Serbest metin seçeneği boş mu (yazı kutusu açılabilir)? Terminalde önceden yazılmışsa Swift yeni metni reddeder.
 * Yalnız sorularda (`kind === 'question'`): plan onayının "Tell Claude what to change"i ve izinlerin serbest satırı
 * sıradan seçenektir — tıklayınca seçilip Enter'lanır, yazma terminalde sürer (Swift o menülere metin göndermez).
 */
export function isPlaceholder(o, kind) {
  return kind === 'question' && !!o?.freeText && FREE_TEXT_PREFIXES.some((p) => String(o.label).startsWith(p));
}

/** Çoklu seçimde satır işaretlenebilir mi: yalnız kutulu satırlar (kutusuz "Chat about this" değil). */
export function isCheckable(prompt, i) {
  const o = prompt?.multi ? (prompt.options || [])[i] : null;
  return !!o && o.checked != null;
}

/** Bölgede menüsü olan robotlar, snapshot sırasıyla. */
export function waitingPrompts(zone) {
  return (zone?.robots || []).filter((r) => r.prompt).map((r) => ({
    robot: r.id, label: r.label, color: zone.color, prompt: r.prompt, terminal: r.terminal,
  }));
}

/**
 * Menünün kimliği: gönderim durumu (sent/failed) dışında her şey. Ardışık iki Bash izni aynı soru ve
 * etiketleri taşıyabilir; ayrıntı (komut) da anahtarda, yoksa yeni izin eskisinin yerel durumunu devralırdı.
 */
export function menuKey(p) {
  return JSON.stringify([p.menuId ?? null, p.kind, p.question, p.detail ?? null, p.multi, p.page ?? null, p.planPath ?? null,
    (p.options || []).map((o) => [o.label, o.description ?? null, !!o.freeText])]);
}

/** Klavye odağı, menüsü değişen (ya da yeni gelen) robottaysa düşer: rakam görülmemiş menüyü cevaplamasın. */
export function dropFocus(focus, changed) {
  return focus && changed.has(focus.robot) ? null : focus;
}

/** Çoklu seçimde snapshot'taki işaretli satırlar (yerel seçim yoksa başlangıç). */
export function initialChecks(prompt) {
  return (prompt.options || []).flatMap((o, i) => (o.checked ? [i] : []));
}

/** Cevap verilemeyen balon: terminal Atölye dışında ya da (oturum dışı plan gibi) seçenek okunamadı. */
export function isOff(prompt) {
  return !prompt.answerable || !(prompt.options || []).length;
}

function title(p, t) {
  if (p.question) return p.question;
  if (p.kind === 'question') return t('Soru soruyor');
  if (p.kind === 'plan') return t('Plan onayı bekliyor');
  return t('İzin bekliyor');
}

const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s);

/**
 * Bölgenin balon içeriği. `pending`: tıklanıp snapshot'ı beklenen robotlar (Set); `checks`: robot → yerel
 * işaret kümesi (Map<id, Set>); `edit`: robot → yazı kutusu açık seçenek (Map<id, index>); `focus`: klavye odağı.
 */
export function balloonHtml(items, { t, esc, compact = false, pending, checks, edit, focus } = {}) {
  return items.map((it) => {
    const p = it.prompt, opts = p.options || [];
    const off = isOff(p);
    // Gitmedi sayılan menüye yeniden deneme yok (Swift de göndermez); "terminali aç" açık kalır.
    const dis = off || p.sent || p.failed || !!pending?.has(it.robot) ? ' disabled' : '';
    const mine = checks?.get(it.robot) ?? new Set(initialChecks(p));
    const editing = edit?.get(it.robot);
    const pages = Number.isInteger(p.page) && p.pages > 1 ? `<span class="pg">${p.page + 1}/${p.pages}</span>` : '';
    let h = `<div class="${off ? 'pq off' : 'pq'}" data-robot="${esc(it.robot)}"${focus === it.robot ? ' data-focus="1"' : ''}>` +
      `<div class="ph"><span class="d" style="background:${esc(it.color)}"></span><span class="pn">${esc(it.label)}</span>${pages}</div>` +
      `<div class="pt">${esc(title(p, t))}</div>`;
    // Küçük görünümde de izin ayrıntısı kısaltılarak gösterilir (tamamı `title` içinde).
    const max = compact ? (p.kind === 'permission' ? DETAIL_COMPACT : 0) : DETAIL_MAX;
    if (p.detail && max) h += `<div class="pd" title="${esc(p.detail)}">${esc(clip(p.detail, max))}</div>`;
    opts.forEach((o, i) => {
      // Çoklu seçimde kutusuz satır ("Chat about this") kutusuz ve kapalı: Swift onu işaretlemez.
      const box = p.multi && isCheckable(p, i) ? (mine.has(i) ? '☑ ' : '☐ ') : '';
      const odis = dis || (p.multi && !isCheckable(p, i) ? ' disabled' : '');
      const desc = o.description && !compact ? `<span class="pds">${esc(o.description)}</span>` : '';
      h += `<button class="po" data-i="${i}"${odis}><span class="pk">[${i + 1}]</span> ${box}${esc(o.label)}${desc}</button>`;
      if (editing === i && !dis) {
        h += `<div class="pin"><input data-i="${i}" placeholder="${esc(t('cevabını yaz…'))}">` +
          (p.multi ? '' : `<button class="psend" data-act="send">${t('Gönder')}</button>`) + `</div>`;
      }
    });
    if (p.multi && opts.length) h += `<button class="psend" data-act="send"${dis}>${t('Gönder')}</button>`;
    if (p.planPath) h += `<a class="pl" data-act="plan">📄 ${t('Planı aç')}</a>`;
    const term = (text) => (it.terminal ? `<a data-act="term" data-term="${esc(it.terminal)}">${text}</a>` : text);
    if (p.failed) h += `<div class="ps err">${term(t('gitmedi — terminali aç'))}</div>`;
    else if (p.sent) h += `<div class="ps">${t('gönderildi…')}</div>`;
    else if (off) h += `<div class="pnote">${t('terminalinden cevapla')}${it.terminal ? ' · ' + term(t('terminali aç')) : ''}</div>`;
    return h + `</div>`;
  }).join('');
}

/**
 * Swift'e gidecek cevap (katı çözümleyici: yanlış tipli alan bütün mesajı düşürür, bu yüzden boş alan hiç yazılmaz).
 * Tek seçimde `option`, çoklu seçimde istenen işaretlerin tamamı `checks` (yalnız kutulu satırlar);
 * `text` yalnız yazı kutusundan.
 */
export function answerMessage(robotId, prompt, { option, checks, text } = {}) {
  const m = { type: 'answer', robot: String(robotId), labels: (prompt.options || []).map((o) => o.label) };
  // Menü kimliği (Swift'te zorunlu): tazelenen ekranınkiyle tutmazsa hiçbir şey gönderilmez.
  if (typeof prompt.menuId === 'string') m.menuId = prompt.menuId;
  if (prompt.multi) m.checks = [...new Set(checks || [])].filter((i) => Number.isInteger(i) && isCheckable(prompt, i)).sort((a, b) => a - b);
  else if (Number.isInteger(option)) m.option = option;
  if (typeof text === 'string' && text !== '') m.text = text;
  return m;
}
