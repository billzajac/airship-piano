import CoreMIDI
import Foundation

struct MIDIDeviceInfo: Identifiable, Equatable {
    let id: Int  // endpoint unique ID
    let endpointName: String
    let deviceName: String
    let manufacturer: String

    /// Display name: use device name if available, otherwise endpoint name
    var displayName: String {
        var name = endpointName
        // Strip device name prefix (e.g. "Nektar SE61 MIDI 1" → "MIDI 1")
        if !deviceName.isEmpty && name.hasPrefix(deviceName) {
            let suffix = name.dropFirst(deviceName.count).trimmingCharacters(in: .whitespaces)
            if !suffix.isEmpty {
                name = suffix
            }
        }
        // Add space between "MIDI" and number if missing (e.g. "MIDI1" → "MIDI 1")
        if let range = name.range(of: #"MIDI(\d)"#, options: .regularExpression) {
            name.insert(" ", at: name.index(range.lowerBound, offsetBy: 4))
        }
        return name
    }
}

/// Groups endpoints by physical device, with per-device note tracking and transpose
struct MIDIDeviceGroup: Identifiable {
    let id: String  // device name as ID
    let deviceName: String
    let manufacturer: String
    let endpoints: [MIDIDeviceInfo]
    var activeNotes: Set<UInt8>
    var transpose: Int  // semitones offset applied to audio + display
}

final class MIDIManager: ObservableObject {
    @Published var deviceGroups: [MIDIDeviceGroup] = []

