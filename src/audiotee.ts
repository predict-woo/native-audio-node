import { EventEmitter } from 'events'
import { createRequire } from 'module'
import path from 'path'
import { fileURLToPath } from 'url'
import type { AudioTeeOptions, AudioTeeEvents, AudioChunk, AudioMetadata } from './types.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const require = createRequire(import.meta.url)

// Native addon event interface
interface NativeEvent {
  type: number // 0=data, 1=start, 2=stop, 3=error, 4=metadata
  data?: Buffer
  message?: string
  sampleRate?: number
  channelsPerFrame?: number
  bitsPerChannel?: number
  isFloat?: boolean
  encoding?: string
}

interface AudioTeeNativeClass {
  start(options: {
    sampleRate?: number
    chunkDurationMs?: number
    mute?: boolean
    stereo?: boolean
    includeProcesses?: number[]
    excludeProcesses?: number[]
  }): void
  stop(): void
  isRunning(): boolean
  processEvents(): NativeEvent[]
}

interface AudioTeeNativeConstructor {
  new (): AudioTeeNativeClass
}

let AudioTeeNative: AudioTeeNativeConstructor

function loadNativeAddon(): AudioTeeNativeConstructor {
  const paths = [
    // Development: build/Release relative to dist/
    path.join(__dirname, '..', 'build', 'Release', 'audiotee.node'),
    // Installed package: build/Release at package root
    path.join(__dirname, '..', '..', 'build', 'Release', 'audiotee.node'),
  ]

  for (const addonPath of paths) {
    try {
      const addon = require(addonPath)
      return addon.AudioTeeNative
    } catch {
      // Try next path
    }
  }

  throw new Error(
    `Failed to load native AudioTee addon. Make sure you've built the native module with 'npm run build:native'.`
  )
}

AudioTeeNative = loadNativeAddon()

export class AudioTee {
  private events = new EventEmitter()
  private native: AudioTeeNativeClass
  private running = false
  private options: AudioTeeOptions
  private pollInterval: ReturnType<typeof setInterval> | null = null
  private metadata: AudioMetadata | null = null

  constructor(options: AudioTeeOptions = {}) {
    // Check platform at construction time
    if (process.platform !== 'darwin') {
      throw new Error(`AudioTee only supports macOS (darwin). Current platform: ${process.platform}`)
    }

    this.options = options
    this.native = new AudioTeeNative()
  }

  on<K extends keyof AudioTeeEvents>(event: K, listener: AudioTeeEvents[K]): this {
    this.events.on(event, listener)
    return this
  }

  once<K extends keyof AudioTeeEvents>(event: K, listener: AudioTeeEvents[K]): this {
    this.events.once(event, listener)
    return this
  }

  off<K extends keyof AudioTeeEvents>(event: K, listener: AudioTeeEvents[K]): this {
    this.events.off(event, listener)
    return this
  }

  removeAllListeners<K extends keyof AudioTeeEvents>(event?: K): this {
    this.events.removeAllListeners(event)
    return this
  }

  private emit<K extends keyof AudioTeeEvents>(
    event: K,
    ...args: Parameters<AudioTeeEvents[K]>
  ): boolean {
    return this.events.emit(event, ...args)
  }

  private processNativeEvents(): void {
    const events = this.native.processEvents()

    for (const event of events) {
      switch (event.type) {
        case 0: // data
          if (event.data) {
            const chunk: AudioChunk = { data: event.data }
            this.emit('data', chunk)
          }
          break

        case 1: // start
          this.emit('start')
          break

        case 2: // stop
          this.emit('stop')
          break

        case 3: // error
          this.emit('error', new Error(event.message || 'Unknown error'))
          break

        case 4: // metadata
          this.metadata = {
            sampleRate: event.sampleRate!,
            channelsPerFrame: event.channelsPerFrame!,
            bitsPerChannel: event.bitsPerChannel!,
            isFloat: event.isFloat!,
            encoding: event.encoding!,
          }
          this.emit('metadata', this.metadata)
          break
      }
    }
  }

  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.running) {
        reject(new Error('AudioTee is already running'))
        return
      }

      try {
        this.native.start({
          sampleRate: this.options.sampleRate,
          chunkDurationMs: this.options.chunkDurationMs,
          mute: this.options.mute,
          stereo: this.options.stereo,
          includeProcesses: this.options.includeProcesses,
          excludeProcesses: this.options.excludeProcesses,
        })

        this.running = true

        // Start polling for events from the native addon
        // Use a fast interval to ensure low latency for audio data
        this.pollInterval = setInterval(() => {
          if (this.running) {
            this.processNativeEvents()
          }
        }, 10) // Poll every 10ms for responsive audio

        resolve()
      } catch (error) {
        reject(error)
      }
    })
  }

  stop(): Promise<void> {
    return new Promise((resolve) => {
      if (!this.running) {
        resolve()
        return
      }

      // Stop the polling interval
      if (this.pollInterval) {
        clearInterval(this.pollInterval)
        this.pollInterval = null
      }

      // Process any remaining events
      this.processNativeEvents()

      // Stop the native addon
      this.native.stop()
      this.running = false

      resolve()
    })
  }

  isActive(): boolean {
    return this.running
  }

  getMetadata(): AudioMetadata | null {
    return this.metadata
  }
}
