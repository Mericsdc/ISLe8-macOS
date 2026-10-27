import AppKit
import SwiftUI

/// A colour kept as "#RRGGBBAA", so a theme reads well as JSON and survives a round trip.
nonisolated struct ThemeColor: Codable, Hashable, Sendable {
    private(set) var hex: String

    init(_ hex: String) {
        self.hex = Self.normalized(hex) ?? "#000000FF"
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        hex = String(format: "#%02X%02X%02X%02X", byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent), byte(ns.alphaComponent))
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let hex = Self.normalized(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a colour: \(text)"))
        }
        self.hex = hex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    var nsColor: NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFF
        return NSColor(
            srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
            green: CGFloat((value >> 16) & 0xFF) / 255,
            blue: CGFloat((value >> 8) & 0xFF) / 255,
            alpha: CGFloat(value & 0xFF) / 255
        )
    }

    var color: Color { Color(nsColor: nsColor) }
    var isClear: Bool { hex.hasSuffix("00") }

    /// "#RGB", "#RRGGBB" or "#RRGGBBAA", with or without "#".
    private static func normalized(_ text: String) -> String? {
        var digits = text.trimmingCharacters(in: .whitespaces).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3: digits = digits.map { "\($0)\($0)" }.joined() + "FF"
        case 6: digits += "FF"
        case 8: break
        default: return nil
        }
        return "#" + digits
    }
}

/// How the open island looks. At rest the island is always black, so it blends with the notch.
nonisolated struct IslandTheme: Codable, Equatable, Identifiable, Sendable {
    enum Material: String, Codable, CaseIterable {
        /// Pure black, at one with the notch.
        case black
        case solid
        /// `background` at the top fading into `backgroundBottom`.
        case gradient
        /// Liquid Glass on macOS 26 and later.
        case glass
        /// A wash of the playing song's artwork colour.
        case artwork
    }

    enum Typeface: String, Codable, CaseIterable {
        case system
        case rounded
        case monospaced
        case serif

        var design: Font.Design {
            switch self {
            case .system: .default
            case .rounded: .rounded
            case .monospaced: .monospaced
            case .serif: .serif
            }
        }
    }

    var id: String
    var name: String
    var material: Material
    var background: ThemeColor
    var backgroundBottom: ThemeColor
    /// Cards and tiles.
    var surface: ThemeColor
    /// Hairline around cards; fully transparent for none.
    var border: ThemeColor
    var accent: ThemeColor
    var cornerRadius: Double
    var typeface: Typeface

    var isPreset: Bool { Self.presets.contains { $0.id == id } }

    // A theme file from an older or newer ISLe8 may lack fields; those take Notch Black's.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = Self.notchBlack
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? base.name
        material = (try? container.decodeIfPresent(Material.self, forKey: .material)) ?? base.material
        background = try container.decodeIfPresent(ThemeColor.self, forKey: .background) ?? base.background
        backgroundBottom = try container.decodeIfPresent(ThemeColor.self, forKey: .backgroundBottom) ?? background
        surface = try container.decodeIfPresent(ThemeColor.self, forKey: .surface) ?? base.surface
        border = try container.decodeIfPresent(ThemeColor.self, forKey: .border) ?? base.border
        accent = try container.decodeIfPresent(ThemeColor.self, forKey: .accent) ?? base.accent
        cornerRadius = min(max(try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? base.cornerRadius, 0), 26)
        typeface = (try? container.decodeIfPresent(Typeface.self, forKey: .typeface)) ?? base.typeface
    }

    init(
        id: String, name: String, material: Material,
        background: String, backgroundBottom: String? = nil,
        surface: String, border: String = "#FFFFFF00", accent: String,
        cornerRadius: Double = 16, typeface: Typeface = .system
    ) {
        self.id = id
        self.name = name
        self.material = material
        self.background = ThemeColor(background)
        self.backgroundBottom = ThemeColor(backgroundBottom ?? background)
        self.surface = ThemeColor(surface)
        self.border = ThemeColor(border)
        self.accent = ThemeColor(accent)
        self.cornerRadius = cornerRadius
        self.typeface = typeface
    }

    // MARK: Built-in themes

    static let notchBlack = IslandTheme(
        id: "notch-black", name: "Notch Black", material: .black,
        background: "#000000", surface: "#FFFFFF0F", accent: "#0A84FF"
    )

    static let presets: [IslandTheme] = [
        notchBlack,
        // After componest's agent card: graphite cards with a hairline, a soft blue.
        IslandTheme(
            id: "graphite", name: "Graphite", material: .solid,
            background: "#0E0E10", surface: "#18181B", border: "#FFFFFF17", accent: "#7AA7FF",
            cornerRadius: 14
        ),
        IslandTheme(
            id: "glass", name: "Liquid Glass", material: .glass,
            background: "#000000", surface: "#0000003D", border: "#FFFFFF29", accent: "#64D2FF",
            cornerRadius: 18
        ),
        IslandTheme(
            id: "artwork", name: String(localized: "Kapak rengi"), material: .artwork,
            background: "#000000", surface: "#FFFFFF12", accent: "#FF9F0A"
        ),
        // LRXe8: monochrome, sharp corners, technical type.
        IslandTheme(
            id: "lrx-mono", name: "LRX Mono", material: .black,
            background: "#000000", surface: "#0B0B0C", border: "#FFFFFF2B", accent: "#FFFFFF",
            cornerRadius: 6, typeface: .monospaced
        ),
        IslandTheme(
            id: "midnight", name: "Midnight", material: .gradient,
            background: "#0B1022", backgroundBottom: "#16204A", surface: "#FFFFFF0D", border: "#8FA6FF24",
            accent: "#8FA6FF", cornerRadius: 18, typeface: .rounded
        ),
        IslandTheme(
            id: "ember", name: "Ember", material: .gradient,
            background: "#110A08", backgroundBottom: "#2E140B", surface: "#FFFFFF0D", border: "#FF8A4C26",
            accent: "#FF8A4C"
        ),
    ]
}

extension EnvironmentValues {
    @Entry var islandTheme: IslandTheme = .notchBlack
}

/// A card or tile in the theme's surface colour, with its hairline and corner radius.
struct IslandCard: ViewModifier {
    @Environment(\.islandTheme) private var theme
    var radius: Double?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.cornerRadius, style: .continuous)
        content
            .background(shape.fill(theme.surface.color))
            .overlay {
                if !theme.border.isClear {
                    shape.strokeBorder(theme.border.color, lineWidth: 1)
                }
            }
    }
}

extension View {
    func islandTile(radius: Double? = nil) -> some View {
        modifier(IslandCard(radius: radius))
    }
}
