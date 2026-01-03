# coreaudio-node

Native macOS audio capture for Node.js - system audio and microphone recording.

A TypeScript-first library that provides low-latency access to macOS Core Audio for capturing both system audio output (everything playing through speakers/headphones) and microphone input.

## Features

- **System Audio Capture** - Record all audio playing on your Mac, or filter by specific processes
- **Microphone Recording** - Capture from any audio input device with gain control
- **Low Latency** - 10ms event polling for real-time audio processing
- **Sample Rate Conversion** - Built-in resampling to common rates (8kHz-48kHz)
- **Process Filtering** - Include or exclude specific application audio
- **Device Selection** - Choose from available input devices programmatically
- **TypeScript Native** - Full type definitions and ESM-first design
- **Universal Binary** - Supports both Apple Silicon (arm64) and Intel (x86_64) Macs

## Requirements

- **macOS 14.2+** (Sonoma or later)
- **Node.js 20+**
- Xcode Command Line Tools (for native addon compilation)

## Installation

```bash
npm install coreaudio-node
```

The native addon is compiled during installation via `cmake-js`.

## Quick Start

### Recording System Audio

```typescript
import { SystemAudioRecorder } from 'coreaudio-node'

const recorder = new SystemAudioRecorder({
  sampleRate: 16000,      // Resample to 16kHz
  chunkDurationMs: 100,   // 100ms audio chunks
  mute: false,            // Don't mute system audio
})

recorder.on('metadata', (meta) => {
  console.log(`Format: ${meta.sampleRate}Hz, ${meta.bitsPerChannel}bit`)
})

recorder.on('data', (chunk) => {
  // chunk.data is a Buffer containing raw PCM audio
  console.log(`Received ${chunk.data.length} bytes`)
})

await recorder.start()

// Record for 10 seconds
setTimeout(async () => {
  await recorder.stop()
}, 10000)
```

### Recording Microphone

```typescript
import { MicrophoneRecorder, listAudioDevices } from 'coreaudio-node'

// List available input devices
const devices = listAudioDevices().filter(d => d.isInput)
console.log('Available microphones:', devices.map(d => d.name))

const recorder = new MicrophoneRecorder({
  sampleRate: 16000,
  gain: 0.8,              // 80% gain (0.0-2.0)
  deviceId: devices[0].id // Optional: specific device
})

recorder.on('data', (chunk) => {
  // Process microphone audio
})

await recorder.start()
```

## API Reference

### Classes

#### `SystemAudioRecorder`

Captures system audio output (everything playing through speakers/headphones).

```typescript
import { SystemAudioRecorder } from 'coreaudio-node'

const recorder = new SystemAudioRecorder(options?: SystemAudioRecorderOptions)
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sampleRate` | `number` | Device native | Target sample rate (8000, 16000, 22050, 24000, 32000, 44100, 48000) |
| `chunkDurationMs` | `number` | `200` | Audio chunk duration in milliseconds (0-5000) |
| `stereo` | `boolean` | `false` | Record in stereo (true) or mono (false) |
| `mute` | `boolean` | `false` | Mute system audio while recording |
| `includeProcesses` | `number[]` | - | Only capture audio from these process IDs |
| `excludeProcesses` | `number[]` | - | Exclude audio from these process IDs |

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `start()` | `Promise<void>` | Start audio capture |
| `stop()` | `Promise<void>` | Stop audio capture |
| `isActive()` | `boolean` | Check if currently recording |
| `getMetadata()` | `AudioMetadata \| null` | Get current audio format info |

---

#### `MicrophoneRecorder`

Captures audio from microphone input devices.

```typescript
import { MicrophoneRecorder } from 'coreaudio-node'

const recorder = new MicrophoneRecorder(options?: MicrophoneRecorderOptions)
```

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `sampleRate` | `number` | Device native | Target sample rate |
| `chunkDurationMs` | `number` | `200` | Audio chunk duration in milliseconds |
| `stereo` | `boolean` | `false` | Record in stereo or mono |
| `deviceId` | `string` | System default | Device UID (from `listAudioDevices()`) |
| `gain` | `number` | `1.0` | Microphone gain (0.0-2.0) |

