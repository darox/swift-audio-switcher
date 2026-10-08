import Foundation
import CoreFoundation

// MARK: - C shim declarations

@_silgen_name("sas_get_all_devices") func sas_get_all_devices(_ ids: UnsafeMutablePointer<UnsafeMutablePointer<UInt32>?>, _ count: UnsafeMutablePointer<UInt32>) -> Int32
@_silgen_name("sas_get_default_output") func sas_get_default_output(_ id: UnsafeMutablePointer<UInt32>) -> Int32
@_silgen_name("sas_set_default_output") func sas_set_default_output(_ id: UInt32) -> Int32
@_silgen_name("sas_get_device_name") func sas_get_device_name(_ id: UInt32, _ out: UnsafeMutableRawPointer) -> Int32
@_silgen_name("sas_get_device_uid") func sas_get_device_uid(_ id: UInt32, _ out: UnsafeMutableRawPointer) -> Int32
@_silgen_name("sas_device_has_output") func sas_device_has_output(_ id: UInt32, _ has: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("sas_device_can_be_default") func sas_device_can_be_default(_ id: UInt32, _ can: UnsafeMutablePointer<Int32>) -> Int32

// MARK: - Error type

struct SasError: Error, CustomStringConvertible {
    let code: Int32
    var description: String { "CoreAudio error \(code)" }
}

func check(_ status: Int32, _ what: String) throws {
    guard status == 0 else { throw SasError(code: status) }
}

// MARK: - Device model

struct AudioDevice: CustomStringConvertible {
    let id: UInt32
    let uid: String
    let name: String
    var isDefault: Bool = false

    var description: String {
        "\(name)\(isDefault ? " (default)" : "") [uid: \(uid)]"
    }
}

func readCFString(_ ptr: UnsafeMutableRawPointer?) -> String {
    guard let ptr = ptr else { return "" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

// MARK: - Device enumeration

func listOutputDevices() throws -> [AudioDevice] {
    var defaultID: UInt32 = 0
    try check(sas_get_default_output(&defaultID), "get default output")

    var rawIDs: UnsafeMutablePointer<UInt32>? = nil
    var count: UInt32 = 0
    try check(sas_get_all_devices(&rawIDs, &count), "get all devices")
    defer { rawIDs?.deallocate() }

    guard let rawIDs = rawIDs, count > 0 else { return [] }
    let ids = Array(UnsafeBufferPointer(start: rawIDs, count: Int(count)))

    var devices: [AudioDevice] = []
    for id in ids {
        var hasOutput: Int32 = 0
        var canDefault: Int32 = 0
        _ = sas_device_has_output(id, &hasOutput)
        _ = sas_device_can_be_default(id, &canDefault)
        guard hasOutput == 1, canDefault == 1 else { continue }

        var namePtr: UnsafeMutableRawPointer? = nil
        var uidPtr: UnsafeMutableRawPointer? = nil
        _ = sas_get_device_name(id, &namePtr)
        _ = sas_get_device_uid(id, &uidPtr)
        let name = readCFString(namePtr).isEmpty ? "Unknown" : readCFString(namePtr)
        let uid = readCFString(uidPtr)
        devices.append(AudioDevice(id: id, uid: uid, name: name, isDefault: id == defaultID))
    }
    return devices
}

// MARK: - Commands

func printUsage() {
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

func findDevice(by query: String, fuzzy: Bool) throws -> AudioDevice {
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

func setDefault(_ device: AudioDevice) throws {
    try check(sas_set_default_output(device.id), "set default output")
    print("Switched to: \(device.name)")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

do {
    guard let command = args.first else {
        for device in try listOutputDevices() { print(device) }
        exit(0)
    }
    switch command {
    case "--help", "-h", "help":
        printUsage()
    case "list", "-l":
        let devices = try listOutputDevices()
        if devices.isEmpty {
            FileHandle.standardError.write(Data("No output devices found.\n".utf8))
            exit(1)
        }
        for device in devices { print(device) }
    case "current", "-c":
        guard let device = try listOutputDevices().first(where: { $0.isDefault }) else {
            FileHandle.standardError.write(Data("Could not determine current output device.\n".utf8))
            exit(1)
        }
        print(device.name)
    case "set", "-s":
        var rest = Array(args.dropFirst())
        var fuzzy = false
        if rest.first == "-n" { fuzzy = true; rest.removeFirst() }
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
        try setDefault(current?.id == a.id ? b : a)
    default:
        FileHandle.standardError.write(Data("Unknown command \"\(command)\".\n".utf8))
        printUsage()
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
