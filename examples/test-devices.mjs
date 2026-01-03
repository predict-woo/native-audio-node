#!/usr/bin/env node

import { listAudioDevices, getDefaultInputDevice, getDefaultOutputDevice } from '../dist/index.js'

console.log('Default input device:', getDefaultInputDevice())
console.log('Default output device:', getDefaultOutputDevice())
console.log('')
console.log('All audio devices:')
const devices = listAudioDevices()
devices.forEach(d => {
  const flags = [
    d.isInput ? 'input' : '',
    d.isOutput ? 'output' : '',
    d.isDefault ? 'DEFAULT' : '',
  ].filter(Boolean).join(', ')

  console.log(`  - ${d.name}`)
  console.log(`    ID: ${d.id}`)
  console.log(`    Manufacturer: ${d.manufacturer || 'N/A'}`)
  console.log(`    Sample Rate: ${d.sampleRate}Hz, Channels: ${d.channelCount}`)
  console.log(`    Flags: ${flags}`)
  console.log('')
})