---

### Events

Both recorder classes emit the following events:

```typescript
interface AudioRecorderEvents {
  data: (chunk: AudioChunk) => void
  metadata: (metadata: AudioMetadata) => void
  start: () => void
  stop: () => void
  error: (error: Error) => void
}
```

| Event | Payload | Description |
|-------|---------|-------------|
| `data` | `AudioChunk` | Raw PCM audio data chunk |
| `metadata` | `AudioMetadata` | Audio format information (emitted once after start) |
| `start` | - | Recording has started |
| `stop` | - | Recording has stopped |
| `error` | `Error` | An error occurred |

**Usage:**

```typescript
recorder.on('data', (chunk) => { /* handle audio */ })
recorder.on('metadata', (meta) => { /* handle format info */ })
recorder.on('start', () => { /* recording started */ })
recorder.on('stop', () => { /* recording stopped */ })
recorder.on('error', (err) => { /* handle error */ })

// One-time listener
recorder.once('start', () => { /* only fires once */ })

// Remove listener
recorder.off('data', myHandler)

// Remove all listeners
recorder.removeAllListeners('data')
```

---

### Types

#### `AudioChunk`

```typescript
interface AudioChunk {
  data: Buffer  // Raw PCM audio bytes
}
```

#### `AudioMetadata`

```typescript
interface AudioMetadata {
  sampleRate: number        // Hz (e.g., 48000, 16000)
  channelsPerFrame: number  // 1 (mono) or 2 (stereo)
  bitsPerChannel: number    // 32 (float) or 16 (int)
  isFloat: boolean          // true = 32-bit float, false = 16-bit int
  encoding: string          // "pcm_f32le" or "pcm_s16le"
}
```

#### `AudioDevice`

```typescript
interface AudioDevice {
  id: string                // Unique device identifier
  name: string              // Human-readable name
  manufacturer?: string     // Device manufacturer
  isDefault: boolean        // Is system default device
  isInput: boolean          // Supports input (microphone)
  isOutput: boolean         // Supports output (speakers)
  sampleRate: number        // Native sample rate
  channelCount: number      // Number of channels
}
```

---

### Device Management

```typescript
import {
  listAudioDevices,
  getDefaultInputDevice,
  getDefaultOutputDevice
} from 'coreaudio-node'

// List all audio devices
const devices = listAudioDevices()
console.log(devices)
// [
//   { id: 'BuiltInMicrophoneDevice', name: 'MacBook Pro Microphone', isInput: true, ... },
//   { id: 'BuiltInSpeakerDevice', name: 'MacBook Pro Speakers', isOutput: true, ... },
//   ...
// ]

// Get input devices only
const microphones = devices.filter(d => d.isInput)

// Get output devices only
const speakers = devices.filter(d => d.isOutput)

// Get default devices
const defaultMic = getDefaultInputDevice()      // Returns device UID or null
const defaultSpeaker = getDefaultOutputDevice() // Returns device UID or null
```

---

### Permission Management

macOS requires permission for audio recording. System audio and microphone have different permission systems.

#### System Audio Permission

Uses macOS TCC (Transparency, Consent, and Control) private API. Permission must often be granted manually in System Settings.

```typescript
import {
  getSystemAudioPermissionStatus,
  isSystemAudioPermissionAvailable,
  requestSystemAudioPermission,
  ensureSystemAudioPermission,
  openSystemSettings,
  PermissionError,
} from 'coreaudio-node'

// Check if TCC API is available
if (isSystemAudioPermissionAvailable()) {
  const status = getSystemAudioPermissionStatus()
  // Returns: 'unknown' | 'denied' | 'authorized'

  if (status !== 'authorized') {
    // Open System Settings to permission pane
    openSystemSettings()
    console.log('Please grant "System Audio Recording Only" permission')
  }
}

// Or use the convenience function (throws PermissionError if denied)
try {
  await ensureSystemAudioPermission()
  // Permission granted, safe to start recording
} catch (err) {
  if (err instanceof PermissionError) {
    console.log('Permission status:', err.status)
  }
}
```

