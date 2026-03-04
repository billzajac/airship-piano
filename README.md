# Piano

A minimal macOS app that turns your MIDI keyboard into a piano using the Salamander Grand Piano sound font.

## Requirements

- macOS 13+
- Swift 5.9+ toolchain (comes with Xcode 15+)
- A MIDI keyboard

## Run

```
git clone <repo-url>
cd piano
./run.sh
```

On first launch, the app downloads the Salamander Grand Piano SF2 (~24MB) and caches it in `~/Library/Application Support/PianoApp/`. Subsequent launches load instantly.

## Features

- Auto-detects MIDI devices (hot-plug supported)
- Sustain pedal support (CC 64)
- Volume control
- Falls back to macOS General MIDI if the sound font download fails
