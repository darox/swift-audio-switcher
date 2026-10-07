import CoreAudio
import Foundation

// MARK: - Error type

struct CoreAudioError: Error, CustomStringConvertible {
    let code: OSStatus
    var description: String {
        if let msg = String(cString: fourCharCode(code), encoding: .ascii), !msg.isEmpty {
            return "CoreAudio error \(code) ('\(msg)')"
        }
        return "CoreAudio error \(code)"
    }

    private func fourCharCode(_ value: OSStatus) -> [CChar] {
        let v = UInt32(bitPattern: value)
        return [
            CChar((v >> 24) & 0xFF | 0x20),
            CChar((v >> 16) & 0xFF | 0x20),
            CChar((v >> 8) & 0xFF | 0x20),
            CChar(v & 0xFF | 0x20),
            0
        ]
    }
}

// MARK: - CoreAudio helpers

private let systemObject: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)

private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: element
    )
}

private func getProperty<T>(
    _ type: T.Type,
    object: AudioObjectID,
    address: AudioObjectPropertyAddress
) throws -> T {
    let storage = UnsafeMutableRawPointer.allocate(
        byteCount: MemoryLayout<T>.size,
        alignment: MemoryLayout<T>.alignment
    )
    defer { storage.deallocate() }
    var size = UInt32(MemoryLayout<T>.size)
    var addr = address
    let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, storage)
    guard status == noErr else {
        throw CoreAudioError(code: status)
    }
    return storage.load(as: T.self)
}

private func getStringProperty(
    _ selector: AudioObjectPropertySelector,
    object: AudioObjectID,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> String {
    var address = propertyAddress(selector, scope: scope)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size)
    guard status == noErr else { throw CoreAudioError(code: status) }
    guard size > 0 else { return "" }
    let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { data.deallocate() }
    status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, data)
    guard status == noErr else { throw CoreAudioError(code: status) }
    let bytes = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: Int(size))
    if selector == kAudioObjectPropertyName || selector == kAudioDevicePropertyDeviceName {
        let cf = CFStringCreateWithBytes(
            kCFAllocatorDefault,
            bytes.baseAddress,
            CFIndex(size),
            CFStringBuiltInEncodings.UTF8.rawValue,
            false
        )
        return (cf as String?) ?? ""
    }
    return String(decoding: bytes, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func allDeviceIDs() throws -> [AudioObjectID] {
    var address = propertyAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
    guard status == noErr else { throw CoreAudioError(code: status) }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var ids = [AudioObjectID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids)
    guard status == noErr else { throw CoreAudioError(code: status) }
    return ids
}

private func isOutputDevice(_ id: AudioObjectID) -> Bool {
    var streamAddress = propertyAddress(
        kAudioDevicePropertyStreamConfiguration,
        scope: kAudioObjectPropertyScopeOutput
    )
    var size: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &size)
    guard status == noErr, size > 0 else { return false }
    let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { data.deallocate() }
    var sz = size
    guard AudioObjectGetPropertyData(id, &streamAddress, 0, nil, &sz, data) == noErr else {
        return false
    }
    let list = data.assumingMemoryBound(to: AudioBufferList.self)
    return list.pointee.mNumberBuffers > 0
}

private func canBeDefaultOutput(_ id: AudioObjectID) -> Bool {
    var address = propertyAddress(kAudioDevicePropertyDeviceCanBeDefaultDevice)
    var can: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &can) == noErr else {
        return false
    }
    return can != 0
}

// MARK: - Device model

struct AudioDevice: Identifiable, CustomStringConvertible {
    let id: AudioObjectID
    let uid: String
    let name: String
    var isDefault: Bool = false

    var description: String {
        "\(name)\(isDefault ? " (default)" : "") [uid: \(uid)]"
    }
}

private func listOutputDevices() throws -> [AudioDevice] {
    let current = try getProperty(
        AudioObjectID.self,
        object: systemObject,
        address: propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    )
    var devices: [AudioDevice] = []
    for id in try allDeviceIDs() {
        guard isOutputDevice(id), canBeDefaultOutput(id) else { continue }
        let name = (try? getStringProperty(kAudioObjectPropertyName, object: id)) ?? "Unknown"
        let uid = (try? getStringProperty(kAudioDevicePropertyDeviceUID, object: id)) ?? ""
        devices.append(AudioDevice(id: id, uid: uid, name: name, isDefault: id == current))
    }
    return devices
}

// MARK: - Commands

private func printUsage() {
    FileHandle.standardError.write(Data("""
        swift-audio-switcher — switch the default macOS audio output device

        Usage:
          swift-audio-switcher list              List output devices (default command)
          swift-audio-switcher current           Print the current default output device
          swift-audio-switcher set <name|uid>    Set the default output device (exact match)
          swift-audio-switcher set -n <name>     Set by name (substring match, first hit)
          swift-audio-switcher toggle <a> <b>    Toggle between two devices (by name or uid)
          swift-audio-switcher --help            Show this help

        "name" matching is case-insensitive. Use "list" to see exact names and uids.

        """.utf8))
}

private func findDevice(by query: String, fuzzy: Bool) throws -> AudioDevice {
    let devices = try listOutputDevices()
    let q = query.lowercased()
    if let exact = devices.first(where: { $0.name.lowercased() == q || $0.uid == query }) {
        return exact
    }
    if fuzzy, let match = devices.first(where: { $0.name.lowercased().contains(q) }) {
        return match
    }
    let names = devices.map { "  - \($0.name) (uid: \($0.uid))" }.joined(separator: "\n")
    FileHandle.standardError.write(Data("No output device matching \"\(query)\".\nAvailable devices:\n\(names)\n".utf8))
    exit(1)
}

private func setDefault(_ device: AudioDevice) throws {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var id = device.id
    let status = AudioObjectSetPropertyData(
        systemObject, &address, 0, nil,
        UInt32(MemoryLayout<AudioObjectID>.size), &id
    )
    guard status == noErr else { throw CoreAudioError(code: status) }
    print("Switched to: \(device.name)")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

func run() throws {
    guard let command = args.first else {
        for device in try listOutputDevices() { print(device) }
        return
    }
    switch command {
    case "--help", "-h", "help":
        printUsage()
    case "list", "-l":
        for device in try listOutputDevices() { print(device) }
    case "current", "-c":
        guard let device = try listOutputDevices().first(where: { $0.isDefault }) else {
            FileHandle.standardError.write(Data("Could not determine current output device.\n".utf8))
            exit(1)
        }
        print(device.name)
    case "set", "-s":
        var rest = Array(args.dropFirst())
        var fuzzy = false
        if rest.first == "-n" {
            fuzzy = true
            rest.removeFirst()
        }
        guard let query = rest.first else {
            FileHandle.standardError.write(Data("Usage: swift-audio-switcher set [-n] <name|uid>\n".utf8))
            exit(1)
        }
        try setDefault(findDevice(by: query, fuzzy: fuzzy))
    case "toggle", "-t":
        let rest = Array(args.dropFirst(2))
        guard rest.count == 2 else {
            FileHandle.standardError.write(Data("Usage: swift-audio-switcher toggle <device-a> <device-b>\n".utf8))
            exit(1)
        }
        let current = try listOutputDevices().first(where: { $0.isDefault })
        let a = try findDevice(by: rest[0], fuzzy: true)
        let b = try findDevice(by: rest[1], fuzzy: true)
        let target: AudioDevice
        if current?.id == a.id { target = b } else { target = a }
        try setDefault(target)
    default:
        FileHandle.standardError.write(Data("Unknown command \"\(command)\".\n".utf8))
        printUsage()
        exit(1)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
