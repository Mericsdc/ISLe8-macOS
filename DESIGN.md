# ISLe8: MacBook için Dynamic Island (Tasarım Planı)

> Hedef: notchy.dev, Droppy, Liqoria ve componest'teki fikirlerin en iyilerini birleştiren,
> boştayken neredeyse sıfır CPU harcayan, tamamen özelleştirilebilir, native bir macOS uygulaması.
> Alınan kararlar için bkz. [§10 Kararlar](#10-kararlar).

---

## 0. Referanslardan çıkanlar

| Kaynak | Alınacak fikir |
|---|---|
| **notchy.dev** (Notchy) | Sekmeli genişletilmiş panel; kapalı pill'de birden çok live activity'nin "kaçırılma maliyetine" göre sıralanıp yan yana durması; her özelliğin ayrı ayrı açılıp kapanması ve kapalı özelliğin timer'ının tamamen durması; bildirim aynası (Full Disk Access ile); kilit ekranında şarkı sözü/medya; geliştirici API'si. |
| **Droppy** (X gönderisi) | Adanın altında küçük ikon dock'u (Home / Raf / Medya / Widget); **Agents widget'ı**: Progress görünümü (aktif dosya, satır sayısı) ve Usage görünümü (Claude / Codex / Cursor kalan limit halkaları). |
| **componest ajan durum bileşeni** (X gönderisi) | Tek satırlık pill ("Reading 12 files · 0:07") → genişleyince adım listesi, "Step 4 of 6" ilerleme çubuğu, Pause/Stop; onay gerekince **Approve / Deny** butonları. Yorumlardaki öneri: "onay bekliyor" durumu çözülene kadar sabit kalmalı. |
| **Liqoria** (X gönderisi) | Liquid Glass; kapak görselinin tüm kartı doldurduğu dikey medya kartı; kapaktan türetilen arka plan rengi; Hi-Res Lossless / Dolby Atmos rozetleri. |
| **Senin ekran görüntün** | Üstte segmentli sekme çubuğu + sağda hızlı sistem çipleri (pil %, Odak, kamera, ses, klavye, sabitle, kilitle); Home'da medya + hava + zamanlayıcı + takvim + "Up Next" ızgarası. |

---

## 1. İlkeler (hafiflik önce gelir)

1. **Native:** Swift 6 + SwiftUI (görünüm) + AppKit (pencere). Electron, WebView, arka plan sunucusu yok.
2. **Olay güdümlü:** Her veri kaynağı sistem bildirimi, KVO, FSEvents, IOKit veya CoreAudio callback'i ile beslenir. Tek istisna: pano `changeCount` kontrolü (0,5 sn'de bir tamsayı karşılaştırması).
3. **Kapalı modül = sıfır maliyet:** Kapatılan modülün observer'ı, timer'ı ve alt süreci kalmaz.
4. **Görünmeyen çizilmez:** Ada kapalıyken SwiftUI ağacı minimumda kalır. Animasyon, visualizer ve ilerleme çubuğu yalnızca ekrandayken çalışır.
5. **Her şey ayarlanabilir**, ama kutudan çıktığı haliyle de iyi görünür.

### Performans bütçesi

| Durum | Hedef |
|---|---|
| Boşta (ada kapalı, müzik yok) | CPU < %0,1 |
| Müzik çalıyor, ada kapalı (kulaklar + visualizer) | CPU < %1 |
| Ada açıkken | CPU < %3 (anlık) |
| Bellek | < 80 MB |
| Activity Monitor enerji etkisi | "Düşük" (< 1) |
| Açılma/kapanma animasyonu | 120 Hz'de takılmasız |

Her fazın sonunda `scripts/measure.sh` (`top`/`ps` örnekleme) ve Instruments (Time Profiler + Energy Log) ile ölçülür. Bütçe aşılırsa faz bitmiş sayılmaz.

---

## 2. Ada durumları

```
            hover (150 ms)              tıkla / hover-hold
   idle ─────────────────▶ peek ─────────────────────────▶ expanded
    ▲  ▲                    │  ◀──── mouse çıktı ────────────┘  │
    │  │ aktivite bitti     ▼                                   │
    │  └──────────────── compact ◀── live activity başladı      │
    │                       ▲                                   │
    │   geçici olay (bildirim, HUD, şarj, AirDrop) → alert ─────┘ (N sn sonra önceki duruma döner)
    │
    ├── dosya sürükleniyor + imleç ekranın üstünde → dropTarget
    └── ekran kilitlendi → lockScreen (salt okunur)
```

| Durum | Görünüm |
|---|---|
| `idle` | Notch ile birebir aynı, siyah, görünmez. Notch'suz harici ekranda üst ortada ince bir pill (varsayılan; istenirse gizlenir). |
| `compact` | Aktif bir aktivite varsa notch'un sağına ve soluna "kulaklar" çıkar. Sol kulakta ikon/kapak, sağ kulakta değer (visualizer, süre, %). |
| `peek` | Hover'da hafif büyür, tek satır bilgi gösterir. |
| `expanded` | Sekmeli tam panel. |
| `alert` | Geçici olay: ada aşağı doğru banner boyutuna açılır, sonra geri döner. |
| `dropTarget` | Dosya sürüklenirken: "Rafa bırak" ve "AirDrop" hedefleri. |
| `lockScreen` | Kilit ekranında ayrı, salt okunur görünüm. |

### Compact öncelik sırası (ActivityCenter)

Kulaklarda aynı anda en fazla 2 aktivite görünür, gerisi `+2` rozetiyle gösterilir. Sıralama ayarlardan değiştirilebilir.

1. Ajan onay bekliyor / gelen arama (kritik, çözülene kadar sabit)
2. Zamanlayıcı bitti, pil kritik
3. AirDrop / indirme ilerlemesi
4. Ajan çalışıyor
5. Medya çalıyor
6. Zamanlayıcı/Pomodoro sayıyor
7. Keep Awake, Odak modu vb. sessiz göstergeler

---

## 3. Görsel dil

**Geometri** (notch ölçüsü `NSScreen.safeAreaInsets.top` ile `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` alanlarından okunur):

| Durum | Boyut |
|---|---|
| idle | notch genişliği × notch yüksekliği (≈ 185–200 × 32–38 pt) |
| compact | notch + 2 × 40 pt kulak |
| peek | notch + 80 pt × 44 pt |
| expanded | varsayılan 680 × 300 pt, ayarlanabilir 520–900 × 200–420 pt |
| alert | 420 × 84 pt |

