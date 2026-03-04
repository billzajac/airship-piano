import SwiftUI

@main
struct PianoApp: App {
    @StateObject private var soundFontManager = SoundFontManager()
    @StateObject private var midiManager = MIDIManager()
    private let audioEngine = AudioEngine()

    var body: some Scene {
        WindowGroup {
            Group {
                switch soundFontManager.state {
                case .checking:
                    ProgressView("Checking sound font...")
                        .onAppear { soundFontManager.ensureSoundFont() }

                case .downloading(let progress):
                    VStack(spacing: 12) {
                        Text("Downloading Piano Sounds")
                            .font(.headline)
                        ProgressView(value: progress)
                            .frame(width: 200)
                        Text("\(Int(progress * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(40)

                case .ready(let url):
                    ContentView(midiManager: midiManager, audioEngine: audioEngine)
                        .onAppear { audioEngine.loadSoundFont(url: url) }

                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Failed to load sound font")
                            .font(.headline)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        HStack {
                            Button("Retry") { soundFontManager.retry() }
                            Button("Use Default Sound") {
                                audioEngine.loadGMFallback()
                                soundFontManager.state = .ready(SoundFontManager.soundFontURL)
                            }
                        }
                    }
                    .padding(40)
                }
            }
        }
        .defaultSize(width: 360, height: 240)
    }
}

struct ContentView: View {
    @ObservedObject var midiManager: MIDIManager
    let audioEngine: AudioEngine
    @State private var volume: Float = 0.8

    var body: some View {
        VStack(spacing: 16) {
            Text("Piano")
                .font(.largeTitle.bold())

            if midiManager.connectedDevices.isEmpty {
                Label("No MIDI device connected", systemImage: "pianokeys")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(midiManager.connectedDevices, id: \.self) { device in
                    Label(device, systemImage: "pianokeys")
                        .foregroundStyle(.green)
                }
            }

            Divider()

            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $volume, in: 0...1) { _ in
                    audioEngine.volume = volume
                }
                Image(systemName: "speaker.wave.3.fill")
            }
            .padding(.horizontal)
        }
        .padding(24)
        .onAppear {
            audioEngine.volume = volume
            midiManager.start(audioEngine: audioEngine)
        }
    }
}
