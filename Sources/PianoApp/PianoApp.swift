import SwiftUI

#if !SWIFT_PACKAGE
private extension Bundle {
    static let module = Bundle.main
}
#endif

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct PianoApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var soundFontManager = SoundFontManager()
    @StateObject private var midiManager = MIDIManager()
    @State private var audioEngine = AudioEngine()

    var body: some Scene {
        WindowGroup {
            MainView(soundFontManager: soundFontManager, midiManager: midiManager, audioEngine: audioEngine)
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 500)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Airship Piano") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Airship Piano",
                        .applicationVersion: "1.0.0",
                        .credits: {
                            let text = NSMutableAttributedString(
                                string: "A lightweight, open-source MIDI program that lets you just play your MIDI keyboard.\n\n",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.textColor
                                ]
                            )
                            let linkString = "github.com/billzajac/airship-piano"
                            text.append(NSAttributedString(
                                string: linkString,
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .link: URL(string: "https://github.com/billzajac/airship-piano")!
                                ]
                            ))
                            return text
                        }()
                    ])
                }
            }
        }
        #endif
    }
}

struct MainView: View {
    @ObservedObject var soundFontManager: SoundFontManager
    @ObservedObject var midiManager: MIDIManager
    let audioEngine: AudioEngine

    var body: some View {
        Group {
            switch soundFontManager.state {
            case .checking:
                ProgressView("Checking sound font...")

            case .downloading(let progress):
                VStack(spacing: 12) {
                    Text("Downloading Yamaha C5 Grand Piano")
                        .font(.headline)
                    Text("Salamander sound font (~24 MB, one-time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
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
                        .accessibilityHidden(true)
                    Text("Failed to load sound font")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    HStack(spacing: 12) {
                        Button("Retry") { soundFontManager.retry() }
                            .buttonStyle(.borderedProminent)
                        #if os(macOS)
                        Button("Use Default (Lower Quality)") {
                            audioEngine.loadGMFallback()
                            soundFontManager.useDefaultSound()
                        }
                        #endif
                    }
                }
                .padding(40)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var midiManager: MIDIManager
    let audioEngine: AudioEngine
    @State private var volume: Float = 0.8
    @State private var logoAppeared = false
    #if os(iOS)
    @State private var showingBluetoothPicker = false
    #endif

    private var allNotes: Set<UInt8> { midiManager.allActiveNotes }

    private var combinedNoteInfo: (label: String, detail: String) {
        NoteDisplay.describe(notes: allNotes)
    }

    private var isPlaying: Bool { !allNotes.isEmpty }
    private var multipleDevices: Bool { midiManager.deviceGroups.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            Image("AppLogo", bundle: Bundle.module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .scaleEffect(logoAppeared ? 1.0 : 0.9)
                .opacity(logoAppeared ? 1.0 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: logoAppeared)
                .padding(.top, 20)

            // Note display — combined view
            VStack(spacing: 4) {
                if isPlaying {
                    Text(combinedNoteInfo.label)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .shadow(color: .blue.opacity(0.3), radius: 12)
                        .transition(.scale.combined(with: .opacity))

                    Text(combinedNoteInfo.detail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)

                    if allNotes.count > 1 {
                        Text("\(allNotes.count) keys")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(.linearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                            .padding(.top, 2)
                    }
                } else {
                    Text("Play a note...")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.quaternary)
                }
            }
            .animation(.easeOut(duration: 0.12), value: combinedNoteInfo.label)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom section
            VStack(spacing: 10) {
                // Volume
                HStack(spacing: 6) {
                    Image(systemName: volume > 0 ? "speaker.fill" : "speaker.slash.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    Slider(value: $volume, in: 0...1) { _ in
                        audioEngine.volume = volume
                    }
                    .accessibilityLabel("Volume")
                    .controlSize(.mini)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                }
                .padding(.horizontal, 32)

                Divider().padding(.horizontal, 32)

                // Per-device sections
                if midiManager.deviceGroups.isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text("No MIDI device")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(midiManager.deviceGroups) { group in
                        DeviceRow(group: group, showNotes: multipleDevices, midiManager: midiManager)
                    }
                }

                #if os(iOS)
                Button {
                    showingBluetoothPicker = true
                } label: {
                    Label("Bluetooth MIDI", systemImage: "wave.3.right")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .sheet(isPresented: $showingBluetoothPicker) {
                    BluetoothMIDIView()
                }
                #endif
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            audioEngine.volume = volume
            midiManager.start(audioEngine: audioEngine)
            logoAppeared = true
        }
    }
}

struct DeviceRow: View {
    let group: MIDIDeviceGroup
    let showNotes: Bool
    @ObservedObject var midiManager: MIDIManager

    private var noteInfo: (label: String, detail: String) {
        NoteDisplay.describe(notes: group.activeNotes, transpose: group.transpose)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Device name + endpoints
                if !group.deviceName.isEmpty {
                    Text(group.deviceName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                ForEach(group.endpoints) { endpoint in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                            .shadow(color: .green.opacity(0.5), radius: 3)
                        Text(endpoint.displayName)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Transpose controls
                HStack(spacing: 2) {
                    Button {
                        midiManager.setTranspose(for: group.deviceName, offset: group.transpose - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)

                    Text(group.transpose == 0 ? "0" : (group.transpose > 0 ? "+\(group.transpose)" : "\(group.transpose)"))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(group.transpose == 0 ? .tertiary : .primary)
                        .frame(width: 24)

                    Button {
                        midiManager.setTranspose(for: group.deviceName, offset: group.transpose + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Per-device note display (only when multiple devices)
            if showNotes && !group.activeNotes.isEmpty {
                Text(noteInfo.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 24)
    }
}
