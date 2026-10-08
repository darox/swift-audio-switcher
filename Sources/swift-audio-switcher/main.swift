import CoreAudio
import Foundation

let version = "1.1.1"

// MARK: - Errors

struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let code: OSStatus

    var description: String {
        var text = "\(operation) failed (OSStatus \(code))"
        let fourCC = Self.fourCharCode(code)
        if !fourCC.isEmpty { text += " '\(fourCC)'" }
        return text
    }

    private static func fourCharCode(_ value: OSStatus) -> String {
        let v = UInt32(bitPattern: value)
        let bytes = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        guard bytes.allSatisfy({ (32...126).contains($0) }) else { return "" }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

// MARK: - CoreAudio property access

private let systemObject = AudioObjectID(kAudioObjectSystemObject)

private func propAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

private func readObjectID(
    _ address: AudioObjectPropertyAddress,
    from object: AudioObjectID = systemObject,
    _ operation: String
) throws -> AudioObjectID {
    var address = address
    var value: AudioObjectID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { throw CoreAudioError(operation: operation, code: status) }
    return value
}

/// Reads a CFString-valued property. The HAL follows the CF "copy" rule, so the
/// returned reference is owned by us; `takeRetainedValue()` hands it to ARC.
private func readString(
    _ address: AudioObjectPropertyAddress,
    from object: AudioObjectID
) -> String? {
    var address = address
    var size = UInt32(MemoryLayout<UnsafeMutableRawPointer>.size)
    var pointer: UnsafeMutableRawPointer?
    let status = withUnsafeMutablePointer(to: &pointer) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let raw = pointer else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeRetainedValue() as String
}

/// Total channel count a device exposes in the given scope; 0 means none.
private func channelCount(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var address = propAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
        return 0
    }
    let storage = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { storage.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else {
        return 0
    }
    let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
}

private func allDeviceIDs() throws -> [AudioObjectID] {
    var address = propAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
    guard status == noErr else {
        throw CoreAudioError(operation: "enumerate audio devices", code: status)
    }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
    guard status == noErr else {
        throw CoreAudioError(operation: "enumerate audio devices", code: status)
    }
    return ids
}

// MARK: - Devices

struct OutputDevice: CustomStringConvertible {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isDefault: Bool

    var description: String {
        "\(name)\(isDefault ? " (default)" : "") [uid: \(uid)]"
    }
}

func outputDevices() throws -> [OutputDevice] {
    let defaultID = try readObjectID(
        propAddress(kAudioHardwarePropertyDefaultOutputDevice),
        "read the default output device"
    )
    return try allDeviceIDs()
        .filter { channelCount(of: $0, scope: kAudioObjectPropertyScopeOutput) > 0 }
        .map { id in
            OutputDevice(
                id: id,
                uid: readString(propAddress(kAudioDevicePropertyDeviceUID), from: id) ?? "",
                name: readString(propAddress(kAudioObjectPropertyName), from: id) ?? "Unknown",
                isDefault: id == defaultID
            )
        }
        .sorted { ($0.isDefault ? 0 : 1, $0.name) < ($1.isDefault ? 0 : 1, $1.name) }
}

func setDefaultOutput(_ device: OutputDevice) throws {
    var address = propAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var id = device.id
    let status = AudioObjectSetPropertyData(
        systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id
    )
    guard status == noErr else {
        throw CoreAudioError(operation: "set the default output device", code: status)
    }
}

// MARK: - Output

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() {
    FileHandle.standardError.write(Data("""
    swift-audio-switcher — switch the default macOS audio output device

    Usage:
      swift-audio-switcher list               List output devices (default command)
      swift-audio-switcher current            Print the name of the default output device
      swift-audio-switcher set <name|uid>     Switch to a device (exact match, case-insensitive)
      swift-audio-switcher set -n <name>      Switch by partial name (first match)
      swift-audio-switcher toggle <a> <b>     Toggle between two devices
      swift-audio-switcher diagnose          Print raw CoreAudio state (for troubleshooting)
      swift-audio-switcher --help             Show this help

    """.utf8))
}

func findDevice(_ query: String, fuzzy: Bool) throws -> OutputDevice {
    let devices = try outputDevices()
    let lowered = query.lowercased()
    if let exact = devices.first(where: { $0.name.lowercased() == lowered || $0.uid == query }) {
        return exact
    }
    if fuzzy, let partial = devices.first(where: { $0.name.lowercased().contains(lowered) }) {
        return partial
    }
    let available = devices.map { "  \($0.name)  (uid: \($0.uid))" }.joined(separator: "\n")
    fail("No output device matches \"\(query)\".\nAvailable devices:\n\(available)")
}

func diagnose() throws {
    print("swift-audio-switcher \(version)")
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    let defaultID = try? readObjectID(
        propAddress(kAudioHardwarePropertyDefaultOutputDevice),
        "read the default output device"
    )
    print("default output device: \(defaultID.map(String.init) ?? "unavailable")")
    let ids = try allDeviceIDs()
    print("devices reported by kAudioHardwarePropertyDevices: \(ids.count)")
    for id in ids {
        let name = readString(propAddress(kAudioObjectPropertyName), from: id) ?? "?"
        let uid = readString(propAddress(kAudioDevicePropertyDeviceUID), from: id) ?? "?"
        let outputs = channelCount(of: id, scope: kAudioObjectPropertyScopeOutput)
        let inputs = channelCount(of: id, scope: kAudioObjectPropertyScopeInput)
        print("  id=\(id) name=\"\(name)\" uid=\"\(uid)\" outputs=\(outputs) inputs=\(inputs)")
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first ?? "list" {
    case "list", "-l":
        let devices = try outputDevices()
        guard !devices.isEmpty else {
            fail("No output devices found. Run 'swift-audio-switcher diagnose' for details.")
        }
        devices.forEach { print($0) }

    case "--help", "-h", "help":
        usage()

    case "current", "-c":
        let devices = try outputDevices()
        guard let current = devices.first(where: { $0.isDefault }) else {
            fail("Could not determine the current output device.")
        }
        print(current.name)

    case "set", "-s":
        var rest = Array(arguments.dropFirst())
        let fuzzy = rest.first == "-n"
        if fuzzy { rest.removeFirst() }
        guard let query = rest.first else {
            fail("Usage: swift-audio-switcher set [-n] <name|uid>")
        }
        let device = try findDevice(query, fuzzy: fuzzy)
        try setDefaultOutput(device)
        print("Switched to: \(device.name)")

    case "toggle", "-t":
        let rest = Array(arguments.dropFirst())
        guard rest.count == 2 else {
            fail("Usage: swift-audio-switcher toggle <device-a> <device-b>")
        }
        let devices = try outputDevices()
        let first = try findDevice(rest[0], fuzzy: true)
        let second = try findDevice(rest[1], fuzzy: true)
        let firstIsActive = devices.first(where: { $0.isDefault })?.id == first.id
        let target = firstIsActive ? second : first
        try setDefaultOutput(target)
        print("Switched to: \(target.name)")

    case "diagnose":
        try diagnose()

    case let unknown:
        usage()
        fail("Unknown command \"\(unknown)\".")
    }
} catch {
    fail("Error: \(error)")
}
