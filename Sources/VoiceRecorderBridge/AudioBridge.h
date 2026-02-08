//
//  AudioBridge.h
//  Objective-C interface wrapping the C++ AudioRecorder.
//
//  Manages recording sessions, chunk splitting (every 35 seconds), and
//  metering levels for real-time UI waveform display.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C wrapper around `vr::AudioRecorder`.
///
/// Usage from Swift:
/// ```swift
/// let audio = AudioBridge()
/// audio.onChunkComplete = { data, index in
///     // Persist chunk
/// }
/// audio.startRecording()
/// // ... later ...
/// audio.stopRecording { sessionId, error in
///     guard let sessionId else { return }
///     // Recording finished
/// }
/// ```
@interface AudioBridge : NSObject

/// Start recording audio.  A new session UUID is generated automatically.
/// Audio is captured via the C++ AudioRecorder; chunks are delivered every
/// 35 seconds through `onChunkComplete`.
- (void)startRecording;

/// Stop the active recording.
///
/// @param completionBlock Called on the **main queue** with the session UUID
///                        (or an NSError if something went wrong).
- (void)stopRecordingWithCompletion:(void (^)(NSString * _Nullable sessionId,
                                              NSError * _Nullable error))completionBlock;

/// Returns the current audio metering level (0.0 - 1.0).
/// Safe to call from any thread; typically polled by the UI on a display-link timer.
- (float)currentMeteringLevel;

/// Called every 35 seconds with the finalized chunk's M4A data and its
/// zero-based index within the session.  Fired on the **main queue**.
@property (nonatomic, copy, nullable) void (^onChunkComplete)(NSData *audioData,
                                                               NSInteger chunkIndex);

/// The session UUID of the current (or most recent) recording.
/// `nil` if no recording has been started yet.
@property (nonatomic, strong, readonly, nullable) NSString *currentSessionId;

/// Whether a recording is currently in progress.
@property (nonatomic, readonly) BOOL isRecording;

@end

NS_ASSUME_NONNULL_END
