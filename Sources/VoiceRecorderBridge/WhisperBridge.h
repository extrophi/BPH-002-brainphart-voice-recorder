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
/// whisper.transcribePCMData(pcmData, sampleRate: 16000,
///                           progress: { p in print(p) },
///                           completion: { text, err in ... })
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

/// Transcribe raw PCM Float32 audio data directly (no file I/O needed).
///
/// The data should be mono Float32 samples at the given sample rate.
/// Runs on a background serial queue.
///
/// @param pcmData         Raw PCM data (mono Float32 samples as bytes).
/// @param sampleRate      Sample rate of the PCM data (e.g. 16000).
/// @param progressBlock   Called repeatedly on the **main queue** with 0.0-1.0.
/// @param completionBlock Called once on the **main queue** with the transcript
///                        string or an NSError.
- (void)transcribePCMData:(NSData *)pcmData
               sampleRate:(int)sampleRate
                 progress:(void (^)(float progress))progressBlock
               completion:(void (^)(NSString * _Nullable transcript,
                                    NSError * _Nullable error))completionBlock;

/// Explicitly free the whisper engine and all GGML backends.
/// Must be called before process exit to avoid a crash in ggml_metal_rsets_free
/// when C++ static destructors race with the Metal residency-set background thread.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
