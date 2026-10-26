import AppKit

/// Names and icons of installed apps by bundle ID, looked up once each.
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func name(for bundleID: String) -> String {
        if let name = names[bundleID] {
            return name
        }
        let name = url(for: bundleID).map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        names[bundleID] = trimmed
        return trimmed
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let icon = icons[bundleID] {
            return icon
        }
        guard let url = url(for: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    static func open(_ bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
