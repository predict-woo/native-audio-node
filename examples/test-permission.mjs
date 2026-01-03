#!/usr/bin/env node

import {
  getPermissionStatus,
  isPermissionAvailable,
  requestPermission,
  openSystemSettings,
  ensurePermission,
  PermissionError,
} from '../dist/index.js'

console.log('Testing AudioTee Permission API\n')

// Check if TCC API is available
const available = isPermissionAvailable()
console.log(`TCC API available: ${available}`)

if (!available) {
  console.log('⚠️  TCC API not available - permission checking may not work')
  process.exit(0)
}

// Check current permission status
const status = getPermissionStatus()
console.log(`Current permission status: ${status}`)

if (status === 'authorized') {
  console.log('✅ Permission already granted!')
  process.exit(0)
}

if (status === 'denied') {
  console.log('❌ Permission denied. Opening System Settings...')
  openSystemSettings()
  console.log('\nPlease enable "System Audio Recording Only" for your terminal app.')
  console.log('Then run this test again.')
  process.exit(1)
}

// Status is 'unknown' - try requesting permission
console.log('\n📋 Requesting permission...')

try {
  const granted = await requestPermission()
  console.log(`Permission request result: ${granted ? 'granted' : 'denied'}`)

  if (granted) {
    console.log('✅ Permission granted!')
  } else {
    console.log('❌ Permission denied or dismissed.')
    console.log('\nOpening System Settings...')
    openSystemSettings()
    console.log('Please enable "System Audio Recording Only" for your terminal app.')
  }
} catch (error) {
  console.error('Error requesting permission:', error)
}
