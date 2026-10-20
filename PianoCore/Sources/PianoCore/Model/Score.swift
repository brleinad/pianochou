/// A score as imported. All times are in quarter notes.
public struct Score: Equatable, Sendable {
    public var title: String?
    public var composer: String?
    public var parts: [Part]
    /// Measure indices in the order they are played, with repeats and endings unfolded.
    /// Taken from the first part; parts share barlines.
    public var playedOrder: [Int]

    public init(title: String? = nil, composer: String? = nil, parts: [Part], playedOrder: [Int]? = nil) {
        self.title = title
        self.composer = composer
        self.parts = parts
        self.playedOrder = playedOrder ?? PlayedOrder.unfold(parts.first?.measures ?? [])
    }
}

public struct Part: Equatable, Sendable {
    public var id: String
    public var name: String?
    /// 2 for a piano grand staff: staff 1 is usually the right hand, staff 2 the left.
    public var staves: Int
    /// In written order.
    public var measures: [Measure]
}

public struct Measure: Equatable, Sendable {
    /// Position in `Part.measures`.
    public var index: Int
    /// The printed number, as written ("0" for a pickup, can be "12a").
    public var number: String
    public var isPickup: Bool

    /// In effect at the start of the measure (carried forward from earlier measures).
    public var key: KeySignature
    public var time: TimeSignature
    /// Clef per staff number, in effect at the start of the measure.
    public var clefs: [Int: Clef]
    public var clefChanges: [ClefChange]

    /// Offset from the start of the score, in written order.
    public var start: Rational
    /// Actual length of the content (shorter than the time signature for a pickup).
    public var duration: Rational
    /// Sorted by onset, then staff, then voice. Grace notes come before the note they lead into.
    public var events: [Event]
    public var directions: [Direction]

    // Barlines
    public var startRepeat: Bool
    /// Set on a measure ending with a backward repeat: how many times the section is played in total.
    public var endRepeatTimes: Int?
    /// The volta numbers ("1.", "2.") when this measure is inside an ending bracket.
    public var endingNumbers: [Int]?
}

/// One rhythmic slot in one voice: a rest (no notes), a single note, or a chord.
public struct Event: Equatable, Sendable {
    /// From the start of the measure.
    public var onset: Rational
    /// Sounding length. Zero for grace notes.
    public var duration: Rational
    /// Written note value; nil for a whole-measure rest written without a type.
    public var type: NoteType?
    public var dots: Int
    public var tuplet: Tuplet?
    public var staff: Int
    public var voice: Int
    public var isGrace: Bool
    public var isMeasureRest: Bool
    public var notes: [Note]
    public var beams: [Beam]
    public var stem: Stem?
    /// The dynamic marking in effect ("p", "mf", …), carried forward across measures.
    public var dynamic: String?
    /// Whether the sustain pedal is down when this event starts.
    public var pedalDown: Bool

    public var isRest: Bool { notes.isEmpty }
    public var isChord: Bool { notes.count > 1 }
}

public struct Note: Equatable, Sendable {
    public var pitch: Pitch
    public var tie: Tie
    public var fingering: Int?
    /// Written accidental to display ("sharp", "flat", "natural", …), if the score prints one.
    public var accidental: String?
}

public struct Tie: Equatable, Sendable {
    public var start: Bool
    public var stop: Bool

    public init(start: Bool = false, stop: Bool = false) {
        self.start = start
        self.stop = stop
    }
}

public struct Tuplet: Equatable, Sendable {
    /// `actual` notes in the time of `normal`: 3 in the time of 2 for a triplet.
    public var actual: Int
    public var normal: Int
    public var bracketStart: Bool
    public var bracketStop: Bool
}

public enum NoteType: String, Sendable {
    case breve, whole, half, quarter, eighth
    case sixteenth = "16th"
    case thirtySecond = "32nd"
    case sixtyFourth = "64th"
    case oneHundredTwentyEighth = "128th"
}

public struct Beam: Equatable, Sendable {
    public enum Value: String, Sendable {
        case begin, `continue`, end
        case forwardHook = "forward hook"
        case backwardHook = "backward hook"
    }

    /// 1 for eighth beams, 2 for sixteenths, …
    public var level: Int
    public var value: Value
}

public enum Stem: String, Sendable {
    case up, down, none, double
}

public struct KeySignature: Equatable, Sendable {
    /// Sharps (positive) or flats (negative).
    public var fifths: Int
    public var mode: String?

    public init(fifths: Int, mode: String? = nil) {
        self.fifths = fifths
        self.mode = mode
    }
}

public struct TimeSignature: Equatable, Sendable {
    public var beats: Int
    public var beatType: Int

    public init(beats: Int, beatType: Int) {
        self.beats = beats
        self.beatType = beatType
    }

    /// Full measure length in quarter notes.
    public var measureLength: Rational { Rational(beats * 4, beatType) }
}

public struct Clef: Equatable, Sendable {
    public enum Sign: String, Sendable {
        case g = "G", f = "F", c = "C", percussion, tab, none
    }

    public var sign: Sign
    /// Staff line the clef sits on, counted from the bottom (G clef: 2, F clef: 4).
    public var line: Int
    /// +1 / -1 for an 8va / 8vb clef.
    public var octaveChange: Int

    public init(sign: Sign, line: Int, octaveChange: Int = 0) {
        self.sign = sign
        self.line = line
        self.octaveChange = octaveChange
    }

    public static let treble = Clef(sign: .g, line: 2)
    public static let bass = Clef(sign: .f, line: 4)
}

public struct ClefChange: Equatable, Sendable {
    public var offset: Rational
    public var staff: Int
    public var clef: Clef
}

public struct Direction: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case dynamic(String)
        case pedal(PedalAction)
        /// Quarter notes per minute.
        case tempo(Double)
        case words(String)
    }

    public enum PedalAction: String, Sendable {
        case start, stop, change, `continue`
    }

    /// From the start of the measure.
    public var offset: Rational
    public var staff: Int?
    public var kind: Kind
}
