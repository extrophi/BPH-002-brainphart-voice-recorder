//
//  StorageBridge.mm
//  Obj-C++ implementation – bridges DatabaseManager to Obj-C.
//
//  All public methods are synchronous.  Thread safety is provided by
//  DatabaseManager's internal SQLite serialization.
//

#import "StorageBridge.h"

#include "DatabaseManager.hpp"
#include "Types.hpp"

#include <memory>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// VRSession implementation
// ---------------------------------------------------------------------------

@implementation VRSession
@end

// ---------------------------------------------------------------------------
// Error domain & codes
// ---------------------------------------------------------------------------

static NSString * const kStorageBridgeErrorDomain = @"com.brainphart.StorageBridge";

typedef NS_ENUM(NSInteger, StorageBridgeErrorCode) {
    StorageBridgeErrorDatabaseInit = 1,
    StorageBridgeErrorSessionCreate,
    StorageBridgeErrorChunkAdd,
    StorageBridgeErrorQuery,
};

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface StorageBridge () {
    std::unique_ptr<vr::DatabaseManager> _db;
}
@end

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert a C++ RecordingSession to an Obj-C VRSession.
static VRSession *SessionToObjC(const vr::RecordingSession &s) {
    VRSession *obj = [[VRSession alloc] init];
    obj.sessionId   = [[NSString alloc] initWithUTF8String:s.id.c_str()];
    obj.createdAt   = static_cast<NSInteger>(s.created_at);
    obj.completedAt = static_cast<NSInteger>(s.completed_at);
    obj.status      = [[NSString alloc] initWithUTF8String:vr::status_to_string(s.status)];
    obj.durationMs  = static_cast<NSInteger>(s.duration_ms);

    if (!s.transcript.empty()) {
        obj.transcript = [[NSString alloc] initWithUTF8String:s.transcript.c_str()];
    } else {
        obj.transcript = nil;
    }

    return obj;
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation StorageBridge

- (instancetype)initWithDatabasePath:(NSString *)dbPath {
    self = [super init];
    if (self) {
        try {
            std::string path = std::string([dbPath UTF8String]);
            _db = std::make_unique<vr::DatabaseManager>(path);
            if (!_db->open()) {
                NSLog(@"[StorageBridge] Failed to open database at: %@", dbPath);
                _db = nullptr;
            }
        } catch (const std::exception &e) {
            NSLog(@"[StorageBridge] DatabaseManager init failed: %s", e.what());
            _db = nullptr;
        }
    }
    return self;
}

- (instancetype)init {
    // Fallback: resolve via HOME env (non-sandbox only).
    NSArray *paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupport = paths.firstObject ?: NSTemporaryDirectory();
    NSString *dir = [appSupport stringByAppendingPathComponent:@"VoiceRecorder"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *dbPath = [dir stringByAppendingPathComponent:@"voicerecorder.db"];
    return [self initWithDatabasePath:dbPath];
}

// ---- Session lifecycle ----------------------------------------------------

- (NSString *)createSession {
    if (!_db) {
        NSLog(@"[StorageBridge] createSession called but database is not initialized.");
        return @"";
    }

    try {
        std::string sessionId = _db->create_session();
        return [[NSString alloc] initWithUTF8String:sessionId.c_str()];
    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] createSession exception: %s", e.what());
        return @"";
    }
}

- (BOOL)addChunk:(NSData *)audioData
       toSession:(NSString *)sessionId
         atIndex:(NSInteger)index {
    if (!_db) {
        NSLog(@"[StorageBridge] addChunk called but database is not initialized.");
        return NO;
    }

    if (!audioData || audioData.length == 0) {
        NSLog(@"[StorageBridge] addChunk called with empty audio data for session %@", sessionId);
        return NO;
    }

    try {
        std::string sid = std::string([sessionId UTF8String]);
        int32_t idx = static_cast<int32_t>(index);

        // Copy NSData bytes into the vector.
        const uint8_t *bytes = static_cast<const uint8_t *>(audioData.bytes);
        std::vector<uint8_t> data(bytes, bytes + audioData.length);

        bool ok = _db->add_chunk(sid, idx, data, 0);
        if (!ok) {
            NSLog(@"[StorageBridge] add_chunk returned false for session %@ chunk %d (%lu bytes)",
                  sessionId, idx, (unsigned long)audioData.length);
        } else {
            NSLog(@"[StorageBridge] Stored chunk %d for session %@ (%lu bytes)",
                  idx, sessionId, (unsigned long)audioData.length);
        }
        return ok ? YES : NO;

    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] addChunk exception: %s", e.what());
        return NO;
    }
}

