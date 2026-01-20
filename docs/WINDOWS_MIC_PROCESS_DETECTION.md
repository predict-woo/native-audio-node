# Windows Microphone Process Detection - Implementation Plan

## Overview

Add the ability to detect which processes are using the microphone on Windows, matching the existing macOS functionality via `MicrophoneActivityMonitor.getActiveProcesses()`.

**Current State:**
- macOS: ✅ Fully implemented using Core Audio APIs
- Windows: ❌ Returns empty array (stub)

**Goal:** Windows feature parity using WASAPI audio session enumeration.

---

## Architecture

### API Flow

```
IAudioSessionManager2 (from capture device)
        ↓
GetSessionEnumerator()
        ↓
IAudioSessionEnumerator
        ↓
Iterate: IAudioSessionControl → IAudioSessionControl2
        ↓
Filter: GetState() == AudioSessionStateActive
        ↓
GetProcessId() → PID
        ↓
OpenProcess() + GetModuleBaseNameW() → Process Name
```

### File Changes

```
native/
├── include/
│   └── audio_bridge.h          # Already has mic_activity_get_active_processes()
├── windows/
│   └── windows_bridge.cpp      # UPDATE: Implement the function
└── napi/
    └── audio_napi.cpp          # No changes needed (already calls bridge)
```

---

## Implementation Steps

### Step 1: Add Required Headers

**File:** `native/windows/windows_bridge.cpp`

```cpp
#include <mmdeviceapi.h>      // IMMDeviceEnumerator, IMMDevice
#include <audiopolicy.h>      // IAudioSessionManager2, IAudioSessionControl2
#include <Psapi.h>            // GetModuleBaseNameW
#include <atlbase.h>          // CComPtr (or use raw pointers with Release())

#pragma comment(lib, "Psapi.lib")
```

### Step 2: Implement Helper Function - Get Process Name from PID

```cpp
static std::wstring GetProcessNameFromPid(DWORD pid) {
    std::wstring name;
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (hProcess) {
        WCHAR buffer[MAX_PATH];
        if (GetModuleBaseNameW(hProcess, NULL, buffer, MAX_PATH) > 0) {
            name = buffer;
            // Remove .exe extension if present
            size_t extPos = name.rfind(L".exe");
            if (extPos != std::wstring::npos) {
                name = name.substr(0, extPos);
            }
        }
        CloseHandle(hProcess);
    }
    return name;
}
```

### Step 3: Implement `mic_activity_get_active_processes()`

**File:** `native/windows/windows_bridge.cpp`

Replace the stub implementation:

