import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private var engineStarted = false
    // Each device gets its own sampler for true voice isolation
    private var samplers: [String: AVAudioUnitSampler] = [:]
    private var soundFontURL: URL?
    private var usingFallback = false

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    init() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        // Restart engine when audio route changes (e.g. Bluetooth speaker connects)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleRouteChange()
        }
        // Restart engine after interruptions (phone calls, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .ended else { return }
            self?.handleRouteChange()
        }
        #endif
    }

    private func ensureEngineStarted() {
        guard !engineStarted else { return }
        do {
            try engine.start()
            engineStarted = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    #if os(iOS)
    private func handleRouteChange() {
        guard engineStarted else { return }
        // Engine stops on route change; restart it
        if !engine.isRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                print("Audio engine restarted after route change")
            } catch {
                print("Failed to restart audio engine: \(error)")
            }
        }
    }
    #endif

    /// Get or create a sampler for a given device
    func sampler(for device: String) -> AVAudioUnitSampler {
        if let existing = samplers[device] { return existing }

        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        ensureEngineStarted()
        sampler.overallGain = 12.0

        // Load sound font onto this sampler
        if let url = soundFontURL {
            loadSoundFont(url: url, into: sampler)
        } else if usingFallback {
            loadGMFallback(into: sampler)
        }

        samplers[device] = sampler
        print("Created sampler for device: \(device)")
        return sampler
    }

    func loadSoundFont(url: URL) {
        soundFontURL = url
        usingFallback = false
        if samplers.isEmpty {
            // Create a default sampler so single-device use works immediately
            let _ = sampler(for: "")
        }
        for (_, s) in samplers {
            loadSoundFont(url: url, into: s)
        }
    }

    private func loadSoundFont(url: URL, into sampler: AVAudioUnitSampler) {
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
            print("Failed to load SF2 \(url.path): \(error)")
            loadGMFallback(into: sampler)
        }
        // Disable reverb/chorus
        sampler.sendController(91, withValue: 0, onChannel: 0)
        sampler.sendController(93, withValue: 0, onChannel: 0)
    }

    func loadGMFallback() {
        usingFallback = true
        soundFontURL = nil
        if samplers.isEmpty {
            let _ = sampler(for: "")
        }
        for (_, s) in samplers {
            loadGMFallback(into: s)
        }
    }

    private func loadGMFallback(into sampler: AVAudioUnitSampler) {
        #if os(macOS)
        let gmPaths = [
            "/Library/Audio/Sounds/Banks/gs_instruments.dls",
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"
        ]
        for path in gmPaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try sampler.loadSoundBankInstrument(
                        at: URL(fileURLWithPath: path),
                        program: 0,
                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                        bankLSB: UInt8(kAUSampler_DefaultBankLSB)
                    )
                    return
                } catch {
                    print("Failed to load \(path): \(error)")
                }
            }
        }
        #endif
        print("Warning: No sound bank found, using default sampler")
    }

    func noteOn(note: UInt8, velocity: UInt8, device: String = "") {
        sampler(for: device).startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func noteOff(note: UInt8, device: String = "") {
        sampler(for: device).stopNote(note, onChannel: 0)
    }

    func sustainPedal(value: UInt8, device: String = "") {
        sampler(for: device).sendController(64, withValue: value, onChannel: 0)
    }

    func controlChange(controller: UInt8, value: UInt8, device: String = "") {
        sampler(for: device).sendController(controller, withValue: value, onChannel: 0)
    }
}
