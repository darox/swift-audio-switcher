import Foundation
import CoreFoundation
import CoreAudio
import Darwin

// MARK: - CoreAudio via dlsym
//
// The deprecated C API (AudioHardwareGetProperty, AudioDeviceGetProperty, etc.)
// still works on current macOS but is marked unavailable in Swift and may not
// compile on all SDK versions. We call them via dlsym at runtime instead.

// MARK: - Error type

struct SasError: Error, CustomStringConvertible {
    let code: Int32
    let fn: String
    var description: String { "CoreAudio error \(code) in \(fn)" }
}

func check(_ status: OSStatus, _ fn: String) throws {
    guard status == 0 else { throw SasError(code: status, fn: fn) }
}

// MARK: - Function pointer types

typealias GetPropertyInfoFn = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<Bool>?) -> OSStatus
typealias GetPropertyFn = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutableRawPointer?) -> OSStatus
typealias SetPropertyFn = @convention(c) (UInt32, UInt32, UnsafeRawPointer?) -> OSStatus
typealias DeviceGetPropertyInfoFn = @convention(c) (UInt32, UInt32, Bool, UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<Bool>?) -> OSStatus
typealias DeviceGetPropertyFn = @convention(c) (UInt32, UInt32, Bool, UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutableRawPointer?) -> OSStatus
typealias DeviceSetPropertyFn = @convention(c) (UInt32, UInt32, Bool, UInt32, UInt32, UnsafeRawPointer?) -> OSStatus

// MARK: - CoreAudio symbols loaded via dlsym

final class CoreAudioAPI {
    static let shared = CoreAudioAPI()

    let audioHardwareGetPropertyInfo: GetPropertyInfoFn
    let audioHardwareGetProperty: GetPropertyFn
    let audioHardwareSetProperty: SetPropertyFn
    let audioDeviceGetPropertyInfo: DeviceGetPropertyInfoFn
    let audioDeviceGetProperty: DeviceGetPropertyFn
    let audioDeviceSetProperty: DeviceSetPropertyFn

    private init() {
        let path = "/System/Library/Frameworks/CoreAudio.framework/CoreAudio"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            let err = dlerror()
            fatalError("Failed to load CoreAudio: \(err != nil ? String(cString: err!) : "unknown")")
        }
        func sym<T>(_ name: String, as type: T.Type) -> T {
            guard let ptr = dlsym(handle, name) else {
                fatalError("Symbol not found: \(name)")
            }
            return unsafeBitCast(ptr, to: T.self)
        }
        audioHardwareGetPropertyInfo = sym("AudioHardwareGetPropertyInfo", as: GetPropertyInfoFn.self)
        audioHardwareGetProperty = sym("AudioHardwareGetProperty", as: GetPropertyFn.self)
        audioHardwareSetProperty = sym("AudioHardwareSetProperty", as: SetPropertyFn.self)
        audioDeviceGetPropertyInfo = sym("AudioDeviceGetPropertyInfo", as: DeviceGetPropertyInfoFn.self)
        audioDeviceGetProperty = sym("AudioDeviceGetProperty", as: DeviceGetPropertyFn.self)
        audioDeviceSetProperty = sym("AudioDeviceSetProperty", as: DeviceSetPropertyFn.self)
    }
}

let ca = CoreAudioAPI.shared

// Property selector constants (fourcc values from CoreAudio headers)
private let kAudioHardwarePropertyDevices: UInt32 = 0x64657623        // 'dev#'
private let kAudioHardwarePropertyDefaultOutputDevice: UInt32 = 0x644F7574 // 'dOut'
private let kAudioDevicePropertyStreamConfiguration: UInt32 = 0x736C6179   // 'slay'
private let kAudioDevicePropertyDeviceCanBeDefaultDevice: UInt32 = 0x64666C74 // 'dflt'
private let kAudioDevicePropertyDeviceNameCFString: UInt32 = 0x6C6E616D     // 'lnam'
private let kAudioDevicePropertyDeviceUID: UInt32 = 0x75696420             // 'uid '

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

// MARK: - Device enumeration

func listOutputDevices() throws -> [AudioDevice] {
    // Get default output device
    var defaultID: UInt32 = 0
    var defSize = UInt32(MemoryLayout<UInt32>.size)
    try check(ca.audioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &defSize, &defaultID),
              "AudioHardwareGetProperty(DefaultOutput)")

    // Get all device IDs
    var listSize: UInt32 = 0
    try check(ca.audioHardwareGetPropertyInfo(kAudioHardwarePropertyDevices, &listSize, nil),
              "AudioHardwareGetPropertyInfo(Devices)")
    guard listSize > 0 else { return [] }

    let idsPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(listSize), alignment: 8)
    defer { idsPtr.deallocate() }
    var sz = listSize
    try check(ca.audioHardwareGetProperty(kAudioHardwarePropertyDevices, &sz, idsPtr),
              "AudioHardwareGetProperty(Devices)")
    let count = Int(sz) / MemoryLayout<UInt32>.size
    let ids = Array(UnsafeBufferPointer(start: idsPtr.assumingMemoryBound(to: UInt32.self), count: count))

    var devices: [AudioDevice] = []
    for id in ids {
        // Check if device has output streams
        var streamSize: UInt32 = 0
        let streamSt = ca.audioDeviceGetPropertyInfo(id, 0, false, kAudioDevicePropertyStreamConfiguration, &streamSize, nil)
        guard streamSt == 0, streamSize > 0 else { continue }

        // Check if device can be default output
        var canDefault: UInt32 = 0
        var cdSize = UInt32(MemoryLayout<UInt32>.size)
        let cdSt = ca.audioDeviceGetProperty(id, 0, false, kAudioDevicePropertyDeviceCanBeDefaultDevice, &cdSize, &canDefault)
        guard cdSt == 0, canDefault != 0 else { continue }

        // Get name and UID (CFStringRef properties)
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var namePtr: UnsafeMutableRawPointer? = nil
        _ = ca.audioDeviceGetProperty(id, 0, false, kAudioDevicePropertyDeviceNameCFString, &nameSize, &namePtr)
        let name: String
        if let ptr = namePtr {
            name = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        } else {
            name = "Unknown"
        }

        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidPtr: UnsafeMutableRawPointer? = nil
        _ = ca.audioDeviceGetProperty(id, 0, false, kAudioDevicePropertyDeviceUID, &uidSize, &uidPtr)
        let uid: String
        if let ptr = uidPtr {
            uid = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        } else {
            uid = ""
        }

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
    var id = device.id
    try check(ca.audioHardwareSetProperty(kAudioHardwarePropertyDefaultOutputDevice, UInt32(MemoryLayout<UInt32>.size), &id),
              "AudioHardwareSetProperty(DefaultOutput)")
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
