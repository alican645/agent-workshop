# Claude seçenek menüsü fikstürleri

Gerçek Claude Code **2.1.327** ekranları (120×40, `tui: fullscreen`, model Haiku, `--permission-mode default`;
plan için `--permission-mode plan`). `swift run prompt-capture` ile geçici bir git klasöründe yakalandı;
stdin yönergeleri (`@wait`, `@key`, `@text`, `@snap`) ile sürüldü. Her `X.txt` görünen satırlardır,
`X.txt.registry.json` aynı anda o sürecin `sessions/<pid>.json` kaydı.

Kişisel veri temizliği: kullanıcı adı aynı uzunlukta `exampleuser` ile değiştirildi (satır kırılmaları
bozulmasın diye), profil klasörü `~/.claude/` yazıldı. E-posta ekranda yoktu.

| Dosya | Ne | Ayrıştırıcı |
|---|---|---|
| `bash-permission.txt` | "Run `touch out.txt` with the Bash tool" — 4 seçenek, 2. seçenek iki satıra kırılmış | permission |
| `bash-permission-down.txt` | aynısı, bir kez ↓ basılmış | permission, selected 1 |
| `bash-permission-dont-ask.txt` | `git add notes.txt` — "Yes, and don’t ask again for: git add *" | permission |
| `edit-permission.txt` | Edit ile notes.txt düzenleme (diff satırları `1  hello` numaralı ama noktasız) | permission |
| `read-outside-permission.txt` | çalışma klasörü dışını okuma izni (kendiliğinden çıktı) | permission |
| `ask-single.txt` | AskUserQuestion, tek soru, tek seçim | question |
| `ask-single-typed.txt` | aynısı; "Type something." satırına gidilip `hello` yazılmış | question, freeText etiketi `hello` |
| `ask-multi.txt` | tek soru, multiSelect | question, multi |
| `ask-multi-checked.txt` | Boşluk ile 1., ↓↓ Enter ile 3. işaretlenmiş; ❯ 3.'te | question, checked |
| `ask-multi-submit-row.txt` | ❯ numarasız "Submit" satırında | nil |
| `ask-pages.txt` | tek çağrıda 3 soru, ilk sayfa | question, page 0/3 |
| `ask-pages-q2.txt` | 1. soru serbest metinle cevaplanmış, 2. sayfa | question, page 1/3 |
| `ask-pages-review.txt` | son "Review your answers" sayfası (alt ipucu satırı yok) | nil |
| `plan-approval.txt` | ExitPlanMode onayı; plan gövdesinde de `1.` `2.` satırları var | plan |
| `idle-input.txt` | menü yok, boş giriş kutusu | nil |
| `partial.txt` | **elle**: `bash-permission.txt`'in 23. satırdan sonrası silinmiş (yarım çizim) | nil |
| `stale-above-input.txt` | **elle**: `bash-permission.txt` menüsü `idle-input.txt` giriş kutusunun üstüne konmuş | nil |

Not: tam ekran arayüzde cevaplanan menü ekrandan kalkar ("Answered Claude's questions…" özeti kalır);
gerçek bir "eski menü + giriş kutusu" ekranı oluşmadı, o yüzden `stale-above-input.txt` elle yapıldı.

## Bulgular (2.1.327)

**Kayıt durumu:** `ask-*.registry.json` ve `plan-approval.registry.json` içinde `status == "waiting"` —
AskUserQuestion ve ExitPlanMode beklerken de kayıt `waiting` yazıyor (izinlerde olduğu gibi). İkinci
tetik (sohbet kaydına bakma) gerekmez; tek tetik `waiting` yeter.

**İzin menüsü:** artık 3 değil 4 seçenek: `1. Yes`, `2. Yes, and …` (bağlama göre: "don’t ask again for: git add *",
"always allow access to <klasör> from this project", "allow reading from … during this session",
Edit'te "switch to accept edits …"), `3. Yes, and switch to auto mode …` (Edit/Read'de yok), son `No`.
"No, and tell Claude what to do differently" seçeneği **yok**; serbest metin izinlerde `Tab to amend`
ile (alt satır: `Esc to cancel · Tab to amend`) — bu yüzden izin menüsünde `freeText` seçenek yoktur.
Kesme işareti düz değil: `don’t` (U+2019).

**Tek seçimli soru (tek soru):** ↑/↓ ile git, **Enter seçer ve hemen gönderir** (inceleme sayfası yok).
Çok sorulu çağrıda tek seçimli sayfada Enter o soruyu cevaplar ve **sonraki sayfaya geçer**.

**Serbest metin ("Type something."):** imleç o satıra gelince yazılan harfler doğrudan satıra yazılır
(`❯ 4. hello` — etiket yazılan metin olur, ayrı kutu açılmaz). Tek seçimde ardından **Enter** gönderir
(`ask-pages-q2.txt`: `teal` + Enter → 1. soru `teal` diye cevaplandı, 2. sayfaya geçti). Yani dizi:
`↓…` (hedefe) + metin + `\r`. Çoklu seçimde metin yazmak o satırı **kendiliğinden işaretler** (`[✔] kiwi`).
Serbest metin satırının ardından bir `────` çizgisi ve `N. Chat about this` gelir (sohbete dönüş; serbest metin değil).

**Çoklu seçim (multiSelect):** satırlar `N. [ ] Etiket` / `N. [✔] Etiket`. **Boşluk da Enter da** imlecin
olduğu satırı işaretler/kaldırır (imleç yerinde kalır, gönderilmez). "Type something" satırının hemen altında
numarasız `     Submit` satırı var (imleç oradayken `❯    Submit`). Gönderme:
son numaralı serbest metin satırından bir ↓ ile `Submit` satırına git → Enter → "Review your answers"
sayfası (`❯ 1. Submit answers` / `2. Cancel`, imleç 1'de) → **Enter** gönderir. Tek sorulu çoklu seçimde de
bu inceleme sayfası çıkar (`←  ☐ Fruits  ✔ Submit  →` şeridi). Tab ve → "Chat about this" üzerindeyken
hiçbir şey yapmadı. Doğrulanmış tam dizi (tek soru, 1. seçeneği işaretle, gönder):
`" "` (Boşluk) + `ESC[B` ×4 (Apple→Banana→Cherry→Type something→Submit) + `\r` + `\r`.

**Sayfalar (çok sorulu):** üstte sekme şeridi `←  ☐ Color  ☐ Size  ☐ Fruits  ✔ Submit  →`; `☐` cevapsız,
`☒` cevaplı. Hangi sekmenin açık olduğu yalnız renkle belli (metinde yok); ayrıştırıcı açık sayfayı
**ilk `☐`** sayar (kullanıcı ← ile geri dönmediyse doğru). Tek sorulu tek seçimde şerit yalnız ` ☐ Color`.

**Plan onayı:** başlık `Claude has written up a plan and is ready to execute. Would you like to proceed?`,
seçenekler `1. Yes, and use auto mode`, `2. Yes, manually approve edits`, `3. Tell Claude what to change`
(altında açıklama `shift+tab to approve with this feedback`); alt satır `ctrl+g to edit in Vim · <plan dosyası>`.

**Menü çevresi:** menü açıkken giriş kutusu ekrandan kalkar; menünün altında yalnız ipucu satırı
(`Esc to cancel …` / `Enter to select …` / `ctrl+g to edit in Vim …`) ve boş satırlar olur. Kelimeler imleç
atlamasıyla yerleştirildiği için yazılmamış hücreler `ScreenMirror`'da boşluğa çevrilir.
