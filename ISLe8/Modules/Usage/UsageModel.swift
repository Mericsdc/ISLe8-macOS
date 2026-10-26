import AppKit
import CoreFoundation
import Foundation

// Ported from LimitBar LRX's Model.swift (see UsageModule.swift for the credit).

/// A service whose usage limits are shown. Each one is asked only through its own official CLI.
nonisolated enum UsageVendor: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex, claude, gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    /// The CLI that is asked, and the one the login hint names.
    var cli: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .gemini: "agy"
        }
    }

    /// The product the limits belong to.
    var product: String {
        switch self {
        case .codex: "ChatGPT"
        case .claude: "Claude Code"
        case .gemini: "Antigravity"
        }
    }

    /// Signing in stays with the CLI; ISLe8 never asks for credentials.
    var loginHint: String {
        switch self {
        case .codex: String(localized: "Terminal’de codex login çalıştır")
        case .claude: String(localized: "Terminal’de claude auth login çalıştır")
        case .gemini: String(localized: "Terminal’de agy ile giriş yap")
        }
    }

    /// The mark's file name in the bundle. Prefixed, because the synchronized group copies every
    /// resource flat into Contents/Resources, where a plain "claude.svg" could collide.
    var markName: String {
        switch self {
        case .codex: "usage-openai"
        case .claude: "usage-claude"
        case .gemini: "usage-gemini"
        }
    }

    /// The vendor's mark (simple-icons, CC0) as a 16 pt template image; nil if it can't be loaded.
    @MainActor var markImage: NSImage? { UsageMarks.image(self) }
}

/// Loaded once per vendor: views ask for the mark on every render.
private enum UsageMarks {
    private static var cache: [UsageVendor: NSImage?] = [:]

    static func image(_ vendor: UsageVendor) -> NSImage? {
        if let cached = cache[vendor] { return cached }
        let url = Bundle.main.url(forResource: vendor.markName, withExtension: "svg", subdirectory: "usage-marks")
            ?? Bundle.main.url(forResource: vendor.markName, withExtension: "svg")
        let image = url.flatMap { NSImage(contentsOf: $0) }
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        cache[vendor] = image
        return image
    }
}

/// Why a vendor shows no numbers. `ok` = the CLI answered.
nonisolated enum UsageState: String, Codable, Sendable {
    case ok
    /// CLI not found.
    case missing
    /// Found, but owned by another account or writable by others: never run.
    case untrusted
    /// The CLI says nobody is signed in.
    case signedOut
    /// It ran and did not give limits (timeout, error, changed format). Previous numbers are kept.
    case failed
}

/// Where a snapshot's numbers came from: a fixed label, never a path or CLI output.
nonisolated enum UsageSource: String, Codable, Sendable {
    /// The CLI was asked.
    case live
    /// Codex wrote them into its own session log.
    case localSession

    var label: String {
        switch self {
        case .live: String(localized: "Canlı sorgu")
        case .localSession: String(localized: "Yerel oturum")
        }
    }
}

/// One limit window as the vendor reports it.
nonisolated struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    /// What the vendor calls the window. Kept apart from the display text so the cache stays
    /// readable after a language change.
    enum Kind: Codable, Equatable, Hashable, Sendable {
        case fiveHour
        case week
        /// Claude's weekly limit for one model family, e.g. "Opus".
        case modelWeek(String)
        /// A Codex window of another length.
        case minutes(Int)
        /// A Codex window that gives no length.
        case quota
        /// An Antigravity model group, named by Google.
        case group(String)
    }

    var kind: Kind
    /// Weekly rather than 5-hour, for the small "haftalık" / "5 saat" tag.
    var isWeekly: Bool
    /// Percent USED, 0–100. nil = the vendor gave none, which is not 0 %.
    var used: Double?
    var resetsAt: Date?

    var id: String {
        let name = switch kind {
        case .fiveHour: "5-hour"
        case .week: "week"
        case .modelWeek(let model): "week:\(model)"
        case .minutes(let minutes): "minutes:\(minutes)"
        case .quota: "quota"
        case .group(let group): "group:\(group)"
        }
        return "\(name)|\(isWeekly ? "w" : "5h")"
    }

    var label: String {
        switch kind {
        case .fiveHour: String(localized: "5 saat")
        case .week: String(localized: "Haftalık")
        case .modelWeek(let model): String(localized: "\(model) haftalık")
        case .minutes(let minutes): String(localized: "\(minutes) dk")
        case .quota: String(localized: "Kota")
        case .group(let group): group
        }
    }

    /// The window's length, for a secondary tag next to a group name.
    var periodLabel: String {
        isWeekly ? String(localized: "haftalık") : String(localized: "5 saat")
    }

    var remaining: Double? { used.map { max(0, 100 - $0) } }

    /// The reset time has passed since it was read: the old percent is obsolete, not "0 %".
    var resetPassed: Bool { resetsAt.map { $0 < Date() } ?? false }

    /// At or above 90 % and still current.
    var isHot: Bool { !resetPassed && (used ?? 0) >= 90 }

    /// Rounded, but 99.6 % must never read as 100 %.
    static func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        let rounded = value.rounded()
        return String(Int(rounded >= 100 && value < 100 ? 99 : rounded))
    }
}

nonisolated struct UsageSnapshot: Codable, Equatable, Sendable, Identifiable {
    var vendor: UsageVendor
    var state: UsageState = .ok
    /// From the CLI's own answer: "Max", "ChatGPT Plus". Nothing else of the account is kept.
    var plan: String = ""
    /// The window to show when there is room for one.
    var bar: UsageWindow?
    /// Every window, `bar` first.
    var windows: [UsageWindow] = []
    /// E.g. "2 ücretsiz kota sıfırlama · son kullanım yarın 09:00".
    var notes: [String] = []
    /// When the vendor's numbers were taken, not when they were looked at.
    var measuredAt: Date?
    /// The last failure, one of our own fixed texts; previous numbers are kept beside it.
    var error: String?
    var source: UsageSource?

    var id: UsageVendor { vendor }

    /// A window other than `bar` is at 90 % or more.
    var otherHot: Bool {
        windows.contains { $0 != bar && $0.isHot }
    }

    static func status(_ vendor: UsageVendor, _ state: UsageState, _ error: String? = nil) -> UsageSnapshot {
        UsageSnapshot(vendor: vendor, state: state, error: error)
    }
}

/// Numbers from a CLI are only used when they are finite, and percentages only within 0…100.
nonisolated enum UsageNumber {
    static func finite(_ any: Any?) -> Double? {
        if let number = any as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let value: Double? = switch any {
        case let double as Double: double
        case let int as Int: Double(int)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
        guard let value, value.isFinite else { return nil }
        return value
    }

    static func percent(_ any: Any?) -> Double? {
        guard let value = finite(any), value >= 0, value <= 100 else { return nil }
        return value
    }
}
