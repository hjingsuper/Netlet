import CSQLite
import Foundation

enum TrafficHistoryDatabaseError: Error, Equatable {
    case openFailed(code: Int32, message: String)
    case sqlite(code: Int32, message: String)
}

private final class SQLiteConnection: @unchecked Sendable {
    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        close()
    }

    private(set) var handle: OpaquePointer?

    func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }
}

actor TrafficHistoryDatabase {
    static let currentSchemaVersion: Int32 = 1
    static let retentionDuration: TimeInterval = 7 * 24 * 60 * 60

    init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            let openedConnection = SQLiteConnection(handle: try Self.openDatabase(at: url))
            connection = openedConnection
            try Self.configureAndMigrate(openedConnection.handle)
        } catch {
            connection?.close()
            connection = nil

            guard Self.isCorruption(error) else { throw error }
            try Self.quarantineDatabaseFiles(at: url)
            let rebuiltConnection = SQLiteConnection(handle: try Self.openDatabase(at: url))
            connection = rebuiltConnection
            try Self.configureAndMigrate(rebuiltConnection.handle)
        }
    }

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return applicationSupport
            .appendingPathComponent("Netlet", isDirectory: true)
            .appendingPathComponent("history.sqlite", isDirectory: false)
    }

    func upsertAndPrune(_ record: TrafficMinuteRecord, now: Date) throws {
        let database = try requireConnection()
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)

        do {
            try upsert(record, on: database)
            try deleteRecords(before: now.addingTimeInterval(-Self.retentionDuration), on: database)
            try execute("COMMIT", on: database)
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    func prune(now: Date) throws {
        let database = try requireConnection()
        try execute("BEGIN IMMEDIATE TRANSACTION", on: database)

        do {
            try deleteRecords(before: now.addingTimeInterval(-Self.retentionDuration), on: database)
            try execute("COMMIT", on: database)
        } catch {
            try? execute("ROLLBACK", on: database)
            throw error
        }
    }

    func records(since startDate: Date, through endDate: Date) throws -> [TrafficMinuteRecord] {
        let database = try requireConnection()
        let sql = """
        SELECT timestamp, avg_download, avg_upload, peak_download, peak_upload,
               sample_count, download_bytes, upload_bytes
        FROM minute_traffic
        WHERE timestamp >= ?1 AND timestamp <= ?2
        ORDER BY timestamp ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(for: database)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(floor(startDate.timeIntervalSince1970)))
        sqlite3_bind_int64(statement, 2, Int64(ceil(endDate.timeIntervalSince1970)))

        var result: [TrafficMinuteRecord] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                result.append(
                    TrafficMinuteRecord(
                        timestamp: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0))),
                        averageDownloadBytesPerSecond: sqlite3_column_double(statement, 1),
                        averageUploadBytesPerSecond: sqlite3_column_double(statement, 2),
                        peakDownloadBytesPerSecond: sqlite3_column_double(statement, 3),
                        peakUploadBytesPerSecond: sqlite3_column_double(statement, 4),
                        sampleCount: Int(sqlite3_column_int64(statement, 5)),
                        downloadBytes: unsignedValue(sqlite3_column_int64(statement, 6)),
                        uploadBytes: unsignedValue(sqlite3_column_int64(statement, 7))
                    )
                )
            case SQLITE_DONE:
                return result
            default:
                throw sqliteError(for: database)
            }
        }
    }

    func clear() throws {
        try execute("DELETE FROM minute_traffic", on: requireConnection())
    }

    func schemaVersion() throws -> Int32 {
        let database = try requireConnection()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(for: database)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(for: database)
        }
        return sqlite3_column_int(statement, 0)
    }

    private var connection: SQLiteConnection?

    private static func openDatabase(at url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let database { sqlite3_close_v2(database) }
            throw TrafficHistoryDatabaseError.openFailed(code: result, message: message)
        }
        return database
    }

    private static func configureAndMigrate(_ database: OpaquePointer?) throws {
        guard let database else {
            throw TrafficHistoryDatabaseError.openFailed(code: SQLITE_CANTOPEN, message: "Missing database connection")
        }
        sqlite3_busy_timeout(database, 2_000)
        try execute("PRAGMA journal_mode = WAL", on: database)
        try execute("PRAGMA synchronous = NORMAL", on: database)

        let version = try readSchemaVersion(from: database)
        guard version <= currentSchemaVersion else {
            throw TrafficHistoryDatabaseError.sqlite(
                code: SQLITE_SCHEMA,
                message: "History database schema is newer than this version of Netlet"
            )
        }

        if version < 1 {
            try execute("BEGIN IMMEDIATE TRANSACTION", on: database)
            do {
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS minute_traffic (
                        timestamp INTEGER PRIMARY KEY NOT NULL,
                        avg_download REAL NOT NULL,
                        avg_upload REAL NOT NULL,
                        peak_download REAL NOT NULL,
                        peak_upload REAL NOT NULL,
                        sample_count INTEGER NOT NULL,
                        download_bytes INTEGER NOT NULL,
                        upload_bytes INTEGER NOT NULL
                    )
                    """,
                    on: database
                )
                try execute(
                    "CREATE INDEX IF NOT EXISTS idx_minute_traffic_timestamp ON minute_traffic(timestamp)",
                    on: database
                )
                try execute("PRAGMA user_version = 1", on: database)
                try execute("COMMIT", on: database)
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
    }

    private static func readSchemaVersion(from database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(for: database)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(for: database)
        }
        return sqlite3_column_int(statement, 0)
    }

    private func upsert(_ record: TrafficMinuteRecord, on database: OpaquePointer) throws {
        let sql = """
        INSERT INTO minute_traffic (
            timestamp, avg_download, avg_upload, peak_download, peak_upload,
            sample_count, download_bytes, upload_bytes
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        ON CONFLICT(timestamp) DO UPDATE SET
            avg_download = (
                minute_traffic.avg_download * minute_traffic.sample_count
                + excluded.avg_download * excluded.sample_count
            ) / (minute_traffic.sample_count + excluded.sample_count),
            avg_upload = (
                minute_traffic.avg_upload * minute_traffic.sample_count
                + excluded.avg_upload * excluded.sample_count
            ) / (minute_traffic.sample_count + excluded.sample_count),
            peak_download = MAX(minute_traffic.peak_download, excluded.peak_download),
            peak_upload = MAX(minute_traffic.peak_upload, excluded.peak_upload),
            sample_count = minute_traffic.sample_count + excluded.sample_count,
            download_bytes = minute_traffic.download_bytes + excluded.download_bytes,
            upload_bytes = minute_traffic.upload_bytes + excluded.upload_bytes
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(for: database)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(floor(record.timestamp.timeIntervalSince1970)))
        sqlite3_bind_double(statement, 2, finiteNonnegative(record.averageDownloadBytesPerSecond))
        sqlite3_bind_double(statement, 3, finiteNonnegative(record.averageUploadBytesPerSecond))
        sqlite3_bind_double(statement, 4, finiteNonnegative(record.peakDownloadBytesPerSecond))
        sqlite3_bind_double(statement, 5, finiteNonnegative(record.peakUploadBytesPerSecond))
        sqlite3_bind_int64(statement, 6, Int64(max(1, record.sampleCount)))
        sqlite3_bind_int64(statement, 7, signedClamped(record.downloadBytes))
        sqlite3_bind_int64(statement, 8, signedClamped(record.uploadBytes))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(for: database)
        }
    }

    private func deleteRecords(before cutoff: Date, on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "DELETE FROM minute_traffic WHERE timestamp < ?1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw sqliteError(for: database)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(floor(cutoff.timeIntervalSince1970)))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(for: database)
        }
    }

    private func requireConnection() throws -> OpaquePointer {
        guard let connection = connection?.handle else {
            throw TrafficHistoryDatabaseError.openFailed(
                code: SQLITE_CANTOPEN,
                message: "History database is closed"
            )
        }
        return connection
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw TrafficHistoryDatabaseError.sqlite(code: result, message: message)
        }
    }

    private func execute(_ sql: String, on database: OpaquePointer) throws {
        try Self.execute(sql, on: database)
    }

    private static func sqliteError(for database: OpaquePointer) -> TrafficHistoryDatabaseError {
        TrafficHistoryDatabaseError.sqlite(
            code: sqlite3_errcode(database),
            message: String(cString: sqlite3_errmsg(database))
        )
    }

    private func sqliteError(for database: OpaquePointer) -> TrafficHistoryDatabaseError {
        Self.sqliteError(for: database)
    }

    private static func isCorruption(_ error: Error) -> Bool {
        let code: Int32?
        switch error {
        case let TrafficHistoryDatabaseError.openFailed(errorCode, _): code = errorCode
        case let TrafficHistoryDatabaseError.sqlite(errorCode, _): code = errorCode
        default: code = nil
        }
        return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
    }

    private static func quarantineDatabaseFiles(at url: URL) throws {
        let fileManager = FileManager.default
        let suffix = ".corrupt-\(Int(Date().timeIntervalSince1970))"
        for source in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: source.path + suffix)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func signedClamped(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }

    private func unsignedValue(_ value: Int64) -> UInt64 {
        value > 0 ? UInt64(value) : 0
    }

    private func finiteNonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
