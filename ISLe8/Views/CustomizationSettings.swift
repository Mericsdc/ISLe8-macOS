import Carbon.HIToolbox
import SwiftUI

// MARK: Appearance

struct AppearanceSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            ThemeSettings()

            Section {
                Picker("Home düzeni", selection: $settings.homeStyle) {
                    Text("Geniş").tag(SettingsStore.HomeStyle.dashboard)
                    Text("Kompakt").tag(SettingsStore.HomeStyle.compact)
                    Text("Minimal").tag(SettingsStore.HomeStyle.minimal)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(homeStyleNote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Harici ekranlarda boyut", selection: $settings.externalScale) {
                    Text("Otomatik").tag(0.0)
                    ForEach([0.75, 0.9, 1.0, 1.15, 1.3, 1.5], id: \.self) { scale in
                        Text(verbatim: "%\(Int((scale * 100).rounded()))").tag(scale)
                    }
                }
            } footer: {
                Text("Notch'u olmayan ekranlarda (harici monitörler) adanın boyutu. Otomatik: 1080p'de ve \"1080p gibi görünen\" 4K'da %100, 2K'da %115, tam çözünürlükte 4K'da %125–130. Ada ekrandan geniş olmaz. MacBook'un kendi ekranında ada notch'un boyutundadır.")
                    .foregroundStyle(.secondary)
            }

            Section("Boyut ve hareket") {
                if settings.homeStyle == .dashboard {
                    LabeledContent("Açık ada genişliği") {
                        HStack {
                            Slider(value: $settings.expandedWidth, in: 680...980, step: 10)
                                .frame(width: 180)
                            Text("\(Int(settings.expandedWidth)) pt")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                LabeledContent("Animasyon hızı") {
                    HStack {
                        Slider(value: $settings.animationSpeed, in: 0.6...1.6, step: 0.1)
                            .frame(width: 180)
                        Text("\(settings.animationSpeed.formatted(.number.precision(.fractionLength(1))))×")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("Başlık çubuğu") {
                Toggle("Pil", isOn: $settings.showBatteryChip)
                Toggle("Kablolu bağlantı (LAN)", isOn: $settings.showNetworkChip)
                Toggle("Uyanık tut düğmesi", isOn: $settings.showKeepAwakeChip)
                Toggle("Kamera ve mikrofon göstergesi", isOn: $settings.showPrivacyChip)
            }

            Section {
                Toggle("Özel gün süslemeleri", isOn: $settings.showSeasonal)
                Picker("Önizle", selection: $settings.seasonalPreview) {
                    Text("Önizleme yok").tag(Occasion?.none)
                    ForEach(Occasion.allCases) { occasion in
                        Text(verbatim: "\(occasion.name) · \(occasion.period)").tag(Occasion?.some(occasion))
                    }
                }
            } header: {
                Text("Özel günler")
            } footer: {
                Text(Occasion.current().map { String(localized: "Bugün: \($0.name). Süsler yalnızca ada açıkken, içeriğin arkasında görünür.") }
                     ?? String(localized: "Bugün özel bir gün yok. Süsler yalnızca ada açıkken, içeriğin arkasında görünür."))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.hideFromScreenCapture) {
                    Text("Ekran görüntüsü ve ekran paylaşımında gizle")
                    Text("Ada, ekran görüntülerinde, kayıtlarda ve toplantılarda paylaşılan ekranda görünmez.")
                }
                Toggle("İki parmakla yana kaydırarak sekme değiştir", isOn: $settings.swipeToChangeTabs)
            }
        }
        .formStyle(.grouped)
    }
}

extension AppearanceSettings {
    fileprivate var homeStyleNote: String {
        switch settings.homeStyle {
        case .dashboard: String(localized: "Takvim ayı, büyük oynatıcı ve ayrıntılı hava; ~820 pt genişlik.")
        case .compact: String(localized: "Kartsız tek şerit: bu hafta, ortada oynatıcı, hava ve 5 gün; ~870 pt. Diğer sekmeler açılınca ada büyür.")
        case .minimal: String(localized: "Tek ince satır: sıradaki etkinlik, ortada şarkı ve kontroller, şehir ve hava; ~720 pt. Diğer sekmeler açılınca ada büyür.")
        }
    }
}

// MARK: Layout

struct LayoutSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                ForEach(Array(settings.tabOrder.enumerated()), id: \.element) { index, id in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { !settings.hiddenTabs.contains(id) },
                            set: { visible in
                                if visible {
                                    settings.hiddenTabs.removeAll { $0 == id }
                                } else if settings.tabOrder.count - settings.hiddenTabs.count > 1 {
                                    settings.hiddenTabs.append(id)
                                }
                            }
                        )) {
                            Label(Self.tabTitle(id), systemImage: IslandTab(rawValue: id)?.systemImage ?? "square")
                        }
                        Spacer()
                        MoveButtons(index: index, count: settings.tabOrder.count) { settings.tabOrder.swapAt(index, $0) }
                    }
                }
            } header: {
                Text("Sekmeler")
            } footer: {
                Text("Açık adanın başlığındaki sekmeler, soldan sağa. En az biri açık kalır.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(settings.homeTiles.enumerated()), id: \.element) { index, id in
                    HStack {
                        Label(Self.tileTitle(id), systemImage: Self.tileSymbol(id))
                        Spacer()
                        MoveButtons(index: index, count: settings.homeTiles.count) { settings.homeTiles.swapAt(index, $0) }
                        Button {
                            settings.homeTiles.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Kaldır")
                        .accessibilityLabel("Kaldır")
                    }
                }
                let missing = SettingsStore.allHomeTiles.filter { !settings.homeTiles.contains($0) }
                if !missing.isEmpty {
                    Menu("Sütun ekle") {
                        ForEach(missing, id: \.self) { id in
                            Button(Self.tileTitle(id)) { settings.homeTiles.append(id) }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Home sütunları")
            } footer: {
                Text("Soldan sağa sütunlar halinde dizilir. Zamanlayıcı dar bir sütundur; geniş bir ada (Görünüm > Açık ada genişliği) dört sütuna rahat yeter.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Array(settings.activityOrder.enumerated()), id: \.element) { index, id in
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(Self.activityTitle(id))
                        Spacer()
                        MoveButtons(index: index, count: settings.activityOrder.count) { settings.activityOrder.swapAt(index, $0) }
                    }
                }
            } header: {
                Text("Kulak önceliği")
            } footer: {
                Text("Birkaç şey aynı anda notch'un yanında görünmek isterse üstteki kazanır. Onay bekleyen bir ajan her zaman önce gelir.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static func tabTitle(_ id: String) -> String {
        IslandTab(rawValue: id)?.title ?? id
    }

    static func tileTitle(_ id: String) -> String {
        switch id {
        case "calendar": String(localized: "Takvim")
        case "media": String(localized: "Çalan şarkı")
        case "weather": String(localized: "Hava durumu")
        case "timer": String(localized: "Zamanlayıcı")
        default: id
        }
    }

    static func tileSymbol(_ id: String) -> String {
        switch id {
        case "calendar": "calendar"
        case "media": "music.note"
        case "weather": "cloud.sun"
        case "timer": "timer"
        default: "square"
        }
    }

    static func activityTitle(_ id: String) -> String {
        switch id {
        case "agents": String(localized: "Ajanlar (Claude Code, Codex, betikler)")
        case "media": String(localized: "Çalan şarkı")
        case "timer": String(localized: "Zamanlayıcı")
        case "system": String(localized: "Kamera ve mikrofon")
        default: id
        }
    }
}

private struct MoveButtons: View {
    let index: Int
    let count: Int
    let swap: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { swap(index - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Yukarı taşı")
                .accessibilityLabel("Yukarı taşı")
            Button { swap(index + 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("Aşağı taşı")
                .accessibilityLabel("Aşağı taşı")
        }
        .buttonStyle(.borderless)
    }
}

// MARK: Shortcuts

struct ShortcutSettings: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Pano") {
                    ShortcutRecorder(shortcut: $settings.clipboardShortcut)
                }
                LabeledContent("Komut paleti") {
                    ShortcutRecorder(shortcut: $settings.paletteShortcut)
                }
            } footer: {
                Text("Kutuya tıkla, sonra yeni kısayola bas. En az bir ⌘, ⌃ ya da ⌥ gerekir; Esc vazgeçer.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Click, press a key combination, done.
private struct ShortcutRecorder: View {
    @Binding var shortcut: SettingsStore.Shortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? String(localized: "Kısayola bas…") : shortcut.display)
                .monospaced()
                .frame(minWidth: 90)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else {
            NSSound.beep()
            return
        }
        var carbon = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }
        let key = (event.charactersIgnoringModifiers ?? "?").uppercased()
        shortcut = .make(keyCode: Int(event.keyCode), modifiers: carbon, display: symbols + key)
        stop()
    }
}

// MARK: Agents

struct AgentSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(UsageModule.self) private var usage
    @State private var installed: [AgentKind: Bool] = [:]
    @State private var problem: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                hookRow(.claude, note: "~/.claude/settings.json'a eklenir. Bu Mac'teki tüm Claude Code oturumlarını etkiler; Claude uygulamasının Code sekmesi de dahil.")
                hookRow(.codex, note: "~/.codex/hooks.json'a eklenir. Codex, kullanıcı hook'larını çalıştırmadan önce onay ister: Codex'te /hooks yazıp ISLe8'in hook'larına güven.")
                if let problem {
                    Text(problem).foregroundStyle(Color.orange)
                }
            } header: {
                Text("Bağlantılar")
            } footer: {
                Text("Mevcut ayarlar korunur, ilk değişiklikten önce dosyanın yedeği (.isle8-backup) alınır. ISLe8 kapalıyken hook'lar hiçbir şey yapmadan geçer.")
                    .foregroundStyle(.secondary)
            }

            UsageSettings(usage: usage)

            Section("Onaylar") {
                Toggle(isOn: $settings.agentApprovalsOnIsland) {
                    Text("İzin isteklerini adada sor")
                    Text("Ajan bir komut için izin isteyince adada Onayla / Reddet çıkar. Kapalıysa ajan her zamanki gibi kendi penceresinde sorar.")
                }
                Stepper(
                    "Cevap gelmezse \(settings.agentApprovalTimeout) sn sonra ajana bırak",
                    value: $settings.agentApprovalTimeout,
                    in: 15...300,
                    step: 15
                )
                Toggle("Ajan bitince haber ver", isOn: $settings.agentDoneAlert)
            }

            Section {
                Text("isle8 activity start --id derleme --title \"Derleme\" --progress 0.4")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("isle8 activity end --id derleme")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("Komut satırı")
            } footer: {
                Text("Herhangi bir betik adaya canlı aktivite koyabilir. isle8 komutu ~/.local/bin içinde.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func hookRow(_ agent: AgentKind, note: LocalizedStringKey) -> some View {
        let target: AgentHooks.Target = agent == .claude ? .claude : .codex
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                AgentIcon(agent: agent, size: 20)
                Text(agent.name)
                Spacer()
                if installed[agent] == true {
                    Text("Bağlı").foregroundStyle(.secondary)
                    Button("Kaldır") { change(target, install: false) }
                } else {
                    Button("Bağla") { change(target, install: true) }
                }
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func change(_ target: AgentHooks.Target, install: Bool) {
        do {
            if install {
                try AgentHooks.install(target)
            } else {
                try AgentHooks.uninstall(target)
            }
            problem = nil
        } catch {
            problem = String(localized: "Değiştirilemedi: \(error.localizedDescription)")
        }
        refresh()
    }

    private func refresh() {
        installed = [.claude: AgentHooks.isInstalled(.claude), .codex: AgentHooks.isInstalled(.codex)]
    }
}

/// Settings > Agents > Usage limits: Limitbar's options, now inside ISLe8.
private struct UsageSettings: View {
    @Bindable var usage: UsageModule

    var body: some View {
        Section {
            Toggle(isOn: $usage.isEnabled) {
                Text("Kullanım limitlerini göster")
                Text("Claude Code, Codex ve Antigravity'nin kalan kotası; her servisin kendi komut satırı aracıyla sorulur. ISLe8 parola, token ya da çerez okumaz.")
            }
            if usage.isEnabled {
                ForEach(UsageVendor.allCases) { vendor in
                    Toggle(isOn: Binding(
                        get: { usage.enabledVendors.contains(vendor) },
                        set: { on in
                            if on { usage.enabledVendors.insert(vendor) } else { usage.enabledVendors.remove(vendor) }
                        }
                    )) {
                        HStack(spacing: 6) {
                            if let mark = vendor.markImage {
                                Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 14, height: 14)
                            }
                            Text(vendor.product)
                            Text(verbatim: "(\(vendor.cli))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: $usage.saverMode) {
                    Text("Tasarruf modu")
                    Text("Codex ve Antigravity'ye 15 dakikada bir sorulur (kapalıysa 5). Claude en fazla 20 dakikada bir sorulur. Codex'in kendi kayıtları her zaman anında okunur.")
                }
            }
        } header: {
            Text("Kullanım limitleri")
        } footer: {
            Text("LimitBar LRX'ten taşındı. Bir servisin limiti %90'ı geçince adada kısa bir uyarı çıkar. Giriş, servisin kendi aracıyla yapılır: codex login, claude auth login, agy.")
                .foregroundStyle(.secondary)
        }
    }
}
