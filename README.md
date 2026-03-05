# Airship Piano

Sometimes you just want to play the piano.

GarageBand is great, but when you sit down at your MIDI keyboard and just want to *play*, you don't want to open a DAW, pick a project, configure a track, and find the right instrument. You want to press keys and hear a piano.

That's what this is. A tiny app that connects to your MIDI keyboard and plays piano. Nothing else. Available on iPhone, iPad, Mac, and Android.

## Get the App

### App Stores

| Platform | Link |
|----------|------|
| iOS / iPadOS | [![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/airship-piano/id6744194091) *Coming Soon* |
| Mac App Store | [![Download on the Mac App Store](https://developer.apple.com/assets/elements/badges/download-on-the-mac-app-store.svg)](https://apps.apple.com/app/airship-piano/id6744194091) *Coming Soon* |
| Android | [![Get it on Google Play](https://upload.wikimedia.org/wikipedia/commons/7/78/Google_Play_Store_badge_EN.svg)](https://play.google.com/store/apps/details?id=com.windupairships.airshippiano) *Coming Soon* |

### Direct Download (macOS)

If you'd rather not use the Mac App Store, you can download the app directly:

1. Download the latest `.dmg` from [Releases](../../releases) *Coming Soon*
2. Open the DMG and drag **Airship Piano** to **Applications**
3. Double-click to launch — macOS will block it because it's not signed through the App Store
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
5. Click **Open** in the confirmation dialog

After that first launch, macOS remembers your choice and the app opens normally.

### Build from Source

This project is open source — anyone can clone the repo and build it themselves.

```
git clone https://github.com/billzajac/airship-piano.git
cd airship-piano
./run.sh
```

See [Building from source](#building-from-source) below for details.

## The Sound

This app uses the [Salamander Grand Piano](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html), a free sample library recorded from a Yamaha C5 grand piano by Alexander Holm. It's distributed as an SF2 sound font — a format that maps real recorded samples across the keyboard so each note sounds like an actual piano, not a synthesizer.

The SF2 file (~24MB) isn't bundled with the app. On first launch, it downloads automatically from the [Salamander project's distribution](https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html) and caches locally. After that, it loads instantly.

If the download fails, the app falls back to the built-in General MIDI piano — functional but not nearly as nice.

## Requirements

- macOS 13+ / iOS 16+ / Android 8+
- A MIDI keyboard (USB or Bluetooth)

## Building from source

**Apple (macOS / iOS):** Requires Swift 5.9+ (comes with Xcode 15+).

```
./build.sh          # creates AirshipPiano.app in build/
./run.sh            # build and run directly
```

**Android:** Requires Android Studio and NDK.

```
cd android
./gradlew assembleRelease
```

## Features

- Plug in and play — auto-detects MIDI devices, including hot-plug
- Sustain pedal support
- Volume control
- That's it

## License

MIT