**Şekil:** Üst köşeler menü çubuğuna içe kıvrılan "omuz" (6–10 pt), alt köşeler compact'ta 14 pt, expanded'da 32 pt. Tek bir `IslandShape: Shape`, `animatableData` ile tüm durumlar arasında akıcı biçimde dönüşür.

**Malzeme (tema seçenekleri):**
- **Notch Black** (varsayılan): saf `#000`, notch ile kaynaşır.
- **Liquid Glass:** macOS 26+ `glassEffect`, eski sürümlerde `NSVisualEffectView`.
- **Artwork Tint:** Liqoria tarzı; çalan şarkının kapağından türetilen degrade.

**Renk token'ları:** `bg #000` · `surface #1C1C1E` · `surface2 #2C2C2E` · metin beyaz %100 / %60 / %35 · accent sistemden ya da kapaktan · durum renkleri yeşil `#30D158`, turuncu `#FF9F0A`, kırmızı `#FF453A`, mavi `#0A84FF`.

**Tipografi:** SF Pro. Başlık 15 semibold, gövde 13, ikincil 11. Sayılarda `.monospacedDigit()`, zamanlayıcıda SF Pro Rounded.

**Hareket:**
- Açılış `spring(response: 0.38, dampingFraction: 0.78)`, kapanış `spring(response: 0.30, dampingFraction: 0.90)`.
- İçerik, şekilden 80 ms sonra opacity + hafif blur ile gelir (önce kabuk, sonra içerik).
- Kapak görseli `matchedGeometryEffect` ile sol kulaktan expanded oynatıcıya uçar.
- "Hareketi azalt" açıksa yalnızca crossfade kullanılır.

**İkonlar:** SF Symbols, hierarchical rendering.

---

## 4. Genişletilmiş panel yerleşimi

```
╭──────────────────────────────── notch ────────────────────────────────╮
│ [⌂ Home] ♪ ▤ ⧉ 📅 ⏱ ✦ …                 [▮ 80%] [☾] [◉] [🔊] [📌] [🔒] │  ← sekmeler | hızlı çipler
│                                                                         │
│  ┌ Medya ─────────┐  ┌ Hava ──────────┐  ┌ Zamanlayıcı ─┐               │
│  │ kapak · başlık │  │ 19° Parçalı    │  │ 24:59  ▶     │               │  ← 12 kolonluk ızgara
│  │ ⏮  ⏯  ⏭        │  │ Amsterdam      │  └──────────────┘               │     (widget'lar S/M/L)
│  └────────────────┘  └────────────────┘                                 │
│  ┌ Takvim ────────┐  ┌ Up Next ─────────────────────┐                   │
│  │ Ekim 2026      │  │ ▌Design review  15:00        │                   │
│  └────────────────┘  └──────────────────────────────┘                   │
╰─────────────────────────────────────────────────────────────────────────╯
```

- **Sekmeler:** Home, Medya, Raf, Pano, Takvim, Zamanlayıcı, Ajanlar (+ eklentiler). Aktif sekme ikon + etiketli kapsül, diğerleri yalnızca ikon.
- **Hızlı çipler:** pil, Odak, kamera/mikrofon gizlilik göstergesi, ses çıkışı, Keep Awake, sabitle, kilitle. Hangilerinin görüneceği ve sırası kullanıcıya ait.
- **Home ızgarası:** düzenleme modunda widget'lar sürükle-bırak ile dizilir ve boyutlanır.
- **Jestler:** iki parmakla yatay kaydırma sekme değiştirir, yukarı kaydırma kapatır. Her jest ayrı ayrı kapatılabilir.
- **Sabitle (📌):** mouse çıkınca panel kapanmaz.

---

## 5. Modüller

Her modül aynı kalıpta yazılır: **Service** (veri ve olay kaynakları) + **CompactView** + **ExpandedView** + **SettingsView**. `start()` observer'ları kurar, `stop()` hepsini söker.

### 5.1 Medya (öncelik 1: "net çalışmalı")

macOS 15.4'ten beri `MediaRemote` özel framework'ü yalnızca Apple'ın yetkilendirdiği süreçlere açık. Bu yüzden **katmanlı kaynak** kullanılır:

