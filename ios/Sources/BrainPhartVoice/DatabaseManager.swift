import Foundation
import SQLite

// MARK: - Database Manager

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    private var db: Connection!

    private init() {
        #if os(macOS)
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/brainphart-voice")
        #else
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("brainphart-voice")
        #endif

        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        let dbPath = path.appendingPathComponent("database.db").path

        do {
            db = try Connection(dbPath)
            try db.execute("PRAGMA foreign_keys = ON")
            print("Database opened at: \(dbPath)")
            createTables()
        } catch {
            print("Database error: \(error)")
        }
    }

    // MARK: - Schema

    private func createTables() {
        // Sessions table
        let sessionsTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            completed_at INTEGER,
            status TEXT NOT NULL DEFAULT 'recording'
        )
        """

        // Chunks table (audio segments as BLOBs)
        let chunksTable = """
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            chunk_num INTEGER NOT NULL,
            audio_blob BLOB NOT NULL,
            duration_ms INTEGER,
            status TEXT DEFAULT 'pending',
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
        """

        // Transcripts table
        let transcriptsTable = """
        CREATE TABLE IF NOT EXISTS transcripts (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            chunk_num INTEGER,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
        """

        // Versions table (edit history)
        let versionsTable = """
        CREATE TABLE IF NOT EXISTS versions (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            version_num INTEGER NOT NULL,
            version_type TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
        """

        // Dictionary table (personal words)
        let dictionaryTable = """
        CREATE TABLE IF NOT EXISTS dictionary (
            id TEXT PRIMARY KEY,
            word TEXT NOT NULL UNIQUE,
            added_at INTEGER NOT NULL
        )
        """

        // Settings table
        let settingsTable = """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """

        do {
            try db.execute(sessionsTable)
            try db.execute(chunksTable)
            try db.execute(transcriptsTable)
            try db.execute(versionsTable)
            try db.execute(dictionaryTable)
            try db.execute(settingsTable)
            print("Database tables created")
        } catch {
            print("Table creation error: \(error)")
        }
    }

    // MARK: - Sessions

    func createSession(id: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let sql = "INSERT INTO sessions (id, created_at, status) VALUES (?, ?, 'recording')"
        do {
            try db.run(sql, id, timestamp)
            print("Session created: \(id)")
        } catch {
            print("Failed to create session: \(error)")
        }
    }

    func completeSession(id: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let sql = "UPDATE sessions SET status = 'complete', completed_at = ? WHERE id = ?"
        do {
            try db.run(sql, timestamp, id)
            print("Session completed: \(id)")
        } catch {
            print("Failed to complete session: \(error)")
        }
    }

    func cancelSession(id: String) {
        let sql = "UPDATE sessions SET status = 'cancelled' WHERE id = ?"
        do {
            try db.run(sql, id)
            print("Session cancelled: \(id)")
        } catch {
            print("Failed to cancel session: \(error)")
        }
    }

    func deleteSession(id: String) {
        let sql = "DELETE FROM sessions WHERE id = ?"
        do {
            try db.run(sql, id)
            print("Session deleted: \(id)")
        } catch {
            print("Failed to delete session: \(error)")
        }
    }

    func getAllSessions() -> [Session] {
        var sessions: [Session] = []
        let sql = "SELECT id, created_at, status FROM sessions WHERE status != 'cancelled' ORDER BY created_at DESC"

        do {
            for row in try db.prepare(sql) {
                let session = Session(
                    id: row[0] as! String,
                    createdAt: row[1] as! Int,
                    status: row[2] as! String
                )
                sessions.append(session)
            }
        } catch {
            print("Failed to get sessions: \(error)")
        }

        return sessions
    }

    // MARK: - Chunks

    func createChunk(sessionId: String, chunkNumber: Int, audioData: Data, durationMs: Int) -> String {
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let blob: Blob = audioData.datatypeValue

        let sql = """
        INSERT INTO chunks (id, session_id, chunk_num, audio_blob, duration_ms, status, created_at)
        VALUES (?, ?, ?, ?, ?, 'pending', ?)
        """

        do {
            try db.run(sql, id, sessionId, chunkNumber, blob, durationMs, timestamp)
            print("Chunk created: \(id)")
        } catch {
            print("Failed to create chunk: \(error)")
        }

        return id
    }

    func getPendingChunks() -> [PendingChunk] {
        var chunks: [PendingChunk] = []
        let sql = """
        SELECT id, session_id, chunk_num, audio_blob
        FROM chunks
        WHERE status = 'pending'
        ORDER BY created_at ASC
        LIMIT 5
        """

        do {
            for row in try db.prepare(sql) {
                if let blob = row[3] as? Blob {
                    let chunk = PendingChunk(
                        id: row[0] as! String,
                        sessionId: row[1] as! String,
                        chunkNumber: row[2] as! Int,
                        audioData: Data(blob.bytes)
                    )
                    chunks.append(chunk)
                }
            }
        } catch {
            print("Failed to get pending chunks: \(error)")
        }

        return chunks
    }

    func updateChunkStatus(chunkId: String, status: String) {
        let sql = "UPDATE chunks SET status = ? WHERE id = ?"
        do {
            try db.run(sql, status, chunkId)
        } catch {
            print("Failed to update chunk status: \(error)")
        }
    }

    func getChunkAudio(sessionId: String) -> [Data] {
        var audioData: [Data] = []
        let sql = "SELECT audio_blob FROM chunks WHERE session_id = ? ORDER BY chunk_num ASC"

        do {
            for row in try db.prepare(sql, sessionId) {
                if let blob = row[0] as? Blob {
                    audioData.append(Data(blob.bytes))
                }
            }
        } catch {
            print("Failed to get chunk audio: \(error)")
        }

        return audioData
    }

    func getSessionDuration(sessionId: String) -> Int {
        let sql = "SELECT SUM(duration_ms) FROM chunks WHERE session_id = ?"
        do {
            if let result = try db.scalar(sql, sessionId) as? Int64 {
                return Int(result)
            }
        } catch {
            print("Failed to get session duration: \(error)")
        }
        return 0
    }

    // MARK: - Transcripts

    func saveChunkTranscript(sessionId: String, chunkNumber: Int, transcript: String) {
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        let sql = """
        INSERT INTO transcripts (id, session_id, chunk_num, content, created_at)
        VALUES (?, ?, ?, ?, ?)
        """

        do {
            try db.run(sql, id, sessionId, chunkNumber, transcript, timestamp)
            print("Transcript saved for chunk \(chunkNumber)")

            // Also save as version 1 (original)
            saveTranscriptVersion(sessionId: sessionId, content: transcript, versionType: "original")
        } catch {
            print("Failed to save transcript: \(error)")
        }
    }

    func getTranscript(sessionId: String) -> String {
        // Get all chunk transcripts, joined
        let sql = """
        SELECT content FROM transcripts
        WHERE session_id = ?
        ORDER BY chunk_num ASC
        """

        var transcripts: [String] = []
        do {
            for row in try db.prepare(sql, sessionId) {
                if let content = row[0] as? String {
                    transcripts.append(content)
                }
            }
        } catch {
            print("Failed to get transcript: \(error)")
        }

        // If we have a user edit, return the latest version instead
        if let latest = getLatestVersion(sessionId: sessionId), latest.versionType == "user_edit" {
            return latest.content
        }

        return transcripts.joined(separator: " ")
    }

    // MARK: - Versions

    func saveTranscriptVersion(sessionId: String, content: String, versionType: String) {
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)

        // Get next version number
        let countSql = "SELECT COUNT(*) FROM versions WHERE session_id = ?"
        var versionNum = 1
        do {
            if let count = try db.scalar(countSql, sessionId) as? Int64 {
                versionNum = Int(count) + 1
            }
        } catch {}

        let sql = """
        INSERT INTO versions (id, session_id, version_num, version_type, content, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        do {
            try db.run(sql, id, sessionId, versionNum, versionType, content, timestamp)
            print("Version \(versionNum) saved for session \(sessionId)")

            NotificationCenter.default.post(name: .transcriptSaved, object: sessionId)
        } catch {
            print("Failed to save version: \(error)")
        }
    }

    func getLatestVersion(sessionId: String) -> TranscriptVersion? {
        let sql = """
        SELECT id, version_num, version_type, content, created_at
        FROM versions
        WHERE session_id = ?
        ORDER BY version_num DESC
        LIMIT 1
        """

        do {
            for row in try db.prepare(sql, sessionId) {
                return TranscriptVersion(
                    id: row[0] as! String,
                    sessionId: sessionId,
                    versionNum: row[1] as! Int,
                    versionType: row[2] as! String,
                    content: row[3] as! String,
                    createdAt: row[4] as! Int
                )
            }
        } catch {
            print("Failed to get latest version: \(error)")
        }

        return nil
    }

    func getAllVersions(sessionId: String) -> [TranscriptVersion] {
        var versions: [TranscriptVersion] = []
        let sql = """
        SELECT id, version_num, version_type, content, created_at
        FROM versions
        WHERE session_id = ?
        ORDER BY version_num ASC
        """

        do {
            for row in try db.prepare(sql, sessionId) {
                let version = TranscriptVersion(
                    id: row[0] as! String,
                    sessionId: sessionId,
                    versionNum: row[1] as! Int,
                    versionType: row[2] as! String,
                    content: row[3] as! String,
                    createdAt: row[4] as! Int
                )
                versions.append(version)
            }
        } catch {
            print("Failed to get versions: \(error)")
        }

        return versions
    }

    // MARK: - Dictionary

    func addWord(_ word: String) {
        let id = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        let sql = "INSERT OR IGNORE INTO dictionary (id, word, added_at) VALUES (?, ?, ?)"

        do {
            try db.run(sql, id, word.lowercased(), timestamp)
            print("Word added to dictionary: \(word)")
        } catch {
            print("Failed to add word: \(error)")
        }
    }

    func removeWord(_ word: String) {
        let sql = "DELETE FROM dictionary WHERE word = ?"
        do {
            try db.run(sql, word.lowercased())
            print("Word removed from dictionary: \(word)")
        } catch {
            print("Failed to remove word: \(error)")
        }
    }

    func getAllWords() -> [String] {
        var words: [String] = []
        let sql = "SELECT word FROM dictionary ORDER BY word ASC"

        do {
            for row in try db.prepare(sql) {
                if let word = row[0] as? String {
                    words.append(word)
                }
            }
        } catch {
            print("Failed to get words: \(error)")
        }

        return words
    }

    // MARK: - Settings

    func setSetting(key: String, value: String) {
        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
        do {
            try db.run(sql, key, value)
        } catch {
            print("Failed to set setting: \(error)")
        }
    }

    func getSetting(key: String) -> String? {
        let sql = "SELECT value FROM settings WHERE key = ?"
        do {
            for row in try db.prepare(sql, key) {
                return row[0] as? String
            }
        } catch {
            print("Failed to get setting: \(error)")
        }
        return nil
    }
}

// MARK: - Models

struct TranscriptVersion {
    let id: String
    let sessionId: String
    let versionNum: Int
    let versionType: String
    let content: String
    let createdAt: Int

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
    }
}
