import { createRequire } from 'module'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const require = createRequire(import.meta.url)

export type PermissionStatus = 'unknown' | 'denied' | 'authorized'

interface NativeAddon {
  getPermissionStatus(): PermissionStatus
  isPermissionAvailable(): boolean
  requestPermission(callback: (granted: boolean) => void): void
  openSystemSettings(): boolean
}

let addon: NativeAddon | null = null

function loadAddon(): NativeAddon {
  if (addon) return addon

  const paths = [
    path.join(__dirname, '..', 'build', 'Release', 'audiotee.node'),
    path.join(__dirname, '..', '..', 'build', 'Release', 'audiotee.node'),
  ]

  for (const addonPath of paths) {
    try {
      addon = require(addonPath)
      return addon!
    } catch {
      // Try next path
    }
  }

  throw new Error('Failed to load native AudioTee addon')
}

/**
 * Check the current system audio recording permission status.
 * @returns 'authorized' | 'denied' | 'unknown'
 */
export function getPermissionStatus(): PermissionStatus {
  return loadAddon().getPermissionStatus()
}

/**
 * Check if the TCC permission API is available.
 * This uses private macOS APIs that may not be available on all systems.
 */
export function isPermissionAvailable(): boolean {
  return loadAddon().isPermissionAvailable()
}

/**
 * Request system audio recording permission.
 * This will show the macOS permission dialog if the permission hasn't been determined yet.
 * @returns Promise that resolves to true if permission was granted, false otherwise
 */
export function requestPermission(): Promise<boolean> {
  return new Promise((resolve) => {
    loadAddon().requestPermission((granted) => {
      resolve(granted)
    })
  })
}

/**
 * Open System Settings to the Screen & System Audio Recording pane.
 * Use this when the user needs to manually grant permission.
 * @returns true if System Settings was opened successfully
 */
export function openSystemSettings(): boolean {
  return loadAddon().openSystemSettings()
}

/**
 * Ensure system audio recording permission is granted.
 * If not authorized, will attempt to request permission or open System Settings.
 * @throws Error if permission is denied and user needs to grant it manually
 */
export async function ensurePermission(): Promise<void> {
  if (!isPermissionAvailable()) {
    // TCC API not available, can't check permission
    // Recording may work or fail silently
    return
  }

  const status = getPermissionStatus()

  if (status === 'authorized') {
    return
  }

  if (status === 'unknown') {
    // Try to request permission
    const granted = await requestPermission()
    if (granted) {
      return
    }
  }

  // Permission denied or request failed
  throw new PermissionError(
    'System audio recording permission is required. Please grant permission in System Settings.',
    getPermissionStatus()
  )
}

export class PermissionError extends Error {
  public readonly status: PermissionStatus

  constructor(message: string, status: PermissionStatus) {
    super(message)
    this.name = 'PermissionError'
    this.status = status
  }
}
