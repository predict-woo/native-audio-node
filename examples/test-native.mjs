import { AudioTee } from '../dist/index.js'

console.log('Testing native AudioTee addon...')

try {
  const audiotee = new AudioTee({
    chunkDurationMs: 100,
    mute: true, // Mute so we don't hear ourselves
  })

  console.log('AudioTee instance created successfully!')

  audiotee.on('metadata', (metadata) => {
    console.log('Metadata received:', metadata)
  })

  audiotee.on('start', () => {
    console.log('Recording started!')
  })

  audiotee.on('data', (chunk) => {
    console.log(`Received audio chunk: ${chunk.data.length} bytes`)
  })

  audiotee.on('error', (error) => {
    console.error('Error:', error.message)
  })

  audiotee.on('stop', () => {
    console.log('Recording stopped!')
  })

  console.log('Starting audio capture...')
  await audiotee.start()

  // Record for 2 seconds
  await new Promise((resolve) => setTimeout(resolve, 2000))

  console.log('Stopping audio capture...')
  await audiotee.stop()

  console.log('Test completed successfully!')
} catch (error) {
  console.error('Test failed:', error)
  process.exit(1)
}
