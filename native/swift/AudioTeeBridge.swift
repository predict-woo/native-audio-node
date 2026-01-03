import Foundation
import CoreAudio
import AVFoundation
import AudioToolbox

// MARK: - Global State Management

/// Opaque handle type for the audio capture session
public typealias AudioTeeHandle = UnsafeMutableRawPointer

/// Callback type for receiving audio data
public typealias AudioDataCallback = @convention(c) (
    UnsafePointer<UInt8>,  // data pointer
    Int32,                  // data length
    UnsafeMutableRawPointer? // user context
) -> Void

/// Callback type for receiving events (start, stop, error)
public typealias AudioEventCallback = @convention(c) (
    Int32,                   // event type: 0=start, 1=stop, 2=error
    UnsafePointer<CChar>?,   // message (for errors)
    UnsafeMutableRawPointer? // user context
) -> Void

/// Callback type for receiving metadata
public typealias AudioMetadataCallback = @convention(c) (
    Double,   // sample rate
    UInt32,   // channels per frame
    UInt32,   // bits per channel
    Bool,     // is float
    UnsafePointer<CChar>, // encoding string
    UnsafeMutableRawPointer? // user context
) -> Void

// MARK: - Session State

class AudioTeeSession {
    var tapManager: AudioTapManager?
    var recorder: NativeAudioRecorder?
    var isRunning: Bool = false

    let dataCallback: AudioDataCallback?
    let eventCallback: AudioEventCallback?
    let metadataCallback: AudioMetadataCallback?
    let userContext: UnsafeMutableRawPointer?

    init(
        dataCallback: AudioDataCallback?,
        eventCallback: AudioEventCallback?,
        metadataCallback: AudioMetadataCallback?,
        userContext: UnsafeMutableRawPointer?
    ) {
        self.dataCallback = dataCallback
        self.eventCallback = eventCallback
        self.metadataCallback = metadataCallback
        self.userContext = userContext
    }

    func emitData(_ data: Data) {
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                dataCallback?(baseAddress, Int32(buffer.count), userContext)
            }
        }
    }

    func emitEvent(_ eventType: Int32, message: String? = nil) {
        if let msg = message {
            msg.withCString { cstr in
                eventCallback?(eventType, cstr, userContext)
            }
        } else {
            eventCallback?(eventType, nil, userContext)
        }
    }

    func emitMetadata(_ metadata: NativeAudioMetadata) {
        metadata.encoding.withCString { encodingCStr in
            metadataCallback?(
                metadata.sampleRate,
                metadata.channelsPerFrame,
                metadata.bitsPerChannel,
                metadata.isFloat,
                encodingCStr,
                userContext
            )
        }
    }
}

// MARK: - C-Compatible API

/// Creates a new AudioTee session
/// Returns an opaque handle that must be freed with audiotee_destroy
@_cdecl("audiotee_create")
public func audiotee_create(
    dataCallback: AudioDataCallback?,
    eventCallback: AudioEventCallback?,
    metadataCallback: AudioMetadataCallback?,
    userContext: UnsafeMutableRawPointer?
) -> AudioTeeHandle? {
    let session = AudioTeeSession(
        dataCallback: dataCallback,
        eventCallback: eventCallback,
        metadataCallback: metadataCallback,
        userContext: userContext
    )

    return Unmanaged.passRetained(session).toOpaque()
}

/// Configuration options passed as a struct
@_cdecl("audiotee_start")
public func audiotee_start(
    handle: AudioTeeHandle,
    sampleRate: Double,           // 0 for native rate
    chunkDurationMs: Double,      // chunk duration in milliseconds
    mute: Bool,
    isMono: Bool,
    includeProcesses: UnsafePointer<Int32>?,
    includeProcessCount: Int32,
    excludeProcesses: UnsafePointer<Int32>?,
    excludeProcessCount: Int32
) -> Int32 {
    guard let session = Unmanaged<AudioTeeSession>.fromOpaque(handle).takeUnretainedValue() as AudioTeeSession? else {
        return -1
    }

    if session.isRunning {
        return -2 // Already running
    }

    // Convert process arrays
    var includeList: [Int32] = []
    var excludeList: [Int32] = []

    if let ptr = includeProcesses, includeProcessCount > 0 {
        includeList = Array(UnsafeBufferPointer(start: ptr, count: Int(includeProcessCount)))
    }

    if let ptr = excludeProcesses, excludeProcessCount > 0 {
        excludeList = Array(UnsafeBufferPointer(start: ptr, count: Int(excludeProcessCount)))
    }

    // Determine process configuration
    let (processes, isExclusive): ([Int32], Bool)
    if !includeList.isEmpty {
        processes = includeList
        isExclusive = false
    } else if !excludeList.isEmpty {
        processes = excludeList
        isExclusive = true
    } else {
        processes = []
        isExclusive = true
    }

    // Create tap configuration
    let tapConfig = TapConfiguration(
        processes: processes,
        muteBehavior: mute ? .muted : .unmuted,
        isExclusive: isExclusive,
        isMono: isMono
    )

    // Set up audio tap
    let tapManager = AudioTapManager()
    do {
        try tapManager.setupAudioTap(with: tapConfig)
    } catch {
        session.emitEvent(2, message: "Failed to setup audio tap: \(error)")
        return -3
    }

    guard let deviceID = tapManager.getDeviceID() else {
        session.emitEvent(2, message: "Failed to get device ID")
        return -4
    }

    session.tapManager = tapManager

    // Create native output handler that calls our callbacks
    let outputHandler = NativeAudioOutputHandler(session: session)

    // Convert chunk duration from ms to seconds
    let chunkDurationSec = chunkDurationMs / 1000.0

    // Create recorder
    let targetSampleRate: Double? = sampleRate > 0 ? sampleRate : nil
    let recorder = NativeAudioRecorder(
        deviceID: deviceID,
        outputHandler: outputHandler,
        convertToSampleRate: targetSampleRate,
        chunkDuration: chunkDurationSec
    )

    session.recorder = recorder
    session.isRunning = true

    // Start recording in a background thread
    DispatchQueue.global(qos: .userInitiated).async {
        recorder.startRecording()

        // Run the audio processing loop
        while session.isRunning {
            let result = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, false)
            if result == CFRunLoopRunResult.stopped || result == CFRunLoopRunResult.finished {
                break
            }
        }
    }

    return 0
}

/// Stops the audio capture session
@_cdecl("audiotee_stop")
public func audiotee_stop(handle: AudioTeeHandle) -> Int32 {
    guard let session = Unmanaged<AudioTeeSession>.fromOpaque(handle).takeUnretainedValue() as AudioTeeSession? else {
        return -1
    }

    if !session.isRunning {
        return 0 // Already stopped
    }

    session.isRunning = false
    session.recorder?.stopRecording()
    session.recorder = nil
    session.tapManager = nil

    return 0
}

/// Destroys the AudioTee session and frees resources
@_cdecl("audiotee_destroy")
public func audiotee_destroy(handle: AudioTeeHandle) {
    // Stop if running
    _ = audiotee_stop(handle: handle)

    // Release the session
    Unmanaged<AudioTeeSession>.fromOpaque(handle).release()
}

/// Returns whether the session is currently recording
@_cdecl("audiotee_is_running")
public func audiotee_is_running(handle: AudioTeeHandle) -> Bool {
    guard let session = Unmanaged<AudioTeeSession>.fromOpaque(handle).takeUnretainedValue() as AudioTeeSession? else {
        return false
    }
    return session.isRunning
}
