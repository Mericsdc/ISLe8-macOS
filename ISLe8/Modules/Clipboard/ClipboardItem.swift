import AppKit

/// One entry of the clipboard history, as the list shows it. The full content stays in the
/// database until it is copied back.
struct ClipboardItem: Identifiable, Equatable {
    enum Kind: String {
        case text
        case richText
        case url
        case image
        case files
    }

    let id: Int64
    var kind: Kind
    /// The start of the text, or the file paths. Empty for images.
    var preview: String
    var imageName: String?
    var sourceApp: String?
    var copiedAt: Date
    var isPinned: Bool

    /// One line for the list: whitespace runs collapsed, file paths reduced to names.
    var title: String {
        switch kind {
        case .image:
            return String(localized: "Görsel")
        case .files:
            let names = preview.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
            return names.joined(separator: ", ")
        case .text, .richText, .url:
            return preview.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    /// The color, when the whole text is a hex color such as #FF9F0A.
    var color: NSColor? {
        guard kind == .text else { return nil }
        var hex = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var emailAddress: String? {
        guard kind == .text else { return nil }
        let text = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmail = text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        return isEmail ? text : nil
    }
}

/// What was read off the pasteboard, ready to be stored.
struct ClipboardCapture {
    var kind: ClipboardItem.Kind
    var text: String
    var rtf: Data?
    var imagePNG: Data?
    /// Identifies the content, so copying the same thing again only moves it to the top.
    var hash: String
}
