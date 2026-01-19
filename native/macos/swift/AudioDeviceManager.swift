import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

// MARK: - Device Info Structure

struct DeviceInfo {
    let uid: String
    let name: String
    let manufacturer: String
    let isDefault: Bool
    let isInput: Bool
    let isOutput: Bool
    let sampleRate: Double
    let channelCount: UInt32
}

// MARK: - Audio Device Manager

class AudioDeviceManager {

    /// List all audio devices using AVCaptureDevice for inputs (Bluetooth auto-connect support)
    /// and Core Audio for outputs
    static func listAllDevices() -> [DeviceInfo] {
        var devices: [DeviceInfo] = []

        // Get input devices using AVCaptureDevice (supports Bluetooth auto-connect)
        let inputDevices = listInputDevicesUsingAVCapture()
        devices.append(contentsOf: inputDevices)

        // Get output devices using Core Audio (AVCaptureDevice doesn't expose outputs)
        let outputDevices = listOutputDevicesUsingCoreAudio()
        devices.append(contentsOf: outputDevices)

        return devices
    }

    /// List input devices using AVCaptureDevice.DiscoverySession
    /// This can trigger Bluetooth device switching from other Apple devices
    private static func listInputDevicesUsingAVCapture() -> [DeviceInfo] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        let defaultDevice = AVCaptureDevice.default(for: .audio)

        return discoverySession.devices.compactMap { device -> DeviceInfo? in
            // Get sample rate from the device's active format
            var sampleRate: Double = 48000.0  // Default fallback
            var channelCount: UInt32 = 1

            // Try to get format info from Core Audio using the device UID
            if let deviceID = getDeviceIDFromUID(device.uniqueID) {
                sampleRate = getDeviceSampleRate(deviceID: deviceID)
                channelCount = getInputChannelCount(deviceID: deviceID)
                if channelCount == 0 {
                    channelCount = 1  // Default to mono if we can't determine
                }
            }

            return DeviceInfo(
                uid: device.uniqueID,
                name: device.localizedName,
                manufacturer: device.manufacturer,
                isDefault: device.uniqueID == defaultDevice?.uniqueID,
                isInput: true,
                isOutput: false,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        }
    }

    /// List output devices using Core Audio (AVCaptureDevice doesn't expose outputs)
    private static func listOutputDevicesUsingCoreAudio() -> [DeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            return []
        }

        let defaultOutputID = getDefaultOutputDeviceID()

        return deviceIDs.compactMap { deviceID -> DeviceInfo? in
            // Only include devices that are output-only (not also inputs, to avoid duplicates)
            let outputChannels = getOutputChannelCount(deviceID: deviceID)
            let inputChannels = getInputChannelCount(deviceID: deviceID)

            // Skip devices that are also inputs (already covered by AVCaptureDevice)
            guard outputChannels > 0 && inputChannels == 0 else {
                return nil
            }

            guard let uid = getDeviceUID(deviceID: deviceID),
                  let name = getDeviceName(deviceID: deviceID) else {
                return nil
            }

            let manufacturer = getDeviceManufacturer(deviceID: deviceID) ?? ""
            let sampleRate = getDeviceSampleRate(deviceID: deviceID)
            let isDefault = deviceID == defaultOutputID

            return DeviceInfo(
                uid: uid,
                name: name,
                manufacturer: manufacturer,
                isDefault: isDefault,
                isInput: false,
                isOutput: true,
                sampleRate: sampleRate,
                channelCount: outputChannels
            )
        }
    }

    /// Get default input device UID using AVCaptureDevice
    static func getDefaultInputDeviceUID() -> String? {
        return AVCaptureDevice.default(for: .audio)?.uniqueID
    }

    /// Get default output device UID using Core Audio
    static func getDefaultOutputDeviceUID() -> String? {
        guard let deviceID = getDefaultOutputDeviceID() else {
            return nil
        }
        return getDeviceUID(deviceID: deviceID)
    }

    // MARK: - Core Audio Helpers (for output devices and format info)

    private static func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private static func getDeviceIDFromUID(_ uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID: deviceID), deviceUID == uid {
                return deviceID
            }
        }

        return nil
    }

    private static func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &dataSize,
                uidPtr
            )
        }

        guard status == noErr, let cfString = uid?.takeUnretainedValue() else {
            return nil
        }
        return cfString as String
    }

    private static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &name) { namePtr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &dataSize,
                namePtr
            )
        }

        guard status == noErr, let cfString = name?.takeUnretainedValue() else {
            return nil
        }
        return cfString as String
    }

    private static func getDeviceManufacturer(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var manufacturer: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &manufacturer) { mfgPtr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0, nil,
                &dataSize,
                mfgPtr
            )
        }

        guard status == noErr, let cfString = manufacturer?.takeUnretainedValue() else {
            return nil
        }
        return cfString as String
    }

    private static func getDeviceSampleRate(deviceID: AudioDeviceID) -> Double {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &sampleRate
        )

        return status == noErr ? sampleRate : 0
    }

    private static func getInputChannelCount(deviceID: AudioDeviceID) -> UInt32 {
        return getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)
    }

    private static func getOutputChannelCount(deviceID: AudioDeviceID) -> UInt32 {
        return getChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func getChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else {
            return 0
        }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            bufferListPointer
        )

        guard status == noErr else {
            return 0
        }

        var totalChannels: UInt32 = 0

        let buffers = UnsafeMutableAudioBufferListPointer(&bufferListPointer.pointee)
        for buffer in buffers {
            totalChannels += buffer.mNumberChannels
        }

        return totalChannels
    }
}