#### Microphone Permission

Uses standard AVFoundation API with system permission dialog.

```typescript
import {
  getMicrophonePermissionStatus,
  requestMicrophonePermission,
  ensureMicrophonePermission,
  PermissionError,
} from 'coreaudio-node'

// Check current status
const status = getMicrophonePermissionStatus()
// Returns: 'unknown' | 'denied' | 'authorized'

// Request permission (shows system dialog if 'unknown')
const granted = await requestMicrophonePermission()
if (granted) {
  // Start recording
}

// Or use convenience function
try {
  await ensureMicrophonePermission()
} catch (err) {
  if (err instanceof PermissionError) {
    console.log('Microphone access denied')
  }
}
```

#### Permission Types

```typescript
type PermissionStatus = 'unknown' | 'denied' | 'authorized'

class PermissionError extends Error {
  status: PermissionStatus
}
```

---

## Audio Format Details

### Native Format

Audio is captured in the device's native format, typically:
- **Sample Rate:** 48000 Hz (device dependent)
- **Bit Depth:** 32-bit IEEE float
- **Channels:** Mono or stereo

### After Sample Rate Conversion

When you specify a `sampleRate` option, audio is converted:
- **Sample Rate:** Your specified rate
- **Bit Depth:** 16-bit signed integer
- **Channels:** Mono (unless `stereo: true`)
- **Encoding:** `pcm_s16le` (little-endian)

### Supported Sample Rates

8000, 16000, 22050, 24000, 32000, 44100, 48000 Hz

---

## Examples

### Record to WAV File

```typescript
import { SystemAudioRecorder } from 'coreaudio-node'
import { writeFileSync } from 'fs'

const chunks: Buffer[] = []
let metadata: AudioMetadata

const recorder = new SystemAudioRecorder({ sampleRate: 16000 })

recorder.on('metadata', (meta) => { metadata = meta })
recorder.on('data', (chunk) => { chunks.push(chunk.data) })

await recorder.start()

// Record for 5 seconds
await new Promise(resolve => setTimeout(resolve, 5000))

await recorder.stop()

// Combine chunks and write with WAV header
const audioData = Buffer.concat(chunks)
const wavFile = createWavFile(audioData, metadata)
writeFileSync('recording.wav', wavFile)
```

### Process-Specific Recording

```typescript
import { SystemAudioRecorder } from 'coreaudio-node'
import { execSync } from 'child_process'

// Get Chrome's process ID
const chromePid = parseInt(
  execSync("pgrep -x 'Google Chrome'").toString().trim()
)

const recorder = new SystemAudioRecorder({
  includeProcesses: [chromePid],
  mute: true,  // Mute Chrome audio while recording
})

await recorder.start()
```

### Real-time Audio Processing

```typescript
import { MicrophoneRecorder } from 'coreaudio-node'

const recorder = new MicrophoneRecorder({
  sampleRate: 16000,
  chunkDurationMs: 50,  // 50ms chunks for low latency
})

recorder.on('data', (chunk) => {
  // Calculate RMS (volume level)
  const samples = new Int16Array(chunk.data.buffer)
  let sum = 0
  for (const sample of samples) {
    sum += sample * sample
  }
  const rms = Math.sqrt(sum / samples.length)
  const db = 20 * Math.log10(rms / 32768)
  console.log(`Volume: ${db.toFixed(1)} dB`)
})

await recorder.start()
```

### Device Selection UI

