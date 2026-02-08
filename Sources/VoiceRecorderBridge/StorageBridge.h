//
//  StorageBridge.h
//  Objective-C interface wrapping the C++ DatabaseManager.
//
//  All methods are **synchronous** -- callers are expected to dispatch from
//  background queues as needed.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// VRSession – Obj-C mirror of vr::RecordingSession
// ---------------------------------------------------------------------------

/// A lightweight value object representing a single recording session.
/// Maps 1-to-1 with the `recording_sessions` table in the SQLite database.
@interface VRSession : NSObject

/// UUID string identifying this session.
@property (nonatomic, strong) NSString *sessionId;

/// Unix timestamp (seconds) when the session was created.
@property (nonatomic) NSInteger createdAt;

/// Unix timestamp (seconds) when the session was completed (0 if still active).
@property (nonatomic) NSInteger completedAt;

/// Human-readable status: "recording", "transcribing", "complete", "failed".
@property (nonatomic, strong) NSString *status;

/// Total duration of all chunks in milliseconds.
@property (nonatomic) NSInteger durationMs;

/// Final concatenated transcript, or nil if not yet transcribed.
@property (nonatomic, strong, nullable) NSString *transcript;

@end

// ---------------------------------------------------------------------------
// StorageBridge
// ---------------------------------------------------------------------------

/// Obj-C wrapper around `vr::DatabaseManager`.
///
/// Usage from Swift:
/// ```swift
/// let storage = StorageBridge()
/// let sessionId = storage.createSession()
/// storage.addChunk(chunkData, toSession: sessionId, atIndex: 0)
/// storage.updateTranscript("Hello world", forSession: sessionId)
/// let sessions = storage.getAllSessions()  // [VRSession]
/// ```
@interface StorageBridge : NSObject

/// Initializes the bridge with an explicit database file path.
/// The path is resolved by the Swift layer (Config.databasePath) which
/// uses FileManager to handle sandbox correctly.
- (instancetype)initWithDatabasePath:(NSString *)dbPath;

/// Convenience init — uses a default path. Prefer initWithDatabasePath:.
- (instancetype)init;

// ---- Session lifecycle ----------------------------------------------------

/// Create a new recording session in the database.
/// @return The UUID string of the newly created session.
- (NSString *)createSession;

/// Persist an audio chunk (M4A data) for the given session.
/// @param audioData  Raw M4A file bytes.
/// @param sessionId  The session this chunk belongs to.
/// @param index      Zero-based chunk index within the session.
- (void)addChunk:(NSData *)audioData
       toSession:(NSString *)sessionId
         atIndex:(NSInteger)index;

/// Replace (or set) the transcript text for a session.
- (void)updateTranscript:(NSString *)transcript
              forSession:(NSString *)sessionId;

/// Mark a session as complete with the given total duration.
- (void)completeSession:(NSString *)sessionId
           withDuration:(NSInteger)durationMs;

// ---- Queries --------------------------------------------------------------

/// Return every session in the database, ordered by creation time descending.
- (NSArray<VRSession *> *)getAllSessions;

/// Reconstruct the full audio for a session by concatenating all of its
/// chunks' M4A data.  Returns nil if no chunks exist.
- (NSData * _Nullable)getAudioForSession:(NSString *)sessionId;

/// Permanently delete a session and all its chunks.
- (void)deleteSession:(NSString *)sessionId;

/// Find sessions whose status is still "recording" (likely left behind by a
/// crash).  The Swift layer can decide whether to attempt recovery.
- (NSArray<VRSession *> *)getOrphanedSessions;

@end

NS_ASSUME_NONNULL_END
