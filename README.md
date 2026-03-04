# Airship Piano

Sometimes you just want to play the piano.

GarageBand is great, but when you sit down at your MIDI keyboard and just want to *play*, you don't want to open a DAW, pick a project, configure a track, and find the right instrument. You want to press keys and hear a piano.

That's what this is. A tiny macOS app that connects to your MIDI keyboard and plays piano. Nothing else.

## The Sound

This app uses the [Salamander Grand Piano](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html), a free sample library recorded from a Yamaha C5 grand piano by Alexander Holm. It's distributed as an SF2 sound font — a format that maps real recorded samples across the keyboard so each note sounds like an actual piano, not a synthesizer.

The SF2 file (~24MB) isn't bundled with the app. On first launch, it downloads automatically from the [Salamander project's distribution](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html) and caches in `~/Library/Application Support/AirshipPiano/`. After that, it loads instantly.

If the download fails, the app falls back to the General MIDI piano built into macOS — functional but not nearly as nice.

## Install

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag **Airship Piano** to **Applications**
3. Double-click to launch — macOS will block it because it's not notarized
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
5. Click **Open** in the confirmation dialog

After that first launch, macOS remembers your choice and the app opens normally.

### Build from source

```
git clone https://github.com/billzajac/airship-piano.git
cd airship-piano
./run.sh
```

## Requirements

- macOS 13+
- A MIDI keyboard (USB or Bluetooth)

## Building from source

Requires Swift 5.9+ (comes with Xcode 15+).

```
./build.sh          # creates AirshipPiano.app in build/
./run.sh            # build and run directly
```

## Features

- Plug in and play — auto-detects MIDI devices, including hot-plug
- Sustain pedal support
- Volume control
- That's it

## License

MIT
