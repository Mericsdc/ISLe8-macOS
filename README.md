# ISLe8

MacBook notch'u için hafif bir Dynamic Island. by LRXe8.

Tasarım ve yol haritası: [DESIGN.md](DESIGN.md). Şu an **Faz 0 (iskelet)**, **Faz 1 (medya)**, **Faz 2 (raf, AirDrop, pano)**, **Faz 3 (bildirimler, kilit ekranı)**, **Faz 4 (HUD'lar, pil, takvim, hava, zamanlayıcı)**, **Faz 5 (özelleştirme, ajanlar, `isle8` komutu, ⌘K)** **Faz 6 (çoklu ekran, Türkçe/İngilizce, cila)** ve **Faz 7 (akıcı açılış, tema sistemi, alt dock, AI sekmesi, Limitbar)** hazır.

## Kullanım

- **Açılma:** Üzerine gelince ada doğrudan açılır (Ayarlar > Genel > Açılma gecikmesi varsayılan 0). "Tıklayınca" modunda üzerine gelince hafifçe büyür, tıklayınca açılır.
- **Medya:** İmleci notch'a getir. Müzik çalarken notch'un yanında kapak ve ses çubukları görünür.
- **Raf ve AirDrop:** Bir dosyayı notch'a doğru sürükle. Ada iki alan açar: **Rafa bırak** ve **AirDrop**. Raftaki dosyaları istediğin yere geri sürükleyebilirsin. Sağ tıkla: aç, Finder'da göster, paylaş, zip'le, görseli PNG/JPEG/HEIC'e dönüştür. AirDrop ile gelen dosyalar kısa bir banner'la duyurulur ve rafa eklenir.
- **Pano:** Açık adada **Pano** sekmesi ya da her yerden **⌃⌥V**. Tıkla: kopyala. ⌥ ile tıkla: aktif uygulamaya yapıştır. Arama, aksan ve büyük/küçük harf fark etmeksizin kelime başlarını bulur.
- **Bildirimler:** Başka uygulamalardan gelen bildirimler notch'un altında banner olarak görünür. Üzerine gelince banner bekler, tıklayınca bildirimi gönderen uygulama açılır. Arka arkaya gelenler sıraya girer ve banner'da "+N" olarak görünür. Ayarlar > Bildirimler'den uygulama bazında kapatılabilir.
- **Kilit ekranı:** Mac kilitliyken notch yalnızca kulaklarını gösterir: solda kilit, müzik çalıyorsa sağda ses çubukları. Çalan şarkı (kontrolleriyle) ve kilitliyken gelen bildirimler, sistem saatinin altında buzlu cam kartlar olarak durur. Kartların yüksekliği Ayarlar > Kilit Ekranı > Konum'dan ayarlanır; kaydırıcıyı oynatınca kartlar 3 saniyeliğine masaüstünde önizlenir. Bildirim içeriği varsayılan olarak gizlidir ("2 yeni bildirim"). Raf, pano ve dosya bırakma kilitliyken kapalıdır. Kilit açılınca kulakta kısa bir açık kilit animasyonu oynar.
- **HUD'lar:** Ses ya da parlaklık değişince notch'un kulaklarında simge ve seviye çubuğu görünür. Otomatik parlaklığın yavaş ayarlarında görünmez. Ayarlar > Sistem'den macOS'un kendi göstergesinin yerine geçebilir (Erişilebilirlik izni gerekir; ⌥⇧ ile çeyrek adım).
- **Kablosuz cihazlar:** AirPods (iki kulaklık ve kutu), Beats, Magic Keyboard/Mouse/Trackpad ve pilini bildiren diğer Bluetooth cihazları. Dock'ta ayrı bir **Cihazlar** sekmesi, iPhone'un piller widget'ı gibi: her pil bir halka, içinde cihazın simgesi (dizüstü, sol/sağ kulaklık, kutu), altında yüzde; önce "Bu Mac", sonra bağlı cihazlar. Kartlar halka sayısına göre satırı paylaşır. Bağlanınca iPhone'daki gibi bir banner, pil %15'e inince uyarı, başlıkta pili en az olan cihazın çipi. AirPods Bluetooth raporunda iki kez (LE ve klasik) görünür; aynı adlı kayıtlar birleştirilir. `isle8 devices` aynı listeyi yazar.
- **Pil ve sistem:** Açık adanın başlığında pil yüzdesi, kamera/mikrofon kullanımı ve "uyanık tut" (fincan) düğmesi. Şarja takınca, tam dolunca ve pil %20 ile %10'a inince kısa bir banner çıkar. Kamera ya da mikrofon kullanılırken, başka bir şey yoksa kulakta yeşil kamera / turuncu mikrofon görünür.
- **Açık ada:** Notch satırında solda durum çipleri (pil, W, kamera/mikrofon, cihaz, uyanık tut), sağda sabitle ve ayarlar. Çipler notch'un yanındaki alana sığmazsa önce cihaz, sonra W, sonra uyanık tut çipi düşer. Sekmeler altta küçük bir ikon dock'unda: Home, Raf, Pano, AI, Cihazlar. Bütün sekmeler aynı yükseklikte; sekme değiştirince ada ve dock yerinde kalır, yalnızca içerik geçiş yapar. AI ve Pano fazlasını içeride kaydırır.
- **Home (pano):** Yan yana sütunlar: **Takvim** (ay görünümü, etkinlikli günlerde nokta, ok tuşlarıyla aylar arasında gezinme, bir güne tıklayınca o günün etkinlikleri, "+" ile tek satırda etkinlik ekleme: "14:30 Toplantı"), **Müzik** (büyük kapak, kaynak uygulama, ilerleme çubuğu, karışık çal / önceki / oynat / sonraki / tekrarla, Mac'in ses düzeyi kaydırıcısı), **Hava** (hissedilen, nem, rüzgar, yön, UV, sonraki 5 saat, sonraki 5 gün ve yağış ihtimali). İstersen dar bir Zamanlayıcı sütunu. Sütunların sırası ve görünürlüğü Ayarlar > Düzen'den.
- **Home düzeni (Ayarlar > Görünüm):** **Geniş** (yukarıdaki pano, ~820 pt), **Kompakt** (aynı sütunlar küçük: bugünün etkinlikleri, küçük oynatıcı, kısa hava ve 3 gün; ~640 pt) ya da **Minimal** (tek ince şerit: sıradaki etkinlik, şarkı ve oynat/sonraki, hava; ~600 pt). Minimal'de diğer sekmeler açılınca ada büyür, Home'a dönünce küçülür; imleç eski çerçevenin içindeyken ada kapanmaz.
- **Harici monitörler (1080p, 2K, 4K):** Notch'u olmayan ekranlarda ada pill olarak durur ve boyutu ekranın çözünürlüğüne göre ölçeklenir: 1080p'de ve "1080p gibi görünen" 4K'da %100, 2K'da (ya da "1440p gibi görünen" 4K'da) %115, tam çözünürlükte 4K'da %125–130. Ayarlar > Görünüm > Harici ekranlarda boyut ile %75–%150 arası elle seçilebilir; ada hiçbir zaman ekrandan geniş olmaz. MacBook ekranında ada notch'un fiziksel boyutundadır, ölçeklenmez.
- **Takvim:** "Takvimi bağla" ile. Toplantı linki (Zoom, Meet, Teams, Webex, FaceTime) olan etkinliklerde katıl düğmesi ve hizmet adı. Toplantıdan 5 dakika önce banner. İstersen bugünkü hatırlatıcılar da. Hızlı ekleme varsayılan takvime yazar (saat yazılmazsa bir sonraki tam saat, bir saatlik).
- **Hava durumu:** Open-Meteo'dan; konum izni istemez. Şehir seçilmezse Mac'in saat dilimindeki şehir kullanılır (Ayarlar > Widget'lar'dan değiştirilebilir). Tek istekte şu an, 5 saat ve 5 gün.
- **Zamanlayıcı:** 5 ve 15 dakika, Pomodoro (odak/mola döngüsü) ve kronometre. Çalışırken kalan süre kulakta görünür; bitince ses ve banner.
- **AI (Claude Code, Codex):** Ayarlar > Ajanlar'dan "Bağla". Ajan çalışırken kulakta ajanın simgesi ve hareketli çubuklar; bir komut için izin isteyince adada **Onayla / Reddet / Terminalde sor**; tur bitince kısa bir banner. AI sekmesinde componest tarzı bir çalışma kartı: şu anki adım ve geçen süre, ajan · proje, ajanın planı varsa "Adım 3/6" ve plan kadar parçalı ilerleme çubuğu, son adımlar ve süreleri, bitince "Bitti · 13 sn · 6 dosya değişti", **Oturuma git ↗** (ajanın çalıştığı Terminal'i ya da Claude uygulamasını öne getirir). Birden fazla oturum varsa üstte aralarında geçiş. Codex'te bir kez `/hooks` yazıp ISLe8'in hook'larına güvenmek gerekir.
- **Kullanım limitleri (LimitBar LRX'ten taşındı):** AI sekmesinin altında Claude, Codex ve Gemini için halkalar: 5 saatlik ve haftalık pencereler, sıfırlanma saati; %70'te turuncu, %90'da kırmızı. Bir limit %90'ı geçince adada kısa bir uyarı. Home'daki AI satırında, çalışan ajan yokken özet. Şarj olurken başlıkta adaptörden giren güç (W). Ayarlar > Ajanlar > Kullanım limitleri: servisleri tek tek kapatma, tasarruf modu (varsayılan açık). LimitBar uygulamasına artık gerek yok.
- **`isle8` komutu:** Herhangi bir betik adaya canlı aktivite koyabilir: `isle8 activity start --id derleme --title "Derleme" --progress 0.4`, sonra `isle8 activity end --id derleme`. `isle8 open [home|shelf|clipboard|agents]` adayı açar, `isle8 close` kapatır (Kestirmeler için de kullanışlı), `isle8 devices` bağlı cihazların pillerini yazar. `isle8 ping` ISLe8'in çalışıp çalışmadığını söyler.
- **⌘K komut paleti (⌃⌥K):** Sekmeye git, "25" yazıp zamanlayıcı başlat, Pomodoro, müzik, uyanık tut, panoda ara ve kopyala, uygulama aç, Kestirme çalıştır. Oklarla seç, Return ile çalıştır, Esc ile kapat.
- **Ekran:** Ayarlar > Genel > Ekran. **Otomatik:** MacBook'un notch'lu ekranı; kapak kapalıysa ana ekranda pill. **Ana ekran:** menü çubuğunun olduğu ekran. **Etkin ekran:** tıkladığın ya da penceresini öne aldığın ekrana geçer. Ya da listeden belirli bir ekran; o ekran bağlı değilken ada otomatik seçime döner. Kilit ekranı kartları ve dosya bırakma alanı adayla aynı ekranda.
- **Dil:** Ayarlar > Genel > Dil: Sistem, Türkçe ya da English. Değişince ISLe8 yeniden başlar. `isle8` komutunun mesajları da aynı dili kullanır.
- **Ayarlara ulaşmak:** Menü çubuğundaki ikon, ⌘K paletinde "Ayarlar" ya da ISLe8 çalışırken uygulamayı Finder'dan/Launchpad'den yeniden açmak.
- **Temalar (Ayarlar > Görünüm):** Hazır temalar: Notch Black, Graphite (componest tarzı), Liquid Glass, Kapak rengi, LRX Mono, Midnight, Ember. Her temada malzeme (siyah, düz renk, degrade, cam, kapak rengi), kart rengi, kart kenarlığı, vurgu rengi, köşe yuvarlaklığı ve yazı tipi (sistem, yuvarlak, mono, serif) ayarlanır. Hazır bir temayı değiştirince kopyası oluşur. Temalar `.isle8theme.json` olarak dışa/içe aktarılabilir. Ada kapalıyken her temada siyah kalır.
- **Özelleştirme:** Görünüm (tema, genişlik, animasyon hızı, başlık çipleri, ekran paylaşımında gizleme, iki parmakla sekme değiştirme), Düzen (sekmelerin sırası ve görünürlüğü, Home kutuları ve sırası, kulak önceliği), Kısayollar (pano ve palet kısayolları kaydedilebilir), Genel > ayarları JSON olarak dışa/içe aktarma.

## İzinler

| İzin | Ne için | Ne zaman istenir |
|---|---|---|
| Yapıştır (Gizlilik ve Güvenlik) | Pano geçmişi | Pano sekmesindeki "İzin iste" ile. Sonra Sistem Ayarları'ndan **Her zaman izin ver** seçilmeli. |
| Tam Disk Erişimi | Bildirimleri okumak | macOS bunu soramaz ve uygulama listeye kendiliğinden düşmez. ISLe8 Ayarlar > Bildirimler > "Tam Disk Erişimi…" listeyi ve `/Applications/ISLe8.app`'i Finder'da açar. Uygulamayı listeye sürükle (ya da "+" ile ekle), anahtarını aç, sonra "Tekrar dene"ye bas. |
| İndirilenler klasörü | AirDrop ile gelenleri yakalamak | İlk açılışta, bir kez |
| Erişilebilirlik | ⌥ tıkla yapıştır | İlk ⌥ tıklamada |
| Otomasyon (Spotify / Music) | Medya komut yedeği | Gerekirse, ilk komutta |
| Takvimler / Hatırlatıcılar | Sıradaki etkinlikler | "Takvimi bağla"ya basınca; hatırlatıcılar, ayarı açınca |
| Erişilebilirlik | Sistem göstergesinin yerine geçmek | Ayarlar > Sistem'de o seçeneği açınca |

## Gereksinimler

- macOS 14 Sonoma veya sonrası
- Xcode (ücretsiz Apple ID ile Personal Team yeterli)

## Kurulum

İlk seferde imzalama için kendi Apple ekibini gir (ücretsiz Personal Team yeter; kimliği Xcode > Settings > Accounts'ta). Bu dosya git'e girmez:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

`Config/Local.xcconfig` içinde `DEVELOPMENT_TEAM` değerini kendi ekip kimliğinle değiştir. Xcode'da Signing & Capabilities'ten ekip seçersen Xcode bunu proje dosyasına yazar; o değişikliği commit'leme.

```bash
scripts/install.sh
```

Release sürümü derler, `/Applications/ISLe8.app`'e kopyalar ve başlatır. Çalışan kopya varsa önce kapatılır. Güncellemek için aynı komutu tekrar çalıştır. Uygulamanın sabit bir yerde durması önemli, çünkü Tam Disk Erişimi gibi gizlilik listeleri uygulamayı orada arar.

## Geliştirirken çalıştırma

```bash
scripts/build.sh
open build/Debug/ISLe8.app
```

Aynı anda tek bir ISLe8 çalışmalı; Debug sürümünü açmadan önce `/Applications`'takini kapat. `scripts/build.sh Release` hem Apple silicon hem Intel için derler. İlk derlemede Xcode, Personal Team için "Apple Development" sertifikasını kendisi oluşturur. İmza sabit kaldığı için macOS izinleri derlemeler arasında korunur.

ISLe8'in Dock ikonu yok. Ayarlar ve çıkış, menü çubuğundaki kapsül ikonunda.

## Performansı ölçmek

ISLe8 çalışırken, ona dokunmadan:

```bash
scripts/measure.sh 30
```

Uygulamanın ve MediaRemote köprüsünün CPU ve bellek kullanımını ayrı ayrı yazar. Ölçüm sırasında adayla etkileşime girersen animasyonlar da ölçüme girer.

## Nasıl çalışıyor

- **Pencere:** Menü çubuğunun üstünde, odak çalmayan şeffaf bir panel. Boyutu sabit: adanın en büyük hali kadar. Ada bu pencerenin içinde büyüyüp küçülür, pencere animasyon sırasında hiç yeniden boyutlanmaz. Şeffaf kısımlara yapılan tıklamalar alttaki uygulamalara geçer (macOS şeffaf piksellerdeki tıklamaları alttaki pencereye iletir); üzerine gelme yalnızca adanın kendi alanında sayılır.
- **Durumlar:** `idle` (notch'un arkasında) → `peek` (üzerine gelince) → `expanded` (açık panel). Müzik çalarken `compact` (notch'un yanında kulaklar). Şarkı değişince `alert` (kısa banner).
- **Medya, üç katman:**
  1. **MediaRemote köprüsü** (`Adapter/isle8_mr.m`): macOS 15.4'ten beri MediaRemote yalnızca Apple kimliği taşıyan süreçlere cevap veriyor. Köprü, sistemin Perl'ine (`/usr/bin/perl`) yüklenen küçük bir kütüphane. Bütün uygulamaları (Spotify, Music, tarayıcılar…) görür ve değişiklik olduğunda JSON satırı yazar, polling yapmaz.
  2. **Spotify/Music yedeği:** İki uygulamanın kendi distributed notification'ları. İzin gerekmez, kapak görseli gelmez.
  3. **Komut yedeği:** Bir komut 0,9 sn içinde etki etmezse aynı komut AppleScript ile (Spotify/Music) ya da medya tuşuyla tekrar gönderilir. İki kez üst üste etki etmezse MediaRemote komutları bırakılır.
- **Ses çubukları:** Core Animation katmanları. Animasyon pencere sunucusunda döner, uygulamanın CPU'suna yük bindirmez.
- **Dosya sürükleme algısı:** Yalnızca başka uygulamalardaki fare sürüklemelerini dinler. Sürükleme panosunda dosya varsa ve imleç notch'a yaklaşırsa ada bırakma alanına dönüşür. Sürükleme yokken hiçbir şey çalışmaz.
- **AirDrop alımı:** macOS bunun için bir API sunmuyor. AirDrop gelen dosyaları İndirilenler'e koyuyor ve `sharingd` işaretiyle karantinaya alıyor. ISLe8 klasörü bir çekirdek olayıyla izliyor, yeni dosyalarda bu işarete bakıyor. Bu iş arka plandaki kendi kuyruğunda çalışıyor, çünkü İndirilenler'e ilk erişim macOS'un izin sorusunu bekler.
- **Raf:** Dosyalar bookmark ile tutulur, yeniden adlandırma ve taşımadan sonra da bulunur. İstersen kopyası alınır (Ayarlar > Raf).
- **Pano:** Pano değişince haber veren bir API yok. ISLe8 sayaç değerini yarım saniyede bir okur; bu tek bir tamsayıdır ve pano okumak sayılmaz. İçerik yalnızca sayaç değişince ve yalnızca kullanıcı "Her zaman izin ver" seçtiyse okunur, böylece arka planda sistem uyarısı hiç çıkmaz. Parola yöneticilerinden gelenler (`org.nspasteboard.ConcealedType` vb.) ve hariç tutulan uygulamalardan kopyalananlar kaydedilmez. Geçmiş SQLite + FTS5'te, görseller PNG olarak `~/Library/Application Support/ISLe8/` altında.

- **Bildirimler:** macOS başka uygulamaların bildirimlerini okumak için bir API sunmuyor. Bildirim Merkezi bunları `~/Library/Group Containers/group.com.apple.usernoted/db2/db` adresindeki SQLite veritabanında tutuyor. ISLe8 bu veritabanını salt okunur açar ve dosyalarını çekirdek olaylarıyla (kqueue) izler. FSEvents burada işe yaramıyor, çünkü değişikliği dosya kapanınca bildiriyor ve bildirim servisi veritabanını hep açık tutuyor. Yeni bir kayıt gelince yalnızca o kaydın `data` plist'ini (`req` → `titl`, `subt`, `body`) çözer. Bütün bu iş kendi kuyruğunda çalışır. Veritabanı yapısı bir macOS güncellemesinde değişirse diye ISLe8 ilk açılışta tablo, sütun ve plist anahtarlarının **adlarını** (içerik değil) `~/Library/Application Support/ISLe8/notification-db.txt` dosyasına yazar.
- **Odak:** Elle açılan Odak modu `~/Library/DoNotDisturb/DB/Assertions.json` dosyasından okunur. Zamanlanmış Odak modları orada yer almadığı için algılanamaz.
- **Kilit ekranı:** Kilitlenme ve açılma `com.apple.screenIsLocked` / `screenIsUnlocked` bildirimleriyle algılanır. Kilit ekranında ayrı bir pencere gösterilir. Bu pencere, Apple'ın belgelenmemiş SkyLight API'siyle oluşturulan ve kilit ekranının (seviye 300) üstündeki bir alana (seviye 400) taşınır. Pencere yalnızca kilitliyken ekrandadır, kilit açılınca tamamen kaldırılır. Böylece normal ada ve ekranın üstündeki tıklamalar hiç etkilenmez. Ayarlar > Kilit Ekranı'ndan kapatılabilir.
- **HUD'lar:** Ses Core Audio özellik dinleyicileriyle, parlaklık Apple'ın belgelenmemiş DisplayServices bildirimiyle izlenir (ikisi de olay tabanlı). Parlaklık için HUD yalnızca 1 saniyelik bir dalgada en az %4'lük değişiklikte açılır; otomatik parlaklık bu eşiğin altında kalır. "Sistem göstergesinin yerine" açıksa bir CGEventTap ses/parlaklık tuşlarını yakalar, değeri ISLe8 uygular ve macOS'un göstergesi çıkmaz; ayarlanamayan bir çıkışta (bazı HDMI) tuş macOS'a bırakılır.
- **Pil:** IOKit güç kaynağı bildirimi (yaklaşık her yüzde birde bir). **Kamera/mikrofon:** CoreMediaIO ve Core Audio "başka biri kullanıyor" özellikleri; izin gerektirmez. **Uyanık tut:** `IOPMAssertion`, `caffeinate -d` gibi.
- **Takvim:** EventKit; her değişiklikte EventKit haber verir. Arada modül bir sonraki önemli ana (5 dk uyarısı, etkinlik bitişi, gece yarısı) kadar uyur.
- **Hava durumu:** Open-Meteo'ya yalnızca 2 ondalığa yuvarlanmış koordinat gider. Arka planda zamanlayıcı yok: Home görünür olduğunda veri 30 dakikadan eskiyse yenilenir.
- **Zamanlayıcı:** Süreler tarihten hesaplanır, kaymaz. Bitişe kadar tek bir uyku bekler; kulaktaki süre yalnızca çalışırken saniyede bir güncellenir.
- **Yerel soket ve `isle8`:** ISLe8, `~/Library/Application Support/ISLe8/isle8.sock` adresinde yalnızca kullanıcının erişebildiği (0600) bir Unix soketi açar. `isle8` ayrı bir program değil, uygulamanın kendi ikili dosyasıdır: argümanla başlatılınca pencere açmadan sokete bir JSON satırı yazar, yanıtı bekler ve çıkar. `install.sh` onu `~/.local/bin/isle8` olarak bağlar.
- **Kullanım limitleri:** LimitBar LRX'in veri katmanı (MIT). Sorgular yalnızca servislerin resmi CLI'larıyla yapılır (`codex` app-server, `claude -p /usage`, `agy -p /quota`); ISLe8 parola, token, çerez ya da anahtar zinciri öğesi açmaz. Codex ve agy Seatbelt korumalı alanında, claude kendi izolasyon bayraklarıyla (hook'lar ve MCP kapalı) çalışır; her CLI izinli ortam değişkenleri, boş özel bir çalışma klasörü, süre sınırı ve kendi süreç grubuyla başlar. Codex'in kendi oturum kayıtları kqueue ile izlenir ve yazıldığı anda okunur. Önbellek `~/Library/Caches/com.lrxe8.isle8/usage` (klasör 0700, dosya 0600) yalnızca yüzde, zaman ve plan adı tutar. Uykuda hiçbir şey çalışmaz. W ölçümü yalnızca ada açıkken yapılır.
- **Kablosuz cihaz pilleri:** macOS bunun için genel bir API sunmuyor. ISLe8, Sistem Ayarları'nın da kullandığı Bluetooth raporunu (`system_profiler SPBluetoothDataType -json`, ~0,06 sn CPU) okur; yeni bir izin istemez. Polling yok: rapor bir ses aygıtı (AirPods, kulaklık) ya da Apple giriş aygıtı (IOKit `AppleDeviceManagementHIDEventService`) gelip gidince, ada açılınca (1 dakikadan eskiyse) ve bir cihaz bağlıyken 10 dakikada bir okunur.
- **Üzerine gelme:** Pencere sabit boyutlu olduğu için takip alanı adanın kendisi kadar; her boyut değişiminde yeniden kurulur. AppKit bu sırada aynı milisaniyede sahte giriş/çıkış olayları gönderebiliyor; her olay imlecin gerçek konumuyla doğrulanıyor.
- **Ajan hook'ları:** Claude Code (`~/.claude/settings.json`) ve Codex (`~/.codex/hooks.json`) olaylarında `isle8 hook claude|codex` çalışır ve olayın JSON'unu sokete iletir. İzin isteği (PermissionRequest) bağlantıyı açık tutar; kullanıcı Onayla/Reddet'e basınca `hookSpecificOutput.decision.behavior` ile `allow`/`deny` döner. Süre dolarsa, "Terminalde sor" seçilirse ya da ISLe8 kapalıysa hook boş döner ve ajan kendi penceresinde sorar. Bağla/Kaldır yalnızca `isle8 hook` çağıran girdilere dokunur ve ilk değişiklikten önce `.isle8-backup` yedeği alır.

## Proje yapısı

```
ISLe8/
├─ App/        main, AppDelegate, CommandLineTool (isle8), HotKey, menü çubuğu ikonu, ayarlar penceresi
├─ Core/       IslandModel (durum makinesi), IslandModule, SettingsStore, LocalServer (soket)
├─ Window/     IslandPanel, IslandController, ScreenLocator,
│              LockScreen (LockMonitor, SkyLight, LockScreenController)
├─ Views/      IslandView, IslandShape, HeaderBar, HomeView, LockScreenView,
│              FileThumbnail, AppInfo, SettingsView
├─ Modules/
│  ├─ Media/     NowPlayingService, MediaRemoteSource, PlayerAppSource,
│  │             MediaFallbacks, Artwork, AudioBars, MediaViews, MediaModule
│  ├─ Shelf/     ShelfStore, ShelfActions, FileDragWatcher, AirDropReceiver,
│  │             ShelfViews, ShelfModule
│  ├─ Clipboard/ ClipboardStore (SQLite), ClipboardService, ClipboardItem,
│  │             ClipboardViews, ClipboardModule
│  ├─ Notifications/ NotificationDatabase, NotificationModule, NotificationViews
│  ├─ System/    HUDModule, VolumeMonitor, BrightnessMonitor, MediaKeyTap,
│  │             SystemModule, SystemMonitors (pil, kamera/mikrofon, uyanık tut), SystemViews
│  ├─ Calendar/  CalendarModule, CalendarViews
│  ├─ Weather/   WeatherModule, WeatherViews
│  ├─ Timer/     TimerModule, TimerViews
│  ├─ Agents/    AgentsModule, AgentHooks (kurucu), AgentViews (çalışma kartı), UsageViews (halkalar)
│  ├─ Devices/   DevicesModule (Bluetooth pilleri), DeviceViews
│  ├─ Usage/     UsageModule, UsageModel, UsageSpawn, UsageFetchers, UsagePolling,
│  │             UsageWatcher, UsagePower (LimitBar'dan taşınan veri katmanı)
│  └─ Palette/   PaletteModule, PaletteView
└─ Resources/  isle8-media.pl, Localizable.xcstrings (TR kaynak + EN), InfoPlist.xcstrings,
               Assets.xcassets (uygulama ikonu), usage-cli.sb (CLI korumalı alanı), usage-marks/,
               LimitBar-LICENSE.txt
Adapter/       MediaRemote köprüsü (Objective-C) ve onu derleyen build phase script'i
scripts/       build.sh, install.sh (uygulama + isle8 bağlantısı), measure.sh,
               make-icon.swift (ikonu yeniden çizer: swift scripts/make-icon.swift)
```

## Bilinen sınırlar

- **Medya tuşu yedeği** Erişilebilirlik izni ister. ISLe8 bu fazda bu izni istemiyor, o yüzden Spotify ve Music dışındaki uygulamalarda tek komut yolu MediaRemote.
- **Etkin ekran** tıklamayla, uygulama değiştirmeyle ve masaüstü (Space) değişimiyle güncellenir; imleci başka ekrana götürmek tek başına adayı taşımaz. İmleç hareketini sürekli izlemek CPU harcayacağı için bilerek böyle.
- **Çoklu ekran yalnızca tek ekranlı bir MacBook'ta derlenip denendi.** Ekran seçimi ve yedeğe dönüş mantığı hazır, ama harici monitörle gerçek kullanımda doğrulanmadı.
- **Ada aynı anda tek ekranda.** Her ekranda ayrı ada yok.
- **Girişte başlat**, uygulamayı çalıştırdığın konuma bağlanır. Uygulamayı taşırsan bu ayarı yeniden aç.
- **Raf yalnızca gerçek dosyaları kabul eder.** Fotoğraflar uygulamasından ya da Mail ekinden sürüklenen "dosya sözü" (file promise) henüz desteklenmiyor.
- **Zip** tek öğe için çalışır; birden fazla dosyayı tek arşive koymak yok.
- **Bildirimler sistemin banner'ından yaklaşık 5 saniye sonra gelir.** Bildirim servisi kaydı veritabanına o kadar gecikmeyle yazıyor; ISLe8 yazıldıktan sonra ~1 saniye içinde gösteriyor. Gecikmeyi ISLe8 tarafında kısaltmanın bir yolu yok.
- **Teşhis dosyaları:** `~/Library/Application Support/ISLe8/` altında `notification-db.txt` (veritabanının tablo, sütun ve anahtar adları) ve `notification-status.txt` (olay ve iletilen bildirim sayıları, dosya boyutları) bulunur. İkisinde de bildirim içeriği yoktur. Okuyucu sessiz kalırsa ilk bakılacak yer bunlardır.
- **Bildirime tıklamak** uygulamayı açar, o bildirimin kendisini değil.
- **Kartların varsayılan yüksekliği** (ekranın %30'u) saatin yerine göre tahmin edildi. Saatin altına tam oturmuyorsa Ayarlar > Kilit Ekranı > Konum'dan ayarla.
- **Henüz yok:** klavye ışığı HUD'u, AirPods / Magic Mouse gibi Bluetooth cihazların pili, Odak değişimi banner'ı, Caps Lock göstergesi ve ekran görüntüsünün rafa düşmesi.
- **Limit sorguları** servislerin kendi CLI'larıyla yapılır; her biri kısa bir CPU dalgası harcar (Codex ~0,24 sn, Antigravity ~0,4 sn, Claude ~1,2 sn). Tasarruf modunda (varsayılan) ortalaması %0,16 civarı, kapalıyken %0,3; bu yük ISLe8'in değil CLI süreçlerinin. Tamamen kapatmak için Ayarlar > Ajanlar > Kullanım limitleri.
- **Claude Code hook'ları bu Mac'teki bütün Claude Code oturumlarını etkiler**, Claude uygulamasının Code sekmesi dahil. İzin istekleri o zaman adaya da düşer.
- **Temalar** üç hazır tema; kendi renk temanı JSON olarak tanımlamak yok. **Home kutuları** dar/geniş olarak sabit, S/M/L boyut ve sürükle-bırak yok (sıra Ayarlar > Düzen'den).

## Lisans

Kod [Apache License 2.0](LICENSE) ile lisanslı. **ISLe8** ve **LRXe8** adları, logoları ve uygulama simgesi bu lisansa dahil değil; bir çatal dağıtacaksan kendi adını ve simgesini kullan ([TRADEMARKS.md](TRADEMARKS.md)). Üçüncü taraf bileşenler ve telif bildirimleri [NOTICE](NOTICE) dosyasında: kullanım limitleri katmanı [LimitBar](https://github.com/dancik/limitbar)'dan (MIT) taşındı.

Apple, MacBook, AirPods, AirDrop ve Dynamic Island, Apple Inc.'in markalarıdır; ISLe8 bağımsız bir projedir.
