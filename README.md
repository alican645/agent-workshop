# Atölye

**Claude Code oturumlarını bir robot atölyesi olarak gösteren, terminalleri de içinde barındıran macOS uygulaması.**

Her Claude Code oturumu atölyede bir robottur. Robotlar projelerine göre bölgelere ayrılır; çalışırken
tezgâhta iş yapar, seni beklerken el sallar, işi bitince dinlenir. Terminaller atölyenin üstünde yüzen
pencerelerdir: sürükle, büyüt, kenara yapıştır, sahneye dokununca hepsi animasyonla sol paneldeki
projelerine çekilir. Birden çok Claude hesabını, hangisini kullandığını fark etmeden aynı skill'ler,
MCP'ler ve hafızayla kullanırsın.

> *A macOS app that turns your Claude Code sessions into a 3D robot workshop — with built-in floating
> terminals, git status, token/cost tracking and seamless multi-account support. UI is in Turkish.*

---

## Neler yapıyor?

### 🤖 Robot atölyesi
- Açık her Claude Code oturumu bir robot; projelere (git köküne) göre bölgelere yerleşir.
- Durumlar anında görünür: **çalışıyor** (hangi aracı kullandığıyla), **seni bekliyor** (neyi beklediğiyle),
  **bitti**, **boşta**. Yardımcı ajanlar (subagent) robotun yanında küçük yardımcılar olarak çıkar.
- Bölge panelinde son araç çağrıları, açık `TODO.local.md` maddeleri ve git durumu.
- Akış: commit, push, pull ve dal değişikliği olayları sahnede ve olay akışında görünür.

### 🪟 Yüzen terminal pencereleri
- Terminaller uygulamanın içinde, atölyenin üstünde: sürükle, kenarlardan/köşelerden boyutlandır,
  ekranın kenarına ya da köşesine sürükleyince yarım/çeyrek ekrana yapışır, çift tıkla tam ekran.
- Sahneye tıklayınca pencereler sol paneldeki kendi projelerine animasyonla çekilir; projeye tıklayınca geri gelir.
- Aynı projede istediğin kadar Claude oturumu, kabuk, salt okunur **Git** görünümü (değişen dosyalar,
  commit'ler, diff) ve **Markdown** okuyucu.
- Terminaller ayrı bir yardımcı süreçte (`atolye-host`) yaşar: Atölye'yi kapatıp açsan da oturumların sürer.

### 🔔 Seni bekleyen ajanı kaçırma
- Bekleyen Claude'un penceresi ve sol paneldeki etiketi yanıp söner, sesli uyarı çalar.
- Atölye arka plandayken macOS bildirimi; bildirime tıklayınca doğrudan o terminale gidersin.
- Dock simgesinde bekleyen ajan sayısı.

### 💰 Token ve maliyet
- Her oturumun kullandığı token ve Anthropic API liste fiyatıyla karşılığı (yardımcı ajanlar dahil).
- Üst çubukta günün toplamı — kapanmış oturumlar ve bütün hesaplar dahil.
- Abonelikle kullananlar için bu bir fatura değil; hangi oturumun ne kadar iş yaptığını karşılaştırmak içindir.

### 👥 Birden çok Claude hesabı, tek çalışma ortamı
- Profiller (`Profil 1`, `Profil 2`, …) üst çubuktaki menüden yönetilir; yeni Claude oturumları seçili
  profille açılır, istersen tek pencereyi başka profille açarsın.
- Bütün profiller **aynı** skill'leri, plugin'leri, ayarları, hafızayı, komut geçmişini ve dosya geçmişini kullanır.
- MCP sunucuları ve proje izinleri profiller arasında otomatik eşitlenir: bir hesapta eklediğin MCP
  diğerinde de olur. Hesabın kimlik bilgilerine dokunulmaz.
- Her profilin 5 saatlik ve haftalık limiti görünür; %90'ı geçince Atölye uyarır.
- Profile beklenen hesabı yazarsan, yanlış hesapla girişliyse uyarır; "Giriş yap" giriş sayfasını o e-postayla açar.

---

## Kurulum

**Gerekenler:** macOS 26, Xcode 26 (Swift 6.2), [Claude Code](https://claude.com/claude-code), `jq`
(limit göstergesi için, `brew install jq`).

```sh
git clone <bu-repo>
cd AjanTakip
./scripts/build-atolye.sh --install   # build/Atölye.app oluşturur ve ~/Applications'a kopyalar
open ~/Applications/Atölye.app
```

Testler:

```sh
swift test
```

## Kısayollar

| Kısayol | İş |
|---|---|
| ⌘⇧T | Öndeki projede yeni Claude oturumu |
| ⌘T | Yeni terminal |
| ⌘W | Pencereyi kapat (çalışan bir şey varsa sorar) |
| ⌘M | Pencereyi projesine çek |
| ⌘1 … ⌘9 | N'inci pencereyi öne getir |
| ⌘\` · ⌘[ · ⌘] | Pencereler arasında dolaş |

## Nasıl çalışıyor?

Atölye hiçbir yere veri göndermez; her şeyi Claude Code'un kendi yerel dosyalarından okur.

- **Oturum durumu:** Claude Code'un oturum kayıtları (`<profil>/sessions/<pid>.json`) saniyede bir taranır.
- **Ne yapıyor:** sohbet kayıtlarının (`projects/**/*.jsonl`) sonu artımlı okunur; araç çağrıları, yardımcı
  ajanlar ve token kullanımı buradan çıkar.
- **Git:** `git` komut satırı, kilit almadan (`--no-optional-locks`) ve salt okunur.
- **Limitler:** Claude Code'un durum satırı betiğine eklenen küçük bir blok, `rate_limits` bilgisini profil
  başına bir dosyaya yazar.

Atölye'nin bilgisayarında değiştirdikleri (değişen her dosyanın aslı önce
`~/Library/Application Support/Atolye/yedek/` altına kopyalanır):

- `~/.claude/statusline-command.sh` sonuna limit bloğu.
- Ek profillerde ortak öğeler için ana `~/.claude` klasörüne sembolik bağlar.
- Profillerin `.claude.json` dosyalarında yalnız MCP ve proje izni alanları (üç yollu birleştirme;
  Claude dosyayı o an yazıyorsa o tur atlanır).

## Proje yapısı

| Hedef | Ne |
|---|---|
| `Atolye` | SwiftUI uygulaması; sahne `WKWebView` içinde three.js ile çizilir (`Sources/Atolye/Web`) |
| `atolye-host` | Terminalleri barındıran arka plan yardımcısı (Unix soketi üzerinden) |
| `AtolyeHostKit` | Yardımcının sunucu/istemci kodu, [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) ile |
| `AjanTakipCore` | Arayüzden bağımsız çekirdek: oturum tarama, git, kullanım/maliyet, profiller, eşitleme |
| `AjanTakip` | Projenin ilk hâli olan menü çubuğu uygulaması (artık kullanılmıyor) |

Tasarım notları ve uygulama planları `docs/superpowers/` altında.

## Teşekkürler

- [three.js](https://threejs.org) (MIT) ve robot modeli *RobotExpressive* — Tomás Laulhé, düzenleme
  Don McCurdy (CC0).
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT), [marked](https://marked.js.org) (MIT).
- Bazı fikirler (token/maliyet takibi gibi) Orbiterm'den esinlendi; kod paylaşılmadı.
