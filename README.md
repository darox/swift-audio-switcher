# swift-audio-switcher

Switch the default macOS audio output device from the command line. Pure Swift, no third-party dependencies — only Apple's CoreAudio framework. No Accessibility permissions, no UI automation.

Works with Raycast, Hammerspoon, Keyboard Maestro, or any launcher.

## Install

Requires up-to-date Xcode Command Line Tools (`xcode-select --install`).

```sh
brew tap darox/swift-audio-switcher https://github.com/darox/swift-audio-switcher.git
brew trust darox/swift-audio-switcher   # required once for third-party taps (Homebrew 4.6+)
brew install swift-audio-switcher
```

## Usage

```sh
swift-audio-switcher list              # list output devices (marks the current default)
swift-audio-switcher current           # print the current default device name
swift-audio-switcher set "Living Room TV"   # switch by exact name or UID
swift-audio-switcher set -n "Living"        # switch by partial name (first match)
swift-audio-switcher toggle "Speakers" "TV" # toggle between two devices
```

Example `list` output:

```
MacBook Pro Speakers (default) [uid: BuiltInSpeakerDevice]
Living Room TV [uid: AA:BB:CC:DD:EE:FF]
```

## Raycast

Create a script command (⌘K → "Create Script Command"):

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title AirPlay: Living Room TV
# @raycast.mode silent
# @raycast.icon 🔊

/usr/local/bin/swift-audio-switcher set "Living Room TV"
```

Or a toggle between two devices:

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Audio Output
# @raycast.mode silent
# @raycast.icon 🔀

/usr/local/bin/swift-audio-switcher toggle "MacBook Pro Speakers" "Living Room TV"
```

## How it works

Uses the CoreAudio HAL API (`AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`) to enumerate output devices and set `kAudioHardwarePropertyDefaultOutputDevice`.

## Release automation

Push a tag to build and publish a release:

```sh
git tag v1.1.0 && git push origin v1.1.0
```

GitHub Actions builds a universal binary, creates the GitHub Release, and updates the Homebrew formula automatically.

## License

MIT
