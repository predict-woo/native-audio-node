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
                manufacturer: device.manufacturer ?? "",
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

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &uid
        )

        return status == noErr ? (uid as String?) : nil
    }

    private static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &name
        )

        return status == noErr ? (name as String?) : nil
    }

    private static func getDeviceManufacturer(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceManufacturerCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var manufacturer: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &manufacturer
        )

        return status == noErr ? (manufacturer as String?) : nil
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

// Using raw pointers to match C struct layout
// C struct: { char* uid, char* name, char* manufacturer, bool isDefault, bool isInput, bool isOutput, double sampleRate, uint32_t channelCount }

@_cdecl("coreaudio_list_devices")
public func coreaudio_list_devices(
    devices: UnsafeMutablePointer<UnsafeMutableRawPointer?>,
    count: UnsafeMutablePointer<Int32>
) -> Int32 {
    let deviceList = AudioDeviceManager.listAllDevices()

    guard !deviceList.isEmpty else {
        devices.pointee = nil
        count.pointee = 0
        return 0
    }

    // Calculate struct size: 3 pointers (24 bytes on 64-bit) + 3 bools (3 bytes + padding) + double (8 bytes) + uint32 (4 bytes)
    // Using 8-byte alignment: 24 + 8 (3 bools padded) + 8 + 8 (uint32 padded) = 48 bytes
    let structSize = 48
    let arrayPointer = UnsafeMutableRawPointer.allocate(byteCount: structSize * deviceList.count, alignment: 8)

    for (index, device) in deviceList.enumerated() {
        let offset = index * structSize
        let uidCStr = strdup(device.uid)
        let nameCStr = strdup(device.name)
        let manufacturerCStr = strdup(device.manufacturer)

        // Write fields at their offsets
        arrayPointer.storeBytes(of: uidCStr, toByteOffset: offset + 0, as: UnsafeMutablePointer<CChar>?.self)
        arrayPointer.storeBytes(of: nameCStr, toByteOffset: offset + 8, as: UnsafeMutablePointer<CChar>?.self)
        arrayPointer.storeBytes(of: manufacturerCStr, toByteOffset: offset + 16, as: UnsafeMutablePointer<CChar>?.self)
        arrayPointer.storeBytes(of: device.isDefault, toByteOffset: offset + 24, as: Bool.self)
        arrayPointer.storeBytes(of: device.isInput, toByteOffset: offset + 25, as: Bool.self)
        arrayPointer.storeBytes(of: device.isOutput, toByteOffset: offset + 26, as: Bool.self)
        arrayPointer.storeBytes(of: device.sampleRate, toByteOffset: offset + 32, as: Double.self)
        arrayPointer.storeBytes(of: device.channelCount, toByteOffset: offset + 40, as: UInt32.self)
    }

    devices.pointee = arrayPointer
    count.pointee = Int32(deviceList.count)

    return 0
}

@_cdecl("coreaudio_free_device_list")
public func coreaudio_free_device_list(
    devices: UnsafeMutableRawPointer?,
    count: Int32
) {
    guard let devices = devices else { return }

    let structSize = 48
    for i in 0..<Int(count) {
        let offset = i * structSize
        if let uid = devices.load(fromByteOffset: offset + 0, as: UnsafeMutablePointer<CChar>?.self) {
            free(uid)
        }
        if let name = devices.load(fromByteOffset: offset + 8, as: UnsafeMutablePointer<CChar>?.self) {
            free(name)
        }
        if let manufacturer = devices.load(fromByteOffset: offset + 16, as: UnsafeMutablePointer<CChar>?.self) {
            free(manufacturer)
        }
    }

    devices.deallocate()
}

@_cdecl("coreaudio_get_default_input_device")
public func coreaudio_get_default_input_device() -> UnsafeMutablePointer<CChar>? {
    guard let uid = AudioDeviceManager.getDefaultInputDeviceUID() else {
        return nil
    }
    return strdup(uid)
}

@_cdecl("coreaudio_get_default_output_device")
public func coreaudio_get_default_output_device() -> UnsafeMutablePointer<CChar>? {
    guard let uid = AudioDeviceManager.getDefaultOutputDeviceUID() else {
        return nil
    }
    return strdup(uid)
}
