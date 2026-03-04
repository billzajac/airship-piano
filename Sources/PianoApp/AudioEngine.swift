import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        sampler.overallGain = 12.0

        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // Disable GM reverb and chorus sends
        sampler.sendController(91, withValue: 0, onChannel: 0)
        sampler.sendController(93, withValue: 0, onChannel: 0)
    }

    func loadSoundFont(url: URL) {
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            print("Loaded sound font: \(url.lastPathComponent)")
        } catch {
            print("Failed to load SF2 \(url.path): \(error)")
            loadGMFallback()
        }
    }

    func loadGMFallback() {
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
                    print("Loaded fallback GM sound bank: \(path)")
                    return
                } catch {
                    print("Failed to load \(path): \(error)")
                }
            }
        }
        print("Warning: No sound bank found, using default sampler")
    }

    func noteOn(note: UInt8, velocity: UInt8) {
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    func noteOff(note: UInt8) {
        sampler.stopNote(note, onChannel: 0)
    }

    func sustainPedal(value: UInt8) {
        sampler.sendController(64, withValue: value, onChannel: 0)
    }

    func controlChange(controller: UInt8, value: UInt8) {
        sampler.sendController(controller, withValue: value, onChannel: 0)
    }
}
