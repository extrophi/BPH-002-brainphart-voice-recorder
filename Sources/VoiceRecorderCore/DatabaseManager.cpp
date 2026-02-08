#include "DatabaseManager.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <random>
#include <sstream>
#include <stdexcept>

#include <sqlite3.h>

namespace vr {

// ---------------------------------------------------------------------------
// RAII helper for SQLite transactions
// ---------------------------------------------------------------------------

class Transaction {
public:
    explicit Transaction(sqlite3* db) : db_(db) {
        sqlite3_exec(db_, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr);
    }
    void commit() {
        if (!committed_) {
            sqlite3_exec(db_, "COMMIT", nullptr, nullptr, nullptr);
            committed_ = true;
        }
    }
    ~Transaction() {
        if (!committed_) {
            sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr);
        }
    }

private:
    sqlite3* db_;
    bool committed_ = false;
};

// ---------------------------------------------------------------------------
// RAII helper for SQLite prepared statements
// ---------------------------------------------------------------------------

class Statement {
public:
    Statement(sqlite3* db, const char* sql) {
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt_, nullptr);
        if (rc != SQLITE_OK) {
            stmt_ = nullptr;
        }
    }
    ~Statement() {
        if (stmt_) sqlite3_finalize(stmt_);
    }
    operator sqlite3_stmt*() const { return stmt_; }
    bool ok() const { return stmt_ != nullptr; }

private:
    sqlite3_stmt* stmt_ = nullptr;
};

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

DatabaseManager::DatabaseManager(const std::string& db_path)
    : db_path_(db_path) {}

DatabaseManager::~DatabaseManager() {
    close();
}

// ---------------------------------------------------------------------------
// open / close / is_open
// ---------------------------------------------------------------------------

bool DatabaseManager::open() {
    std::lock_guard<std::mutex> lock(mu_);

    if (db_) return true;   // already open

    if (db_path_.empty()) return false;

    // Ensure parent directory exists.
    auto parent = std::filesystem::path(db_path_).parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent);
    }

    int rc = sqlite3_open(db_path_.c_str(), &db_);
    if (rc != SQLITE_OK) {
        if (db_) {
            sqlite3_close(db_);
            db_ = nullptr;
        }
        return false;
    }

    // Enable WAL mode for crash safety and concurrent reads.
    sqlite3_exec(db_, "PRAGMA journal_mode=WAL", nullptr, nullptr, nullptr);

    // Enable foreign keys.
    sqlite3_exec(db_, "PRAGMA foreign_keys=ON", nullptr, nullptr, nullptr);

    return create_tables();
}

void DatabaseManager::close() {
    std::lock_guard<std::mutex> lock(mu_);
    if (db_) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

bool DatabaseManager::is_open() const {
    std::lock_guard<std::mutex> lock(mu_);
    return db_ != nullptr;
}

// ---------------------------------------------------------------------------
// create_tables
// ---------------------------------------------------------------------------

bool DatabaseManager::create_tables() {
    const char* sql = R"SQL(
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            completed_at INTEGER,
            status TEXT DEFAULT 'recording',
            duration_ms INTEGER,
            transcript TEXT
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            audio_blob BLOB NOT NULL,
            duration_ms INTEGER,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id)
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_session
            ON chunks(session_id, chunk_index);
    )SQL";

    char* err = nullptr;
    int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        if (err) sqlite3_free(err);
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Session operations
// ---------------------------------------------------------------------------

std::string DatabaseManager::create_session() {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return "";

    std::string id = generate_uuid();
    int64_t ts = now_unix();

    Transaction txn(db_);

    const char* sql =
        "INSERT INTO sessions (id, created_at, status) VALUES (?, ?, 'recording')";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return "";

    sqlite3_bind_text(stmt, 1, id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 2, ts);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) return "";

    txn.commit();
    return id;
}

bool DatabaseManager::update_transcript(const std::string& session_id,
                                        const std::string& transcript,
                                        int64_t duration_ms) {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return false;

    Transaction txn(db_);

    const char* sql =
        "UPDATE sessions SET transcript = ?, duration_ms = ?, "
        "status = 'complete', completed_at = ? WHERE id = ?";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return false;

    sqlite3_bind_text(stmt, 1, transcript.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 2, duration_ms);
    sqlite3_bind_int64(stmt, 3, now_unix());
    sqlite3_bind_text(stmt, 4, session_id.c_str(), -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) return false;

    txn.commit();
    return true;
}

bool DatabaseManager::mark_failed(const std::string& session_id) {
    return update_status(session_id, RecordingStatus::failed);
}

bool DatabaseManager::update_status(const std::string& session_id,
                                    RecordingStatus status) {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return false;

    Transaction txn(db_);

    const char* sql = "UPDATE sessions SET status = ? WHERE id = ?";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return false;

    sqlite3_bind_text(stmt, 1, status_to_string(status), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, session_id.c_str(), -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) return false;

    txn.commit();
    return true;
}

std::optional<RecordingSession> DatabaseManager::get_session(
    const std::string& session_id) const {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return std::nullopt;

    const char* sql =
        "SELECT id, created_at, completed_at, status, duration_ms, transcript "
        "FROM sessions WHERE id = ?";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return std::nullopt;

    sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) != SQLITE_ROW) return std::nullopt;

    RecordingSession s;
    s.id           = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
    s.created_at   = sqlite3_column_int64(stmt, 1);
    s.completed_at = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                         ? 0 : sqlite3_column_int64(stmt, 2);
    s.status       = status_from_string(
        reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3)));
    s.duration_ms  = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                         ? 0 : sqlite3_column_int64(stmt, 4);
    const char* t  = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5));
    s.transcript   = t ? t : "";

    return s;
}

