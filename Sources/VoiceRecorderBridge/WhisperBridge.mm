//
//  WhisperBridge.mm
//  Obj-C++ implementation – bridges WhisperEngine and AudioConverter to Obj-C.
//

#import "WhisperBridge.h"

#include "WhisperEngine.hpp"
#include "AudioConverter.hpp"

#include <memory>
#include <string>
#include <vector>

// ---------------------------------------------------------------------------
// Error domain & codes
// ---------------------------------------------------------------------------

static NSString * const kWhisperBridgeErrorDomain = @"com.brainphart.WhisperBridge";

typedef NS_ENUM(NSInteger, WhisperBridgeErrorCode) {
    WhisperBridgeErrorModelNotLoaded = 1,
    WhisperBridgeErrorConversionFailed,
    WhisperBridgeErrorTranscriptionFailed,
    WhisperBridgeErrorFileNotFound,
};

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface WhisperBridge () {
    std::unique_ptr<vr::WhisperEngine>   _engine;
    std::unique_ptr<vr::AudioConverter>  _converter;
    dispatch_queue_t                     _workerQueue;
}
@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation WhisperBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine    = std::make_unique<vr::WhisperEngine>();
        _converter = std::make_unique<vr::AudioConverter>();
        _workerQueue = dispatch_queue_create("com.brainphart.whisperbridge.worker",
                                             DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// ---- Model loading --------------------------------------------------------

- (BOOL)loadModel:(NSString *)modelPath {
    if (!modelPath || modelPath.length == 0) {
        return NO;
    }

    try {
        std::string path = std::string([modelPath UTF8String]);
        return _engine->init(path) ? YES : NO;
    } catch (const std::exception &e) {
        NSLog(@"[WhisperBridge] loadModel exception: %s", e.what());
        return NO;
    }
}

- (BOOL)isModelLoaded {
    return _engine->is_loaded() ? YES : NO;
}

// ---- Transcription --------------------------------------------------------

- (void)transcribeAudioAtPath:(NSString *)audioPath
                   sampleRate:(int)sampleRate
                     progress:(void (^)(float progress))progressBlock
                   completion:(void (^)(NSString * _Nullable transcript,
                                        NSError * _Nullable error))completionBlock {

    // Capture Obj-C blocks into the dispatch call.
    // Copy blocks so they outlive this scope.
    void (^safeProgress)(float) = [progressBlock copy];
    void (^safeCompletion)(NSString * _Nullable, NSError * _Nullable) = [completionBlock copy];

    dispatch_async(_workerQueue, ^{

        // 1. Pre-flight checks
        if (!self->_engine->is_loaded()) {
            NSError *err = [NSError errorWithDomain:kWhisperBridgeErrorDomain
                                               code:WhisperBridgeErrorModelNotLoaded
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"Whisper model is not loaded."}];
            [self dispatchCompletion:safeCompletion transcript:nil error:err];
            return;
        }

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:audioPath]) {
            NSError *err = [NSError errorWithDomain:kWhisperBridgeErrorDomain
                                               code:WhisperBridgeErrorFileNotFound
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"Audio file not found at specified path."}];
            [self dispatchCompletion:safeCompletion transcript:nil error:err];
            return;
        }

        // 2. Convert M4A -> PCM float32
        std::vector<float> pcm;
        try {
            std::string path = std::string([audioPath UTF8String]);
            pcm = self->_converter->m4a_to_pcm(path, sampleRate);
        } catch (const std::exception &e) {
            NSError *err = [NSError errorWithDomain:kWhisperBridgeErrorDomain
                                               code:WhisperBridgeErrorConversionFailed
                                           userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Audio conversion failed: %s", e.what()]}];
            [self dispatchCompletion:safeCompletion transcript:nil error:err];
            return;
        }

        if (pcm.empty()) {
            NSError *err = [NSError errorWithDomain:kWhisperBridgeErrorDomain
                                               code:WhisperBridgeErrorConversionFailed
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                          @"Audio conversion produced empty PCM data."}];
            [self dispatchCompletion:safeCompletion transcript:nil error:err];
            return;
        }

        // 3. Build progress callback that dispatches to main queue
        vr::ProgressCallback cppProgress = nullptr;
        if (safeProgress) {
            cppProgress = [safeProgress](float p) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    safeProgress(p);
                });
            };
        }

        // 4. Run transcription
        std::string result;
        try {
            result = self->_engine->transcribe(pcm, sampleRate, cppProgress);
        } catch (const std::exception &e) {
            NSError *err = [NSError errorWithDomain:kWhisperBridgeErrorDomain
                                               code:WhisperBridgeErrorTranscriptionFailed
                                           userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Transcription failed: %s", e.what()]}];
            [self dispatchCompletion:safeCompletion transcript:nil error:err];
            return;
        }

        // 5. Deliver result
        NSString *transcript = [[NSString alloc] initWithUTF8String:result.c_str()];
        [self dispatchCompletion:safeCompletion transcript:transcript error:nil];
    });
}

// ---- Helpers --------------------------------------------------------------

/// Dispatch a completion block to the main queue.
- (void)dispatchCompletion:(void (^)(NSString * _Nullable, NSError * _Nullable))block
                transcript:(NSString * _Nullable)transcript
                     error:(NSError * _Nullable)error {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(transcript, error);
    });
}

@end
