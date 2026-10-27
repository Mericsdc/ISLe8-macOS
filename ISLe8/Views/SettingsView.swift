import SwiftUI
import UniformTypeIdentifiers

/// Settings, with a sidebar like System Settings: there are too many sections for tabs.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, layout, shortcuts
        case media, shelf, clipboard, notifications, lockScreen, system, widgets, agents

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: String(localized: "Genel")
            case .appearance: String(localized: "Görünüm")
            case .layout: String(localized: "Düzen")
            case .shortcuts: String(localized: "Kısayollar")
            case .media: String(localized: "Medya")
            case .shelf: String(localized: "Raf ve AirDrop")
            case .clipboard: String(localized: "Pano")
            case .notifications: String(localized: "Bildirimler")
            case .lockScreen: String(localized: "Kilit Ekranı")
            case .system: String(localized: "Sistem")
            case .widgets: String(localized: "Widget'lar")
            case .agents: String(localized: "Ajanlar")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintbrush"
            case .layout: "rectangle.3.group"
            case .shortcuts: "keyboard"
            case .media: "music.note"
            case .shelf: "tray.full"
            case .clipboard: "doc.on.clipboard"
            case .notifications: "bell"
            case .lockScreen: "lock"
            case .system: "speaker.wave.2"
            case .widgets: "square.grid.2x2"
            case .agents: "sparkles"
            }
        }
    }

    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch pane ?? .general {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .layout: LayoutSettings()
            case .shortcuts: ShortcutSettings()
            case .media: MediaSettings()
            case .shelf: ShelfSettings()
            case .clipboard: ClipboardSettings()
            case .notifications: NotificationSettings()
            case .lockScreen: LockScreenSettings()
            case .system: SystemSettings()
            case .widgets: WidgetSettings()
            case .agents: AgentSettings()
            }
        }
        .frame(width: 780, height: 560)
    }
}

