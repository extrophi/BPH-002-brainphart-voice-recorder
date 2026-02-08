//
//  AudioBridge.mm
//  Obj-C++ implementation – bridges AudioRecorder to Obj-C.
//

#import "AudioBridge.h"

#include "AudioRecorder.hpp"
#include "Types.hpp"

#include <memory>
#include <string>

// ---------------------------------------------------------------------------
// Error domain & codes
// ---------------------------------------------------------------------------

static NSString * const kAudioBridgeErrorDomain = @"com.brainphart.AudioBridge";

typedef NS_ENUM(NSInteger, AudioBridgeErrorCode) {
    AudioBridgeErrorNotRecording = 1,
    AudioBridgeErrorStartFailed,
    AudioBridgeErrorStopFailed,
};

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface AudioBridge () {
    std::unique_ptr<vr::AudioRecorder> _recorder;
    dispatch_queue_t                   _recorderQueue;
}

@property (nonatomic, strong, readwrite) NSString *currentSessionId;
@property (nonatomic, readwrite)         BOOL      isRecording;

@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation AudioBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _recorder = std::make_unique<vr::AudioRecorder>();
        _recorderQueue = dispatch_queue_create("com.brainphart.audiobridge.recorder",
                                               DISPATCH_QUEUE_SERIAL);
        _isRecording = NO;
    }
    return self;
}

// ---- Recording lifecycle --------------------------------------------------

- (void)startRecording {
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    self.currentSessionId = sessionId;

    NSString *tempDir = NSTemporaryDirectory();
    NSString *sessionDir = [tempDir stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"vr_%@", sessionId]];

    // Create the session directory.
    [[NSFileManager defaultManager] createDirectoryAtPath:sessionDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    __weak AudioBridge *weakSelf = self;

    dispatch_async(_recorderQueue, ^{
        __strong AudioBridge *strongSelf = weakSelf;
        if (!strongSelf) return;

        try {
            std::string dir = std::string([sessionDir UTF8String]);
            std::string sid = std::string([sessionId UTF8String]);

            // Build burst callback.
            vr::BurstCallback burst_cb = [weakSelf](const vr::AudioChunk &chunk) {
                __strong AudioBridge *innerSelf = weakSelf;
                if (!innerSelf) return;

                NSData *audioData = [[NSData alloc] initWithBytes:chunk.audio_data.data()
                                                           length:chunk.audio_data.size()];
                NSInteger idx = static_cast<NSInteger>(chunk.chunk_index);

                if (innerSelf.onChunkComplete) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (innerSelf.onChunkComplete) {
                            innerSelf.onChunkComplete(audioData, idx);
                        }
                    });
                }
            };

            // Build metering callback.
            vr::MeteringCallback meter_cb = [weakSelf](float level) {
                // metering is polled via currentMeteringLevel, no need to dispatch
            };

            bool ok = strongSelf->_recorder->start_recording(dir, sid,
                                                              std::move(burst_cb),
                                                              std::move(meter_cb));

            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.isRecording = ok;
            });

        } catch (const std::exception &e) {
            NSLog(@"[AudioBridge] startRecording exception: %s", e.what());
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong AudioBridge *s = weakSelf;
                if (s) s.isRecording = NO;
            });
        }
    });
}

- (void)stopRecordingWithCompletion:(void (^)(NSString * _Nullable sessionId,
                                              NSError * _Nullable error))completionBlock {

    void (^safeCompletion)(NSString * _Nullable, NSError * _Nullable) = [completionBlock copy];

    if (!self.isRecording) {
        NSError *err = [NSError errorWithDomain:kAudioBridgeErrorDomain
                                           code:AudioBridgeErrorNotRecording
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                      @"No recording is in progress."}];
        if (safeCompletion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                safeCompletion(nil, err);
            });
        }
        return;
    }

    NSString *sessionId = self.currentSessionId;

    __weak AudioBridge *weakSelf = self;

    dispatch_async(_recorderQueue, ^{
        __strong AudioBridge *strongSelf = weakSelf;
        if (!strongSelf) return;

        try {
            std::string finalPath = strongSelf->_recorder->stop_recording();

            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.isRecording = NO;
                if (safeCompletion) {
                    safeCompletion(sessionId, nil);
                }
            });

        } catch (const std::exception &e) {
            NSError *err = [NSError errorWithDomain:kAudioBridgeErrorDomain
                                               code:AudioBridgeErrorStopFailed
                                           userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Stop recording failed: %s", e.what()]}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf) {
                    strongSelf.isRecording = NO;
                }
                if (safeCompletion) {
                    safeCompletion(nil, err);
                }
            });
        }
    });
}

// ---- Metering -------------------------------------------------------------

- (float)currentMeteringLevel {
    try {
        return _recorder->get_metering();
    } catch (const std::exception &e) {
        return 0.0f;
    }
}

@end