std::vector<RecordingSession> DatabaseManager::get_sessions() const {
    std::lock_guard<std::mutex> lock(mu_);
    std::vector<RecordingSession> results;
    if (!db_) return results;

    const char* sql =
        "SELECT id, created_at, completed_at, status, duration_ms, transcript "
        "FROM sessions ORDER BY created_at DESC";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return results;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        RecordingSession s;
        s.id           = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        s.created_at   = sqlite3_column_int64(stmt, 1);
        s.completed_at = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                             ? 0 : sqlite3_column_int64(stmt, 2);
        s.status       = status_from_string(
            reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3)));
        s.duration_ms  = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                             ? 0 : sqlite3_column_int64(stmt, 4);
        const char* t  = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5));
        s.transcript   = t ? t : "";
        results.push_back(std::move(s));
    }

    return results;
}

bool DatabaseManager::delete_session(const std::string& session_id) {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return false;

    Transaction txn(db_);

    // Delete chunks first (foreign key).
    {
        const char* sql = "DELETE FROM chunks WHERE session_id = ?";
        Statement stmt(db_, sql);
        if (!stmt.ok()) return false;
        sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) != SQLITE_DONE) return false;
    }

    // Delete session.
    {
        const char* sql = "DELETE FROM sessions WHERE id = ?";
        Statement stmt(db_, sql);
        if (!stmt.ok()) return false;
        sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) != SQLITE_DONE) return false;
    }

    txn.commit();
    return true;
}

std::vector<RecordingSession> DatabaseManager::get_orphaned_sessions() const {
    std::lock_guard<std::mutex> lock(mu_);
    std::vector<RecordingSession> results;
    if (!db_) return results;

    const char* sql =
        "SELECT id, created_at, completed_at, status, duration_ms, transcript "
        "FROM sessions WHERE status = 'recording' ORDER BY created_at DESC";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return results;

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        RecordingSession s;
        s.id           = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        s.created_at   = sqlite3_column_int64(stmt, 1);
        s.completed_at = sqlite3_column_type(stmt, 2) == SQLITE_NULL
                             ? 0 : sqlite3_column_int64(stmt, 2);
        s.status       = status_from_string(
            reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3)));
        s.duration_ms  = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                             ? 0 : sqlite3_column_int64(stmt, 4);
        const char* t  = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5));
        s.transcript   = t ? t : "";
        results.push_back(std::move(s));
    }

    return results;
}

// ---------------------------------------------------------------------------
// Chunk operations
// ---------------------------------------------------------------------------

bool DatabaseManager::add_chunk(const std::string& session_id,
                                int chunk_index,
                                const std::vector<uint8_t>& audio_data,
                                int64_t duration_ms) {
    std::lock_guard<std::mutex> lock(mu_);
    if (!db_) return false;

    Transaction txn(db_);

    const char* sql =
        "INSERT INTO chunks (session_id, chunk_index, audio_blob, duration_ms, created_at) "
        "VALUES (?, ?, ?, ?, ?)";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return false;

    sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, chunk_index);
    sqlite3_bind_blob(stmt, 3, audio_data.data(),
                      static_cast<int>(audio_data.size()), SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 4, duration_ms);
    sqlite3_bind_int64(stmt, 5, now_unix());

    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_DONE) return false;

    txn.commit();
    return true;
}

std::vector<AudioChunk> DatabaseManager::get_chunks(
    const std::string& session_id) const {
    std::lock_guard<std::mutex> lock(mu_);
    std::vector<AudioChunk> results;
    if (!db_) return results;

    const char* sql =
        "SELECT session_id, chunk_index, audio_blob, duration_ms "
        "FROM chunks WHERE session_id = ? ORDER BY chunk_index ASC";
    Statement stmt(db_, sql);
    if (!stmt.ok()) return results;

    sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        AudioChunk c;
        c.session_id  = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        c.chunk_index = sqlite3_column_int(stmt, 1);

        const void* blob = sqlite3_column_blob(stmt, 2);
        int blob_size    = sqlite3_column_bytes(stmt, 2);
        if (blob && blob_size > 0) {
            const auto* data = static_cast<const uint8_t*>(blob);
            c.audio_data.assign(data, data + blob_size);
        }

        c.duration_ms = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                            ? 0 : sqlite3_column_int64(stmt, 3);
        results.push_back(std::move(c));
    }

    return results;
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------


std::string DatabaseManager::generate_uuid() {
    // Simple UUID v4 generator using <random>.
    static thread_local std::mt19937 rng(std::random_device{}());
    std::uniform_int_distribution<uint32_t> dist(0, 15);

    const char* hex = "0123456789abcdef";
    // Format: 8-4-4-4-12
    constexpr int kPattern[] = {
        8, -1, 4, -1, 4, -1, 4, -1, 12
    };

    std::string uuid;
    uuid.reserve(36);

    for (int group : kPattern) {
        if (group == -1) {
            uuid += '-';
        } else {
            for (int i = 0; i < group; ++i) {
                uuid += hex[dist(rng)];
            }
        }
    }

    // Set version (4) and variant (8/9/a/b) bits.
    uuid[14] = '4';
    uuid[19] = hex[(dist(rng) & 0x3) | 0x8];

    return uuid;
}

int64_t DatabaseManager::now_unix() {
    return static_cast<int64_t>(
        std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch())
            .count());
}

} // namespace vr
