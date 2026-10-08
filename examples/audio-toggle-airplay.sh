#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Audio: Toggle AirPlay
# @raycast.description Switch the default audio output between the built-in speakers and an AirPlay device
# @raycast.mode compact
# @raycast.icon 🔊
# @raycast.packageName Audio

# Grant Accessibility permission to Raycast once, in System Settings > Privacy &
# Security > Accessibility. airplay-pick needs it, because macOS offers a
# not-yet-active AirPlay device only in the System Settings Sound pane.

set -uo pipefail

AUDIO=/opt/homebrew/bin/swift-audio-switcher
PICK=/opt/homebrew/bin/airplay-pick
SPEAKERS="MacBook Pro Speakers"
STATE="${TMPDIR:-/tmp}/swift-audio-switcher.previous"

# The AirPlay device as shown by: airplay-pick --list
AIRPLAY_DEVICE="Büro"

current=$("$AUDIO" current 2>/dev/null)

if [ "$current" = "AirPlay" ]; then
  restore="$SPEAKERS"
  if [ -r "$STATE" ]; then restore=$(cat "$STATE"); fi
  "$AUDIO" set "$restore" >/dev/null && echo "Output: $restore"
  exit 0
fi

printf '%s' "$current" > "$STATE"
exec "$PICK" "$AIRPLAY_DEVICE"
