import Foundation

/// Days celebrated around the world, each with its own decoration on the open island. Only
/// global ones, not a single country's.
nonisolated enum Occasion: String, CaseIterable, Identifiable, Sendable {
    case valentines
    case stPatricks
    case easter
    case halloween
    case lunarNewYear
    case winter
    case newYear

    var id: String { rawValue }

    var name: String {
        switch self {
        case .valentines: String(localized: "Sevgililer Günü")
        case .stPatricks: String(localized: "Aziz Patrick Günü")
        case .easter: String(localized: "Paskalya")
        case .halloween: String(localized: "Cadılar Bayramı")
        case .lunarNewYear: String(localized: "Ay Yeni Yılı")
        case .winter: String(localized: "Kış tatili")
        case .newYear: String(localized: "Yılbaşı")
        }
    }

    /// When it shows, for Settings.
    var period: String {
        switch self {
        case .valentines: String(localized: "13–14 Şubat")
        case .stPatricks: String(localized: "16–17 Mart")
        case .easter: String(localized: "Paskalya'dan önceki cumadan pazara")
        case .halloween: String(localized: "24–31 Ekim")
        case .lunarNewYear: String(localized: "Ay Yeni Yılı'nın bir gün öncesinden iki gün sonrasına")
        case .winter: String(localized: "20–30 Aralık, 2–6 Ocak")
        case .newYear: String(localized: "31 Aralık – 1 Ocak")
        }
    }

    /// The day's own look while it lasts: a dark gradient deepening into its colour, its
    /// accent (today in the calendar, the selected tab, the play ring) and the glow along the
    /// island's edge. Corner rounding and type stay the user's.
    func theme(over base: IslandTheme) -> IslandTheme {
        let (top, bottom, accent, glow) = palette
        return IslandTheme(
            id: "occasion-\(rawValue)", name: name, material: .gradient,
            background: top, backgroundBottom: bottom,
            surface: "#FFFFFF10", border: glow + "40", accent: accent,
            cornerRadius: base.cornerRadius, typeface: base.typeface
        )
    }

    /// Top, bottom, accent, glow.
    var palette: (String, String, String, String) {
        switch self {
        case .valentines: ("#2B0710", "#4D0A1F", "#FF2D55", "#FF2D55")
        case .stPatricks: ("#04170B", "#0B3D1C", "#22C55E", "#22C55E")
        case .easter: ("#15150A", "#3B3410", "#F59E0B", "#FBBF24")
        case .halloween: ("#1A0A03", "#3F1505", "#F97316", "#FB923C")
        case .lunarNewYear: ("#2A0303", "#5C0A07", "#EF4444", "#F59E0B")
        case .winter: ("#06142B", "#0E2C55", "#3B82F6", "#60A5FA")
        case .newYear: ("#0E0820", "#2E1065", "#FBBF24", "#C084FC")
        }
    }

    /// The occasion on `date`, if any. New Year's Eve and Day win over the winter snow.
    static func current(on date: Date = .now) -> Occasion? {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        switch (month, day) {
        case (2, 13...14): return .valentines
        case (3, 16...17): return .stPatricks
        case (10, 24...31): return .halloween
        case (12, 31), (1, 1): return .newYear
        case (12, 20...30), (1, 2...6): return .winter
        default: break
        }
        let today = calendar.startOfDay(for: date)
        if let sunday = easterSunday(year), let friday = calendar.date(byAdding: .day, value: -2, to: sunday),
           today >= friday, today <= sunday {
            return .easter
        }
        if let newYear = lunarNewYear(year),
           let start = calendar.date(byAdding: .day, value: -1, to: newYear),
           let end = calendar.date(byAdding: .day, value: 2, to: newYear),
           today >= start, today <= end {
            return .lunarNewYear
        }
        return nil
    }

    /// Western Easter Sunday (the anonymous Gregorian algorithm).
    private static func easterSunday(_ year: Int) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The first day of the first month in the Chinese calendar, which falls between 21
    /// January and 20 February.
    private static func lunarNewYear(_ year: Int) -> Date? {
        let gregorian = Calendar(identifier: .gregorian)
        let chinese = Calendar(identifier: .chinese)
        guard var day = gregorian.date(from: DateComponents(year: year, month: 1, day: 20)) else { return nil }
        for _ in 0..<33 {
            let parts = chinese.dateComponents([.month, .day, .isLeapMonth], from: day)
            if parts.month == 1, parts.day == 1, parts.isLeapMonth != true {
                return gregorian.startOfDay(for: day)
            }
            guard let next = gregorian.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}
