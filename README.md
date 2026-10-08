# swift-audio-switcher

Set the macOS audio output from the command line, including AirPlay devices.

## Why

macOS cannot set the audio output to AirPlay from a script. CoreAudio shows the AirPlay
device only during a session, and no API or Shortcuts action starts one. macOS shows an
inactive AirPlay device only in the System Settings Sound pane.

## Install

```sh
brew tap darox/swift-audio-switcher https://github.com/darox/swift-audio-switcher.git
brew trust darox/swift-audio-switcher
brew install swift-audio-switcher
```

## Use

```sh
swift-audio-switcher list              # output devices
swift-audio-switcher set "DELL"        # set a device
swift-audio-switcher toggle "MacBook Pro Speakers" "DELL"
airplay-pick --list                    # AirPlay devices
airplay-pick "Wohnzimmer"              # set an AirPlay device
```

`airplay-pick` needs Accessibility permission for the app that runs it.

## Raycast

Add `examples/audio-toggle-airplay.sh` as a script command. It toggles between the
speakers and an AirPlay device.

## License

MIT
