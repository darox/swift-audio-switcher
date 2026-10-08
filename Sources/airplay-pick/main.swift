import ApplicationServices
import AppKit
import CoreAudio
import CoreGraphics
import Foundation

// airplay-pick — make an AirPlay device the macOS default audio output.
//
// macOS 26 has no public API, no Shortcuts action and no supported command that
// starts an AirPlay audio session. The device only exists in CoreAudio while a
// session runs. The Sound settings pane is the one place a not-yet-active
// AirPlay device can be picked, so this helper drives that pane through the
// accessibility API and confirms the result through CoreAudio.

// MARK: - arguments

let arguments = Array(CommandLine.arguments.dropFirst())
let listOnly = arguments.contains("--list")
let wanted = arguments.first { !$0.hasPrefix("--") } ?? ""

if arguments.contains("--help") {
    print("""
    usage: airplay-pick <device name>
           airplay-pick --list

    <device name>   the AirPlay device as shown in System Settings > Sound,
                    for example "Büro" or "Wohnzimmer"
    --list          print the output devices the Sound pane offers
    """)
    exit(0)
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// MARK: - CoreAudio

private let systemObject = AudioObjectID(kAudioObjectSystemObject)

func defaultOutputName() -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr,
          device != kAudioObjectUnknown else { return nil }

    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var nameSize = UInt32(MemoryLayout<UnsafeMutableRawPointer>.size)
    var pointer: UnsafeMutableRawPointer?
    guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &pointer) == noErr,
          let raw = pointer else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeRetainedValue() as String
}

// MARK: - accessibility

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func text(_ element: AXUIElement, _ name: String) -> String { (attribute(element, name) as? String) ?? "" }

func label(_ element: AXUIElement) -> String {
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
        let value = text(element, name)
        if !value.isEmpty { return value }
    }
    return ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func centre(_ element: AXUIElement) -> CGPoint? {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGPoint(x: point.x + dimensions.width / 2, y: point.y + dimensions.height / 2)
}

func descendants(of element: AXUIElement, into result: inout [AXUIElement], depth: Int = 0) {
    result.append(element)
    guard depth < 16 else { return }
    for child in children(element) { descendants(of: child, into: &result, depth: depth + 1) }
}

/// Rows of the Sound pane output list: label of the first cell plus its kind.
func outputRows() -> [(element: AXUIElement, name: String, kind: String)] {
    guard let application = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
    else { return [] }
    let root = AXUIElementCreateApplication(application.processIdentifier)
    var all: [AXUIElement] = []
    descendants(of: root, into: &all)

    let headings = all.filter { text($0, kAXRoleAttribute) == "AXHeading" && label($0) == "Output & Input" }
    var rows: [(AXUIElement, String, String)] = []
    for row in all where text(row, kAXRoleAttribute) == "AXRow" {
        var cells: [AXUIElement] = []
        for child in children(row) { descendants(of: child, into: &cells) }
        let labels = cells.map { label($0) }.filter { !$0.isEmpty }
        guard labels.count >= 2 else { continue }
        // Only rows that sit below the "Output & Input" heading belong to the output list.
        guard let rowY = centre(row)?.y, headings.contains(where: { (centre($0)?.y ?? .infinity) < rowY }) else { continue }
        rows.append((row, labels[0], labels[1]))
    }
    return rows
}

func soundWindow() -> AXUIElement? {
    guard let application = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
    else { return nil }
    let root = AXUIElementCreateApplication(application.processIdentifier)
    let windows = (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    return windows.first { text($0, kAXTitleAttribute) == "Sound" }
}

func closeSoundWindow() {
    guard let window = soundWindow(), let button = attribute(window, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
}

func openSoundPane() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
        NSWorkspace.shared.open(url)
    }
}

func raiseSystemSettings() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        .first?.activate()
}

// MARK: - input

func click(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

// MARK: - commands

if listOnly {
    let before = defaultOutputName() ?? "?"
    print("default output: \(before)")
    let rows = outputRows()
    if rows.isEmpty { print("no output devices listed") }
    for row in rows { print("  \(row.name) — \(row.kind)") }
    exit(0)
}

guard !wanted.isEmpty else { fail("No device name given. Run airplay-pick --help.") }
guard AXIsProcessTrusted() else {
    fail("Grant Accessibility permission to the app that runs this command (Raycast or Terminal), then retry.")
}
if let session = CGSessionCopyCurrentDictionary() as? [String: Any], (session["CGSSessionScreenIsLocked"] as? Int) == 1 {
    fail("The screen is locked. Unlock the Mac, then run the command again.")
}

let previousApplication = NSWorkspace.shared.frontmostApplication
let before = defaultOutputName()

func row(named name: String) -> (element: AXUIElement, name: String, kind: String)? {
    outputRows().first { $0.name.localizedCaseInsensitiveContains(name) }
}

func pick(_ name: String) -> String? {
    for attempt in 1...3 {
        guard let target = row(named: name) else { return nil }
        raiseSystemSettings()
        usleep(attempt == 1 ? 700_000 : 400_000)
        guard let point = centre(target.element) else { return nil }
        click(point)

        // The switch happens shortly after the click; wait for CoreAudio to agree.
        for _ in 0..<16 {
            usleep(200_000)
            if let now = defaultOutputName(), now != before { return now }
        }
    }
    return nil
}

var result = pick(wanted)

if result == nil {
    // The output list is refreshed when the pane is opened, so retry with a fresh pane.
    closeSoundWindow()
    usleep(400_000)
    openSoundPane()
    for _ in 0..<30 {
        usleep(400_000)
        if row(named: wanted) != nil { break }
    }
    result = pick(wanted)
}

previousApplication?.activate()

guard let output = result else {
    let seen = outputRows().map { "\($0.name) (\($0.kind))" }.joined(separator: ", ")
    fail("Could not switch to \"\(wanted)\".\nOutput devices listed: \(seen.isEmpty ? "none" : seen)")
}
print("Output: \(output)")
