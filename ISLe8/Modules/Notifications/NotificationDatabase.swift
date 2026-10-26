import Foundation
import SQLite3

/// A notification another app posted, as Notification Center stored it.
nonisolated struct AppNotification: Identifiable, Equatable, Sendable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date

    /// Subtitle and body on one line, the way a banner shows them.
    var detail: String {
        [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Reads other apps' notifications from the database Notification Center keeps. macOS has
/// no API for this; the database is the only source, and reading it needs Full Disk Access.
///
/// The database files are watched with kernel events (kqueue), so nothing runs until
/// Notification Center writes. FSEvents would not work here: it reports a change when a file
/// is closed, and usernoted keeps its database open for good. All work happens on `queue`,
/// never on the main thread, and all state is touched only there.
nonisolated final class NotificationDatabase: @unchecked Sendable {
    enum Access: Sendable {
        case granted
        case needsFullDiskAccess
        /// The database is missing or laid out differently than expected.
        case unavailable
    }

    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Group Containers/group.com.apple.usernoted/db2", directoryHint: .isDirectory)

    private let queue = DispatchQueue(label: "com.lrxe8.isle8.notifications", qos: .utility)
    private let diagnosticsURL: URL
    private var db: OpaquePointer?
    private var sources: [DispatchSourceFileSystemObject] = []
    /// Inodes of the files being watched; a new inode means SQLite recreated the file.
    private var watchedInodes: [String: ino_t] = [:]
    private var pendingRead: DispatchWorkItem?
    private var lastID: Int64 = 0
    private var hasDeliveredDate = false
    private var onNew: (@Sendable ([AppNotification]) -> Void)?

    // Counters for notification-status.txt: numbers only, never content.
    private let statusURL: URL
    private var isWatching = false
    private var eventCount = 0
    private var deliveredCount = 0
    private var skippedCount = 0
    private var lastStatusWrite = Date.distantPast

    init(diagnosticsURL: URL) {
        self.diagnosticsURL = diagnosticsURL
        statusURL = diagnosticsURL.deletingLastPathComponent().appending(path: "notification-status.txt")
    }

    func start(
        onAccess: @escaping @Sendable (Access) -> Void,
        onNew: @escaping @Sendable ([AppNotification]) -> Void
    ) {
        queue.async { [self] in
            self.onNew = onNew
            let access = open()
            onAccess(access)
            guard access == .granted else { return }
            // Only what arrives from now on is shown.
            lastID = maxID()
            writeDiagnostics()
            startWatching()
            writeStatus(force: true)
        }
    }

    func stop() {
        queue.async { [self] in
            pendingRead?.cancel()
            sources.forEach { $0.cancel() }
            sources.removeAll()
            sqlite3_close(db)
            db = nil
            onNew = nil
        }
    }

    // MARK: Opening

    private func open() -> Access {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path)
        } catch CocoaError.fileReadNoPermission {
            return .needsFullDiskAccess
        } catch {
            let code = (error as NSError).underlyingErrors.first.map { ($0 as NSError).code }
            return code == Int(EPERM) || code == Int(EACCES) ? .needsFullDiskAccess : .unavailable
        }

        var connection: OpaquePointer?
        let path = Self.folder.appending(path: "db").path
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            return .unavailable
        }
        db = connection

        let recordColumns = columns(of: "record")
        guard recordColumns.isSuperset(of: ["rec_id", "app_id", "data"]),
              columns(of: "app").isSuperset(of: ["app_id", "identifier"])
        else {
            NSLog("ISLe8: the notification database has an unexpected layout")
            sqlite3_close(db)
            db = nil
            return .unavailable
        }
        hasDeliveredDate = recordColumns.contains("delivered_date")
        return .granted
    }

    /// New notifications are appended to the write-ahead log (db-wal); checkpoints write the
    /// database itself. The folder is watched too, for files that appear or are replaced.
    private func startWatching() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        watchedInodes.removeAll()
        for name in ["db-wal", "db"] {
            let path = Self.folder.appending(path: name).path
            if watch(path, events: [.write, .extend, .delete, .rename]) {
                watchedInodes[path] = Self.inode(of: path)
            }
        }
        _ = watch(Self.folder.path, events: [.write])
        isWatching = !watchedInodes.isEmpty
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> Bool {
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler { [weak self] in
            self?.changed()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        source.resume()
        sources.append(source)
        return true
    }

    /// A transaction writes the log several times in a row; read once it has settled.
    private func changed() {
        eventCount += 1
        pendingRead?.cancel()
        let read = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if watchedFilesWereReplaced() {
                startWatching()
            }
            readNew()
        }
        pendingRead = read
        queue.asyncAfter(deadline: .now() + 0.15, execute: read)
    }

    private func watchedFilesWereReplaced() -> Bool {
        ["db-wal", "db"].contains { name in
            let path = Self.folder.appending(path: name).path
            return Self.inode(of: path) != watchedInodes[path]
        }
    }

    private static func inode(of path: String) -> ino_t? {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_ino : nil
    }

    /// How the watcher is doing, for diagnosing a reader that stays silent. At most every
    /// two seconds unless something was delivered.
    private func writeStatus(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStatusWrite) >= 2 else { return }
        lastStatusWrite = now
        let lines = [
            "Notification reader status, written \(now)",
            "watching: \(isWatching)",
            "file events: \(eventCount)",
            "newest record id: \(maxID()), last read id: \(lastID)",
            "delivered: \(deliveredCount), skipped (no text or unreadable): \(skippedCount)",
            "watched inodes: \(watchedInodes.map { "\(URL(fileURLWithPath: $0.key).lastPathComponent)=\($0.value)" }.sorted().joined(separator: ", "))",
            "files:",
        ] + Self.folderListing()
        try? lines.joined(separator: "\n").write(to: statusURL, atomically: true, encoding: .utf8)
    }

    /// Name, size, modification time and inode of each file in the database folder.
    private static func folderListing() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().map { name in
            var info = stat()
            guard stat(folder.appending(path: name).path, &info) == 0 else { return "  \(name): ?" }
            return "  \(name): \(info.st_size) bytes, modified \(info.st_mtimespec.tv_sec), inode \(info.st_ino)"
        }
    }

    // MARK: Reading

    /// Runs on `queue` shortly after the database files change.
    private func readNew() {
        guard db != nil, let onNew else { return }
        defer { writeStatus() }
        // usernoted sometimes rebuilds its database, which restarts the IDs.
        let newest = maxID()
        if newest < lastID {
            lastID = newest
            return
        }
        guard newest > lastID else { return }

        let date = hasDeliveredDate ? "r.delivered_date" : "NULL"
        let sql = """
            SELECT r.rec_id, a.identifier, r.data, \(date)
            FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 20
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lastID)

        var notifications: [AppNotification] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            lastID = max(lastID, id)
            guard let bundleID = Self.string(statement, 1), let data = Self.data(statement, 2) else { continue }
            let delivered = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            if let notification = Self.decode(id: id, bundleID: bundleID, data: data, delivered: delivered) {
                notifications.append(notification)
            } else {
                skippedCount += 1
            }
        }
        lastID = max(lastID, newest)
        if !notifications.isEmpty {
            deliveredCount += notifications.count
            lastStatusWrite = .distantPast
            onNew(notifications)
        }
    }

    /// The record's `data` is a binary plist; the notification itself sits under "req".
    static func decode(id: Int64, bundleID: String, data: Data, delivered: Double?) -> AppNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let request = plist["req"] as? [String: Any] ?? [:]
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        // Stored as seconds since 2001, like every Cocoa date.
        let date = delivered.map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date()
        return AppNotification(id: id, bundleID: bundleID, title: title, subtitle: subtitle, body: body, date: date)
    }

    // MARK: Helpers

    private func maxID() -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT max(rec_id) FROM record", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
    }

    private func columns(of table: String) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = Self.string(statement, 1) {
                names.insert(name)
            }
        }
        return names
    }

    /// Records the database layout (table, column and plist key names, never content) so a
    /// layout change in a future macOS can be diagnosed.
    private func writeDiagnostics() {
        var lines = ["Notification database layout, written \(Date())"]
        for table in ["app", "record"] {
            lines.append("\(table): \(columns(of: table).sorted().joined(separator: ", "))")
        }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT data FROM record ORDER BY rec_id DESC LIMIT 1", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW, let data = Self.data(statement, 0),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                lines.append("record.data keys: \(plist.keys.sorted().joined(separator: ", "))")
                if let request = plist["req"] as? [String: Any] {
                    lines.append("record.data.req keys: \(request.keys.sorted().joined(separator: ", "))")
                }
            }
            sqlite3_finalize(statement)
        }
        try? lines.joined(separator: "\n").write(to: diagnosticsURL, atomically: true, encoding: .utf8)
    }

    private static func string(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private static func data(_ statement: OpaquePointer?, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

/// Whether a Focus is on. Focus switched on by hand is recorded in this file; a Focus that
/// starts on a schedule is not, so it can't be detected here.
nonisolated enum FocusStatus {
    static func isActive() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else { return false }
        return entries.contains { ($0["storeAssertionRecords"] as? [Any])?.isEmpty == false }
    }
}
