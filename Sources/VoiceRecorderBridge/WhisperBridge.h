//
//  WhisperBridge.h
//  Objective-C interface wrapping the C++ WhisperEngine + AudioConverter.
//
//  Thread-safe.  Transcription runs on a background dispatch queue; progress
//  and completion blocks are always dispatched back to the main queue.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C wrapper around `vr::WhisperEngine` and `vr::AudioConverter`.
///
/// Typical usage from Swift:
/// ```swift
/// let whisper = WhisperBridge()
/// whisper.loadModel(Bundle.main.path(forResource: "ggml-base.en", ofType: "bin")!)
/// whisper.transcribeAudio(atPath: chunkURL.path, sampleRate: 16000,
///                         progress: { p in print(p) },
///                         completion: { text, err in ... })
/// ```
@interface WhisperBridge : NSObject

/// Load a whisper.cpp ggml model from the given filesystem path.
/// Returns YES on success, NO on failure (bad path, corrupt model, etc.).
- (BOOL)loadModel:(NSString *)modelPath;

/// Whether a model has been successfully loaded and is ready for inference.
- (BOOL)isModelLoaded;

/// Transcribe audio from an M4A (or other supported) file on disk.
///
/// The file is first converted to raw PCM via AudioConverter, then fed into
/// WhisperEngine.  The work happens on a background serial queue.
///
/// @param audioPath      Absolute path to the audio file (typically M4A).
/// @param sampleRate     Desired decode sample rate (e.g. 16000).
/// @param progressBlock  Called repeatedly on the **main queue** with 0.0-1.0.
/// @param completionBlock Called once on the **main queue** with the transcript
///                        string or an NSError.
- (void)transcribeAudioAtPath:(NSString *)audioPath
                   sampleRate:(int)sampleRate
                     progress:(void (^)(float progress))progressBlock
                   completion:(void (^)(NSString * _Nullable transcript,
                                        NSError * _Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
