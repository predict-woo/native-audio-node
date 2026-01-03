// Common audio chunk structure
export interface AudioChunk {
  data: Buffer
}

// Audio metadata from native layer
export interface AudioMetadata {
  sampleRate: number
  channelsPerFrame: number
  bitsPerChannel: number
  isFloat: boolean
  encoding: string
}

// Common options shared by all recorder types
export interface AudioRecorderOptions {
  sampleRate?: number
  chunkDurationMs?: number
  stereo?: boolean
}

// System audio specific options
export interface SystemAudioRecorderOptions extends AudioRecorderOptions {
  mute?: boolean
  includeProcesses?: number[]
  excludeProcesses?: number[]
}

// Microphone specific options
export interface MicrophoneRecorderOptions extends AudioRecorderOptions {
  deviceId?: string
  gain?: number
}

// Audio device information
export interface AudioDevice {
  id: string
  name: string
  manufacturer?: string
  isDefault: boolean
  isInput: boolean
  isOutput: boolean
  sampleRate: number
  channelCount: number
}

// Events shared by all recorder types
export interface AudioRecorderEvents {
  data: (chunk: AudioChunk) => void
  metadata: (metadata: AudioMetadata) => void
  start: () => void
  stop: () => void
  error: (error: Error) => void
}

// Native addon event interface (internal)
export interface NativeEvent {
  type: number // 0=data, 1=start, 2=stop, 3=error, 4=metadata
  data?: Buffer
  message?: string
  sampleRate?: number
  channelsPerFrame?: number
  bitsPerChannel?: number
  isFloat?: boolean
  encoding?: string
}

// Native addon interface (internal)
export interface AudioRecorderNativeClass {
  startSystemAudio(options: {
    sampleRate?: number
    chunkDurationMs?: number
    mute?: boolean
    stereo?: boolean
    includeProcesses?: number[]
    excludeProcesses?: number[]
  }): void
  startMicrophone(options: {
    sampleRate?: number
    chunkDurationMs?: number
    stereo?: boolean
    deviceId?: string
    gain?: number
  }): void
  stop(): void
  isRunning(): boolean
  processEvents(): NativeEvent[]
}

export interface AudioRecorderNativeConstructor {
  new (): AudioRecorderNativeClass
}
