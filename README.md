# swift-audio-switcher

Set the macOS audio output device from the command line. The package also sets AirPlay
devices on the network. The code is Swift, with no third-party dependencies.

## What this solves

macOS cannot set the audio output to AirPlay from a script.

CoreAudio shows the AirPlay device only during a session. macOS removes the device when
the output changes back. No API, no CLI command, and no Shortcuts action starts that
session. macOS shows an inactive AirPlay device only in the System Settings Sound pane.

For this reason, the command below stops with an error when no AirPlay session is active:

```
$ swift-audio-switcher set "AirPlay"
No output device matches "AirPlay".
```

This package solves that problem with two commands.

`swift-audio-switcher` shows the output devices and sets the default device. It uses
CoreAudio. No permissions are necessary.

`airplay-pick` sets an AirPlay device in the System Settings Sound pane. Then it reads
the default output device from CoreAudio to make sure that the change occurred. It needs
Accessibility permission.

Use the two commands together for a full AirPlay toggle. `airplay-pick` sets the output
to AirPlay, and `swift-audio-switcher` sets the speakers again.

## Install

The Xcode Command Line Tools must be current. If they are not, do this command:

```sh
xcode-select --install
```

Then install the package:

```sh
brew tap darox/swift-audio-switcher https://github.com/darox/swift-audio-switcher.git
brew trust darox/swift-audio-switcher   # once, for third-party taps (Homebrew 4.6+)
brew install swift-audio-switcher
```

## Usage

CoreAudio devices:

```sh
swift-audio-switcher list                     # show output devices, current one marked
swift-audio-switcher current                  # print the current output device
swift-audio-switcher set "DELL U2725QE"       # set by exact name or UID
swift-audio-switcher set -n "DELL"            # set by partial name
swift-audio-switcher toggle "MacBook Pro Speakers" "DELL U2725QE"
swift-audio-switcher diagnose                 # raw CoreAudio state
```

AirPlay devices:

```sh
airplay-pick --list         # show the devices that the Sound pane offers
airplay-pick "Wohnzimmer"   # set that AirPlay device as the output device
```

`airplay-pick` needs Accessibility permission. Give the permission to the app that runs
the command. Open System Settings > Privacy & Security > Accessibility. A launcher such
as Raycast needs one entry. All scripts that Raycast starts then inherit the permission.

## Raycast

A Raycast script command is tested. Add the script directory in Raycast. Open Settings >
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

Set `AIRPLAY_DEVICE` to a name from `airplay-pick --list`. The AirPlay direction is
complete in approximately 2 to 6 seconds, because `airplay-pick` opens the Sound pane and
waits for the device. The direction back to the speakers is complete in less than one
second.

## How it works

`swift-audio-switcher` uses the CoreAudio HAL API to show the output devices and to set
`kAudioHardwarePropertyDefaultOutputDevice`.

`airplay-pick` reads and operates the System Settings Sound pane through the macOS
accessibility API. Then it reads the default output device from CoreAudio again to
confirm the switch.

## License

MIT
