import AppKit
import SwiftUI

struct PaletteCommand: Identifiable {
    enum Icon {
        case symbol(String)
        case image(NSImage)
    }

    let id: String
    let title: String
    var subtitle: String = ""
    let icon: Icon
    /// Extra words it should be found by.
    var keywords: [String] = []
    /// Leave the island open afterwards (for example when the command switches tabs).
    var keepsOpen = false
    let run: () -> Void
}

/// The ⌘K command palette: type to find an action, an app, a Shortcut or something you
/// copied, then press return. Apps and Shortcuts are listed once, in the background, the
/// first time the palette opens.
@Observable
final class PaletteModule: IslandModule {
    let id = "palette"
    var activity: LiveActivity? { nil }
    var query = "" {
        didSet {
            selection = 0
            rebuild()
        }
    }
    private(set) var results: [PaletteCommand] = []
    var selection = 0

    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored private weak var model: IslandModel?
    @ObservationIgnored private let modules: [any IslandModule]
    @ObservationIgnored private var apps: [URL] = []
    @ObservationIgnored private var shortcuts: [String] = []
    @ObservationIgnored private var catalogLoaded: Date?

    init(modules: [any IslandModule]) {
        self.modules = modules
    }

    func attach(to model: IslandModel) {
        self.model = model
    }

    func start() {}
    func stop() {}

    /// Called when the palette appears.
    func prepare() {
        if query.isEmpty {
            rebuild()
        } else {
            query = ""
        }
        if catalogLoaded == nil || Date().timeIntervalSince(catalogLoaded!) > 600 {
            catalogLoaded = Date()
            Task {
                async let apps = Task.detached(priority: .utility) { Self.findApps() }.value
                async let shortcuts = Task.detached(priority: .utility) { Self.findShortcuts() }.value
                self.apps = await apps
                self.shortcuts = await shortcuts
                self.rebuild()
            }
        }
    }

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    func run(_ command: PaletteCommand) {
        command.run()
        if !command.keepsOpen {
            model?.close()
        }
    }

    // MARK: Building the list

    private func rebuild() {
        let text = Self.fold(query.trimmingCharacters(in: .whitespaces))
        var found: [(score: Int, command: PaletteCommand)] = []

        if let minutes = Self.minutes(in: text), let timer = module(TimerModule.self) {
            found.append((100, PaletteCommand(
                id: "timer-\(minutes)",
                title: String(localized: "\(minutes) dakikalık zamanlayıcı başlat"),
                icon: .symbol("timer")
            ) { timer.startCountdown(minutes: minutes) }))
        }
        for command in actions() + shortcutCommands() {
            if let score = Self.score(command, for: text) {
                found.append((score, command))
            }
        }
        // Apps are matched by name first, so icons are only fetched for the few that match.
        if !text.isEmpty {
            for url in apps {
                let probe = PaletteCommand(id: "app-", title: url.deletingPathExtension().lastPathComponent, icon: .symbol("app")) {}
                if let score = Self.score(probe, for: text) {
                    found.append((score, appCommand(url)))
                }
            }
        }
        if text.count >= 2, let clipboard = module(ClipboardModule.self)?.service {
            for item in clipboard.search(query, limit: 3) {
                found.append((15, PaletteCommand(
                    id: "clip-\(item.id)",
                    title: item.title,
                    subtitle: String(localized: "Panoya kopyala"),
                    icon: .symbol("doc.on.clipboard")
                ) { clipboard.copy(item) }))
            }
        }
        results = found
            .sorted { $0.score > $1.score }
            .prefix(text.isEmpty ? 8 : 10)
            .map(\.command)
    }

