/// The SMuFL glyphs the staff renderer uses, with Bravura's metrics.
///
/// Metrics come from Bravura's metadata (`Bravura.json`), in staff spaces, y up from the glyph origin,
/// as SMuFL defines them. A font size of 4 staff spaces makes the em one staff height.
public enum Glyph: UInt32, Sendable, CaseIterable {
    case brace = 0xE000

    case gClef = 0xE050
    case gClef8vb = 0xE052
    case gClef8va = 0xE053
    case cClef = 0xE05C
    case fClef = 0xE062
    case fClef8vb = 0xE064
    case gClefChange = 0xE07A
    case cClefChange = 0xE07B
    case fClefChange = 0xE07C

    case timeSig0 = 0xE080, timeSig1, timeSig2, timeSig3, timeSig4, timeSig5, timeSig6, timeSig7, timeSig8, timeSig9
    case timeSigCommon = 0xE08A

    case noteheadDoubleWhole = 0xE0A0
    case noteheadWhole = 0xE0A2
    case noteheadHalf = 0xE0A3
    case noteheadBlack = 0xE0A4

    case augmentationDot = 0xE1E7
    case repeatDot = 0xE044

    case flag8thUp = 0xE240, flag8thDown, flag16thUp, flag16thDown, flag32ndUp, flag32ndDown, flag64thUp, flag64thDown

    case accidentalFlat = 0xE260
    case accidentalNatural = 0xE261
    case accidentalSharp = 0xE262
    case accidentalDoubleSharp = 0xE263
    case accidentalDoubleFlat = 0xE264

    case restDoubleWhole = 0xE4E2
    case restWhole = 0xE4E3
    case restHalf = 0xE4E4
    case restQuarter = 0xE4E5
    case rest8th = 0xE4E6
    case rest16th = 0xE4E7
    case rest32nd = 0xE4E8
    case rest64th = 0xE4E9

    case tuplet0 = 0xE880, tuplet1, tuplet2, tuplet3, tuplet4, tuplet5, tuplet6, tuplet7, tuplet8, tuplet9

    /// The glyph as a one-character string, for drawing with the font.
    public var string: String { String(Character(Unicode.Scalar(rawValue)!)) }

    public var width: Double { bounds.ne.x }

    /// Bounding box corners: south-west and north-east, y up.
    public var bounds: (sw: Engraving.Point, ne: Engraving.Point) {
        let b = Self.boxes[self]!
        return (Engraving.Point(x: b.0, y: b.1), Engraving.Point(x: b.2, y: b.3))
    }

    /// Where a stem meets a flag, relative to the flag's origin (SMuFL `stemUpNW` / `stemDownSW`), y up.
    var stemAnchorY: Double {
        switch self {
        case .flag8thUp: -0.04
        case .flag8thDown: 0.132
        case .flag16thUp: -0.088
        case .flag16thDown: 0.128
        case .flag32ndUp: 0.376
        case .flag32ndDown: -0.448
        case .flag64thUp: 1.172
        case .flag64thDown: -1.244
        default: 0
        }
    }

    static func timeSigDigit(_ digit: Int) -> Glyph { Glyph(rawValue: Glyph.timeSig0.rawValue + UInt32(digit))! }
    static func tupletDigit(_ digit: Int) -> Glyph { Glyph(rawValue: Glyph.tuplet0.rawValue + UInt32(digit))! }

    /// sw.x, sw.y, ne.x, ne.y
    private static let boxes: [Glyph: (Double, Double, Double, Double)] = [
        .brace: (0, -0.003, 0.277, 4.002),
        .gClef: (0, -2.632, 2.684, 4.392),
        .gClef8vb: (0, -3.512, 2.684, 4.392),
        .gClef8va: (0, -2.632, 2.684, 5.28),
        .cClef: (0, -2.024, 2.796, 2.024),
        .fClef: (-0.02, -2.54, 2.736, 1.048),
        .fClef8vb: (-0.02, -2.976, 2.736, 1.048),
        .gClefChange: (0, -1.82, 1.76, 2.828),
        .cClefChange: (0, -1.328, 2.024, 1.328),
        .fClefChange: (-0.06, -1.656, 1.852, 0.68),
        .timeSig0: (0.08, -1, 1.8, 1.004),
        .timeSig1: (0.08, -1, 1.256, 1.004),
        .timeSig2: (0.08, -1.028, 1.704, 1.016),
        .timeSig3: (0.08, -1.004, 1.604, 0.996),
        .timeSig4: (0.08, -1, 1.8, 1.004),
        .timeSig5: (0.08, -1.004, 1.532, 0.984),
        .timeSig6: (0.08, -0.996, 1.656, 1.004),
        .timeSig7: (0.08, -1, 1.684, 0.996),
        .timeSig8: (0.08, -1.036, 1.664, 1.036),
        .timeSig9: (0.08, -0.996, 1.656, 1.004),
        .timeSigCommon: (0.02, -0.996, 1.696, 1.004),
        .noteheadDoubleWhole: (0, -0.62, 2.396, 0.62),
        .noteheadWhole: (0, -0.5, 1.688, 0.5),
        .noteheadHalf: (0, -0.5, 1.18, 0.5),
        .noteheadBlack: (0, -0.5, 1.18, 0.5),
        .augmentationDot: (0, -0.2, 0.4, 0.2),
        .repeatDot: (0, -0.2, 0.4, 0.2),
        .flag8thUp: (0, -3.24, 1.056, 0.036),
        .flag8thDown: (0, -0.056, 1.224, 3.232),
        .flag16thUp: (0, -3.252, 1.116, 0.008),
        .flag16thDown: (0, -0.036, 1.164, 3.248),
        .flag32ndUp: (0, -3.248, 1.044, 0.596),
        .flag32ndDown: (0, -0.688, 1.092, 3.248),
        .flag64thUp: (0, -3.248, 1.044, 1.388),
        .flag64thDown: (0, -1.504, 1.092, 3.248),
        .accidentalFlat: (0, -0.7, 0.904, 1.756),
        .accidentalNatural: (0, -1.34, 0.672, 1.364),
        .accidentalSharp: (0, -1.392, 0.996, 1.4),
        .accidentalDoubleSharp: (0, -0.5, 0.988, 0.508),
        .accidentalDoubleFlat: (0, -0.7, 1.644, 1.748),
        .restDoubleWhole: (0, 0, 0.5, 1),
        .restWhole: (0, -0.54, 1.128, 0.036),
        .restHalf: (0, -0.008, 1.128, 0.568),
        .restQuarter: (0.004, -1.5, 1.08, 1.492),
        .rest8th: (0, -1.004, 0.988, 0.696),
        .rest16th: (0, -2, 1.28, 0.716),
        .rest32nd: (0, -2, 1.452, 1.704),
        .rest64th: (0, -3.012, 1.692, 1.72),
        .tuplet0: (0, -0.032, 1.272, 1.5),
        .tuplet1: (0.04, 0, 1.024, 1.488),
        .tuplet2: (0.04, -0.024, 1.316, 1.5),
        .tuplet3: (0.04, -0.032, 1.224, 1.5),
        .tuplet4: (0.04, 0, 1.252, 1.488),
        .tuplet5: (0.04, -0.032, 1.308, 1.492),
        .tuplet6: (0.04, -0.032, 1.256, 1.5),
        .tuplet7: (0.12, -0.016, 1.332, 1.488),
        .tuplet8: (0.04, -0.032, 1.292, 1.5),
        .tuplet9: (0.04, -0.032, 1.256, 1.5),
    ]
}
