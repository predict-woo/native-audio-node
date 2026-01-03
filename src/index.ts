export { AudioTee } from './audiotee.js'
export type { AudioTeeOptions, AudioChunk, AudioMetadata, AudioTeeEvents } from './types.js'

// Permission API
export {
  getPermissionStatus,
  isPermissionAvailable,
  requestPermission,
  openSystemSettings,
  ensurePermission,
  PermissionError,
} from './permission.js'
export type { PermissionStatus } from './permission.js'
