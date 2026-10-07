# swift-audio-switcher

A small, dependency-free CLI to list and switch the default macOS audio output device. No third-party dependencies — only Apple's CoreAudio framework.

Use it with Raycast, Hammerspoon, Keyboard Maestro, or any launcher.

## Install

```sh
git clone https://github.com/darox/swift-audio-switcher.git
cd swift-audio-switcher
swift build -c release
# Binary at: .build/release/swift-audio-switcher
# Optionally copy to /usr/local/bin:
sudo cp .build/release/swift-audio-switcher /usr/local/bin/
```

Or with [Mint](https://github.com/yonaskolb/Mint):

```sh
mint install darox/swift-audio-switcher
```

## Usage

```sh
# List all output devices (marks the current default)
swift-audio-switcher list
# Example output:
#   MacBook Pro Speakers (default) [uid: BuiltInSpeakerDevice]
#   Living Room TV [uid: AA:BB:CC:DD:EE:FF]

# Show the current default device name
swift-audio-switcher current

# Switch by exact name or UID (case-insensitive name match)
swift-audio-switcher set "Living Room TV"

# Switch by partial name (first match wins)
swift-audio-switcher set -n "Living"

# Toggle between two devices
swift-audio-switcher toggle "MacBook Pro Speakers" "Living Room TV"
```

## Raycast Script Command

Create a script command in Raycast (⌘K → "Create Script Command"):

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title AirPlay: Living Room TV
# @raycast.mode silent
# @raycast.icon 🔊

/usr/local/bin/swift-audio-switcher set "Living Room TV"
```

For a toggle between two devices:

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Audio Output
# @raycast.mode silent
# @raycast.icon 🔀

/usr/local/bin/swift-audio-switcher toggle "MacBook Pro Speakers" "Living Room TV"
```

## How it works

Uses the CoreAudio HAL API (`AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`) to enumerate output devices and set `kAudioHardwarePropertyDefaultOutputDevice`. No Accessibility permissions, no UI automation, no network access.

## License

MIT
