export interface AudioTeeOptions {
  sampleRate?: number
  chunkDurationMs?: number
  mute?: boolean
  stereo?: boolean
  includeProcesses?: number[]
  excludeProcesses?: number[]
}

export interface AudioChunk {
  data: Buffer
}

export interface AudioMetadata {
  sampleRate: number
  channelsPerFrame: number
  bitsPerChannel: number
  isFloat: boolean
  encoding: string
}

export interface AudioTeeEvents {
  data: (chunk: AudioChunk) => void
  metadata: (metadata: AudioMetadata) => void
  start: () => void
  stop: () => void
  error: (error: Error) => void
}