private struct SystemSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(HUDModule.self) private var hud
    @Environment(SystemModule.self) private var system
    @State private var needsAccessibility = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Klavye temizliği") {
                LabeledContent {
                    Button("Klavyeyi kilitle") {
                        needsAccessibility = !system.lockKeyboard()
                    }
                } label: {
                    Text("Klavyeyi temizle")
                    Text("Klavyeyi iki dakikalığına kilitler; silerken tuşlar bir şey yazmaz. Fare ve trackpad çalışır, ekrandaki düğmeyle istediğin an açarsın. Erişilebilirlik izni gerekir.")
                }
                if needsAccessibility {
                    Text("Erişilebilirlik izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten ISLe8'i açıp yeniden dene.")
                        .foregroundStyle(Color.orange)
                }
            }

            Section("Göstergeler") {
                Toggle("Ses değişince göster", isOn: $settings.showVolumeHUD)
                Toggle(isOn: $settings.showBrightnessHUD) {
                    Text("Parlaklık değişince göster")
                    Text("Yalnızca parlaklık tuşlarıyla yapılan değişiklikler; otomatik parlaklık ve ekranın kararması gösterilmez.")
                }
                Toggle(isOn: $settings.replaceSystemHUD) {
                    Text("Sistem göstergesinin yerine ISLe8'inkini kullan")
                    Text("Ses ve parlaklık tuşlarını ISLe8 karşılar, macOS'un kendi göstergesi çıkmaz. Erişilebilirlik izni gerekir.")
                }
                if settings.replaceSystemHUD && !hud.isReplacingSystemHUD {
                    HStack {
                        Text("Erişilebilirlik izni yok; macOS'un göstergesi kullanılıyor.")
                            .foregroundStyle(Color.orange)
                        Spacer()
                        Button("İzin ver…") { hud.requestAccessibility() }
                    }
                }
            }

            Section("Pil") {
                Toggle(isOn: $settings.showBatteryAlerts) {
                    Text("Şarj ve pil uyarılarını göster")
                    Text("Şarja takınca, çıkarınca ve pil %20 ile %10'a inince.")
                }
            }

            Section {
                Toggle("Cihaz bağlanınca pillerini göster", isOn: $settings.showDeviceConnectedAlert)
                Toggle("Cihazın pili %15'e inince uyar", isOn: $settings.showDeviceLowBatteryAlert)
                Toggle("Başlıkta cihaz pilleri", isOn: $settings.showDevicesChip)
                Toggle(isOn: $settings.showAppleDevices) {
                    Text("iPhone ve iPad pilleri")
                    Text("Bu Mac'e güvenen iPhone ve iPad'ler, Finder'ın onlara ulaştığı yolla okunur: kabloyla ya da Finder'da \"Wi-Fi'deyken bu iPhone'u göster\" açıkken aynı ağda. Yalnızca okunur, izin gerekmez.")
                }
            } header: {
                Text("Kablosuz cihazlar")
            } footer: {
                Text("AirPods (iki kulaklık ve kutu), Beats, Magic Keyboard, Mouse, Trackpad ve pilini bildiren diğer Bluetooth cihazları. Pil bilgisi macOS'un Bluetooth raporundan, cihaz bağlanınca, ada açılınca ve bağlıyken 10 dakikada bir okunur.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(CalendarModule.self) private var calendar
    @Environment(WeatherModule.self) private var weather
    @State private var cityQuery = ""
    @State private var results: [WeatherPlace] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Takvim") {
                LabeledContent("Erişim") {
                    switch calendar.access {
                    case .granted:
                        Text("Bağlı").foregroundStyle(.secondary)
                    case .notDetermined:
                        Button("Takvimi bağla") { calendar.requestAccess() }
                    case .denied:
                        Text("Kapalı · Sistem Ayarları > Gizlilik ve Güvenlik > Takvimler")
                            .foregroundStyle(Color.orange)
                    }
                }
                Toggle("Toplantıdan 5 dakika önce haber ver", isOn: $settings.meetingHeadsUp)
                Toggle("Bugünkü hatırlatıcıları da göster", isOn: $settings.showReminders)
                    .onChange(of: settings.showReminders) { _, show in
                        if show { calendar.requestRemindersIfNeeded() }
                    }
            }

            Section("Hava durumu") {
                LabeledContent("Şehir") {
                    Text(settings.weatherCity.isEmpty ? String(localized: "Saat dilimine göre (\(weather.report?.place ?? "…"))") : settings.weatherCity)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Şehir ara", text: $cityQuery)
                        .onSubmit(search)
                    Button("Ara", action: search)
                    if !settings.weatherCity.isEmpty {
                        Button("Saat dilimine dön") {
                            settings.weatherCity = ""
                            settings.weatherLatitude = 0
                            settings.weatherLongitude = 0
                            weather.refresh()
                        }
                    }
                }
                ForEach(results) { place in
                    Button {
                        weather.choose(place)
                        results = []
                        cityQuery = ""
                    } label: {
                        HStack {
                            Text(place.name)
                            Text(place.detail).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Picker("Birim", selection: $settings.weatherUnit) {
                    Text("°C").tag(SettingsStore.TemperatureUnit.celsius)
                    Text("°F").tag(SettingsStore.TemperatureUnit.fahrenheit)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.weatherUnit) { weather.refresh() }
            }

            Section("Zamanlayıcı") {
                Toggle("Süre dolunca ses çal", isOn: $settings.timerSound)
                Stepper("Pomodoro odak: \(settings.pomodoroWorkMinutes) dk", value: $settings.pomodoroWorkMinutes, in: 5...90, step: 5)
                Stepper("Pomodoro mola: \(settings.pomodoroBreakMinutes) dk", value: $settings.pomodoroBreakMinutes, in: 1...30)
            }
        }
        .formStyle(.grouped)
    }

    private func search() {
        let query = cityQuery
        Task { results = await weather.search(query) }
    }
}

private struct NotificationSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(NotificationModule.self) private var notifications

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Bildirimleri adada göster", isOn: $settings.notificationsEnabled)
                LabeledContent("Erişim") {
                    HStack {
                        Text(accessText)
                            .foregroundStyle(notifications.access == .granted ? Color.secondary : Color.orange)
                        if notifications.access == .needsFullDiskAccess {
                            Button("Tam Disk Erişimi…") { notifications.openFullDiskAccessSettings() }
                        }
                        if notifications.access != .granted && notifications.access != .off {
                            Button("Tekrar dene") { notifications.retry() }
                        }
                    }
                }
            } footer: {
                Text("macOS başka uygulamaların bildirimlerini okumak için bir API sunmuyor. ISLe8 bunları Bildirim Merkezi'nin veritabanından okur; bu yüzden Tam Disk Erişimi gerekir. Uygulamalar o listeye kendiliğinden düşmez: \"Tam Disk Erişimi…\" düğmesi listeyi ve ISLe8'i Finder'da açar; ISLe8'i listeye sürükle (ya da \"+\" ile ekle), anahtarını aç, sonra burada \"Tekrar dene\"ye bas. Bildirimler iki kez görünmesin diye, Sistem Ayarları > Bildirimler'de ilgili uygulamaların uyarı stilini \"Yok\" yapabilirsin.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Ne zaman", selection: $settings.notificationTiming) {
                    Text("Her zaman").tag(SettingsStore.NotificationTiming.always)
                    Text("Sadece ekran açıkken").tag(SettingsStore.NotificationTiming.whenUnlocked)
                    Text("Sadece kilit ekranında").tag(SettingsStore.NotificationTiming.whenLocked)
                }
                Toggle(isOn: $settings.respectFocus) {
                    Text("Odak modu açıkken gösterme")
                    Text("Elle açılan Odak modlarını algılar; zamanlanmış olanları algılayamaz.")
                }
                LabeledContent("Ekranda kalma süresi") {
                    HStack {
                        Slider(value: $settings.notificationDuration, in: 2...10, step: 0.5)
                            .frame(width: 180)
                        Text("\(settings.notificationDuration.formatted(.number.precision(.fractionLength(1)))) sn")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("Uygulamalar") {
                if settings.notificationSeenApps.isEmpty {
                    Text("Bildirim gönderen uygulamalar burada listelenir.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.notificationSeenApps, id: \.self) { bundleID in
                    Toggle(isOn: Binding(
                        get: { !settings.mutedNotificationApps.contains(bundleID) },
                        set: { show in
                            if show {
                                settings.mutedNotificationApps.removeAll { $0 == bundleID }
                            } else if !settings.mutedNotificationApps.contains(bundleID) {
                                settings.mutedNotificationApps.append(bundleID)
                            }
                        }
                    )) {
                        Label {
                            Text(AppInfo.name(for: bundleID))
                        } icon: {
                            AppIconView(bundleID: bundleID, size: 16)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accessText: String {
        switch notifications.access {
        case .off: String(localized: "Kapalı")
        case .checking: String(localized: "Kontrol ediliyor")
        case .granted: String(localized: "Okunuyor")
        case .needsFullDiskAccess: String(localized: "Tam Disk Erişimi gerekiyor")
        case .unavailable: String(localized: "Veritabanı okunamadı")
        }
    }
}

private struct LockScreenSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(IslandModel.self) private var model

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Kilit ekranında göster", isOn: $settings.lockScreenEnabled)
            } footer: {
                Text("Adayı kilit ekranının üstüne taşımak için Apple'ın belgelenmemiş bir API'si kullanılır. Bir macOS güncellemesinden sonra sorun çıkarsa bunu kapat; adanın geri kalanı etkilenmez.")
                    .foregroundStyle(.secondary)
            }

            Section("Gösterilenler") {
                Toggle("Çalan müzik", isOn: $settings.lockScreenShowsMedia)
                Toggle("Medya kontrolleri", isOn: $settings.lockScreenMediaControls)
                    .disabled(!settings.lockScreenShowsMedia)
                Toggle("Kilitliyken gelen bildirimler", isOn: $settings.lockScreenShowsNotifications)
                Toggle(isOn: $settings.hideNotificationContentWhenLocked) {
                    Text("Bildirim içeriğini gizle")
                    Text("Açıkken yalnızca \"Mesajlar · 2 yeni bildirim\" gibi bir özet görünür.")
                }
                .disabled(!settings.lockScreenShowsNotifications)
            }
            .disabled(!settings.lockScreenEnabled)

            Section {
                LabeledContent("Kartların yüksekliği") {
                    HStack {
                        Slider(value: $settings.lockScreenCardPosition, in: 0.15...0.7)
                            .frame(width: 180)
                        Text("%\(Int((settings.lockScreenCardPosition * 100).rounded()))")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Kilitlemeden bak") {
                    Button("Önizle") { model.previewLockScreen() }
                }
            } header: {
                Text("Konum")
            } footer: {
                Text("Müzik ve bildirim kartları, kilit ekranındaki saatin hemen altında durmalı. Kaydırıcıyı oynatınca kartlar 3 saniyeliğine masaüstünde önizlenir.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.lockScreenEnabled)
            .onChange(of: settings.lockScreenCardPosition) {
                model.previewLockScreen()
            }

            Section {
                LabeledContent("Kilitliyken kapalı") {
                    Text("Raf, pano ve dosya bırakma")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @Environment(SettingsStore.self) private var settings
    /// Screen names, refreshed when a display is connected or removed.
    @State private var screenNames = NSScreen.screens.map(\.localizedName)

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Girişte başlat", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Menü çubuğunda simge")
                    Text("Kapalıyken ayarlar adadaki ⚙ düğmesiyle ya da ISLe8'i yeniden açınca açılır.")
                }
            }

            Section {
                Picker("Ekran", selection: screenChoice) {
                    Text("Otomatik").tag("automatic")
                    Text("Ana ekran").tag("primary")
                    Text("Etkin ekran").tag("active")
                    Divider()
                    ForEach(listedScreens, id: \.self) { name in
                        Text(screenNames.contains(name) ? name : String(localized: "\(name) (bağlı değil)")).tag("named:" + name)
                    }
                }
                if settings.screenMode == .automatic {
                    Toggle("Notch'u olmayan ekranda pill olarak göster", isOn: $settings.showOnScreensWithoutNotch)
                }
            } footer: {
                Text(screenNote)
                    .foregroundStyle(.secondary)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screenNames = NSScreen.screens.map(\.localizedName)
            }

            Section {
                Picker("Dil", selection: Binding(
                    get: { settings.language },
                    set: { code in
                        guard code != settings.language else { return }
                        settings.setLanguage(code)
                        relaunch()
                    }
                )) {
                    Text("Sistem").tag("")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
            } footer: {
                Text("Dil değişince ISLe8 yeniden başlar.")
                    .foregroundStyle(.secondary)
            }

            Section("Davranış") {
                Picker("Açılma", selection: $settings.openMode) {
                    Text("Üzerine gelince").tag(SettingsStore.OpenMode.hover)
                    Text("Tıklayınca").tag(SettingsStore.OpenMode.click)
                }
                .pickerStyle(.segmented)
                if settings.openMode == .hover {
                    SecondsSlider(title: "Açılma gecikmesi", value: $settings.openDelay, range: 0...1)
                }
                SecondsSlider(title: "Kapanma gecikmesi", value: $settings.closeDelay, range: 0...1.5)
            }

            Section {
                LabeledContent("Ayarları yedekle") {
                    HStack {
                        Button("Dışa aktar…", action: exportSettings)
                        Button("İçe aktar…", action: importSettings)
                    }
                }
            } footer: {
                Text("Tüm ayarlar tek bir JSON dosyasına yazılır; başka bir Mac'e taşıyabilir ya da saklayabilirsin. İçe aktarınca ISLe8 yeniden başlar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Sürüm", value: appVersion)
                LabeledContent("Geliştirici", value: "LRXe8")
            }
        }
        .formStyle(.grouped)
    }

    /// One value for the picker: the mode, with the screen's name for a named screen.
    private var screenChoice: Binding<String> {
        Binding(
            get: { settings.screenMode == .named ? "named:" + settings.screenName : settings.screenMode.rawValue },
            set: { choice in
                if choice.hasPrefix("named:") {
                    settings.screenName = String(choice.dropFirst("named:".count))
                    settings.screenMode = .named
                } else {
                    settings.screenMode = SettingsStore.ScreenMode(rawValue: choice) ?? .automatic
                }
            }
        )
    }

    /// Connected screens, plus the chosen one while it is unplugged.
    private var listedScreens: [String] {
        var names = screenNames
        if settings.screenMode == .named, !settings.screenName.isEmpty, !names.contains(settings.screenName) {
            names.append(settings.screenName)
        }
        return names
    }

    private var screenNote: String {
        switch settings.screenMode {
        case .automatic: String(localized: "MacBook'un notch'lu ekranı; kapak kapalıysa ana ekran.")
        case .primary: String(localized: "Menü çubuğunun olduğu ekran (Sistem Ayarları > Ekranlar).")
        case .active: String(localized: "Tıkladığın ya da öne aldığın pencerenin ekranına geçer.")
        case .named: String(localized: "Bu ekran bağlı değilken ada otomatik seçimle görünür.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "ISLe8 Ayarları.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportJSON().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.importJSON(Data(contentsOf: url))
            relaunch()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Settings are read once at launch, so imported ones need a fresh start.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

private struct MediaSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(NowPlayingService.self) private var media

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Şarkı değişince kısaca göster", isOn: $settings.showTrackChangeAlert)
                Toggle("Kulakta ses çubukları", isOn: $settings.showVisualizer)
                Picker(selection: $settings.defaultPlayer) {
                    Text("Son kullanılan").tag("")
                    Text(verbatim: "Spotify").tag(PlayerApp.spotify.rawValue)
                    Text("Müzik").tag(PlayerApp.music.rawValue)
                } label: {
                    Text("Varsayılan müzik uygulaması")
                    Text("Hiçbir şey çalmıyorken oynat'a basınca arka planda açılır ve kaldığı yerden devam eder.")
                }
                LabeledContent("MediaRemote köprüsü", value: bridgeStatus)
            }
        }
        .formStyle(.grouped)
    }

    private var bridgeStatus: String {
        switch media.bridgeStatus {
        case .starting: String(localized: "Başlatılıyor")
        case .running: String(localized: "Çalışıyor")
        case .unavailable: String(localized: "Kullanılamıyor, Spotify/Music yedeği devrede")
        }
    }
}

private struct ShelfSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle(isOn: $settings.copyFilesToShelf) {
                    Text("Rafa bırakılan dosyaların kopyasını al")
                    Text("Kapalıyken raf orijinal dosyayı gösterir; dosya taşınsa da bulunur.")
                }
                Toggle(isOn: $settings.showAirDropReceived) {
                    Text("AirDrop ile gelen dosyaları göster ve rafa ekle")
                    Text("İndirilenler klasörünü izler. macOS ilk seferde klasöre erişim izni isteyebilir.")
                }
            }
            Section {
                LabeledContent("Gönderme") {
                    Text("Dosyayı notch'a sürükle, AirDrop alanına bırak.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ClipboardService.self) private var clipboard

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Pano geçmişini kaydet", isOn: $settings.recordClipboard)
                LabeledContent("Erişim") {
                    HStack {
                        Text(accessText)
                            .foregroundStyle(clipboard.access == .allowed ? Color.secondary : Color.orange)
                        if clipboard.access != .allowed {
                            Button("Sistem Ayarları…") { clipboard.openPrivacySettings() }
                        }
                    }
                }
                LabeledContent("Kısayol", value: "⌃⌥V")
            }

            Section("Saklama") {
                Stepper("En fazla \(settings.clipboardLimit) öğe", value: $settings.clipboardLimit, in: 50...1000, step: 50)
                Stepper("\(settings.clipboardMaxAgeDays) gün sakla", value: $settings.clipboardMaxAgeDays, in: 1...365)
                LabeledContent("Sabitlenen öğeler hiç silinmez.") {
                    Button("Geçmişi temizle", role: .destructive) { clipboard.clearHistory() }
                }
            }

            Section("Kaydedilmeyen uygulamalar") {
                ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(appName(bundleID))
                        Spacer()
                        Button {
                            settings.clipboardExcludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Kaldır")
                        .accessibilityLabel("Kaldır")
                    }
                }
                Button("Uygulama ekle…") { addExcludedApp() }
            }
        }
        .formStyle(.grouped)
        .onAppear { clipboard.refreshAccess() }
    }

    private var accessText: String {
        switch clipboard.access {
        case .allowed: String(localized: "İzin verildi")
        case .needsPermission: String(localized: "\"Her zaman izin ver\" gerekiyor")
        case .denied: String(localized: "Reddedildi")
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.clipboardExcludedApps.contains(id) {
                settings.clipboardExcludedApps.append(id)
            }
        }
    }
}

private struct SecondsSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 0.05)
                    .frame(width: 180)
                Text("\(value.formatted(.number.precision(.fractionLength(2)))) sn")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
