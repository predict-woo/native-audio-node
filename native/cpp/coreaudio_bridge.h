#ifndef COREAUDIO_BRIDGE_H
#define COREAUDIO_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle type for the audio capture session
typedef void* AudioRecorderHandle;

// Callback types
typedef void (*AudioDataCallback)(const uint8_t* data, int32_t length, void* context);
typedef void (*AudioEventCallback)(int32_t eventType, const char* message, void* context);
typedef void (*AudioMetadataCallback)(double sampleRate, uint32_t channelsPerFrame,
                                       uint32_t bitsPerChannel, bool isFloat,
                                       const char* encoding, void* context);

// Create a new audio recorder session
AudioRecorderHandle coreaudio_create(
    AudioDataCallback dataCallback,
    AudioEventCallback eventCallback,
    AudioMetadataCallback metadataCallback,
    void* userContext
);

// Start system audio capture
int32_t coreaudio_start_system_audio(
    AudioRecorderHandle handle,
    double sampleRate,
    double chunkDurationMs,
    bool mute,
    bool isMono,
    const int32_t* includeProcesses,
    int32_t includeProcessCount,
    const int32_t* excludeProcesses,
    int32_t excludeProcessCount
);

// Start microphone capture
int32_t coreaudio_start_microphone(
    AudioRecorderHandle handle,
    double sampleRate,
    double chunkDurationMs,
    bool isMono,
    const char* deviceUID,  // NULL for default device
    double gain             // 0.0 to 1.0
);

// Stop audio capture
int32_t coreaudio_stop(AudioRecorderHandle handle);

// Destroy the session and free resources
void coreaudio_destroy(AudioRecorderHandle handle);

// Check if session is running
bool coreaudio_is_running(AudioRecorderHandle handle);

// ============================================================================
// Device Enumeration
// ============================================================================

// List all audio devices
// Returns 0 on success, populates devices with raw pointer to device array
// Struct layout per device (48 bytes): uid(8) + name(8) + manufacturer(8) + isDefault(1) + isInput(1) + isOutput(1) + pad(5) + sampleRate(8) + channelCount(4) + pad(4)
// Caller must free with coreaudio_free_device_list
int32_t coreaudio_list_devices(void** devices, int32_t* count);

// Free device list allocated by coreaudio_list_devices
void coreaudio_free_device_list(void* devices, int32_t count);

// Get default input device UID (caller must free)
char* coreaudio_get_default_input_device(void);

// Get default output device UID (caller must free)
char* coreaudio_get_default_output_device(void);

// ============================================================================
// System Audio Permission API (uses TCC private framework)
// ============================================================================

// Status: 0 = unknown, 1 = denied, 2 = authorized
int32_t coreaudio_system_audio_permission_status(void);

// Request permission callback type
typedef void (*PermissionCallback)(bool granted, void* context);

// Request system audio permission (async)
void coreaudio_system_audio_permission_request(PermissionCallback callback, void* context);

// Check if TCC framework is available
bool coreaudio_system_audio_permission_available(void);

// Open System Settings to permission pane
bool coreaudio_open_system_settings(void);

// ============================================================================
// Microphone Permission API (uses public AVFoundation API)
// ============================================================================

// Status: 0 = unknown, 1 = denied, 2 = authorized
int32_t coreaudio_mic_permission_status(void);

// Request microphone permission (async)
void coreaudio_mic_permission_request(PermissionCallback callback, void* context);

#ifdef __cplusplus
}
#endif

#endif // COREAUDIO_BRIDGE_H
