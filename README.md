# swift-audio-switcher

Switch the macOS audio output device from the command line, including remote AirPlay
devices. Pure Swift, no third-party dependencies.

## What this solves

macOS cannot switch the audio output to AirPlay from a script.

- The AirPlay device does not exist in CoreAudio until a session runs.
- The device disappears again when the output changes back.
- No API, CLI, or Shortcuts action starts that session.
- macOS lists a not-yet-active AirPlay device only in the System Settings Sound pane.

So this fails while no AirPlay session runs:

```
$ swift-audio-switcher set "AirPlay"
No output device matches "AirPlay".
```

The package closes that gap with two commands:

- **`swift-audio-switcher`** — lists output devices and sets the default one, through
  CoreAudio. No permissions needed.
- **`airplay-pick`** — selects an AirPlay device in the System Settings Sound pane, then
  confirms the switch through CoreAudio. Needs Accessibility permission.

Use both for a complete AirPlay toggle: `airplay-pick` turns AirPlay on,
`swift-audio-switcher` switches back to the speakers.

## Install

Requires up-to-date Xcode Command Line Tools (`xcode-select --install`).

```sh
brew tap darox/swift-audio-switcher https://github.com/darox/swift-audio-switcher.git
brew trust darox/swift-audio-switcher   # once, for third-party taps (Homebrew 4.6+)
brew install swift-audio-switcher
```

## Usage

CoreAudio devices:

```sh
swift-audio-switcher list                     # list output devices, current one marked
swift-audio-switcher current                  # print the current output device
swift-audio-switcher set "DELL U2725QE"       # switch by exact name or UID
swift-audio-switcher set -n "DELL"            # switch by partial name
swift-audio-switcher toggle "MacBook Pro Speakers" "DELL U2725QE"
swift-audio-switcher diagnose                 # raw CoreAudio state
```

AirPlay devices:

```sh
airplay-pick --list         # list the devices the Sound pane offers
airplay-pick "Wohnzimmer"   # make that AirPlay device the output device
```

`airplay-pick` needs Accessibility permission for the app that runs it, in System
Settings > Privacy & Security > Accessibility. A launcher such as Raycast needs one
entry; every script that Raycast runs then inherits it.

## Raycast

Tested with a Raycast script command. Add the script directory in Raycast: Settings >
Extensions > Script Commands.

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
PICK=/opt/homebrew/bin/airplay-pick
SPEAKERS="MacBook Pro Speakers"
STATE="${TMPDIR:-/tmp}/swift-audio-switcher.previous"

# The AirPlay device as shown by: airplay-pick --list
AIRPLAY_DEVICE="Wohnzimmer"

current=$("$AUDIO" current 2>/dev/null)

if [ "$current" = "AirPlay" ]; then
  restore="$SPEAKERS"
  if [ -r "$STATE" ]; then restore=$(cat "$STATE"); fi
  "$AUDIO" set "$restore" >/dev/null && echo "Output: $restore"
  exit 0
fi

printf '%s' "$current" > "$STATE"
exec "$PICK" "$AIRPLAY_DEVICE"
```

`airplay-pick` opens the Sound pane and waits for the device to appear, so the AirPlay
direction takes a few seconds. The direction back to the speakers is immediate.

## How it works

`swift-audio-switcher` uses the CoreAudio HAL API (`AudioObjectGetPropertyData` and
`AudioObjectSetPropertyData`) to enumerate output devices and set
`kAudioHardwarePropertyDefaultOutputDevice`.

`airplay-pick` reads and drives the System Settings Sound pane through the macOS
accessibility API, then reads the default output device from CoreAudio again to confirm
the switch.

## License

MIT
