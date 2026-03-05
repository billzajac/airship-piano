import Foundation

struct NoteDisplay {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    static func noteName(_ midi: UInt8) -> String {
        let note = Int(midi) % 12
        let octave = Int(midi) / 12 - 1
        return "\(noteNames[note])\(octave)"
    }

    static func pitchClass(_ midi: UInt8) -> Int {
        Int(midi) % 12
    }

    /// Given a set of active MIDI notes and an optional transpose, return a human-readable description
    static func describe(notes: Set<UInt8>, transpose: Int = 0) -> (label: String, detail: String) {
        guard !notes.isEmpty else {
            return ("", "Play a note...")
        }

        let transposed = notes.compactMap { n -> UInt8? in
            let t = Int(n) + transpose
            return (t >= 0 && t <= 127) ? UInt8(t) : nil
        }
        let sorted = transposed.sorted()
        guard !sorted.isEmpty else { return ("", "") }

        if sorted.count == 1 {
            let name = noteName(sorted[0])
            return (name, "Single note")
        }

        // Try chord detection
        if let chord = detectChord(notes: sorted) {
            let noteList = sorted.map { noteName($0) }.joined(separator: " + ")
            return (chord, noteList)
        }

        // Multiple notes, no recognized chord
        let noteList = sorted.map { noteName($0) }.joined(separator: " + ")
        return ("\(sorted.count) Notes", noteList)
    }

    /// Detect common chord types from a set of notes
    static func detectChord(notes: [UInt8]) -> String? {
        guard notes.count >= 2 else { return nil }

        // Get unique pitch classes relative to each possible root
        let pitchClasses = Set(notes.map { pitchClass($0) })
        guard pitchClasses.count >= 2 else { return nil }

        // Try each note as a potential root
        for root in pitchClasses.sorted() {
            let intervals = Set(pitchClasses.map { ($0 - root + 12) % 12 })
            let rootName = noteNames[root]

            if let name = matchIntervals(intervals, root: rootName) {
                return name
            }
        }

        // Try with flat names too for better readability of some chords
        return nil
    }

    private static func matchIntervals(_ intervals: Set<Int>, root: String) -> String? {
        // Common chord interval patterns (semitones from root)
        // Triads
        if intervals == [0, 4, 7] { return "\(root) Major" }
        if intervals == [0, 3, 7] { return "\(root) Minor" }
        if intervals == [0, 3, 6] { return "\(root) Dim" }
        if intervals == [0, 4, 8] { return "\(root) Aug" }
        if intervals == [0, 5, 7] { return "\(root)sus4" }
        if intervals == [0, 2, 7] { return "\(root)sus2" }

        // Seventh chords
        if intervals == [0, 4, 7, 11] { return "\(root)maj7" }
        if intervals == [0, 4, 7, 10] { return "\(root)7" }
        if intervals == [0, 3, 7, 10] { return "\(root)m7" }
        if intervals == [0, 3, 6, 10] { return "\(root)m7b5" }
        if intervals == [0, 3, 6, 9] { return "\(root)dim7" }
        if intervals == [0, 3, 7, 11] { return "\(root)mMaj7" }
        if intervals == [0, 4, 8, 10] { return "\(root)7#5" }

        // Extended
        if intervals == [0, 4, 7, 10, 2] || intervals == [0, 2, 4, 7, 10] { return "\(root)9" }
        if intervals == [0, 4, 7, 11, 2] || intervals == [0, 2, 4, 7, 11] { return "\(root)maj9" }
        if intervals == [0, 4, 7, 10, 14 % 12] { return "\(root)9" }

        // Power chord
        if intervals == [0, 7] { return "\(root)5" }

        // Intervals (2 notes)
        if intervals.count == 2 {
            let sorted = intervals.sorted()
            let interval = sorted[1]
            switch interval {
            case 1: return "\(root) + minor 2nd"
            case 2: return "\(root) + major 2nd"
            case 3: return "\(root) + minor 3rd"
            case 4: return "\(root) + major 3rd"
            case 5: return "\(root) + perfect 4th"
            case 6: return "\(root) + tritone"
            case 7: return "\(root) + perfect 5th"
            case 8: return "\(root) + minor 6th"
            case 9: return "\(root) + major 6th"
            case 10: return "\(root) + minor 7th"
            case 11: return "\(root) + major 7th"
            default: break
            }
        }

        return nil
    }
}
