import Foundation
import SQLite3

// MARK: - Database Manager (SQLite3 for iOS)
// Uses App Groups container for sharing between app and keyboard extension

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbPath: String
    private let appGroupID = "group.com.brainphart.voicerecorder"

    private init() {
        // Use App Groups container for shared access between app and keyboard
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            dbPath = containerURL.appendingPathComponent("voicerecorder.db").path
            print("[DB] Using shared container: \(dbPath)")
        } else {
            // Fallback to Documents (shouldn't happen if entitlements are correct)
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            dbPath = documentsPath.appendingPathComponent("voicerecorder.db").path
            print("[DB] WARNING: Using Documents directory (App Groups not available)")
        }

        openDatabase()
        createTables()
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[DB] Error opening database")
        } else {
            print("[DB] Database opened at: \(dbPath)")
        }
    }

    private func createTables() {
        let sessionsSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL,
                completed_at INTEGER,
                status TEXT DEFAULT 'recording',
                transcript TEXT,
                source TEXT DEFAULT 'app'
            );
        """

        let chunksSQL = """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                chunk_number INTEGER NOT NULL,
                audio_blob BLOB NOT NULL,
                duration_ms INTEGER,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );
        """

        execute(sql: sessionsSQL)
        execute(sql: chunksSQL)

        // Migrations for existing databases
        execute(sql: "ALTER TABLE sessions ADD COLUMN transcript TEXT;")
        execute(sql: "ALTER TABLE sessions ADD COLUMN source TEXT DEFAULT 'app';")
    }

    private func execute(sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("[DB] Error executing: \(sql)")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Sessions

    func createSession(id: String) {
        let sql = "INSERT INTO sessions (id, created_at, status) VALUES (?, ?, 'recording');"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Session created: \(id)")
            }
        }
        sqlite3_finalize(statement)
    }

    func completeSession(id: String) {
        let sql = "UPDATE sessions SET status = 'completed', completed_at = ? WHERE id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(statement, 2, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Session completed: \(id)")
            }
        }
        sqlite3_finalize(statement)
    }

    func saveTranscript(sessionId: String, transcript: String) {
        let sql = "UPDATE sessions SET transcript = ? WHERE id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (transcript as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (sessionId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                let rowsAffected = sqlite3_changes(db)
                print("[DB] Transcript saved for session: \(sessionId) (rows affected: \(rowsAffected))")
                if rowsAffected == 0 {
                    print("[DB] WARNING: No rows updated - session \(sessionId) may not exist")
                } else if rowsAffected > 1 {
                    print("[DB] ERROR: Multiple rows updated (\(rowsAffected)) - this should never happen!")
                }
            } else {
                print("[DB] ERROR: Failed to save transcript for session: \(sessionId)")
            }
        } else {
            print("[DB] ERROR: Failed to prepare statement for saveTranscript")
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Chunks

    func createChunk(sessionId: String, chunkNumber: Int, audioData: Data, durationMs: Int) {
        let sql = """
            INSERT INTO chunks (session_id, chunk_number, audio_blob, duration_ms, created_at)
            VALUES (?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(chunkNumber))

            audioData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 3, ptr.baseAddress, Int32(audioData.count), nil)
            }

            sqlite3_bind_int(statement, 4, Int32(durationMs))
            sqlite3_bind_int64(statement, 5, Int64(Date().timeIntervalSince1970))

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Chunk saved: session=\(sessionId), chunk=\(chunkNumber), size=\(audioData.count)")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Query

    func getSessionCount() -> Int {
        let sql = "SELECT COUNT(*) FROM sessions;"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    func getChunkCount(sessionId: String) -> Int {
        let sql = "SELECT COUNT(*) FROM chunks WHERE session_id = ?;"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Session Retrieval

    struct SessionInfo {
        let id: String
        let createdAt: Date
        let completedAt: Date?
        let status: String
        let totalDurationMs: Int
        let transcript: String?
        let source: String  // "app" or "keyboard"
    }

    func getAllSessions() -> [SessionInfo] {
        let sql = """
            SELECT s.id, s.created_at, s.completed_at, s.status, s.transcript,
                   COALESCE(SUM(c.duration_ms), 0) as total_duration_ms,
                   COALESCE(s.source, 'app') as source
            FROM sessions s
            LEFT JOIN chunks c ON s.id = c.session_id
            GROUP BY s.id
            ORDER BY s.created_at DESC;
        """
        var statement: OpaquePointer?
        var sessions: [SessionInfo] = []

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let createdAtTimestamp = sqlite3_column_int64(statement, 1)
                let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtTimestamp))

                var completedAt: Date? = nil
                if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                    let completedAtTimestamp = sqlite3_column_int64(statement, 2)
                    completedAt = Date(timeIntervalSince1970: TimeInterval(completedAtTimestamp))
                }

                let status = String(cString: sqlite3_column_text(statement, 3))

                var transcript: String? = nil
                if sqlite3_column_type(statement, 4) != SQLITE_NULL {
                    transcript = String(cString: sqlite3_column_text(statement, 4))
                }

                let totalDurationMs = Int(sqlite3_column_int(statement, 5))

                var source = "app"
                if sqlite3_column_type(statement, 6) != SQLITE_NULL {
                    source = String(cString: sqlite3_column_text(statement, 6))
                }

                sessions.append(SessionInfo(
                    id: id,
                    createdAt: createdAt,
                    completedAt: completedAt,
                    status: status,
                    totalDurationMs: totalDurationMs,
                    transcript: transcript,
                    source: source
                ))
            }
        }
        sqlite3_finalize(statement)
        return sessions
    }

    func getSessionAudio(sessionId: String) -> Data? {
        let sql = """
            SELECT audio_blob FROM chunks
            WHERE session_id = ?
            ORDER BY chunk_number ASC;
        """
        var statement: OpaquePointer?
        var combinedData = Data()

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let blobPointer = sqlite3_column_blob(statement, 0) {
                    let blobSize = Int(sqlite3_column_bytes(statement, 0))
                    let chunkData = Data(bytes: blobPointer, count: blobSize)

                    // Each chunk is a complete WAV file, we need to extract raw PCM
                    // WAV header is 44 bytes, PCM data starts after
                    if chunkData.count > 44 {
                        let pcmData = chunkData.suffix(from: 44)
                        combinedData.append(pcmData)
                    }
                }
            }
        }
        sqlite3_finalize(statement)

        if combinedData.isEmpty {
            return nil
        }

        // Wrap combined PCM in a new WAV header
        // Assume 48000 Hz sample rate, 16-bit mono (typical iOS)
        return createWAVFromPCM(pcmData: combinedData, sampleRate: 48000)
    }

    private func createWAVFromPCM(pcmData: Data, sampleRate: Int32) -> Data {
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let bytesPerSample = Int16(bitsPerSample / 8)

        var data = Data()

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(36 + pcmData.count).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })

        let byteRate = sampleRate * Int32(numChannels) * Int32(bytesPerSample)
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })

        let blockAlign = numChannels * bytesPerSample
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Data($0) })
        data.append(pcmData)

        return data
    }

    // MARK: - Session Deletion

    func deleteSession(sessionId: String) {
        // Delete chunks first (foreign key)
        let deleteChunksSQL = "DELETE FROM chunks WHERE session_id = ?;"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteChunksSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Chunks deleted for session: \(sessionId)")
            }
        }
        sqlite3_finalize(statement)

        // Delete session
        let deleteSessionSQL = "DELETE FROM sessions WHERE id = ?;"
        if sqlite3_prepare_v2(db, deleteSessionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Session deleted: \(sessionId)")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Keyboard Extension Support

    /// Create a complete session from keyboard with audio and transcript
    /// Returns the session ID for reference
    @discardableResult
    func createKeyboardSession(audioData: Data, transcript: String, durationMs: Int) -> String {
        let sessionId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        // Create session with transcript and source = 'keyboard'
        let sessionSQL = """
            INSERT INTO sessions (id, created_at, completed_at, status, transcript, source)
            VALUES (?, ?, ?, 'completed', ?, 'keyboard');
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sessionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, now)
            sqlite3_bind_int64(statement, 3, now)
            sqlite3_bind_text(statement, 4, (transcript as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Keyboard session created: \(sessionId)")
            } else {
                print("[DB] Error creating keyboard session")
            }
        }
        sqlite3_finalize(statement)

        // Store audio as single chunk
        let chunkSQL = """
            INSERT INTO chunks (session_id, chunk_number, audio_blob, duration_ms, created_at)
            VALUES (?, 0, ?, ?, ?);
        """

        if sqlite3_prepare_v2(db, chunkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)

            audioData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 2, ptr.baseAddress, Int32(audioData.count), nil)
            }

            sqlite3_bind_int(statement, 3, Int32(durationMs))
            sqlite3_bind_int64(statement, 4, now)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[DB] Keyboard audio saved: \(audioData.count) bytes")
            }
        }
        sqlite3_finalize(statement)

        return sessionId
    }

    /// Get the most recent session (for keyboard edit button)
    func getLatestSession() -> SessionInfo? {
        return getAllSessions().first
    }
}

// MARK: - Lightweight Database Access for Keyboard Extension
// This class can be used directly in the keyboard extension without the full DatabaseManager

final class SharedDatabaseAccess {
    static let shared = SharedDatabaseAccess()

    private var db: OpaquePointer?
    private let appGroupID = "group.com.brainphart.voicerecorder"

    private init() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("[SharedDB] ERROR: App Groups not available")
            return
        }

        let dbPath = containerURL.appendingPathComponent("voicerecorder.db").path

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("[SharedDB] Opened: \(dbPath)")
            createTablesIfNeeded()
        } else {
            print("[SharedDB] Failed to open database")
        }
    }

    private func createTablesIfNeeded() {
        let sessionsSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                created_at INTEGER NOT NULL,
                completed_at INTEGER,
                status TEXT DEFAULT 'recording',
                transcript TEXT,
                source TEXT DEFAULT 'app'
            );
        """

        let chunksSQL = """
            CREATE TABLE IF NOT EXISTS chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                chunk_number INTEGER NOT NULL,
                audio_blob BLOB NOT NULL,
                duration_ms INTEGER,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sessionsSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        if sqlite3_prepare_v2(db, chunksSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    /// Save keyboard transcription to shared database
    @discardableResult
    func saveKeyboardTranscription(audioData: Data, transcript: String, durationMs: Int) -> String {
        let sessionId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970)

        // Create session
        let sessionSQL = """
            INSERT INTO sessions (id, created_at, completed_at, status, transcript, source)
            VALUES (?, ?, ?, 'completed', ?, 'keyboard');
        """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sessionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, now)
            sqlite3_bind_int64(statement, 3, now)
            sqlite3_bind_text(statement, 4, (transcript as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[SharedDB] Session saved: \(sessionId)")
            }
        }
        sqlite3_finalize(statement)

        // Save audio chunk
        let chunkSQL = """
            INSERT INTO chunks (session_id, chunk_number, audio_blob, duration_ms, created_at)
            VALUES (?, 0, ?, ?, ?);
        """

        if sqlite3_prepare_v2(db, chunkSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (sessionId as NSString).utf8String, -1, nil)

            audioData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 2, ptr.baseAddress, Int32(audioData.count), nil)
            }

            sqlite3_bind_int(statement, 3, Int32(durationMs))
            sqlite3_bind_int64(statement, 4, now)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[SharedDB] Audio saved: \(audioData.count) bytes")
            }
        }
        sqlite3_finalize(statement)

        return sessionId
    }
}