```cpp
int32_t mic_activity_get_active_processes(
    MicActivityMonitorHandle handle,
    int32_t** pids,
    char*** names,
    char*** bundleIds,
    int32_t* count
) {
    if (!pids || !names || !bundleIds || !count) {
        return -1;
    }

    // Initialize outputs
    *pids = nullptr;
    *names = nullptr;
    *bundleIds = nullptr;
    *count = 0;

    HRESULT hr = S_OK;
    
    // Get device enumerator
    CComPtr<IMMDeviceEnumerator> pEnumerator;
    hr = CoCreateInstance(
        __uuidof(MMDeviceEnumerator),
        nullptr,
        CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator),
        reinterpret_cast<void**>(&pEnumerator)
    );
    if (FAILED(hr)) return -1;

    // Get default capture (microphone) device
    CComPtr<IMMDevice> pDevice;
    hr = pEnumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &pDevice);
    if (FAILED(hr)) return 0;  // No mic device, return empty

    // Activate session manager
    CComPtr<IAudioSessionManager2> pSessionManager;
    hr = pDevice->Activate(
        __uuidof(IAudioSessionManager2),
        CLSCTX_ALL,
        nullptr,
        reinterpret_cast<void**>(&pSessionManager)
    );
    if (FAILED(hr)) return -1;

    // Get session enumerator
    CComPtr<IAudioSessionEnumerator> pSessionEnum;
    hr = pSessionManager->GetSessionEnumerator(&pSessionEnum);
    if (FAILED(hr)) return -1;

    // Get session count
    int sessionCount = 0;
    hr = pSessionEnum->GetCount(&sessionCount);
    if (FAILED(hr) || sessionCount == 0) return 0;

    // Collect active sessions
    std::vector<DWORD> activePids;
    std::vector<std::wstring> activeNames;

    for (int i = 0; i < sessionCount; i++) {
        CComPtr<IAudioSessionControl> pSessionControl;
        hr = pSessionEnum->GetSession(i, &pSessionControl);
        if (FAILED(hr)) continue;

        // Check if session is active
        AudioSessionState state;
        hr = pSessionControl->GetState(&state);
        if (FAILED(hr) || state != AudioSessionStateActive) continue;

        // Get IAudioSessionControl2 for process info
        CComPtr<IAudioSessionControl2> pSessionControl2;
        hr = pSessionControl->QueryInterface(
            __uuidof(IAudioSessionControl2),
            reinterpret_cast<void**>(&pSessionControl2)
        );
        if (FAILED(hr)) continue;

        // Skip system sounds
        hr = pSessionControl2->IsSystemSoundsSession();
        if (hr == S_OK) continue;

        // Get process ID
        DWORD pid = 0;
        hr = pSessionControl2->GetProcessId(&pid);
        if (FAILED(hr) || pid == 0) continue;
        // Note: AUDCLNT_S_NO_SINGLE_PROCESS means multi-process session
        // We skip these as we can't identify a single process

        // Avoid duplicates
        bool duplicate = false;
        for (DWORD existingPid : activePids) {
            if (existingPid == pid) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;

        // Get process name
        std::wstring procName = GetProcessNameFromPid(pid);
        if (procName.empty()) {
            procName = L"Unknown";
        }

        activePids.push_back(pid);
        activeNames.push_back(procName);
    }

    // Allocate output arrays
    if (activePids.empty()) return 0;

    size_t n = activePids.size();
    *pids = static_cast<int32_t*>(malloc(n * sizeof(int32_t)));
    *names = static_cast<char**>(malloc(n * sizeof(char*)));
    *bundleIds = static_cast<char**>(malloc(n * sizeof(char*)));

    if (!*pids || !*names || !*bundleIds) {
        free(*pids);
        free(*names);
        free(*bundleIds);
        *pids = nullptr;
        *names = nullptr;
        *bundleIds = nullptr;
        return -1;
    }

    for (size_t i = 0; i < n; i++) {
        (*pids)[i] = static_cast<int32_t>(activePids[i]);

        // Convert wide string to UTF-8
        int utf8Len = WideCharToMultiByte(CP_UTF8, 0, activeNames[i].c_str(), -1, nullptr, 0, nullptr, nullptr);
        (*names)[i] = static_cast<char*>(malloc(utf8Len));
        if ((*names)[i]) {
            WideCharToMultiByte(CP_UTF8, 0, activeNames[i].c_str(), -1, (*names)[i], utf8Len, nullptr, nullptr);
        }

        // Windows doesn't have bundle IDs - use empty string
        (*bundleIds)[i] = _strdup("");
    }

    *count = static_cast<int32_t>(n);
    return 0;
}
```

### Step 4: Ensure COM is Initialized

The MicActivityMonitor on Windows needs COM initialized. Check if `CoInitializeEx` is called in the monitor's constructor/start.

**Option A:** Initialize per-call (simpler but slower)
```cpp
// At start of mic_activity_get_active_processes
CoInitializeEx(nullptr, COINIT_MULTITHREADED);
// ... do work ...
CoUninitialize();
```

**Option B:** Initialize once in monitor lifecycle (better)
```cpp
// In MicActivityMonitor constructor or start()
CoInitializeEx(nullptr, COINIT_MULTITHREADED);

// In destructor or stop()
CoUninitialize();
```

