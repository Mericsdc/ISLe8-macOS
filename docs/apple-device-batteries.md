# iPhone, iPad ve Apple Watch pilleri: araştırma

**Soru:** ISLe8'in Cihazlar sekmesi bugün Bluetooth aksesuarlarının pilini gösteriyor (AirPods, Magic cihazlar). Kullanıcının iPhone, iPad ve Apple Watch'unun pili de orada görünebilir mi?

**Kısa cevap:** macOS'ta bunun için açık bir API yok. Temiz tek yol, **Finder'ın iPhone'a ulaştığı yol**: usbmuxd üzerinden lockdown oturumu. Root, Tam Disk Erişimi ya da başka bir izin gerektirmiyor. **2026-10-27'de gerçek bir iPhone'la USB üzerinden doğrulandı:** [`scripts/probe-apple-devices.py`](../scripts/probe-apple-devices.py) pil yüzdesini ek izin istemeden okudu. Wi-Fi henüz denenmedi.

---

## 1. Bu Mac'te bugün durum (2026-10-27)

| Kontrol | Sonuç |
|---|---|
| `/var/run/usbmuxd` | `srw-rw-rw- root daemon`: oturum açmış kullanıcı izinsiz bağlanabiliyor. `ListDevices` ve `ReadBUID` yanıt verdi. |
| `MobileDevice.framework` | Var (Apple'ın özel çerçevesi; Finder, Müzik ve Xcode kullanıyor). |
| Eşleşmiş iPhone/iPad | İlk bakışta yoktu (`devicectl` yalnızca bir simülatör gösterdi). iPhone kabloyla bağlanıp güvenilince betik `[USB] <cihaz adı>: 72%` döndürdü. |
| ISLe8'in sandbox'ı | Yok (entitlements dosyası yok), yani usbmuxd soketine erişebilir. |

## 2. Seçenekler

| | Ne gösterir | Kurulum | İzin | CPU | Güvenilirlik |
|---|---|---|---|---|---|
| **A. Lockdown (usbmuxd üzerinden)** | iPhone, iPad. Watch, eşleştiği iPhone üzerinden (doğrulanmadı) | iPhone'u bir kez kabloyla bağlayıp **Güven**. Kablosuz için Finder'da "Wi-Fi'deyken bu iPhone'u göster", aynı ağ | Yok | Bağlanma/kopma olay tabanlı; pil yalnızca okunurken (~0,1–0,3 sn, ağ) | Yüksek. Protokol belgelenmemiş ama yıllardır kararlı |
| **B. Bluetooth (Continuity "Tethering Source")** | iPhone ve hücresel iPad; pil + şebeke | Aynı iCloud hesabı, Bluetooth açık | Bluetooth izni | Tarama açıkken sürekli | Düşük: veri yalnızca Mac kişisel erişim noktası ararken gelir |
| **C. Yardımcı iOS/watchOS uygulaması + iCloud** | Hepsi | Ayrı bir iPhone/Watch uygulaması kurmak | iCloud | Düşük | Düşük: iOS arka planda nadiren çalışır, değer saatlerce eski kalabilir |
| **D. macOS'un iPhone widget'ları** | iPhone | — | — | — | Kullanılamaz: üçüncü taraf uygulamalara kapalı |

### A. Lockdown (önerilen)

Finder, Müzik ve Xcode iPhone'la böyle konuşur:
1. **usbmuxd**, kabloyla bağlı ya da Wi-Fi eşitlemesi açık cihazları listeler. Bağlanma ve kopmayı `Listen` ile bildirir, sorgu gerekmez.
2. "Bu bilgisayara güven"e basılınca macOS bir **eşleşme kaydı** oluşturur. usbmuxd bunu `ReadPairRecord` ile, oturum açmış kullanıcıya verir. Kayıt bu Mac'in kendi kimliğidir; başka bir uygulamanın verisi değil.
3. Cihazdaki **lockdownd**'ye (port 62078) bu kayıtla TLS oturumu açılır ve `com.apple.mobile.battery` alanı okunur: `BatteryCurrentCapacity` (yüzde) ve `BatteryIsCharging`.
4. **Apple Watch** Mac'le değil iPhone'la eşleşir. iPhone'daki `com.apple.companion_proxy` servisi eşleşmiş saatlerin listesini (`GetDeviceRegistry`) ve saatin kayıt değerlerini verir. AirBattery saat pilini bu yoldan okuyor. Hangi anahtarın pil olduğu belgelerde yok (büyük olasılıkla `BatteryCurrentCapacity`); gerçek bir saatle denenmeli.

**Uygulamaya gömmenin üç yolu:**

| Yol | Artı | Eksi |
|---|---|---|
| Kendi Swift istemcimiz (usbmuxd + lockdown + TLS) | Bağımlılık ve lisans yükü yok; yalnızca gereken üç istek | ~400 satır; TLS'te istemci sertifikası (`SecIdentity`) kurmak biraz uğraş |
| libimobiledevice (LGPL-2.1, dinamik bağlama) | Olgun, Watch desteği hazır | 4–5 dylib + OpenSSL paketi büyütür; LGPL için dinamik bağlama ve NOTICE şart |
| `MobileDevice.framework` (`dlopen`, `AMDevice…`) | En az kod | Özel Apple API'si; bir macOS güncellemesi bozabilir |

**Seçilen: `MobileDevice.framework`.** İlk öneri kendi Swift istemcimizdi. Ama lockdown'ın TLS oturumu eşleşme kaydındaki sertifikayla istemci kimliği ister. macOS'ta bunu Swift'te kurmanın yolları iki: anahtarı kullanıcının anahtar zincirine aktarmak (istenmedi) ya da yine özel bir Security fonksiyonu. `MobileDevice` ise oturumu, eşleşme kaydını ve Wi-Fi cihazlarını kendisi yönetiyor; Finder'ın kendi yolu.
- Çerçeve çalışma anında `dlopen` ile yüklenir; bağlanılmaz. Bulunamazsa özellik boş kalır, uygulama etkilenmez.
- Ayar kapalıyken hiç yüklenmez.
- Uygulama: `ISLe8/Modules/Devices/AppleDeviceSource.swift`.

**Hafiflik:** Ayar kapalıyken hiçbir şey çalışmaz. Açıkken usbmuxd'ye tek bir dinleme bağlantısı açılır (olay gelene kadar boşta bekler). Pil yalnızca Cihazlar sekmesi görünürken ya da ada açılınca, en sık 60 sn'de bir okunur. Bugünkü Bluetooth pilleriyle aynı kural, boşta CPU payı 0.

**Riskler:**
- Lockdown Apple'ın belgelediği bir arayüz değil. Ama Finder ve Xcode buna dayandığı için yıllardır geriye dönük uyumlu.
- iOS 17 ile Xcode'un geliştirici bağlantısı RemoteXPC'ye geçti. Lockdown ve Wi-Fi eşitlemesi Finder için hâlâ duruyor. İleride değişirse kablo bağlantısı yine çalışır.
- Kablosuz görünürlük, Finder'daki "Wi-Fi'deyken göster" ayarına ve aynı ağa bağlı.

### B. Bluetooth (Continuity)

- iPhone ve hücresel iPad'ler, aynı iCloud hesabındaki bir Mac **"Tethering Target"** yayınladığında **"Tethering Source"** ile yanıt verir. Yanıtta pil düzeyi ve şebeke bilgisi vardır. Mac bunu kullanıcı Wi-Fi menüsünü açınca yayınlar.
- Üçüncü taraf bir Mac uygulaması Apple'ın üretici verisiyle yayın yapamaz (CoreBluetooth izin vermez). Yalnızca pasif dinleyebilir, bu yüzden veri seyrek ve öngörülemez gelir.
- Diğer Continuity mesajlarında (Nearby Info, Nearby Action, Handoff) iPhone/iPad/Watch pili yok. Pil taşıyan "Proximity Pairing" yalnızca AirPods ve Beats için.
- AirBattery'nin isteğe bağlı Bluetooth modu yalnızca iPhone ve hücresel iPad'i destekliyor. Bu da bu mekanizmaya işaret ediyor.
- Sürekli tarama ve ek izin gerektirdiği için ISLe8'in hafiflik sözüyle uyuşmuyor. **Önerilmez.**

### C. Yardımcı uygulama

- iPhone (ve Watch) için ayrı bir uygulama pilini iCloud'a (CloudKit) yazar, ISLe8 okur.
- iOS bir uygulamayı arka planda yalnızca ara sıra çalıştırır (BGAppRefresh: saatler), yani değer çoğu zaman eski kalır.
- Apple Developer üyeliği, dağıtım ve bakım gerekir; ayrı bir ürün demek. **Şimdilik önerilmez.**

### Mevcut uygulamalar

- **AirBattery** (AGPL-3.0, kodu ISLe8'de kullanılamaz; yalnızca yaklaşımına bakıldı):
  - iPhone ve iPad libimobiledevice ile USB'den ya da Wi-Fi'den okunuyor. Kurulum: cihaza bir kez kabloyla bağlanıp "Güven", sonra aynı ağ.
  - Watch, eşleştiği iPhone üzerinden okunuyor.
  - 10 dakikadır veri gelmeyen cihazı ⚠️ ile işaretliyor.

## 3. Öneri ve sonraki adımlar

1. **Doğrulama (USB'de yapıldı, Wi-Fi bekliyor):** iPhone'u bir kez kabloyla bağla, iPhone'da "Bu bilgisayara güven"e bas, sonra:
   ```
   python3 -I scripts/probe-apple-devices.py
   ```
   Beklenen çıktı: `[USB] iPhone: 84%` (cihazın adı ve yüzdesi). Kablosuz için Finder'da iPhone'u seçip "Wi-Fi'deyken bu iPhone'u göster"i aç, kabloyu çek ve betiği tekrar çalıştır: `[Network] …`.
2. **ISLe8'e eklendi (2026-10-27):**
   - `Modules/Devices/AppleDeviceSource.swift`: MobileDevice bildirimleri (bağlanma/kopma) ve salt okunur lockdown oturumu.
   - Ayarlar > Sistem > Kablosuz cihazlar'da, **varsayılanda kapalı** "iPhone ve iPad pilleri" seçeneği.
   - Cihazlar sekmesinde iPhone/iPad simgeli halka, şarjdayken ⚡ ve "Şarj oluyor". Başlık çipi, `isle8 devices` ve %15 uyarısı da bu cihazları kapsar. Wi-Fi'de cihaz uyuyunca gelip gittiği için "bağlandı" banner'ı yok.
   - Okuma zamanları Bluetooth pilleriyle aynı: bağlanınca (2 sn sonra), ada açılınca veri 60 sn'den eskiyse, bağlıyken 10 dakikada bir.
   - Gerçek iPhone'la USB'de denendi; açıkken boşta CPU ~%0,07.
3. Ardından Watch: `companion_proxy` üzerinden anahtar denenir, ayrı bir adım.

**Betik ne yapar, ne yapmaz:**
- Yalnızca okur. Cihazda hiçbir şeyi değiştirmez, eşleştirme başlatmaz.
- Eşleşme kaydı yalnızca usbmuxd'den alınır. Sertifika yalnızca TLS el sıkışması için, 0700 izinli geçici bir klasöre yazılır ve hemen silinir.
- USB'de gerçek bir iPhone'la denendi ve çalıştı. Wi-Fi ve Apple Watch henüz denenmedi.

## Kaynaklar

- [AirBattery (README)](https://github.com/lihaoyun6/AirBattery): iPhone/iPad için libimobiledevice, Watch için eşleştiği iPhone, isteğe bağlı Bluetooth modu, AGPL-3.0.
- [Bluetooth Framework: Apple Continuity Protocol](https://www.btframework.com/continuity.htm): Tethering Target/Source; pil ve şebeke bilgisi; Proximity Pairing.
- [Discontinued Privacy: Personal Data Leaks in Apple BLE Continuity Protocols (PoPETs 2020)](https://www.petsymposium.org/popets/2020/popets-2020-0003.php): Continuity mesajlarında pil düzeyi gibi bilgiler.
- [libimobiledevice `companion_proxy.h`](https://raw.githubusercontent.com/libimobiledevice/libimobiledevice/master/include/libimobiledevice/companion_proxy.h): eşleşmiş saat listesi ve kayıt değerleri (LGPL-2.1).
- [libimobiledevice belgeleri: companion_proxy_get_value_from_registry](https://libimobiledevice.org/docs/libimobiledevice/latest/companion__proxy_8h_aa8572094010564b6532597e922507851.html)
- [ideviceinfo](https://linuxcommandlibrary.com/man/ideviceinfo): `com.apple.mobile.battery` alanı ve `BatteryCurrentCapacity`.
