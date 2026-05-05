import Foundation
import SQLite3

struct LinkHistoryEntry: Identifiable {
    var id: UUID
    var timestamp: Date
    var url: String
    var scheme: String
    var host: String
    var path: String
    var query: String
    var sourceBundleId: String
    var sourceAppName: String
    var modifiers: String
    var timeOfDay: String
    var dayOfWeek: String
    var runningApps: [String]
    var matchedRuleId: String?
    var matchedRuleName: String?
    var targetBundleId: String?
    var targetProfileId: String?
    var targetBrowserName: String?
}

@MainActor
class LinkHistory: ObservableObject {
    @Published var entries: [LinkHistoryEntry] = []

    static let shared = LinkHistory()

    private var db: OpaquePointer?

    private static var dbURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("HrefTo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.db")
    }

    func open() {
        let url = Self.dbURL
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            print("[HrefTo] Failed to open history database")
            return
        }

        let createTable = """
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                url TEXT NOT NULL,
                scheme TEXT NOT NULL DEFAULT '',
                host TEXT NOT NULL DEFAULT '',
                path TEXT NOT NULL DEFAULT '',
                query TEXT NOT NULL DEFAULT '',
                source_bundle_id TEXT NOT NULL DEFAULT '',
                source_app_name TEXT NOT NULL DEFAULT '',
                modifiers TEXT NOT NULL DEFAULT '',
                time_of_day TEXT NOT NULL DEFAULT '',
                day_of_week TEXT NOT NULL DEFAULT '',
                running_apps TEXT NOT NULL DEFAULT '',
                matched_rule_id TEXT,
                matched_rule_name TEXT,
                target_bundle_id TEXT,
                target_profile_id TEXT,
                target_browser_name TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_history_timestamp ON history(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_history_host ON history(host);
            CREATE INDEX IF NOT EXISTS idx_history_source ON history(source_bundle_id);
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTable, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            print("[HrefTo] Failed to create history table: \(msg)")
            sqlite3_free(errMsg)
        }
    }

    func record(entry: LinkHistoryEntry) {
        guard let db = db else { return }

        let sql = """
            INSERT INTO history (id, timestamp, url, scheme, host, path, query,
                source_bundle_id, source_app_name, modifiers, time_of_day, day_of_week,
                running_apps, matched_rule_id, matched_rule_name,
                target_bundle_id, target_profile_id, target_browser_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let runningAppsStr = entry.runningApps.joined(separator: "\n")

        sqlite3_bind_text(stmt, 1, entry.id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, entry.url, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, entry.scheme, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, entry.host, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 6, entry.path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 7, entry.query, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 8, entry.sourceBundleId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 9, entry.sourceAppName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 10, entry.modifiers, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 11, entry.timeOfDay, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 12, entry.dayOfWeek, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 13, runningAppsStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        bindOptionalText(stmt, 14, entry.matchedRuleId)
        bindOptionalText(stmt, 15, entry.matchedRuleName)
        bindOptionalText(stmt, 16, entry.targetBundleId)
        bindOptionalText(stmt, 17, entry.targetProfileId)
        bindOptionalText(stmt, 18, entry.targetBrowserName)

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[HrefTo] Failed to insert history entry")
        }
    }

    func loadRecent(limit: Int = 100) -> [LinkHistoryEntry] {
        guard let db = db else { return [] }

        let sql = "SELECT * FROM history ORDER BY timestamp DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [LinkHistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = LinkHistoryEntry(
                id: UUID(uuidString: columnText(stmt, 0)) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                url: columnText(stmt, 2),
                scheme: columnText(stmt, 3),
                host: columnText(stmt, 4),
                path: columnText(stmt, 5),
                query: columnText(stmt, 6),
                sourceBundleId: columnText(stmt, 7),
                sourceAppName: columnText(stmt, 8),
                modifiers: columnText(stmt, 9),
                timeOfDay: columnText(stmt, 10),
                dayOfWeek: columnText(stmt, 11),
                runningApps: columnText(stmt, 12).split(separator: "\n").map(String.init),
                matchedRuleId: columnOptionalText(stmt, 13),
                matchedRuleName: columnOptionalText(stmt, 14),
                targetBundleId: columnOptionalText(stmt, 15),
                targetProfileId: columnOptionalText(stmt, 16),
                targetBrowserName: columnOptionalText(stmt, 17)
            )
            results.append(entry)
        }
        return results
    }

    func clear() {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM history", nil, nil, nil)
        entries = []
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Helpers

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}
