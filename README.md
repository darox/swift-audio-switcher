# swift-audio-switcher

Switch the default macOS audio output device from the command line. Pure Swift, no third-party dependencies — only Apple's CoreAudio framework.

Tested with a Raycast script command.

The package installs two commands:

| Command | Purpose | Permissions |
| --- | --- | --- |
| `swift-audio-switcher` | List and set output devices with CoreAudio. | None |
| `airplay-pick` | Select an AirPlay device, which CoreAudio does not publish until the session starts. | Accessibility |

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
swift-audio-switcher diagnose          # print raw CoreAudio state for troubleshooting
```

Example `list` output:

```
MacBook Pro Speakers (default) [uid: BuiltInSpeakerDevice]
Living Room TV [uid: AA:BB:CC:DD:EE:FF]
```

## AirPlay

macOS does not publish an AirPlay device to CoreAudio until a session runs, and the
AirPlay device disappears again when the output changes back. No API and no Shortcuts
action starts that session, so `swift-audio-switcher set "AirPlay"` fails while no
session runs.

`airplay-pick` therefore makes the choice in System Settings > Sound, which is the only
place macOS offers a not-yet-active AirPlay device:

```sh
airplay-pick --list        # list the output devices that Sound offers
airplay-pick "Living Room" # make that AirPlay device the output device
```

The command opens the Sound pane, selects the row, and confirms the result through
CoreAudio. Then `swift-audio-switcher` can switch away from the AirPlay device as usual.

Grant Accessibility permission to the app that runs the command, in System Settings >
Privacy & Security > Accessibility. A launcher such as Raycast needs one entry; each
script that Raycast runs then inherits it.

## Raycast

Add the script directory in Raycast: Settings > Extensions > Script Commands.

Toggle AirPlay, `audio-toggle-airplay.sh`:

```bash
#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Audio: Toggle AirPlay
# @raycast.description Switch the default audio output between the speakers and an AirPlay device
# @raycast.mode compact
# @raycast.icon 🔊
# @raycast.packageName Audio

set -uo pipefail

AUDIO=/opt/homebrew/bin/swift-audio-switcher
SPEAKERS="MacBook Pro Speakers"
AIRPLAY_DEVICE="Wohnzimmer"
STATE="${TMPDIR:-/tmp}/swift-audio-switcher.previous"

current=$("$AUDIO" current 2>/dev/null)

if [ "$current" = "AirPlay" ]; then
  restore="$SPEAKERS"
  if [ -r "$STATE" ]; then restore=$(cat "$STATE"); fi
  "$AUDIO" set "$restore" >/dev/null && echo "Output: $restore"
  exit 0
fi

printf '%s' "$current" > "$STATE"
exec airplay-pick "$AIRPLAY_DEVICE"
```

Set `AIRPLAY_DEVICE` to the name that `airplay-pick --list` prints.

## How it works

`swift-audio-switcher` uses the CoreAudio HAL API (`AudioObjectGetPropertyData` /
`AudioObjectSetPropertyData`) to enumerate output devices and set
`kAudioHardwarePropertyDefaultOutputDevice`.

`airplay-pick` reads and drives the System Settings Sound pane through the macOS
accessibility API, then reads the default output device from CoreAudio again to confirm
the switch.

## License

MIT
