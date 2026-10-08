# swift-audio-switcher

A small, dependency-free CLI to list and switch the default macOS audio output device. No third-party dependencies — only Apple's CoreAudio framework.

Use it with Raycast, Hammerspoon, Keyboard Maestro, or any launcher.

## Install

### Homebrew (recommended)

```sh
brew tap darox/swift-audio-switcher https://github.com/darox/swift-audio-switcher.git
brew install swift-audio-switcher
```

This taps the main repository directly (no separate tap repo needed).

To upgrade later:

```sh
brew upgrade swift-audio-switcher
```

Or install in one step without tapping:

```sh
brew install https://raw.githubusercontent.com/darox/swift-audio-switcher/main/Formula/swift-audio-switcher.rb
```

### Pre-built binary

Download the latest universal binary (Apple Silicon + Intel) from [Releases](https://github.com/darox/swift-audio-switcher/releases):

```sh
VERSION=v1.0.0  # check the Releases page for the latest
curl -LO "https://github.com/darox/swift-audio-switcher/releases/download/${VERSION}/swift-audio-switcher-${VERSION}-universal.tar.gz"
tar -xzf swift-audio-switcher-*-universal.tar.gz
sudo mv swift-audio-switcher /usr/local/bin/
```

### Mint

```sh
mint install darox/swift-audio-switcher
```

### From source

```sh
git clone https://github.com/darox/swift-audio-switcher.git
cd swift-audio-switcher
swift build -c release
sudo cp .build/release/swift-audio-switcher /usr/local/bin/
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