1. **MediaRemote köprüsü** (`Adapter/isle8_mr.m`, `mediaremote-adapter` ile aynı teknik: sistemin imzalı Perl ikilisi üzerinden MediaRemote'a erişir ve JSON akışı verir). Tüm uygulamaları kapsar: Spotify, Music, Safari/Chrome/Arc'ta YouTube, Podcasts, IINA, VLC… Tek bir uzun ömürlü alt süreçtir, polling yapmaz.
2. **Yedek: Spotify ve Apple Music için ScriptingBridge/AppleScript.** Olay bazlı çalışır: Spotify `com.spotify.client.PlaybackStateChanged`, Music `com.apple.Music.playerInfo` distributed notification'ları dinlenir. Yalnızca o uygulama açıkken devrededir (`NSWorkspace` launch/terminate).
3. **Komut yedeği:** sistem medya tuşu olayları (play/next/previous). Adapter'ın komut gönderimi bazı macOS 26.x sürümlerinde sorunlu raporlandığı için bu katman gerekli.

`NowPlayingService` tüm kaynakları tek modelde birleştirir: başlık, sanatçı, albüm, kapak, süre, geçen süre, hız, uygulama, oynuyor mu, shuffle/repeat. Kaynak sağlığı izlenir: bir katman sessiz kalırsa bir sonrakine geçilir.

- **İlerleme çubuğu timer'sız:** `elapsed + (now - timestamp) × rate` formülü, yalnızca görünürken `TimelineView` içinde hesaplanır.
- **Kapak:** hedef boyutun 2 katına küçültülür, LRU cache (20 adet). Baskın renk şarkı başına bir kez hesaplanır (küçültülmüş görselde k-means).
- **Compact:** sol kulakta kapak (6 pt köşe), sağ kulakta visualizer. Varsayılan visualizer oynatma durumuna bağlı 4 çubuk animasyonudur, neredeyse sıfır CPU harcar. İsteğe bağlı gerçek spektrum için Core Audio process tap (macOS 14.2+) ve vDSP FFT kullanılır, yalnızca görünürken çalışır.
- **Expanded:** kapak, başlık/sanatçı (uzunsa kayan yazı), sürüklenebilir scrubber, ⏮ ⏯ ⏭, shuffle/repeat, beğen, ses çıkışı/AirPlay seçici, uygulama ikonu (tıklayınca uygulamaya gider). İsteğe bağlı: LRCLIB'den senkron şarkı sözü.
- Şarkı değişince 2,5 sn'lik "şimdi çalıyor" alert'i gösterilir (kapatılabilir).

### 5.2 Raf (File Shelf) + AirDrop

- **Sürükleme algısı:** sol tuş basılıyken gelen `leftMouseDragged` olayları ve `NSPasteboard(name: .drag).changeCount` izlenir. İmleç ekranın üst ~60 pt'ine girince ada `dropTarget` durumuna açılır. Sürükleme yokken hiçbir kontrol çalışmaz.
- **İki hedef:** "Rafa bırak" ve **"AirDrop"**. AirDrop'a bırakılınca `NSSharingService(named: .sendViaAirDrop)` doğrudan açılır ve sistemin cihaz seçicisi gelir.
- **Raf:** dosyalar security-scoped bookmark olarak tutulur (kopyalanmaz, "kopya al" seçeneği var) ve yeniden açılışta korunur. Küçük resimler `QLThumbnailGenerator` ile üretilip önbelleğe alınır.
- **Raftan dışarı sürükleme**, çoklu seçim ve hızlı eylemler: AirDrop, Paylaş (`NSSharingServicePicker`), Zip (`ditto`), görsel dönüştürme (ImageIO: HEIC ↔ PNG/JPEG), Finder'da göster, kaldır.
- **AirDrop alımı (best-effort):** `~/Downloads` FSEvents ile izlenir. Yeni dosyanın `com.apple.quarantine` özniteliği AirDrop'tan (`sharingd`) geldiğini gösteriyorsa "AirDrop · 3 dosya alındı" alert'i çıkar, istenirse dosyalar rafa eklenir.
- Kilit ekranında raf **kapalıdır** (güvenlik).

### 5.3 Pano (Clipboard)

- **Algılama:** `NSPasteboard.general.changeCount` 0,5 sn'de bir okunur. Bu yalnızca bir tamsayıdır, içerik okunmaz. Değişiklik varsa içerik okunur.
- **macOS pano gizliliği (15.4+ / 26):** programatik okuma sistem iznine tabidir. Onboarding'de "Diğer uygulamalardan yapıştır → Her zaman izin ver" adımı anlatılır. İçerik türü önce `detect` API'leriyle yoklanır.
- **Gizlilik:** parola yöneticilerinden gelenler atlanır (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`). Uygulama bazlı hariç tutma listesi vardır.
- **Türler:** düz metin, zengin metin, URL, renk (#hex önizlemeli), görsel, dosya.
- **Depolama:** SQLite + FTS5 ile tam metin arama. Görseller diskte ayrı tutulur. Varsayılan sınır 200 öğe / 30 gün, sabitlenenler silinmez.
- **Arayüz:** Pano sekmesinde arama ve sabitleme. Tıklamak öğeyi panoya kopyalar, ⌥+tıklama aktif uygulamaya yapıştırır (Erişilebilirlik izni gerekir). ⌘⇧V adayı doğrudan Pano sekmesinde açar.
- **Akıllı eylemler:** link aç, e-posta yaz, rengi farklı formatlarda kopyala.

### 5.4 Bildirimler + Kilit Ekranı

macOS'ta başka uygulamaların bildirimlerini okumak için public API yok. Notchy'nin de kullandığı yöntem izlenir:

- **Kaynak:** Bildirim Merkezi veritabanı. Sequoia ve sonrasında `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, eski sürümlerde `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`. **Tam Disk Erişimi** gerekir.
- Dosya FSEvents/`DispatchSource` ile izlenir, polling yapılmaz. Yeni `record` satırlarındaki binary plist çözülerek uygulama, başlık, alt başlık, gövde ve tarih alınır. Şema macOS sürümüne göre değişebildiği için parser sürümlüdür ve test fixture'larıyla korunur.
- **Gösterim:** ada aşağı doğru açılır (uygulama ikonu + başlık + 2 satır gövde), varsayılan 4 sn kalır. Tıklamak uygulamayı açar. Aynı anda gelenler kuyruğa girer ve `+3` olarak gruplanır.
- **Filtreler:** uygulama bazında aç/kapa, Odak moduna uyma, "yalnızca kilitliyken" / "yalnızca açıkken".
- Sistem banner'ı ile çift görünmemesi için kullanıcıya ilgili uygulamalarda banner stilini "Yok" yapması önerilir. Uygulama sistem ayarlarına dokunmaz.

**Kilit ekranı:**
- Kilitlenme/açılma `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notification'larıyla algılanır.
- Ada penceresi, SkyLight özel API'leriyle kilit ekranı katmanına taşınır (açık kaynak örnekler: mew-notch, DynamicNotch). Bu bir **feature flag** arkasındadır. Kırılırsa yalnızca kilit ekranı özelliği kapanır, ada etkilenmez.
- **Kilit ekranı görünümü (salt okunur):** notch altında medya kartı (oynat/duraklat izni ayarlanabilir), bildirim yığını, pil/şarj, zamanlayıcı.
- **Önizleme gizliliği:** "Kilitliyken içeriği gizle" açıksa yalnızca "Mesajlar · 2 yeni bildirim" görünür (varsayılan açık).
- Raf, pano ve ajan onayı kilitliyken **devre dışıdır**.
- Kilitlenince kulakta kilit ikonu, açılınca kilit açılma animasyonu (iPhone'daki gibi) oynar.

### 5.5 HUD'lar (ses, parlaklık, klavye ışığı)

- **İzleme:** ses, sessiz ve çıkış cihazı için CoreAudio property listener; parlaklık için DisplayServices.
- **Sistem HUD'unu gizleme (isteğe bağlı):** `CGEventTap` medya/parlaklık tuşlarını yakalar ve değeri uygulama kendisi uygular (Erişilebilirlik izni gerekir). Kapalıyken uygulama yalnızca izler, sistem HUD'u yerinde kalır.
- **Stiller:** kulakta ikon + ince çubuk (varsayılan), dairesel gösterge veya kenar çubuğu.

### 5.6 Sistem durumu

- **Pil:** IOKit `IOPSNotificationCreateRunLoopSource` ile olay bazlı izlenir. Şarja takma/çıkarma, %20, %10 ve dolu durumlarında alert gösterilir.
- **Bluetooth cihaz pilleri** (AirPods, Magic Mouse/Keyboard): IORegistry `BatteryPercent`. Cihaz bağlanınca ve sonra 5 dakikada bir okunur.
- **Gizlilik göstergesi:** kamera için CoreMediaIO `DeviceIsRunningSomewhere`, mikrofon için CoreAudio `DeviceIsRunningSomewhere` listener'ları.
- **Diğerleri:** Odak modu değişimi, Keep Awake (`IOPMAssertion`), Caps Lock HUD, ekran görüntüsü alındığında (FSEvents) rafa ekleme.

### 5.7 Takvim / Hatırlatıcılar / Hava / Zamanlayıcı

- **Takvim:** EventKit + `EKEventStoreChanged`. "Up Next" listesi gösterilir. Toplantıya 5 dk kala alert çıkar ve Zoom/Meet/Teams linki varsa "Katıl" butonu sunulur.
- **Hava:** Open-Meteo (ücretsiz, anahtarsız), 30 dk önbellek. Konum CoreLocation ile bir kez alınır ya da şehir elle girilir. (WeatherKit ücretli geliştirici hesabı gerektirir.)
- **Zamanlayıcı / Pomodoro / Kronometre:** `Date` tabanlıdır, kayma yapmaz. Kulakta geri sayım görünür, bitince alert + ses.

### 5.8 Ajanlar ve AI kullanımı (Droppy + componest fikri)

- **Yerel API:** Unix domain socket (`~/Library/Application Support/ISLe8/isle8.sock`), küçük bir CLI (`isle8`) ve `isle8://` URL scheme. Herhangi bir script live activity başlatabilir, güncelleyebilir veya bitirebilir:
  ```bash
  isle8 activity start --id build --title "Build" --progress 0.4
  ```
Desteklenen ajanlar: **Claude Code** ve **Codex** (öncelik bu sırayla). Diğerleri sonradan `isle8` üzerinden eklenebilir.

- **Claude Code entegrasyonu:** hook'lar (`PreToolUse`, `PostToolUse`, `Notification`, `Stop`) `isle8` çağırır. Compact pill'de "Reading 12 files · 0:07", expanded'da adım listesi + "Step 4 of 6" ilerleme çubuğu görünür (componest tasarımı).
- **Onay (Claude Code):** izin isteği hook'u adaya bağlanıp yanıt bekler. Ada **Onayla / Reddet** butonlarını gösterir ve karar hook'a geri döner. "Onay bekliyor" kritik öncelikte sabitlenir.
- **Codex entegrasyonu:** `~/.codex/config.toml` içindeki `notify` ayarı tur bitince `isle8` çağırır. Ayrıca `~/.codex/sessions` altındaki oturum log'ları FSEvents ile izlenir (polling yok), ilerleme ve son eylem buradan okunur.
- **Kullanım halkaları:** Claude Code ve Codex için kalan limit yüzdesi, yerel CLI log'larından hesaplanır. Eşik aşılınca (varsayılan %80) uyarı verilir.

### 5.9 ⌘K komut paleti

Global kısayol (varsayılan ⌃⌥K) adayı arama alanıyla açar: sekmeye git, "25" yazıp zamanlayıcı başlat, panoda ara, uygulama aç, Shortcuts çalıştır, ayar değiştir.

---

## 6. Özelleştirme

| Bölüm | Neler ayarlanır |
|---|---|
| **Görünüm** | Tema (Notch Black / Liquid Glass / Artwork Tint / özel), accent, köşe yarıçapları, canlı önizlemeli panel boyutu, yazı boyutu, animasyon hızı ve yay sertliği, kulak genişliği |
| **Davranış** | Hover ile mi tıklayınca mı açılsın, gecikmeler, otomatik kapanma süresi, her jest ayrı ayrı, tam ekranda gizle, ekran paylaşımında gizle (`NSWindow.sharingType = .none`), hangi ekran(lar)da görünsün, notch'suz ekranda pill |
| **Modüller** | Her modül tek tek açılıp kapanır (kapalı = sıfır maliyet), modül başına ayarlar |
| **Düzen** | Sekme sırası, Home ızgara editörü (sürükle-bırak, S/M/L), compact öncelik sırası, hızlı çip seçimi |
| **Bildirimler** | Uygulama bazında filtre, süre, kilit ekranı önizleme gizliliği |
| **Kısayollar** | Her eylem için global kısayol |
| **Temalar ve yedek** | Temalar `themes/*.json`, tüm ayarlar tek `settings.json` olarak içe/dışa aktarılır |
| **Dil** | Türkçe + İngilizce (String Catalog) |

---

## 7. Mimari

```
ISLe8.app  (LSUIElement: Dock ikonu yok, menü çubuğu ikonu isteğe bağlı · bundle ID com.lrxe8.isle8)
├─ App/        AppDelegate, onboarding, PermissionManager (izinleri modül açıldıkça ister)
├─ Window/     IslandPanel (NSPanel), ScreenManager (notch geometrisi, ekran değişimi),
│              LockScreenBridge (SkyLight, feature flag)
├─ Core/       IslandStateMachine, ActivityCenter (öncelik kuyruğu), ModuleRegistry,
│              SettingsStore (@Observable + JSON), ThemeEngine
├─ Modules/    Media · Shelf · Clipboard · Notifications · HUD · System ·
│              Calendar · Weather · Timer · Agents · Palette
├─ Services/   NowPlaying (adapter + AppleScript), Pasteboard, NotificationDB,
│              Battery, CoreAudio, EventKit, LocalAPI (socket)
└─ CLI/        isle8
```

```swift
@MainActor
protocol IslandModule: AnyObject {
    static var id: String { get }
    func start()                     // observer ve kaynakları kur
    func stop()                      // hepsini sök: kapalı modül sıfır maliyet
    var activity: LiveActivity? { get }   // compact kulaklar için (nil = gösterme)
    func expandedView() -> AnyView
    func settingsView() -> AnyView
}
```

**Pencere:**
- `NSPanel`, `[.borderless, .nonactivatingPanel]`, seviye `.mainMenu + 3` (menü çubuğunun üstünde).
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, gölgesiz, şeffaf, odak çalmaz.
- Pencere **sabit maksimum boyuttadır**. Açılıp kapanırken yeniden boyutlanmaz (takılma kaynağı ortadan kalkar). Şeklin dışındaki tıklamalar alttaki uygulamaya geçer.
- Hover algısı yalnızca ada şekli üzerindeki `NSTrackingArea` ile yapılır, sürekli global mouse monitörü yoktur.
- Ekran/çözünürlük değişiminde `didChangeScreenParametersNotification` ile geometri yeniden hesaplanır.
- Durum `@Observable` ile tutulur (macOS 14+), böylece yalnızca değişen view'lar yeniden çizilir.

**Platform ve dağıtım:**
- Minimum macOS 14 Sonoma. Liquid Glass macOS 26+'da açılır.
- Özel API'ler (MediaRemote adapter, SkyLight) nedeniyle **App Store dışı**. Sandbox kapalı.
- **Şimdilik yalnızca kendi Mac'in için** (ücretli Developer hesabı yok). macOS izinleri (Tam Disk Erişimi, Erişilebilirlik) uygulamanın imzasına bağlı. Saf ad-hoc imzada her yeniden derlemede imza değişir ve izinleri tekrar vermen gerekir.
- **Çözüm: Xcode Personal Team ile imzalama.** Projede "Automatically manage signing" açık ve Personal Team seçili olur. Xcode ilk derlemede "Apple Development" sertifikasını Anahtar Zinciri'nde oluşturur. İmza kimliği sabit kaldığı için izinler derlemeler arasında korunur.
  - Durum (2026-10-25): Xcode 27.1 kurulu, Apple ID ücretsiz Personal Team olarak bağlı. Anahtar Zinciri'nde henüz imzalama sertifikası yok, ilk derlemede oluşacak.
  - Ücretsiz sertifika 1 yıl geçerli. Süresi dolunca Xcode yenisini oluşturur ve izinlerin bir kez yeniden verilmesi gerekebilir.
- Kurulum: `scripts/install.sh` uygulamayı derleyip `/Applications`'a kopyalar ve yeniden başlatır. Otomatik güncelleme yok, güncelleme = script'i tekrar çalıştırmak.
- İleride ücretli hesap alınırsa: Developer ID imzası + notarize edilmiş DMG + Sparkle eklenir. Mimaride bunun için bir değişiklik gerekmez.

**İzinler** (hepsi ilgili modül açıldığında istenir, ilk açılışta toplu istenmez):

| İzin | Neden | Gerekli mi |
|---|---|---|
| Tam Disk Erişimi | Bildirim aynası | Bildirimler için |
| Diğer uygulamalardan yapıştır | Pano geçmişi | Pano için |
| Erişilebilirlik | HUD tuş yakalama, ⌥+tıkla yapıştır | İsteğe bağlı |
| Otomasyon (Spotify / Music) | Medya yedek katmanı | İsteğe bağlı |
| Sistem sesi kaydı | Gerçek spektrum visualizer | İsteğe bağlı |
| Takvim / Hatırlatıcılar | Up Next | İsteğe bağlı |
| Konum | Hava | İsteğe bağlı (şehir elle de girilebilir) |

---

## 8. Yol haritası

| Faz | İçerik | Bitti sayılması için |
|---|---|---|
| **0 · İskelet** | Panel, notch geometrisi, durum makinesi, ayar deposu, modül protokolü, ölçüm scripti | Siyah ada hover'da açılıp kapanıyor, boşta CPU ~%0 |
| **1 · Medya** | Adapter + yedek katmanlar, compact kulaklar, expanded oynatıcı, kapak rengi, scrubber, visualizer | Spotify, Music ve tarayıcıdaki YouTube sorunsuz; bütçe tutuyor |
| **2 · Raf + AirDrop + Pano** | Drop zone, raf, AirDrop gönderme/alma, pano geçmişi | Dosya sürükle → AirDrop 2 adımda gidiyor |
| **3 · Bildirim + Kilit ekranı** | DB okuyucu, alert banner'ı, kilit ekranı katmanı | Kilit ekranında bildirim + medya görünüyor |
| **4 · Sistem** | HUD'lar, pil, takvim, hava, zamanlayıcı, gizlilik göstergesi | |
| **5 · Özelleştirme + Ajanlar** | Ayar penceresi, ızgara editörü, temalar, `isle8`, Claude Code hook'ları, ⌘K | |
| **6 · Cila** | Notch'suz harici ekranda pill, çoklu ekran, TR/EN, `install.sh` | Tek komutla kendi Mac'ine kurulabilen build |

---

## 9. Riskler

| Risk | Etkisi | Önlem |
|---|---|---|
| macOS güncellemesi MediaRemote erişimini tamamen kapatır | Medya bilgisi gelmez | Katmanlı kaynak (adapter → AppleScript → medya tuşu), kaynak sağlığı izlenir |
| Bildirim DB şeması değişir | Bildirim gelmez | Sürümlü parser; hata olursa modül kendini kapatıp kullanıcıyı uyarır |
| SkyLight özel API'si kırılır | Kilit ekranında görünmez | Feature flag; normal ada etkilenmez |
| Pano gizlilik uyarısı kullanıcıyı rahatsız eder | Pano geçmişi kullanılmaz | `changeCount` + tek seferlik izin, onboarding'de açıklama |
| HUD tuş yakalama tuşları bozar | Ses/parlaklık tuşları çalışmaz | İsteğe bağlı; kapalıyken yalnızca izleme |
| Hafiflik hedefi zamanla aşınır | "Hafif" vaadi bozulur | Her faz sonunda ölçüm, bütçe aşımı = faz bitmedi |
| Her derlemede izinlerin sıfırlanması | Tam Disk Erişimi ve Erişilebilirlik tekrar tekrar istenir | Xcode Personal Team ile sabit imza kimliği, bkz. §7 |

---

## 10. Kararlar

| Konu | Karar |
|---|---|
| Ad | **ISLe8** ("by LRXe8"): bundle ID `com.lrxe8.isle8`, CLI `isle8`, URL scheme `isle8://` |
| Varsayılan görünüm | **Notch Black** (Liquid Glass ve Artwork Tint ayarlardan seçilebilir) |
| Dağıtım | **Yalnızca kendi Mac'in**, Xcode Personal Team imzasıyla; notarize ve Sparkle ileride |
| Ajanlar | **Claude Code** (hook'lar + onay butonları) ve **Codex** (`notify` + oturum log'ları) |
| Harici monitör | Notch'suz ekranda **pill olarak görünür** |

---

## 11. Durum

| Faz | Durum | Not |
|---|---|---|
| 0 · İskelet | Bitti (2026-10-26) | Panel, notch geometrisi, durum makinesi, ayarlar, modül protokolü, `scripts/measure.sh` |
| 1 · Medya | Bitti (2026-10-26) | Köprü, yedek katmanlar, kulaklar, oynatıcı, scrubber, şarkı değişim banner'ı. Komutlar kullanıcı tarafından doğrulandı. |
| 2 · Raf + AirDrop + Pano | Bitti (2026-10-26) | Sürükleme algısı, drop target, raf (bookmark, kopya seçeneği, zip, dönüştürme), AirDrop gönderme/alma, pano geçmişi (SQLite + FTS5), ⌃⌥V. Kullanıcı tarafından doğrulandı. |
| 3 · Bildirim + Kilit ekranı | Bitti (2026-10-26) | DB okuyucu (kqueue, salt okunur; macOS 27 yapısı ve uçtan uca akış doğrulandı), banner + kuyruk + "+N", uygulama bazında susturma, Odak (elle açılan), kilit ekranı penceresi (SkyLight 400), kilitliyken özet, açılış animasyonu |
| 4 · Sistem + widget'lar | Bitti (2026-10-26) | Ses/parlaklık HUD'ları (+ isteğe bağlı sistem HUD'unu değiştirme), pil uyarıları ve çipi, kamera/mikrofon göstergesi, uyanık tut, takvim + hatırlatıcılar + toplantı uyarısı, hava durumu (Open-Meteo), zamanlayıcı/Pomodoro/kronometre, iki sıralı Home |
| 5 · Özelleştirme + ajanlar | Bitti (2026-10-26) | Yerel soket + `isle8` komutu, Claude Code ve Codex hook'ları (oturum durumu, adadan onay, bitiş banner'ı), Ajanlar sekmesi, ⌘K paleti, temalar, animasyon hızı, sekme/Home/kulak düzeni, kaydedilebilir kısayollar, iki parmakla sekme değiştirme, ekran paylaşımında gizleme, ayar yedeği, kenar çubuklu ayarlar |
| 6 · Çoklu ekran, TR/EN, cila | Bitti (2026-10-26) | Ekran seçimi (otomatik, ana, etkin, adla), String Catalog ile Türkçe + İngilizce (337 dize, çoğullar dahil), uygulama içi dil seçimi, uygulama ikonu, Hareketi Azalt desteği, VoiceOver etiketleri, yeniden açınca Ayarlar |
| 7 · Açılış, temalar, AI, Limitbar | Bitti (2026-10-26) | Sabit pencere ile notch'tan büyüyen açılış, tema sistemi (7 hazır tema, düzenleyici, JSON), alt ikon dock'u, birim tabanlı Home, componest tarzı AI çalışma kartı, Limitbar'ın kullanım limitleri ve W ölçer |

**Plandan sapmalar:**
- **MediaRemote köprüsü kendi kodumuz** (`Adapter/isle8_mr.m`). `mediaremote-adapter` ile aynı teknik (sistem Perl'ine yüklenen kütüphane), ama dışarıdan kod indirilmedi. macOS 27.0.1'de bilgi okuma doğrulandı. Komutlar henüz gerçek kullanımda doğrulanmadı.
- **Swift 6 dil modu**, varsayılan izolasyon `MainActor`. Arka plan kuyruklarında çalışan tipler açıkça `nonisolated`.
- **Visualizer, Core Animation katmanları** ile yapıldı (SwiftUI timeline yerine), CPU maliyeti sıfıra yakın.
- **Şekil geçişi için `matchedGeometryEffect`** yok. Kulaktan oynatıcıya kapak uçuşu Faz 6'da da yapılmadı; kapak yerinde belirip kayboluyor.
- **Pano kısayolu ⌃⌥V**, plandaki ⌘⇧V değil. ⌘⇧V birçok uygulamada "Biçimi eşleştirerek yapıştır" olduğu için onu ezmek istemedim. ⌃⌥K paletiyle de aynı ailede.
- **Pano izni:** İçerik yalnızca `accessBehavior == .alwaysAllow` iken okunuyor. "Sor" durumunda her okuma sistem uyarısı açacağı için ISLe8 arka planda hiç okumuyor; Pano sekmesi izni nasıl vereceğini anlatıyor.
- **Pano araması** Türkçe ı/I'yı i'ye katlayan ayrı bir arama sütunu üzerinden yapılıyor, çünkü SQLite'ın tokenizer'ı ı'yı i saymıyor. Şema `user_version` ile sürümleniyor.
- **`scripts/install.sh` Faz 6'dan öne alındı:** Tam Disk Erişimi listesine uygulama elle eklenmeli. Gizli bir Library klasöründeki build'i dosya seçicide bulmak zor olduğu için ISLe8 artık `/Applications`'a kuruluyor.
- **Bildirim veritabanı kqueue ile izleniyor, FSEvents ile değil:** FSEvents değişikliği dosya kapanınca bildiriyor; usernoted veritabanını hiç kapatmadığı için tek olay gelmedi. kqueue her `write`'ı anında bildiriyor. macOS 27'de yapı (`record`, `app`, `data.req.titl/body`) doğrulandı. Bildirimler usernoted'un yazma gecikmesi yüzünden sistem banner'ından ~5 sn sonra geliyor.
- **Hava durumu konum izni istemiyor:** Plandaki CoreLocation yerine şehir, Mac'in saat diliminden (ör. `Europe/Istanbul`) tahmin ediliyor ve Ayarlar'dan aranıp değiştirilebiliyor. Daha az izin, aynı sonuç.
- **Parlaklık HUD'u için eşik:** Otomatik parlaklık da aynı bildirimi tetiklediği için HUD yalnızca kısa sürede en az %4'lük değişiklikte açılıyor.
- **Faz 4'ten ertelenenler:** klavye ışığı HUD'u (CoreBrightness'ın özel istemcisi gerekiyor), Bluetooth cihaz pilleri, Odak değişimi banner'ı, Caps Lock HUD'u, ekran görüntüsünü rafa ekleme.
- **Home iki sıralı:** Medya + hava, sıradaki + zamanlayıcı. Saat kutusu kaldırıldı (saat menü çubuğunda zaten var); tarih "Sıradaki" kutusunun başlığında.
- **`isle8` komutu uygulamanın kendisi:** Ayrı bir CLI hedefi yerine aynı ikili dosya argümanla başlatılınca istemci olarak çalışıp çıkıyor. Tek dosya, imza ve sürüm hep uyumlu.
- **Ajan kullanım halkaları ertelendi:** Kalan limit sağlayıcının sunucusunda; okumak için Claude Code / Codex oturum anahtarlarına erişmek gerekiyor. Kimlik bilgisi okuyan bir özelliği kullanıcının ayrıca onaylaması gerektiği için bu fazda yapılmadı.
- **Kulak önceliği bir sıra listesi:** Sayısal öncelikler yerine Ayarlar > Düzen'de sıralanabilen bir liste; onay bekleyen ajan her zaman en üstte.
- **Ayarlar kenar çubuğuna taşındı:** 12 bölüm sekmelere sığmıyordu.
- **Temalar hazır üç tane:** JSON ile özel tema ve Home için S/M/L boyutlu sürükle-bırak ızgara bu fazda yok.
- **Kilit ekranı düzeni (kullanıcı geri bildirimiyle değişti):** İlk sürümde ada notch'tan açık bir kart olarak sarkıyordu. Artık notch yalnızca kulakları (kilit, ses çubukları) gösteriyor; medya ve bildirimler sistem saatinin altında, kilit ekranı widget'ları gibi buzlu cam kartlarda duruyor. Kartların yüksekliği ekran yüksekliğinin yüzdesi olarak ayarlanabiliyor (varsayılan %30) ve kilitlemeden önizlenebiliyor.
- **Kilit ekranı ayrı bir pencere:** Planda ada penceresinin kilit ekranına taşınması vardı. Bunun yerine ikinci bir pencere yalnızca kilitliyken açılıp SkyLight alanına taşınıyor, kilit açılınca kaldırılıyor. Özel API bozulursa ya da beklenmedik davranırsa normal adaya hiçbir etkisi olmuyor.
- **Banner üzerine gelince bekler:** Bildirimi okumaya vakit kalsın diye, imleç banner'dayken süre durur. Ada açıkken gelen bildirimler kaybolmaz, kapanınca sırayla gösterilir.
- **Odak:** Yalnızca elle açılan Odak algılanıyor; zamanlanmış Odak için güvenilir bir kaynak bulunamadı. `record.presented` sütunu kullanılmadı, çünkü uyarı stili "Yok" yapılan uygulamalarda da 0 olabilir ve bu, tam da çift banner'ı önlemek için önerdiğimiz ayar.
- **Dosya sistemine dokunan her iş arka planda:** İndirilenler, Masaüstü gibi korumalı klasörlere ilk erişim macOS'un izin sorusuna cevap gelene kadar bekliyor. İlk denemede bu, adanın ana iş parçacığını kilitledi; düzeltildi.
- **Kaynak dil Türkçe:** Kod içindeki metinler Türkçe yazıldı ve String Catalog'un anahtarı oldu; İngilizce çeviri katalogda. Türkçe değerler de katalogda açıkça var: Türkçe tablo olmayınca macOS Türkçe bir Mac'te bile İngilizceye düşüyordu.
- **Dil seçimi uygulamaya özel:** Ayarlar > Genel > Dil, ISLe8'in kendi `AppleLanguages` değerini yazıp uygulamayı yeniden başlatıyor; sistem dili değişmiyor. `isle8` komutu `~/.local/bin` bağlantısından çalışınca `Bundle.main` uygulamayı bulamadığı için dil klasörünü kendisi seçiyor.
- **Hava durumunda "Kapalı" yerine "Çok bulutlu":** "Kapalı" ayarlarda "kapalı (off)" anlamında da geçiyordu; tek anahtar iki İngilizce karşılık alamaz.
- **Etkin ekran olay güdümlü:** İmleç hareketi izlenmiyor. Ada; bir tıklamada, öne gelen uygulamanın en öndeki penceresinin ekranına (`CGWindowListCopyWindowInfo`, izin gerektirmez) ve Space değişiminde imlecin ekranına geçiyor.
- **Belirli ekran adıyla seçiliyor** (`localizedName`). Aynı modelden iki monitör aynı adı taşıyabilir; o durumda ilki seçilir.
- **Uygulama ikonu bir betikle çiziliyor** (`scripts/make-icon.swift`): Apple'ın macOS ızgarasında (1024 tuvalde 824'lük gövde) koyu zemin, ada, kapak ve ses çubukları, ISLe8 yazısı.
- **Hareketi Azalt açıkken** ada yaylı animasyon yerine 0,16 sn'lik düz bir geçişle büyüyüp küçülüyor.
- **Açılış hatası (Faz 7):** Pencere animasyonun ortasında büyüdüğü için SwiftUI kapsayıcının boyutunu da animasyonla değiştiriyordu; ada ~180 ms boyunca pencerenin ortasında, menü çubuğundan kopuk bir kutu olarak büyüyüp sonra yukarı sıçrıyordu (kullanıcının videosunda ve ekran kaydında görüldü). Artık pencere sabit boyutta; ada içinde notch'tan aşağı doğru büyüyor. Şeffaf kısımlara tıklamanın alttaki uygulamaya geçtiği bir test uygulamasıyla doğrulandı.
- **Açılış hızı:** Droppy'nin kaynağı DMCA nedeniyle erişilemez, videosu da ölçülemedi; yay `response 0,34 / damping 0,78` (açılış) ve `0,28 / 0,95` (kapanış) olarak hızlandırıldı. İçerik kabukla birlikte hafif ölçekle gelip kapanışta notch'a doğru katlanıyor.
- **Temalar açık renkli değil:** Açık bir ada notch'un siyahını bir ısırık gibi gösterirdi; bütün temalar koyu, renkli temalarda notch satırı siyah kalıyor. Metin rengi temaya bağlı değil.
- **AI sekmesi yüksekliği içeriğe göre:** Kart kendi doğal yüksekliğini ölçüp adaya bildiriyor; tek kartla boş alan kalmıyor.
- **Pause/Stop yok:** componest kartındaki Duraklat/Durdur, Claude Code ve Codex hook'larıyla yapılamıyor (hook'lar ajanı dışarıdan durduramaz). Yerine ajanın çalıştığı uygulamayı öne getiren "Oturuma git" var; hook ilk olaylarda ebeveyn süreç zincirinden bu uygulamayı bulur.
- **Plan:** "Adım 3/6" yalnızca ajan bir plan tuttuğunda (Claude Code TodoWrite, Codex update_plan) görünür; yoksa adım sayısı.
- **LimitBar ISLe8'in içinde:** Veri katmanı (CLI bulma ve güven kontrolü, korumalı çalıştırma, sorgular, zamanlama, önbellek, W ölçer) taşındı; arayüz, menü çubuğu ve `--statusline` yardımcısı taşınmadı. Claude'un durum satırı dosyası olmadığı için Claude yalnızca `claude -p /usage` ile sorulur. İki LimitBar davranışı düzeltildi: panel açılınca her seferinde canlı `agy` sorgusu ve başarısız `auth status`'un 30 sn'de bir tekrarı.
- **Tasarruf modu varsayılan:** LimitBar'ın 5 dakikalık temposunda CLI'lar ortalama ~%0,3 CPU harcıyor (ISLe8'in kendisi değil). Hafiflik ilkesi gereği varsayılan 15 dakika; ISLe8'in boştaki CPU'su limitlerle birlikte %0,03.
- **W ölçümü yalnızca ada açıkken:** LimitBar adaptör takılıyken 5 sn'de bir okuyordu; ISLe8'de değer yalnızca başlık görünürken lazım.
- **Üzerine gelince doğrudan açılış (Faz 7 sonrası geri bildirim):** Önceden önce `peek` (hafif büyüme), 0,3 sn sonra açılış vardı. Bu arada gelen herhangi bir olay (ajan hook'u, medya değişimi, takip alanının yeniden kurulması) bekleyen açılışı iptal ediyordu; kullanıcı "efekt atıyor ama açılmıyor" diye gördü (Chrome'a özgü değildi). Hover modunda peek kaldırıldı, varsayılan gecikme 0 (yalnızca 50 ms süzme); takip olayları imlecin gerçek konumuyla doğrulanıyor. Beş denemede beşi 0,35 sn içinde açıldı, Chrome öndeyken de.
- **Kablosuz cihaz pilleri:** IOBluetooth'un pil alanları özel API ve Bluetooth izni ister; CoreBluetooth ile AirPods yayınlarını dinlemek sürekli tarama demek. Bunun yerine macOS'un Bluetooth raporu olay anlarında okunuyor (izin yok, polling yok, okuma başına ~0,06 sn CPU).
- **Cihazlar ayrı sekme (geri bildirim):** İlk sürümde cihazlar Home'da tek satırdı; iki cihazla adlar "…" oluyordu ve AirPods iki kez görünüyordu (Bluetooth raporunda LE ve klasik bağlantı ayrı kayıt). Artık kendi sekmesi var, kayıtlar ada göre birleşiyor, Home satırı kaldırıldı.
- **Başlık çipleri notch'a taşmaz:** Her yan, notch'un yanındaki genişlikle sınırlı; sığmayan çipler önem sırasına göre düşüyor (`ViewThatFits`).
- **Sekmeler tek yükseklikte (geri bildirim):** Her sekmenin kendi yüksekliği vardı; Home'dan Raf'a geçince ada küçülüyor, dock yukarı kaçıyor, imleç adanın dışında kalıyor ve ada kapanıyordu. Artık bütün sekmeler aynı yükseklikte (en az 220 pt, Home'un kutularına göre en fazla 380): sekme değişimi yalnızca içeriği 0,18 sn'lik bir geçişle değiştiriyor. Home'un uzun satırı boş alanı (en fazla 150 pt'ye kadar) dolduruyor; AI ve Pano kaydırılıyor. Dock'tan beş sekmeye art arda tıklama testinde ada her seferinde açık kaldı.
- **Cihazlar sekmesi iPhone'un piller widget'ı gibi:** Her pil, içinde cihaz simgesi olan bir halka; yüzde altında, ad kartın altında. Kartlar halka sayısına göre genişler, tek kart ortada ve sınırlı genişlikte.
- **Home bir pano oldu (kullanıcının tasarımı):** Takvim · Müzik · Hava sütunları, istenirse Zamanlayıcı. Ada varsayılan 820 pt genişlikte (ayar 680–980; eski 590 bir kez taşındı), bütün sekmeler 304 pt içerik yüksekliğinde, dock daha büyük (36 pt). Her öğe çalışır: ay gezinme ve gün seçimi EventKit'ten, hızlı ekleme varsayılan takvime yazar; karışık çal / tekrarla MediaRemote komutları 6 ve 7 (Spotify/Music için AppleScript yedeği, doğrulama yalnızca oynat/duraklat/atla için); ses kaydırıcısı Core Audio ile sistem sesini ayarlar (ses HUD'u kapalıyken de izlenir); hava tek Open-Meteo isteğiyle şu an + 5 saat + 5 gün. Boştaki CPU %0,02.
- **Home düzenleri:** Geniş (pano), Kompakt ve Minimal. Geniş ve Kompakt'ta bütün sekmeler aynı yükseklikte; Minimal Home tek şerit (64 pt) olduğu için diğer sekmeler daha uzun. Bu yüzden açık ada kısalınca imleç eski çerçevenin içindeyse ada açık kalır ("slack"), imleç yeni çerçeveye girince ya da ikisinden de çıkınca normale döner. Minimal'de AI sekmesinden Home'a dönme testi: ada açık kaldı, imleç uzaklaşınca kapandı. Türkçede "Pano" zaten Pano sekmesinin adı olduğu için pano düzeninin adı "Geniş".
- **Harici ekranlarda ölçek:** `scaleEffect` ile tepe ortadan; pencere (tuval) ve üzerine gelme alanı aynı katsayıyla büyür. Notch ekranında hep 1 (notch fiziksel). Otomatik katsayı ekranın nokta genişliği ve backingScaleFactor'den: 2x ekranlarda <2200 pt → 1, <3000 → 1,15, üstü → 1,3; 1x ekranlarda yalnızca ≥3400 pt (tam çözünürlükte 4K) → 1,25, çünkü 1x'te büyütmek yazıyı yumuşatır. Harici monitör olmadan, notch ekranında geçici bir test bayrağıyla 1,3x denendi: çizim ve hover doğru.
- **Windows sürümü** ayrı bir oturumda/projede ("ISLe8 Windows sürümü (1080p–4K)").
