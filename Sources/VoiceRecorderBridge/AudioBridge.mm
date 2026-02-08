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
    // Generate a new UUID for this session.
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    self.currentSessionId = sessionId;

    // Build the file path inside the temporary directory.
    // AudioRecorder will write chunks as <basePath>_chunk_<N>.m4a
    NSString *tempDir = NSTemporaryDirectory();
    NSString *basePath = [tempDir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"vr_%@", sessionId]];

    // Capture a weak reference so the burst callback doesn't create a retain cycle.
    __weak typeof(self) weakSelf = self;

    dispatch_async(_recorderQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        try {
            std::string path = std::string([basePath UTF8String]);

            // Register the burst callback so AudioRecorder tells us about
            // every 35-second chunk.
            strongSelf->_recorder->set_burst_callback([weakSelf](const vr::AudioChunk &chunk) {
                __strong typeof(weakSelf) innerSelf = weakSelf;
                if (!innerSelf) return;

                // Convert the raw bytes to NSData (copies once).
                NSData *audioData = [[NSData alloc] initWithBytes:chunk.audio_data.data()
                                                           length:chunk.audio_data.size()];
                NSInteger idx = static_cast<NSInteger>(chunk.chunk_index);

                // Deliver on the main queue.
                if (innerSelf.onChunkComplete) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (innerSelf.onChunkComplete) {
                            innerSelf.onChunkComplete(audioData, idx);
                        }
                    });
                }
            });

            strongSelf->_recorder->start_recording(path);

            dispatch_async(dispatch_get_main_queue(), ^{
                strongSelf.isRecording = YES;
            });

        } catch (const std::exception &e) {
            NSLog(@"[AudioBridge] startRecording exception: %s", e.what());
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) s = weakSelf;
                if (s) {
                    s.isRecording = NO;
                }
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

    __weak typeof(self) weakSelf = self;

    dispatch_async(_recorderQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
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
