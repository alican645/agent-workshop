// Platform balonu: bekleyen ajanların seçenek menüleri (saf; DOM'a dokunmaz, node:test ile sınanır).
// Snapshot alanları Swift'teki PromptInfo ile sözleşme; isteğe bağlı alanlar yoksa hiç gelmez.

/** Ayrıntı (komut, dosya yolu…) balonda en fazla bu kadar karakter; tamamı `title` içinde. */
export const DETAIL_MAX = 160;

/** Serbest metin satırının henüz yazılmamış hâli (Swift: PromptParser.freeTextPrefixes). */
export const FREE_TEXT_PREFIXES = ['Type something', 'Tell Claude what to change', 'No, and tell Claude'];

/** Serbest metin seçeneği boş mu (yazı kutusu açılabilir)? Terminalde önceden yazılmışsa Swift yeni metni reddeder. */
export function isPlaceholder(o) {
  return !!o?.freeText && FREE_TEXT_PREFIXES.some((p) => String(o.label).startsWith(p));
}

/** Bölgede menüsü olan robotlar, snapshot sırasıyla. */
export function waitingPrompts(zone) {
  return (zone?.robots || []).filter((r) => r.prompt).map((r) => ({
    robot: r.id, label: r.label, color: zone.color, prompt: r.prompt, terminal: r.terminal,
  }));
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
    const dis = off || p.sent || !!pending?.has(it.robot) ? ' disabled' : '';
    const mine = checks?.get(it.robot) ?? new Set(initialChecks(p));
    const editing = edit?.get(it.robot);
    const pages = Number.isInteger(p.page) && p.pages > 1 ? `<span class="pg">${p.page + 1}/${p.pages}</span>` : '';
    let h = `<div class="${off ? 'pq off' : 'pq'}" data-robot="${esc(it.robot)}"${focus === it.robot ? ' data-focus="1"' : ''}>` +
      `<div class="ph"><span class="d" style="background:${esc(it.color)}"></span><span class="pn">${esc(it.label)}</span>${pages}</div>` +
      `<div class="pt">${esc(title(p, t))}</div>`;
    if (p.detail && !compact) h += `<div class="pd" title="${esc(p.detail)}">${esc(clip(p.detail, DETAIL_MAX))}</div>`;
    opts.forEach((o, i) => {
      const box = p.multi ? (mine.has(i) ? '☑ ' : '☐ ') : '';
      const desc = o.description && !compact ? `<span class="pds">${esc(o.description)}</span>` : '';
      h += `<button class="po" data-i="${i}"${dis}><span class="pk">[${i + 1}]</span> ${box}${esc(o.label)}${desc}</button>`;
      if (editing === i && !dis) {
        h += `<div class="pin"><input data-i="${i}" placeholder="${esc(t('cevabını yaz…'))}">` +
          (p.multi ? '' : `<button class="psend" data-act="send">${t('Gönder')}</button>`) + `</div>`;
      }
    });
    if (p.multi && opts.length) h += `<button class="psend" data-act="send"${dis}>${t('Gönder')}</button>`;
    if (p.planPath) h += `<a class="pl" data-act="plan">📄 ${t('Planı aç')}</a>`;
    const term = (text) => (it.terminal ? `<a data-act="term" data-term="${esc(it.terminal)}">${text}</a>` : text);
    if (p.sent) h += `<div class="ps">${t('gönderildi…')}</div>`;
    else if (p.failed) h += `<div class="ps err">${term(t('gitmedi — terminali aç'))}</div>`;
    else if (off) h += `<div class="pnote">${t('terminalinden cevapla')}${it.terminal ? ' · ' + term(t('terminali aç')) : ''}</div>`;
    return h + `</div>`;
  }).join('');
}

/**
 * Swift'e gidecek cevap (katı çözümleyici: yanlış tipli alan bütün mesajı düşürür, bu yüzden boş alan hiç yazılmaz).
 * Tek seçimde `option`, çoklu seçimde istenen işaretlerin tamamı `checks`; `text` yalnız yazı kutusundan.
 */
export function answerMessage(robotId, prompt, { option, checks, text } = {}) {
  const m = { type: 'answer', robot: String(robotId), labels: (prompt.options || []).map((o) => o.label) };
  if (prompt.multi) m.checks = [...new Set(checks || [])].filter(Number.isInteger).sort((a, b) => a - b);
  else if (Number.isInteger(option)) m.option = option;
  if (typeof text === 'string' && text !== '') m.text = text;
  return m;
}
