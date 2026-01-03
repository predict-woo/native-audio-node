import AudioToolbox
import CoreAudio
import Foundation

public class AudioFormatManager {
    public static func getDeviceFormat(deviceID: AudioObjectID) -> AudioStreamBasicDescription {
        let deviceReadyTimeout = 2.0
        let pollInterval = 0.1
        let maxPolls = Int(deviceReadyTimeout / pollInterval)

        for poll in 1...maxPolls {
            if isAudioDeviceValid(deviceID) {
                break
            }

            if poll == maxPolls {
                break
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }

        let maxRetries = 3
        let retryDelayMs = 20

        for attempt in 1...maxRetries {
            var propertyAddress = getPropertyAddress(
                selector: kAudioDevicePropertyStreamFormat,
                scope: kAudioDevicePropertyScopeInput
            )
            var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
            var streamFormat = AudioStreamBasicDescription()
            let status = AudioObjectGetPropertyData(
                deviceID, &propertyAddress, 0, nil, &propertySize, &streamFormat
            )

            if status == noErr {
                return streamFormat
            }

            if attempt < maxRetries {
                Thread.sleep(forTimeInterval: Double(retryDelayMs) / 1000.0)
            }
        }

        fatalError("Failed to get stream format from device: \(deviceID)")
    }
}