    /// Convenience: all active notes across all devices (with transpose applied)
    var allActiveNotes: Set<UInt8> {
        var notes = Set<UInt8>()
        for group in deviceGroups {
            for note in group.activeNotes {
                let transposed = Int(note) + group.transpose
                if transposed >= 0 && transposed <= 127 {
                    notes.insert(UInt8(transposed))
                }
            }
        }
        return notes
    }

    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    // Track by stable unique ID → endpoint ref
    private var connectedByUID: [Int32: MIDIEndpointRef] = [:]
    // Heap-allocated UIDs passed as connRefCon to identify source in callbacks
    private var uidPointers: [Int32: UnsafeMutablePointer<Int32>] = [:]
    // UID → device name mapping for note routing
    private var uidToDeviceName: [Int32: String] = [:]
    // Per-device transpose (persists across reconnects)
    private var transposeByDevice: [String: Int] = [:]
    private var audioEngine: AudioEngine?
    private var started = false
    private var pendingReconnect: DispatchWorkItem?

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
        ) { [weak self] eventList, srcConnRefCon in
            self?.handleMIDIEventList(eventList, sourceUID: srcConnRefCon)
        }
        guard status == noErr else {
            print("Failed to create MIDI input port: \(status)")
            return
        }

        syncSources()
    }

    func setTranspose(for deviceName: String, offset: Int) {
        transposeByDevice[deviceName] = offset
        // Update the published group
        if let idx = deviceGroups.firstIndex(where: { $0.deviceName == deviceName }) {
            deviceGroups[idx].transpose = offset
        }
    }

    private func syncSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var currentUIDs: [Int32: MIDIEndpointRef] = [:]
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid)
            if uid != 0 {
                currentUIDs[uid] = source
            }
        }

        // Disconnect sources that are gone
        let removedUIDs = Set(connectedByUID.keys).subtracting(currentUIDs.keys)
        for uid in removedUIDs {
            if let oldRef = connectedByUID[uid] {
                MIDIPortDisconnectSource(inputPort, oldRef)
                print("Disconnected MIDI source (UID \(uid))")
            }
            connectedByUID.removeValue(forKey: uid)
            if let ptr = uidPointers.removeValue(forKey: uid) {
                ptr.deallocate()
            }
            uidToDeviceName.removeValue(forKey: uid)
        }

        // Connect sources that are new
        let addedUIDs = Set(currentUIDs.keys).subtracting(connectedByUID.keys)
        for uid in addedUIDs {
            guard let source = currentUIDs[uid] else { continue }
            // Allocate a stable pointer for this UID to pass as connRefCon
            let ptr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            ptr.pointee = uid
            let status = MIDIPortConnectSource(inputPort, source, UnsafeMutableRawPointer(ptr))
            if status == noErr {
                connectedByUID[uid] = source
                uidPointers[uid] = ptr
                let info = getDeviceInfo(for: source)
                uidToDeviceName[uid] = info.deviceName
                print("Connected to MIDI source: \(info.endpointName) (device: \(info.deviceName), mfr: \(info.manufacturer))")
            } else {
                ptr.deallocate()
                print("Failed to connect MIDI source (UID \(uid)): \(status)")
            }
        }

        // Update endpoint refs for existing sources (refs may change)
        for (uid, newRef) in currentUIDs where connectedByUID[uid] != nil && !addedUIDs.contains(uid) {
            connectedByUID[uid] = newRef
        }

        // Rebuild device groups
        var allDevices: [MIDIDeviceInfo] = []
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid)
            if connectedByUID[uid] != nil {
                allDevices.append(getDeviceInfo(for: source))
            }
        }

        let grouped = Dictionary(grouping: allDevices) { $0.deviceName }

        DispatchQueue.main.async {
            // Preserve existing active notes and transpose when rebuilding groups
            var newGroups: [MIDIDeviceGroup] = []
            for deviceName in grouped.keys.sorted() {
                guard let endpoints = grouped[deviceName] else { continue }
                let existing = self.deviceGroups.first(where: { $0.deviceName == deviceName })
                newGroups.append(MIDIDeviceGroup(
                    id: deviceName.isEmpty ? "unknown-\(endpoints.first?.id ?? 0)" : deviceName,
                    deviceName: deviceName,
                    manufacturer: endpoints.first?.manufacturer ?? "",
                    endpoints: endpoints,
                    activeNotes: existing?.activeNotes ?? [],
                    transpose: self.transposeByDevice[deviceName] ?? existing?.transpose ?? 0
                ))
            }
            self.deviceGroups = newGroups

            // Pre-create samplers for new devices so first note plays instantly
            for group in newGroups {
                let _ = self.audioEngine?.sampler(for: group.deviceName)
            }
        }
    }

    private func getStringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &value)
        if status == noErr, let cfValue = value?.takeRetainedValue() {
            return cfValue as String
        }
        return ""
    }

    private func getDeviceInfo(for endpoint: MIDIEndpointRef) -> MIDIDeviceInfo {
        let endpointName = getStringProperty(endpoint, kMIDIPropertyName)
        var uniqueID: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

        var entity = MIDIEntityRef()
        MIDIEndpointGetEntity(endpoint, &entity)

        var device = MIDIDeviceRef()
        if entity != 0 {
            MIDIEntityGetDevice(entity, &device)
        }

        let deviceName = device != 0 ? getStringProperty(device, kMIDIPropertyName) : ""
        let manufacturer = device != 0 ? getStringProperty(device, kMIDIPropertyManufacturer) : ""

        return MIDIDeviceInfo(
            id: Int(uniqueID),
            endpointName: endpointName,
            deviceName: deviceName,
            manufacturer: manufacturer
        )
    }

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        if notification.pointee.messageID == .msgSetupChanged {
            pendingReconnect?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.syncSources()
            }
            pendingReconnect = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func handleMIDIEventList(_ eventList: UnsafePointer<MIDIEventList>, sourceUID: UnsafeMutableRawPointer?) {
        // Identify which source sent this event
        let uid: Int32 = sourceUID?.assumingMemoryBound(to: Int32.self).pointee ?? 0
        let deviceName = uidToDeviceName[uid] ?? ""

        let list = eventList.pointee
        var packet = list.packet

        for _ in 0..<list.numPackets {
            let wordCount = Int(packet.wordCount)
            withUnsafePointer(to: packet.words) { wordsPtr in
                wordsPtr.withMemoryRebound(to: UInt32.self, capacity: wordCount) { words in
                    for i in 0..<wordCount {
                        parseMIDI1Word(words[i], deviceName: deviceName)
                    }
                }
            }
            let next = withUnsafePointer(to: packet) { MIDIEventPacketNext($0).pointee }
            packet = next
        }
    }

    private func parseMIDI1Word(_ word: UInt32, deviceName: String) {
        let messageType = (word >> 28) & 0x0F
        let status = UInt8((word >> 16) & 0xF0)
        let data1 = UInt8((word >> 8) & 0xFF)
        let data2 = UInt8(word & 0xFF)

        guard messageType == 0x2 else { return }

        let transpose = transposeByDevice[deviceName] ?? 0

        switch status {
        case 0x90: // Note On
            if data2 > 0 {
                let transposed = Int(data1) + transpose
                if transposed >= 0 && transposed <= 127 {
                    audioEngine?.noteOn(note: UInt8(transposed), velocity: data2, device: deviceName)
                }
                DispatchQueue.main.async {
                    if let idx = self.deviceGroups.firstIndex(where: { $0.deviceName == deviceName }) {
                        self.deviceGroups[idx].activeNotes.insert(data1)
                    }
                }
            } else {
                let transposed = Int(data1) + transpose
                if transposed >= 0 && transposed <= 127 {
                    audioEngine?.noteOff(note: UInt8(transposed), device: deviceName)
                }
                DispatchQueue.main.async {
                    if let idx = self.deviceGroups.firstIndex(where: { $0.deviceName == deviceName }) {
                        self.deviceGroups[idx].activeNotes.remove(data1)
                    }
                }
            }
        case 0x80: // Note Off
            let transposed = Int(data1) + transpose
            if transposed >= 0 && transposed <= 127 {
                audioEngine?.noteOff(note: UInt8(transposed), device: deviceName)
            }
            DispatchQueue.main.async {
                if let idx = self.deviceGroups.firstIndex(where: { $0.deviceName == deviceName }) {
                    self.deviceGroups[idx].activeNotes.remove(data1)
                }
            }
        case 0xB0: // Control Change
            switch data1 {
            case 64: audioEngine?.sustainPedal(value: data2, device: deviceName)
            case 67: audioEngine?.controlChange(controller: data1, value: data2, device: deviceName)
            case 66: audioEngine?.controlChange(controller: data1, value: data2, device: deviceName)
            default: break
            }
        default:
            break
        }
    }

    deinit {
        for (_, ptr) in uidPointers {
            ptr.deallocate()
        }
    }
}