    private func actions() -> [PaletteCommand] {
        var commands: [PaletteCommand] = []
        guard let model else { return commands }

        for tab in model.visibleTabs {
            commands.append(PaletteCommand(
                id: "tab-\(tab.rawValue)",
                title: tab.title,
                subtitle: String(localized: "Sekmeye git"),
                icon: .symbol(tab.systemImage),
                keywords: ["sekme", "tab"],
                keepsOpen: true
            ) { model.select(tab) })
        }
        if let media = module(MediaModule.self)?.service, media.info != nil {
            commands += [
                PaletteCommand(id: "play", title: media.info?.isPlaying == true ? String(localized: "Duraklat") : String(localized: "Oynat"), subtitle: media.info?.title ?? "",
                               icon: .symbol("playpause.fill"), keywords: ["müzik", "play", "pause", "oynat"]) { media.perform(.togglePlayPause) },
                PaletteCommand(id: "next", title: String(localized: "Sonraki şarkı"), icon: .symbol("forward.fill"), keywords: ["müzik", "next", "ileri"]) { media.perform(.next) },
                PaletteCommand(id: "previous", title: String(localized: "Önceki şarkı"), icon: .symbol("backward.fill"), keywords: ["müzik", "previous", "geri"]) { media.perform(.previous) },
            ]
        }
        if let timer = module(TimerModule.self) {
            if timer.mode == .idle {
                commands += [
                    PaletteCommand(id: "pomodoro", title: String(localized: "Pomodoro başlat"), icon: .symbol("brain.head.profile"), keywords: ["odak", "focus", "zamanlayıcı"]) { timer.startPomodoro() },
                    PaletteCommand(id: "stopwatch", title: String(localized: "Kronometre başlat"), icon: .symbol("stopwatch.fill"), keywords: ["süre", "stopwatch"]) { timer.startStopwatch() },
                ]
            } else {
                commands.append(PaletteCommand(id: "timer-stop", title: String(localized: "Zamanlayıcıyı durdur"), icon: .symbol("stop.fill"), keywords: ["timer", "kronometre", "pomodoro"]) { timer.reset() })
            }
        }
        if let system = module(SystemModule.self) {
            commands.append(PaletteCommand(
                id: "awake",
                title: system.isKeepingAwake ? String(localized: "Uyanık tutmayı kapat") : String(localized: "Mac'i uyanık tut"),
                icon: .symbol("cup.and.saucer.fill"),
                keywords: ["kafein", "caffeinate", "uyku", "sleep"]
            ) { system.setKeepAwake(!system.isKeepingAwake) })
        }
        if let shelf = module(ShelfModule.self), !shelf.store.items.isEmpty {
            commands += [
                PaletteCommand(id: "shelf-airdrop", title: String(localized: "Raftakileri AirDrop'la gönder"), icon: .symbol("dot.radiowaves.up.forward"), keywords: ["airdrop", "raf", "paylaş"]) {
                    ShelfActions.airDrop(shelf.store.items.map(\.url))
                },
                PaletteCommand(id: "shelf-clear", title: String(localized: "Rafı temizle"), icon: .symbol("trash"), keywords: ["raf", "sil"]) { shelf.store.removeAll() },
            ]
        }
        commands += [
            PaletteCommand(id: "settings", title: String(localized: "Ayarlar"), icon: .symbol("gearshape.fill"), keywords: ["tercih", "preferences", "settings"]) { model.openSettings() },
            PaletteCommand(id: "lock-preview", title: String(localized: "Kilit ekranını önizle"), icon: .symbol("lock.fill"), keywords: ["kilit", "lock"]) { model.previewLockScreen() },
            PaletteCommand(id: "quit", title: String(localized: "ISLe8'den çık"), icon: .symbol("power"), keywords: ["quit", "kapat"]) { NSApp.terminate(nil) },
        ]
        return commands
    }

    private func appCommand(_ url: URL) -> PaletteCommand {
        PaletteCommand(
            id: "app-\(url.path)",
            title: url.deletingPathExtension().lastPathComponent,
            subtitle: String(localized: "Uygulamayı aç"),
            icon: .image(NSWorkspace.shared.icon(forFile: url.path))
        ) { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    }

    private func shortcutCommands() -> [PaletteCommand] {
        shortcuts.map { name in
            PaletteCommand(id: "shortcut-\(name)", title: name, subtitle: String(localized: "Kestirmeyi çalıştır"), icon: .symbol("square.2.layers.3d.fill"), keywords: ["kestirme", "shortcut"]) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["run", name]
                try? process.run()
            }
        }
    }

    private func module<T>(_ type: T.Type) -> T? {
        modules.lazy.compactMap { $0 as? T }.first
    }

    // MARK: Matching

    /// Higher is better; nil means no match. Built-in actions show without typing; apps and
    /// Shortcuts only once something is typed.
    private static func score(_ command: PaletteCommand, for text: String) -> Int? {
        let isCatalog = command.id.hasPrefix("app-") || command.id.hasPrefix("shortcut-")
        guard !text.isEmpty else { return isCatalog ? nil : 1 }
        let title = fold(command.title)
        if title.hasPrefix(text) { return isCatalog ? 60 : 80 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(text) }) { return isCatalog ? 40 : 60 }
        if command.keywords.map(fold).contains(where: { $0.hasPrefix(text) }) { return 30 }
        if title.contains(text) { return 20 }
        return nil
    }

    /// Case, accents and the Turkish dotless ı don't matter.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    /// "25", "25 dk", "25dk" → 25.
    private static func minutes(in text: String) -> Int? {
        let digits = text.replacingOccurrences(of: "dk", with: "").replacingOccurrences(of: "min", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Int(digits), (1...600).contains(value) else { return nil }
        return value
    }

    // MARK: Catalogs

    nonisolated private static func findApps() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0) } + [home.appending(path: "Applications")]
        var seen: Set<String> = []
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        .filter { seen.insert($0.lastPathComponent).inserted }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated private static func findShortcuts() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
