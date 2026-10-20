/// Vertical positions on a five-line staff, in steps: 0 is the bottom line, 1 the space above it,
/// 8 the top line. Negative steps are below the staff, above 8 are above it.
public enum StaffPosition {

    /// The step a written pitch sits on under a clef.
    public static func step(of pitch: Pitch, clef: Clef) -> Int {
        diatonic(pitch.step, pitch.octave) - bottomLine(clef)
    }

    /// Diatonic index of the bottom staff line: E4 for a treble clef, G2 for a bass clef.
    static func bottomLine(_ clef: Clef) -> Int {
        // Each clef names the pitch of the line it sits on.
        let reference: Int = switch clef.sign {
        case .f: diatonic(.F, 3)
        case .c: diatonic(.C, 4)
        default: diatonic(.G, 4)
        }
        return reference - 2 * (clef.line - 1) + 7 * clef.octaveChange
    }

    static func diatonic(_ step: Step, _ octave: Int) -> Int {
        octave * 7 + Step.allCases.firstIndex(of: step)!
    }

    /// The accidentals of a key signature in drawing order, with their steps.
    public static func keySignature(fifths: Int, clef: Clef) -> [(glyph: Glyph, step: Int)] {
        // Treble-clef steps; other clefs shift them by the same amount as their bottom line.
        let sharps = [8, 5, 9, 6, 3, 7, 4]
        let flats = [4, 7, 3, 6, 2, 5, 1]
        var shift = bottomLine(.treble) - bottomLine(clef)
        // Keep the pattern on the staff: whole octaves don't move a key signature.
        while shift > 3 { shift -= 7 }
        while shift < -3 { shift += 7 }
        let steps = fifths >= 0 ? sharps.prefix(fifths) : flats.prefix(-fifths)
        let glyph: Glyph = fifths >= 0 ? .accidentalSharp : .accidentalFlat
        return steps.map { (glyph, $0 + shift) }
    }

    /// Distance from the top line, in staff spaces, of a step.
    static func y(_ step: Int) -> Double { Double(8 - step) / 2 }
}
