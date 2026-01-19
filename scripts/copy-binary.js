#!/usr/bin/env node

/**
 * Copy the built native binary to the correct platform package.
 * 
 * This script detects the current platform and architecture,
 * then copies the built .node file to the appropriate package directory.
 * 
 * Usage:
 *   node scripts/copy-binary.js           # Copy to current platform package
 *   node scripts/copy-binary.js --all     # Show instructions for all platforms
 */

import { copyFileSync, existsSync, mkdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const rootDir = join(__dirname, '..')

// Source binary path (output of cmake-js)
const sourcePath = join(rootDir, 'build', 'Release', 'native_audio.node')

// Map platform/arch to package directory
const platformMap = {
  'darwin-arm64': 'darwin-arm64',
  'darwin-x64': 'darwin-x64',
  'win32-x64': 'win32-x64',
  'win32-arm64': 'win32-arm64',
}

function getPlatformKey() {
  return `${process.platform}-${process.arch}`
}

function copyBinary(platformKey) {
  const packageDir = platformMap[platformKey]
  
  if (!packageDir) {
    console.error(`❌ Unsupported platform: ${platformKey}`)
    console.error(`   Supported platforms: ${Object.keys(platformMap).join(', ')}`)
    process.exit(1)
  }

  const destDir = join(rootDir, 'packages', packageDir)
  const destPath = join(destDir, 'native_audio.node')

  // Check if source exists
  if (!existsSync(sourcePath)) {
    console.error(`❌ Binary not found at: ${sourcePath}`)
    console.error('   Run "pnpm run build:native" first to compile the native module.')
    process.exit(1)
  }

  // Ensure destination directory exists
  if (!existsSync(destDir)) {
    mkdirSync(destDir, { recursive: true })
  }

  // Copy the binary
  try {
    copyFileSync(sourcePath, destPath)
    console.log(`✅ Copied binary to packages/${packageDir}/native_audio.node`)
  } catch (err) {
    console.error(`❌ Failed to copy binary: ${err.message}`)
    process.exit(1)
  }
}

function showAllPlatforms() {
  console.log('Platform packages and their binaries:\n')
  
  for (const [platform, dir] of Object.entries(platformMap)) {
    const destPath = join(rootDir, 'packages', dir, 'native_audio.node')
    const exists = existsSync(destPath)
    const status = exists ? '✅' : '❌'
    console.log(`  ${status} ${platform} -> packages/${dir}/native_audio.node`)
  }

  console.log('\nTo build for each platform:')
  console.log('  1. Build on the target platform: pnpm run build:native')
  console.log('  2. Copy the binary: node scripts/copy-binary.js')
  console.log('\nFor CI/CD, use GitHub Actions matrix builds to compile for each platform.')
}

// Main
const args = process.argv.slice(2)

if (args.includes('--all') || args.includes('-a')) {
  showAllPlatforms()
} else {
  const platformKey = getPlatformKey()
  console.log(`Building for platform: ${platformKey}`)
  copyBinary(platformKey)
}
