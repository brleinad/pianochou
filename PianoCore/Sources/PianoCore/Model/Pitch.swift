import Foundation

public enum Step: String, CaseIterable, Sendable {
    case C, D, E, F, G, A, B

    /// Semitones above C.
    public var semitone: Int {
        switch self {
        case .C: 0
        case .D: 2
        case .E: 4
        case .F: 5
        case .G: 7
        case .A: 9
        case .B: 11
        }
    }
}

/// A spelled pitch. Spelling matters for drawing (F# vs Gb); `midi` is what the microphone hears.
public struct Pitch: Hashable, Sendable {
    public var step: Step
    /// Semitones: -1 flat, +1 sharp, ±2 double.
    public var alter: Int
    /// Scientific octave: middle C is C4.
    public var octave: Int

    public init(step: Step, alter: Int = 0, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }

    public var midi: Int { (octave + 1) * 12 + step.semitone + alter }

    public var name: String {
        let accidental = alter > 0 ? String(repeating: "#", count: alter) : String(repeating: "b", count: -alter)
        return "\(step.rawValue)\(accidental)\(octave)"
    }
}

extension Pitch {
    /// Equal-tempered frequency of a MIDI note.
    public static func frequency(midi: Int, a4: Double = Tuning.referencePitchHz) -> Double {
        a4 * pow(2, Double(midi - 69) / 12)
    }

    /// A display name for a MIDI note, spelled with sharps.
    public static func name(midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[((midi % 12) + 12) % 12] + "\(midi / 12 - 1)"
    }
}
