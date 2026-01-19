import { loadBinding } from './binding.js'
import type { AudioDevice } from './types.js'

/**
 * List all audio devices on the system.
 * Returns both input and output devices with their properties.
 *
 * @example
 * ```typescript
 * import { listAudioDevices } from 'native-audio-node'
 *
 * const devices = listAudioDevices()
 * const inputDevices = devices.filter(d => d.isInput)
 * console.log('Available microphones:', inputDevices.map(d => d.name))
 * ```
 */
export function listAudioDevices(): AudioDevice[] {
  return loadBinding().listDevices()
}

/**
 * Get the UID of the default input device (microphone).
 * @returns Device UID string, or null if no default input device
 */
export function getDefaultInputDevice(): string | null {
  return loadBinding().getDefaultInputDevice()
}

/**
 * Get the UID of the default output device (speakers).
 * @returns Device UID string, or null if no default output device
 */
export function getDefaultOutputDevice(): string | null {
  return loadBinding().getDefaultOutputDevice()
}
