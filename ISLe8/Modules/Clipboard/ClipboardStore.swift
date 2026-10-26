import Foundation
import SQLite3

/// The clipboard history on disk: one SQLite table with an FTS5 index for search. Images
/// are PNG files in a folder next to the database.
final class ClipboardStore {
    private enum Value {
        case text(String)
        case real(Double)
        case integer(Int64)
        case blob(Data)
        case null
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let previewLength = 300

    let imagesFolder: URL
    private var db: OpaquePointer?

    init?(folder: URL) {
        imagesFolder = folder.appending(path: "Clipboard", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        let path = folder.appending(path: "clipboard.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            NSLog("ISLe8: could not open the clipboard database")
            sqlite3_close(db)
            return nil
        }
        // Version 1 indexed the raw text, so "toplanti" never found "toplantı". Nothing had
        // been released with it, so it is simply rebuilt.
        let reset = Self.userVersion(of: db) < 2 ? """
            DROP TRIGGER IF EXISTS items_ai;
            DROP TRIGGER IF EXISTS items_ad;
            DROP TABLE IF EXISTS items_fts;
            DROP TABLE IF EXISTS items;
            """ : ""
        let schema = reset + """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY,
                kind TEXT NOT NULL,
                text TEXT NOT NULL,
                search TEXT NOT NULL,
                rtf BLOB,
                image TEXT,
                hash TEXT NOT NULL UNIQUE,
                app TEXT,
                created REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                search, content = 'items', content_rowid = 'id',
                tokenize = 'unicode61 remove_diacritics 2'
            );
            CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                INSERT INTO items_fts(rowid, search) VALUES (new.id, new.search);
            END;
            CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                INSERT INTO items_fts(items_fts, rowid, search) VALUES ('delete', old.id, old.search);
            END;
            PRAGMA user_version = 2;
            """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            NSLog("ISLe8: could not set up the clipboard database: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return nil
        }
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: Reading

    /// Newest first, pinned items on top. `query` matches word prefixes, ignoring case and accents.
    func items(matching query: String, limit: Int) -> [ClipboardItem] {
        let columns = "id, kind, substr(text, 1, \(Self.previewLength)), image, app, created, pinned"
        if let match = Self.ftsQuery(query) {
            return rows(
                """
                SELECT \(columns) FROM items
                WHERE id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)
                ORDER BY pinned DESC, created DESC LIMIT ?
                """,
                [.text(match), .integer(Int64(limit))],
                Self.item
            )
        }
        return rows(
            "SELECT \(columns) FROM items ORDER BY pinned DESC, created DESC LIMIT ?",
            [.integer(Int64(limit))],
            Self.item
        )
    }

    func content(of id: Int64) -> (text: String, rtf: Data?, imageName: String?)? {
        rows("SELECT text, rtf, image FROM items WHERE id = ?", [.integer(id)]) { statement in
            (Self.string(statement, 0) ?? "", Self.data(statement, 1), Self.string(statement, 2))
        }.first
    }

    func id(forHash hash: String) -> Int64? {
        rows("SELECT id FROM items WHERE hash = ?", [.text(hash)]) { sqlite3_column_int64($0, 0) }.first
    }

    // MARK: Writing

    func insert(_ capture: ClipboardCapture, imageName: String?, app: String?, at date: Date) {
        run(
            "INSERT INTO items (kind, text, search, rtf, image, hash, app, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
                .text(capture.kind.rawValue),
                .text(capture.text),
                .text(Self.fold(capture.text)),
                capture.rtf.map(Value.blob) ?? .null,
                imageName.map(Value.text) ?? .null,
                .text(capture.hash),
                app.map(Value.text) ?? .null,
                .real(date.timeIntervalSince1970),
            ]
        )
    }

    /// Moves an item to the top, as if it had just been copied.
    func touch(_ id: Int64, at date: Date, app: String?) {
        run("UPDATE items SET created = ?, app = coalesce(?, app) WHERE id = ?", [
            .real(date.timeIntervalSince1970), app.map(Value.text) ?? .null, .integer(id),
        ])
    }

    func setPinned(_ id: Int64, _ pinned: Bool) {
        run("UPDATE items SET pinned = ? WHERE id = ?", [.integer(pinned ? 1 : 0), .integer(id)])
    }

    func delete(_ id: Int64) {
        deleteRows("SELECT id, image FROM items WHERE id = ?", [.integer(id)])
    }

    func deleteAll(keepingPinned: Bool) {
        deleteRows(keepingPinned ? "SELECT id, image FROM items WHERE pinned = 0" : "SELECT id, image FROM items", [])
    }

    /// Drops unpinned items beyond the newest `limit` and those older than `maxAge`.
    func prune(keeping limit: Int, maxAge: TimeInterval) {
        let cutoff = Date().timeIntervalSince1970 - maxAge
        deleteRows("SELECT id, image FROM items WHERE pinned = 0 AND created < ?", [.real(cutoff)])
        deleteRows(
            "SELECT id, image FROM items WHERE pinned = 0 ORDER BY created DESC LIMIT -1 OFFSET ?",
            [.integer(Int64(limit))]
        )
    }

    private func deleteRows(_ selection: String, _ values: [Value]) {
        let doomed = rows(selection, values) { (sqlite3_column_int64($0, 0), Self.string($0, 1)) }
        for (id, image) in doomed {
            run("DELETE FROM items WHERE id = ?", [.integer(id)])
            if let image {
                try? FileManager.default.removeItem(at: imagesFolder.appending(path: image))
            }
        }
    }

    // MARK: SQLite plumbing

    private func prepare(_ sql: String, _ values: [Value]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            NSLog("ISLe8: SQL error: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .real(let number):
                sqlite3_bind_double(statement, index, number)
            case .integer(let number):
                sqlite3_bind_int64(statement, index, number)
            case .blob(let data):
                data.withUnsafeBytes { bytes in
                    _ = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
                }
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) {
        guard let statement = prepare(sql, values) else { return }
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_DONE {
            NSLog("ISLe8: SQL error: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func rows<T>(_ sql: String, _ values: [Value], _ read: (OpaquePointer) -> T) -> [T] {
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(read(statement))
        }
        return result
    }

    private static func item(_ statement: OpaquePointer) -> ClipboardItem {
        ClipboardItem(
            id: sqlite3_column_int64(statement, 0),
            kind: ClipboardItem.Kind(rawValue: string(statement, 1) ?? "") ?? .text,
            preview: string(statement, 2) ?? "",
            imageName: string(statement, 3),
            sourceApp: string(statement, 4),
            copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
            isPinned: sqlite3_column_int(statement, 6) != 0
        )
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private static func data(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    /// Every word becomes a quoted prefix search; all of them have to match.
    private static func ftsQuery(_ text: String) -> String? {
        let terms = fold(text).split(whereSeparator: \.isWhitespace).map { term in
            "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
        }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    /// The FTS tokenizer folds case and accents (ş → s, İ → i) but treats the dotless ı as
    /// a letter of its own. Folding it here lets "toplanti" find "toplantı" and vice versa.
    private static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "I", with: "i")
    }

    private static func userVersion(of db: OpaquePointer?) -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
    }
}
