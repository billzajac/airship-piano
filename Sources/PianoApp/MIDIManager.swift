import CoreMIDI
import Foundation

final class MIDIManager: ObservableObject {
    @Published var connectedDevices: [String] = []

    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: Set<MIDIEndpointRef> = []
    private var audioEngine: AudioEngine?
    private var started = false

    func start(audioEngine: AudioEngine) {
        guard !started else { return }
        started = true
        self.audioEngine = audioEngine

        var status = MIDIClientCreateWithBlock("AirshipPiano" as CFString, &midiClient) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        guard status == noErr else {
            print("Failed to create MIDI client: \(status)")
            return
        }

        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEventList(eventList)
        }
        guard status == noErr else {
            print("Failed to create MIDI input port: \(status)")
            return
        }

        connectAllSources()
    }

    private func connectAllSources() {
        // Disconnect existing sources to prevent duplicate events
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()

        let sourceCount = MIDIGetNumberOfSources()
        var names: [String] = []

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                connectedSources.insert(source)
                if let name = getMIDIObjectName(source) {
                    names.append(name)
                    print("Connected to MIDI source: \(name)")
                }
            } else {
                print("Failed to connect MIDI source \(i): \(status)")
            }
        }

        DispatchQueue.main.async {
            self.connectedDevices = names
        }
    }

    private func getMIDIObjectName(_ object: MIDIObjectRef) -> String? {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyName, &name)
        if status == noErr, let cfName = name?.takeRetainedValue() {
            return cfName as String
        }
        return nil
    }

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        if notification.pointee.messageID == .msgSetupChanged {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.connectAllSources()
            }
        }
    }

    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>) {
        let list = eventList.pointee
        var packet = list.packet

        for _ in 0..<list.numPackets {
            let wordCount = Int(packet.wordCount)
            if wordCount > 0 {
                let word = packet.words.0
                parseMIDI1Word(word)
            }
            let next = withUnsafePointer(to: packet) { MIDIEventPacketNext($0).pointee }
            packet = next
        }
    }

    private func parseMIDI1Word(_ word: UInt32) {
        // MIDI 1.0 Channel Voice Message in UMP format:
        // Word: [message type (4)] [group (4)] [status (8)] [data1 (8)] [data2 (8)]
        let messageType = (word >> 28) & 0x0F
        let status = UInt8((word >> 16) & 0xF0)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        // Message type 0x2 = MIDI 1.0 Channel Voice
        guard messageType == 0x2 else { return }

        switch status {
        case 0x90: // Note On
            if data2 > 0 {
                audioEngine?.noteOn(note: data1, velocity: data2)
            } else {
                audioEngine?.noteOff(note: data1)
            }
        case 0x80: // Note Off
            audioEngine?.noteOff(note: data1)
        case 0xB0: // Control Change
            if data1 == 64 {
                audioEngine?.sustainPedal(value: data2)
            } else {
                audioEngine?.controlChange(controller: data1, value: data2)
            }
        default:
            break
        }
    }
}