// MARK: - C-Compatible API

// C struct layout matching audio_bridge.h AudioDeviceInfo
// Using a tuple-based struct for C ABI compatibility with @_cdecl
// Layout: uid (8 bytes), name (8 bytes), manufacturer (8 bytes), 
//         isDefault (1 byte), isInput (1 byte), isOutput (1 byte), padding (5 bytes),
//         sampleRate (8 bytes), channelCount (4 bytes), padding (4 bytes)
// Total: 48 bytes on 64-bit systems

private let CAudioDeviceInfoSize = 48  // Size of AudioDeviceInfo struct in C

@_cdecl("audio_list_devices")
public func audio_list_devices(
    devices: UnsafeMutableRawPointer,  // AudioDeviceInfo** 
    count: UnsafeMutablePointer<Int32>
) -> Int32 {
    let deviceList = AudioDeviceManager.listAllDevices()
    
    // Cast to the correct pointer type for the out parameter
    let devicesOut = devices.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)

    guard !deviceList.isEmpty else {
        devicesOut.pointee = nil
        count.pointee = 0
        return 0
    }

    // Allocate raw memory for the array of C structs
    let arrayPointer = UnsafeMutableRawPointer.allocate(
        byteCount: CAudioDeviceInfoSize * deviceList.count,
        alignment: 8
    )

    for (index, device) in deviceList.enumerated() {
        let offset = index * CAudioDeviceInfoSize
        let itemPointer = arrayPointer.advanced(by: offset)
        
        // Write each field at the correct offset
        // uid (offset 0)
        itemPointer.storeBytes(of: strdup(device.uid), as: UnsafeMutablePointer<CChar>?.self)
        // name (offset 8)
        itemPointer.advanced(by: 8).storeBytes(of: strdup(device.name), as: UnsafeMutablePointer<CChar>?.self)
        // manufacturer (offset 16)
        itemPointer.advanced(by: 16).storeBytes(of: strdup(device.manufacturer), as: UnsafeMutablePointer<CChar>?.self)
        // isDefault (offset 24)
        itemPointer.advanced(by: 24).storeBytes(of: device.isDefault, as: Bool.self)
        // isInput (offset 25)
        itemPointer.advanced(by: 25).storeBytes(of: device.isInput, as: Bool.self)
        // isOutput (offset 26)
        itemPointer.advanced(by: 26).storeBytes(of: device.isOutput, as: Bool.self)
        // sampleRate (offset 32 - after padding)
        itemPointer.advanced(by: 32).storeBytes(of: device.sampleRate, as: Double.self)
        // channelCount (offset 40)
        itemPointer.advanced(by: 40).storeBytes(of: device.channelCount, as: UInt32.self)
    }

    devicesOut.pointee = arrayPointer
    count.pointee = Int32(deviceList.count)

    return 0
}

@_cdecl("audio_free_device_list")
public func audio_free_device_list(
    devices: UnsafeMutableRawPointer?,  // AudioDeviceInfo*
    count: Int32
) {
    guard let devices = devices else { return }

    for i in 0..<Int(count) {
        let offset = i * CAudioDeviceInfoSize
        let itemPointer = devices.advanced(by: offset)
        
        // Free uid string (offset 0)
        if let uid = itemPointer.load(as: UnsafeMutablePointer<CChar>?.self) {
            free(uid)
        }
        // Free name string (offset 8)
        if let name = itemPointer.advanced(by: 8).load(as: UnsafeMutablePointer<CChar>?.self) {
            free(name)
        }
        // Free manufacturer string (offset 16)
        if let manufacturer = itemPointer.advanced(by: 16).load(as: UnsafeMutablePointer<CChar>?.self) {
            free(manufacturer)
        }
    }

    devices.deallocate()
}

@_cdecl("audio_get_default_input_device")
public func audio_get_default_input_device() -> UnsafeMutablePointer<CChar>? {
    guard let uid = AudioDeviceManager.getDefaultInputDeviceUID() else {
        return nil
    }
    return strdup(uid)
}

@_cdecl("audio_get_default_output_device")
public func audio_get_default_output_device() -> UnsafeMutablePointer<CChar>? {
    guard let uid = AudioDeviceManager.getDefaultOutputDeviceUID() else {
        return nil
    }
    return strdup(uid)
}