### Step 5: Update `mic_activity_free_processes()` (if needed)

The current stub may need updating if not properly freeing memory:

```cpp
void mic_activity_free_processes(
    int32_t* pids,
    char** names,
    char** bundleIds,
    int32_t count
) {
    if (pids) free(pids);
    
    if (names) {
        for (int32_t i = 0; i < count; i++) {
            if (names[i]) free(names[i]);
        }
        free(names);
    }
    
    if (bundleIds) {
        for (int32_t i = 0; i < count; i++) {
            if (bundleIds[i]) free(bundleIds[i]);
        }
        free(bundleIds);
    }
}
```

---

## Testing

### Test Script

```javascript
// examples/test-mic-activity.mjs (already exists)
// Run on Windows with a microphone

node examples/test-mic-activity.mjs -d 30
```

### Manual Test Steps

1. Start the monitor
2. Open an app that uses the microphone (Voice Recorder, Teams, Discord, browser with mic permission)
3. Verify the process appears in `getActiveProcesses()` output
4. Close the app
5. Verify the process disappears

### Edge Cases to Test

| Scenario | Expected Behavior |
|----------|-------------------|
| No mic connected | Returns empty array, no error |
| Multiple apps using mic | Returns all PIDs |
| Browser with mic | May return browser PID or `AUDCLNT_S_NO_SINGLE_PROCESS` (skip) |
| UWP app (e.g., Voice Recorder) | Should return PID |
| Elevated process using mic | May fail `OpenProcess()` - return PID with "Unknown" name |

---

## Build & Test Commands

```bash
# On Windows machine

# Build native addon
pnpm run build:native

# Copy binary to package
pnpm run copy-binary

# Build TypeScript
pnpm run build:ts

# Test
node examples/test-mic-activity.mjs -d 30
```

---

## Potential Issues & Solutions

### Issue 1: `AUDCLNT_S_NO_SINGLE_PROCESS`

**Problem:** Multi-process audio sessions (browsers, some UWP apps) don't have a single PID.

**Solution:** Skip these sessions. Document as a known limitation.

### Issue 2: Access Denied on `OpenProcess()`

**Problem:** Can't get name for elevated/protected processes.

**Solution:** Return PID with name "Unknown" or use process ID as fallback name.

### Issue 3: COM Already Initialized

**Problem:** If Node.js or another addon already initialized COM with different threading model.

**Solution:** Check `CoInitializeEx` return value. `RPC_E_CHANGED_MODE` means COM is already initialized - this is usually fine for our use case.

### Issue 4: Session Enumeration is Stale

**Problem:** WASAPI session list may not update instantly.

**Solution:** This is inherent to the API. The TypeScript layer already polls every 100ms which should be sufficient.

---

## API Parity Checklist

| Feature | macOS | Windows (after impl) |
|---------|-------|---------------------|
| Detect active mic sessions | ✅ | ✅ |
| Get process PID | ✅ | ✅ |
| Get process name | ✅ | ✅ |
| Get bundle ID | ✅ | ❌ (N/A on Windows) |
| No elevation required | ✅ | ✅ |
| Multi-process session support | N/A | ❌ (returns empty for those) |

---

## References

- [IAudioSessionManager2 (Microsoft Docs)](https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-iaudiosessionmanager2)
- [IAudioSessionControl2::GetProcessId](https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nf-audiopolicy-iaudiosessioncontrol2-getprocessid)
- [Mumble WASAPI Implementation](https://github.com/mumble-voip/mumble/blob/master/src/mumble/WASAPI.cpp)
- [Core Audio APIs (Overview)](https://docs.microsoft.com/en-us/windows/win32/coreaudio/core-audio-apis-in-windows-vista)

---

## Estimated Effort

| Task | Time |
|------|------|
| Implement `mic_activity_get_active_processes()` | 2-3 hours |
| Handle COM initialization | 30 min |
| Testing & edge cases | 1-2 hours |
| **Total** | **4-6 hours** |
