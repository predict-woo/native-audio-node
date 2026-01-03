#ifndef AUDIOTEE_BRIDGE_H
#define AUDIOTEE_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle type for the audio capture session
typedef void* AudioTeeHandle;

// Callback types
typedef void (*AudioDataCallback)(const uint8_t* data, int32_t length, void* context);
typedef void (*AudioEventCallback)(int32_t eventType, const char* message, void* context);
typedef void (*AudioMetadataCallback)(double sampleRate, uint32_t channelsPerFrame,
                                       uint32_t bitsPerChannel, bool isFloat,
                                       const char* encoding, void* context);

// Create a new AudioTee session
AudioTeeHandle audiotee_create(
    AudioDataCallback dataCallback,
    AudioEventCallback eventCallback,
    AudioMetadataCallback metadataCallback,
    void* userContext
);

// Start audio capture
int32_t audiotee_start(
    AudioTeeHandle handle,
    double sampleRate,
    double chunkDurationMs,
    bool mute,
    bool isMono,
    const int32_t* includeProcesses,
    int32_t includeProcessCount,
    const int32_t* excludeProcesses,
    int32_t excludeProcessCount
);

// Stop audio capture
int32_t audiotee_stop(AudioTeeHandle handle);

// Destroy the session and free resources
void audiotee_destroy(AudioTeeHandle handle);

// Check if session is running
bool audiotee_is_running(AudioTeeHandle handle);

// Permission API
// Status: 0 = unknown, 1 = denied, 2 = authorized
int32_t audiotee_permission_status(void);

// Request permission callback type
typedef void (*PermissionCallback)(bool granted, void* context);

// Request permission (async)
void audiotee_permission_request(PermissionCallback callback, void* context);

// Check if TCC framework is available
bool audiotee_permission_available(void);

// Open System Settings to permission pane
bool audiotee_open_system_settings(void);

#ifdef __cplusplus
}
#endif

#endif // AUDIOTEE_BRIDGE_H
