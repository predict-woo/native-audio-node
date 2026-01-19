# native-audio-node

Native audio capture for Node.js - system audio and microphone recording for **macOS** and **Windows**.

This is a monorepo containing:
- **`native-audio-node`** - The main TypeScript package
- **`@native-audio-node/darwin-arm64`** - macOS Apple Silicon binary
- **`@native-audio-node/darwin-x64`** - macOS Intel binary
- **`@native-audio-node/win32-x64`** - Windows x64 binary
- **`@native-audio-node/win32-arm64`** - Windows ARM64 binary

## Installation

```bash
npm install native-audio-node
```

Pre-built binaries are automatically installed for your platform. **No build tools required!**

## Quick Start

```typescript
import { SystemAudioRecorder, MicrophoneRecorder } from 'native-audio-node'

// Record system audio
const systemRecorder = new SystemAudioRecorder({
  sampleRate: 16000,
  chunkDurationMs: 100,
})

systemRecorder.on('data', (chunk) => {
  console.log(`Received ${chunk.data.length} bytes`)
})

await systemRecorder.start()

// Record microphone
const micRecorder = new MicrophoneRecorder({
  sampleRate: 16000,
  gain: 0.8,
})

micRecorder.on('data', (chunk) => {
  // Process audio
})

await micRecorder.start()
```

## Documentation

See the [main package README](./packages/native-audio-node/README.md) for full API documentation.

## Development

### Prerequisites

- Node.js 20+
- pnpm
- **macOS**: Xcode Command Line Tools
- **Windows**: Visual Studio Build Tools with C++ workload

### Building

```bash
# Install dependencies
pnpm install

# Build everything (native + TypeScript)
pnpm run build

# Or build separately
pnpm run build:native     # Compile native addon
pnpm run copy-binary      # Copy to platform package
pnpm run build:ts         # Compile TypeScript
```

### Project Structure

```
├── packages/
│   ├── native-audio-node/      # Main TypeScript package
│   ├── darwin-arm64/           # macOS Apple Silicon binary
│   ├── darwin-x64/             # macOS Intel binary
│   ├── win32-x64/              # Windows x64 binary
│   └── win32-arm64/            # Windows ARM64 binary
├── native/                      # Native source code
│   ├── napi/                   # Node-API wrapper
│   ├── macos/swift/            # Swift audio code
│   └── windows/                # WASAPI code
├── scripts/
│   └── copy-binary.js          # Build helper
└── CMakeLists.txt              # Native build config
```

### Publishing

Platform packages must be published before the main package:

```bash
# Publish platform packages (with binaries)
pnpm -r publish --access public

# Or individually
cd packages/darwin-arm64 && npm publish --access public
cd packages/native-audio-node && npm publish
```

## License

MIT