- (void)updateTranscript:(NSString *)transcript
              forSession:(NSString *)sessionId {
    if (!_db) return;

    try {
        std::string sid  = std::string([sessionId UTF8String]);
        std::string text = std::string([transcript UTF8String]);
        _db->update_transcript(sid, text, 0);
    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] updateTranscript exception: %s", e.what());
    }
}

- (void)completeSession:(NSString *)sessionId
           withDuration:(NSInteger)durationMs {
    if (!_db) return;

    try {
        std::string sid = std::string([sessionId UTF8String]);
        _db->update_status(sid, vr::RecordingStatus::complete);
        _db->update_duration(sid, static_cast<int64_t>(durationMs));
    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] completeSession exception: %s", e.what());
    }
}

// ---- Queries --------------------------------------------------------------

- (NSArray<VRSession *> *)getAllSessions {
    if (!_db) return @[];

    try {
        std::vector<vr::RecordingSession> sessions = _db->get_sessions();
        NSMutableArray<VRSession *> *result =
            [[NSMutableArray alloc] initWithCapacity:sessions.size()];

        for (const auto &s : sessions) {
            [result addObject:SessionToObjC(s)];
        }

        return [result copy];

    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] getAllSessions exception: %s", e.what());
        return @[];
    }
}

- (NSData * _Nullable)getAudioForSession:(NSString *)sessionId {
    if (!_db) return nil;

    try {
        std::string sid = std::string([sessionId UTF8String]);
        std::vector<vr::AudioChunk> chunks = _db->get_chunks(sid);

        if (chunks.empty()) {
            return nil;
        }

        // For a single chunk, return it directly.
        if (chunks.size() == 1) {
            const auto &data = chunks[0].audio_data;
            return [[NSData alloc] initWithBytes:data.data() length:data.size()];
        }

        // Multiple chunks: concatenate raw PCM data.
        // Chunks are stored as 16kHz mono Float32 PCM bytes, so simple
        // byte concatenation produces a valid continuous PCM stream.
        //
        // Estimate total size for a single allocation.
        size_t totalSize = 0;
        for (const auto &chunk : chunks) {
            totalSize += chunk.audio_data.size();
        }

        NSMutableData *combined = [[NSMutableData alloc] initWithCapacity:totalSize];
        for (const auto &chunk : chunks) {
            [combined appendBytes:chunk.audio_data.data()
                           length:chunk.audio_data.size()];
        }

        return [combined copy];

    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] getAudioForSession exception: %s", e.what());
        return nil;
    }
}

- (void)deleteSession:(NSString *)sessionId {
    if (!_db) return;

    try {
        std::string sid = std::string([sessionId UTF8String]);
        _db->delete_session(sid);
    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] deleteSession exception: %s", e.what());
    }
}

- (NSArray<VRSession *> *)getOrphanedSessions {
    if (!_db) return @[];

    try {
        std::vector<vr::RecordingSession> orphans = _db->get_orphaned_sessions();
        NSMutableArray<VRSession *> *result =
            [[NSMutableArray alloc] initWithCapacity:orphans.size()];

        for (const auto &s : orphans) {
            [result addObject:SessionToObjC(s)];
        }

        return [result copy];

    } catch (const std::exception &e) {
        NSLog(@"[StorageBridge] getOrphanedSessions exception: %s", e.what());
        return @[];
    }
}

@end
