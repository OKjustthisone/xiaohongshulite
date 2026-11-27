import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open SQLite database: \(msg)"
        case .prepareFailed(let msg): return "Failed to prepare SQLite statement: \(msg)"
        case .stepFailed(let msg): return "Failed to execute SQLite statement: \(msg)"
        }
    }
}

public final class DatabaseStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.rednotelite.database", qos: .userInitiated)
    private var db: OpaquePointer?
    public let path: String

    public static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("RedNoteLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rednotelite.sqlite")
    }

    public init(path: String = DatabaseStore.defaultDatabaseURL().path) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let errMsg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(handle)
            throw DatabaseError.openFailed(errMsg)
        }
        self.db = handle
        try configureAndMigrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func configureAndMigrate() throws {
        try queue.sync {
            // Keep SQLite memory footprint under ~1 MB and enable WAL for fast writes
            try executeRaw("PRAGMA journal_mode = WAL;")
            try executeRaw("PRAGMA synchronous = NORMAL;")
            try executeRaw("PRAGMA cache_size = -1024;")
            try executeRaw("PRAGMA temp_store = FILE;")

            try executeRaw("""
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY,
                note_id TEXT,
                url TEXT NOT NULL,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                cover_url TEXT,
                excerpt TEXT NOT NULL,
                visited_at REAL NOT NULL,
                visit_count INTEGER NOT NULL DEFAULT 1,
                is_video INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_history_visited_at ON history(visited_at DESC);
            """)

            try executeRaw("""
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY,
                note_id TEXT,
                url TEXT NOT NULL,
                title TEXT NOT NULL,
                author TEXT NOT NULL,
                cover_url TEXT,
                excerpt TEXT NOT NULL,
                folder TEXT NOT NULL DEFAULT '默认收藏',
                memo TEXT NOT NULL DEFAULT '',
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_video INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_collections_updated_at ON collections(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_collections_folder ON collections(folder);
            """)

            // Safe non-destructive migration for existing databases created prior to is_video column
            _ = try? executeRaw("ALTER TABLE history ADD COLUMN is_video INTEGER NOT NULL DEFAULT 0;")
            _ = try? executeRaw("ALTER TABLE collections ADD COLUMN is_video INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private func executeRaw(_ sql: String) throws {
        guard let db else { return }
        var errPtr: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errPtr) != SQLITE_OK {
            let msg = errPtr.map { String(cString: $0) } ?? "SQL execution error"
            sqlite3_free(errPtr)
            throw DatabaseError.stepFailed(msg)
        }
    }

    // MARK: - History Operations

    public func recordHistory(
        url: String,
        noteId: String? = nil,
        title: String,
        author: String = "",
        coverURL: String? = nil,
        excerpt: String = "",
        isVideo: Bool = false,
        visitedAt: Date = Date(),
        maxItems: Int = 500
    ) throws {
        let resolvedNoteId = noteId ?? XHSURLClassifier.extractNoteId(from: url)
        let key = XHSURLClassifier.canonicalKey(for: url)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (resolvedNoteId.map { "笔记 \($0.prefix(8))" } ?? url)
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        try queue.sync {
            guard let db else { return }
            let sql = """
            INSERT INTO history (id, note_id, url, title, author, cover_url, excerpt, visited_at, visit_count, is_video)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1, ?9)
            ON CONFLICT(id) DO UPDATE SET
                url = excluded.url,
                title = CASE WHEN length(excluded.title) > 0 THEN excluded.title ELSE history.title END,
                author = CASE WHEN length(excluded.author) > 0 THEN excluded.author ELSE history.author END,
                cover_url = COALESCE(NULLIF(excluded.cover_url, ''), history.cover_url),
                excerpt = CASE WHEN length(excluded.excerpt) > 0 THEN excluded.excerpt ELSE history.excerpt END,
                visited_at = excluded.visited_at,
                visit_count = history.visit_count + 1,
                is_video = CASE WHEN excluded.is_video = 1 THEN 1 ELSE history.is_video END;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, key)
            bindOptionalText(stmt, 2, resolvedNoteId)
            bindText(stmt, 3, url)
            bindText(stmt, 4, cleanTitle)
            bindText(stmt, 5, author)
            bindOptionalText(stmt, 6, coverURL)
            bindText(stmt, 7, excerpt)
            sqlite3_bind_double(stmt, 8, visitedAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 9, isVideo ? 1 : 0)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }

            if maxItems > 0 {
                let pruneSQL = """
                DELETE FROM history WHERE id NOT IN (
                    SELECT id FROM history ORDER BY visited_at DESC LIMIT ?1
                );
                """
                var pruneStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, pruneSQL, -1, &pruneStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(pruneStmt, 1, Int32(maxItems))
                    sqlite3_step(pruneStmt)
                    sqlite3_finalize(pruneStmt)
                }
            }
        }
    }

    public func fetchHistory(query: String = "", limit: Int = 200) throws -> [HistoryEntry] {
        try queue.sync {
            guard let db else { return [] }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let sql: String
            if trimmed.isEmpty {
                sql = """
                SELECT id, note_id, url, title, author, cover_url, excerpt, visited_at, visit_count, is_video
                FROM history
                ORDER BY visited_at DESC
                LIMIT ?1;
                """
            } else {
                sql = """
                SELECT id, note_id, url, title, author, cover_url, excerpt, visited_at, visit_count, is_video
                FROM history
                WHERE title LIKE ?1 OR author LIKE ?1 OR excerpt LIKE ?1
                ORDER BY visited_at DESC
                LIMIT ?2;
                """
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            if trimmed.isEmpty {
                sqlite3_bind_int(stmt, 1, Int32(limit))
            } else {
                let pattern = "%\(trimmed)%"
                bindText(stmt, 1, pattern)
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }

            var results: [HistoryEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(HistoryEntry(
                    id: readText(stmt, 0),
                    noteId: readOptionalText(stmt, 1),
                    url: readText(stmt, 2),
                    title: readText(stmt, 3),
                    author: readText(stmt, 4),
                    coverURL: readOptionalText(stmt, 5),
                    excerpt: readText(stmt, 6),
                    visitedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                    visitCount: Int(sqlite3_column_int(stmt, 8)),
                    isVideo: sqlite3_column_int(stmt, 9) != 0
                ))
            }
            return results
        }
    }

    public func deleteHistory(id: String) throws {
        try queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM history WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func clearHistory() throws {
        try queue.sync {
            try executeRaw("DELETE FROM history;")
        }
    }

    // MARK: - Collections Operations

    public func upsertCollection(
        url: String,
        noteId: String? = nil,
        title: String,
        author: String = "",
        coverURL: String? = nil,
        excerpt: String = "",
        folder: String = "默认收藏",
        memo: String = "",
        isVideo: Bool = false,
        now: Date = Date()
    ) throws -> CollectionEntry {
        let resolvedNoteId = noteId ?? XHSURLClassifier.extractNoteId(from: url)
        let key = XHSURLClassifier.canonicalKey(for: url)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (resolvedNoteId.map { "笔记 \($0.prefix(8))" } ?? url)
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "默认收藏" : folder.trimmingCharacters(in: .whitespacesAndNewlines)

        try queue.sync {
            guard let db else { return }
            let sql = """
            INSERT INTO collections (id, note_id, url, title, author, cover_url, excerpt, folder, memo, created_at, updated_at, is_video)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10, ?11)
            ON CONFLICT(id) DO UPDATE SET
                url = excluded.url,
                title = CASE WHEN length(excluded.title) > 0 THEN excluded.title ELSE collections.title END,
                author = CASE WHEN length(excluded.author) > 0 THEN excluded.author ELSE collections.author END,
                cover_url = COALESCE(NULLIF(excluded.cover_url, ''), collections.cover_url),
                excerpt = CASE WHEN length(excluded.excerpt) > 0 THEN excluded.excerpt ELSE collections.excerpt END,
                folder = excluded.folder,
                memo = CASE WHEN length(excluded.memo) > 0 THEN excluded.memo ELSE collections.memo END,
                updated_at = excluded.updated_at,
                is_video = CASE WHEN excluded.is_video = 1 THEN 1 ELSE collections.is_video END;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, key)
            bindOptionalText(stmt, 2, resolvedNoteId)
            bindText(stmt, 3, url)
            bindText(stmt, 4, cleanTitle)
            bindText(stmt, 5, author)
            bindOptionalText(stmt, 6, coverURL)
            bindText(stmt, 7, excerpt)
            bindText(stmt, 8, cleanFolder)
            bindText(stmt, 9, memo)
            sqlite3_bind_double(stmt, 10, now.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 11, isVideo ? 1 : 0)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        return CollectionEntry(
            id: key,
            noteId: resolvedNoteId,
            url: url,
            title: cleanTitle,
            author: author,
            coverURL: coverURL,
            excerpt: excerpt,
            folder: cleanFolder,
            memo: memo,
            createdAt: now,
            updatedAt: now,
            isVideo: isVideo
        )
    }

    public func isCollected(urlString: String) -> Bool {
        let key = XHSURLClassifier.canonicalKey(for: urlString)
        return queue.sync {
            guard let db else { return false }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM collections WHERE id = ?1 LIMIT 1;", -1, &stmt, nil) == SQLITE_OK else {
                return false
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, key)
            return sqlite3_step(stmt) == SQLITE_ROW
        }
    }

    public func fetchCollections(folder: String? = nil, query: String = "") throws -> [CollectionEntry] {
        try queue.sync {
            guard let db else { return [] }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasFolder = folder != nil && folder != "全部"
            let hasQuery = !trimmed.isEmpty

            var conditions: [String] = []
            if hasFolder { conditions.append("folder = ?") }
            if hasQuery { conditions.append("(title LIKE ? OR author LIKE ? OR memo LIKE ? OR excerpt LIKE ?)") }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = """
            SELECT id, note_id, url, title, author, cover_url, excerpt, folder, memo, created_at, updated_at, is_video
            FROM collections
            \(whereClause)
            ORDER BY updated_at DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var idx: Int32 = 1
            if let folder, hasFolder {
                bindText(stmt, idx, folder)
                idx += 1
            }
            if hasQuery {
                let pattern = "%\(trimmed)%"
                for _ in 0..<4 {
                    bindText(stmt, idx, pattern)
                    idx += 1
                }
            }

            var results: [CollectionEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(CollectionEntry(
                    id: readText(stmt, 0),
                    noteId: readOptionalText(stmt, 1),
                    url: readText(stmt, 2),
                    title: readText(stmt, 3),
                    author: readText(stmt, 4),
                    coverURL: readOptionalText(stmt, 5),
                    excerpt: readText(stmt, 6),
                    folder: readText(stmt, 7),
                    memo: readText(stmt, 8),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10)),
                    isVideo: sqlite3_column_int(stmt, 11) != 0
                ))
            }
            return results
        }
    }

    public func fetchFolders() throws -> [String] {
        try queue.sync {
            guard let db else { return ["默认收藏"] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT DISTINCT folder FROM collections ORDER BY folder ASC;", -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            var folders: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                folders.append(readText(stmt, 0))
            }
            if !folders.contains("默认收藏") {
                folders.insert("默认收藏", at: 0)
            }
            return folders
        }
    }

    public func updateCollection(id: String, folder: String, memo: String) throws {
        try queue.sync {
            guard let db else { return }
            let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "默认收藏" : folder.trimmingCharacters(in: .whitespacesAndNewlines)
            var stmt: OpaquePointer?
            let sql = "UPDATE collections SET folder = ?1, memo = ?2, updated_at = ?3 WHERE id = ?4;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, cleanFolder)
            bindText(stmt, 2, memo)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            bindText(stmt, 4, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func deleteCollection(id: String) throws {
        try queue.sync {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM collections WHERE id = ?1;", -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func exportCollectionsMarkdown() throws -> String {
        let items = try fetchCollections()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = [
            "# RedNote Lite 本地收藏导出",
            "",
            "导出时间：\(formatter.string(from: Date())) · 共 \(items.count) 条笔记",
            ""
        ]

        let grouped = Dictionary(grouping: items, by: { $0.folder })
        for folder in grouped.keys.sorted() {
            lines.append("## \(folder)")
            lines.append("")
            for item in grouped[folder] ?? [] {
                let authorSuffix = item.author.isEmpty ? "" : " — @\(item.author)"
                lines.append("- [\(item.title)](\(item.url))\(authorSuffix)")
                if !item.memo.isEmpty {
                    lines.append("  - 备注：\(item.memo)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func vacuum() throws {
        try queue.sync {
            try executeRaw("PRAGMA wal_checkpoint(TRUNCATE);")
            try executeRaw("VACUUM;")
        }
    }

    // MARK: - Bind & Read Helpers

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let value, !value.isEmpty {
            bindText(stmt, idx, value)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    private func readText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: cStr)
    }

    private func readOptionalText(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, idx) else { return nil }
        let value = String(cString: cStr)
        return value.isEmpty ? nil : value
    }
}