```typescript
import { MicrophoneRecorder, listAudioDevices } from 'coreaudio-node'
import readline from 'readline'

const devices = listAudioDevices().filter(d => d.isInput)

console.log('Select a microphone:')
devices.forEach((d, i) => {
  const marker = d.isDefault ? ' (default)' : ''
  console.log(`  ${i + 1}. ${d.name}${marker}`)
})

const rl = readline.createInterface({ input: process.stdin, output: process.stdout })
const answer = await new Promise<string>(resolve => rl.question('> ', resolve))
rl.close()

const selected = devices[parseInt(answer) - 1]
const recorder = new MicrophoneRecorder({ deviceId: selected.id })

await recorder.start()
```

---

## Command Line Examples

The package includes example scripts:

```bash
# Record system audio to WAV
node examples/record-wav.mjs -o output.wav -d 10 -s 16000 -m

# Record microphone to WAV
node examples/record-mic.mjs -o mic.wav -d 5 -g 0.8

# List audio devices
node examples/record-mic.mjs -l

# Test device listing
node examples/test-devices.mjs
```

---

## Troubleshooting

### "System audio recording permission not configured"

1. Run `openSystemSettings()` or open **System Settings > Privacy & Security > Screen & System Audio Recording**
2. Scroll down to the **"System Audio Recording Only"** section (not the top section)
3. Add and enable your terminal app (Terminal, iTerm2, VS Code, etc.)
4. Restart the terminal app after granting permission

### "Microphone permission denied"

1. Open **System Settings > Privacy & Security > Microphone**
2. Enable access for your terminal app
3. Restart the app if needed

### "No default input device"

- Check that a microphone is connected
- Verify in **System Settings > Sound > Input** that a device is selected

### Build Errors

Ensure you have Xcode Command Line Tools:

```bash
xcode-select --install
```

Rebuild the native addon:

```bash
npm run rebuild
```

### Apple Silicon / Intel Compatibility

The library builds a universal binary supporting both architectures. If you encounter issues:

```bash
npm run clean
npm run build:native
```

---

## Architecture

```
TypeScript API
     |
BaseAudioRecorder (EventEmitter, 10ms polling)
     |
Native NAPI Wrapper (C++)
     |
Swift Bridge (C-compatible API)
     |
+--------------------+--------------------+
|  AudioTapManager   |  MicrophoneRecorder|
|  (System Audio)    |  (AVCaptureSession)|
+--------------------+--------------------+
     |                        |
macOS Core Audio / AVFoundation Frameworks
```

### Native Layer Components

| Component | Purpose |
|-----------|---------|
| `CoreAudioBridge.swift` | C-compatible entry points for NAPI |
| `AudioTapManager.swift` | System audio tapping via `AudioHardwareCreateProcessTap` |
| `MicrophoneCapture.swift` | AVCaptureSession-based microphone recording |
| `AudioDeviceManager.swift` | Device enumeration (AVCaptureDevice + Core Audio) |
| `AudioBuffer.swift` | Ring buffer for audio chunk management |
| `AudioFormatConverter.swift` | Sample rate conversion via AVAudioConverter |
| `AudioPermission.swift` | TCC and AVFoundation permission handling |

---

## Development

```bash
# Clone the repository
git clone https://github.com/your-username/coreaudio-node.git
cd coreaudio-node

# Install dependencies
npm install

# Build native addon and TypeScript
npm run build

# Build native addon only
npm run build:native

# Build TypeScript only
npm run build:ts

# Watch mode for TypeScript
npm run dev

# Clean build artifacts
npm run clean

# Rebuild native addon
npm run rebuild
```

---

## API Stability

During the `0.x.x` release cycle, the API is unstable and subject to change without notice.

---

## Code Signing

The native addon is built locally on your machine. For distribution:

### For Electron Applications

When bundled inside an Electron app, the native addon **inherits the code signature** from the parent application. Ensure your app's entitlements include audio recording permissions.

### For Standalone Usage

If running directly via Node.js:
- **Development**: Works without additional signing
- **Production**: Consider signing with your Developer ID if distributing

---

## License

MIT
