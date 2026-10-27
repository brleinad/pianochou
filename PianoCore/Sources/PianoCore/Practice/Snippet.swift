/// Which hands a practice run covers. On a grand staff the right hand is staff 1, the left hand staff 2.
public enum Hands: String, CaseIterable, Sendable {
    case right, left, both

    public func includes(staff: Int) -> Bool {
        switch self {
        case .right: staff == 1
        case .left: staff >= 2
        case .both: true
        }
    }
}

/// The notes to play in a few bars, for one or both hands, as chords in time order.
/// A "chord" is everything struck at the same moment, so a melody note is a one-note chord.
public struct Snippet: Sendable {
    public struct Note: Equatable, Sendable {
        public var midi: Int
        /// Where it is in the score; two refs when both hands play the same pitch.
        public var refs: [Engraving.NoteRef]
        public var staff: Int
        public var fingering: Int?
        /// How long to hold it: its written length, plus any notes tied on to it.
        public var duration: Rational = .zero
    }

    public struct Chord: Equatable, Sendable {
        /// Written score time, quarter notes.
        public var time: Rational
        /// Until the next chord, or the end of the snippet.
        public var duration: Rational
        /// Sorted low to high.
        public var notes: [Note]
        /// Grace notes just before this chord: allowed, not required.
        public var graces: Set<Int>
        /// Index into `Part.measures`.
        public var measure: Int
        /// The printed bar number.
        public var measureNumber: String
    }

    public let measures: ClosedRange<Int>
    public let hands: Hands
    public let chords: [Chord]

    public var noteCount: Int { chords.reduce(0) { $0 + $1.notes.count } }
    public var start: Rational { chords.first?.time ?? .zero }

    public init(score: Score, part: Int = 0, measures: ClosedRange<Int>, hands: Hands) {
        self.measures = measures
        self.hands = hands
        let allMeasures = score.parts[part].measures
        let range = measures.clamped(to: 0...(allMeasures.count - 1))

        var chords: [Chord] = []
        var pendingGraces: Set<Int> = []
        for m in range {
            let measure = allMeasures[m]
            for (e, event) in measure.events.enumerated() where hands.includes(staff: event.staff) && !event.isRest {
                if event.isGrace {
                    pendingGraces.formUnion(event.notes.map(\.pitch.midi))
                    continue
                }
                let time = measure.start + event.onset
                // Held notes from a tie aren't struck again.
                let struck = event.notes.enumerated().filter { !$0.element.tie.stop }
                guard !struck.isEmpty else { continue }
                if chords.last?.time != time {
                    chords.append(Chord(time: time, duration: .zero, notes: [], graces: [], measure: m, measureNumber: measure.number))
                }
                chords[chords.count - 1].graces.formUnion(pendingGraces)
                pendingGraces = []
                for (n, note) in struck {
                    let ref = Engraving.NoteRef(measure: m, event: e, note: n)
                    let held = Self.heldLength(midi: note.pitch.midi, tied: note.tie.start, in: event, measure: m,
                                               measures: allMeasures, upTo: range.upperBound)
                    if let same = chords[chords.count - 1].notes.firstIndex(where: { $0.midi == note.pitch.midi }) {
                        chords[chords.count - 1].notes[same].refs.append(ref)
                        chords[chords.count - 1].notes[same].duration = max(chords[chords.count - 1].notes[same].duration, held)
                    } else {
                        chords[chords.count - 1].notes.append(Note(midi: note.pitch.midi, refs: [ref], staff: event.staff,
                                                                   fingering: note.fingering, duration: held))
                    }
                }
            }
        }
        // Events are sorted by onset within a measure, but staves interleave; sort to be safe.
        chords.sort { $0.time < $1.time }
        let end = allMeasures[range.upperBound].start + allMeasures[range.upperBound].duration
        for i in chords.indices {
            chords[i].notes.sort { $0.midi < $1.midi }
            chords[i].duration = (i + 1 < chords.count ? chords[i + 1].time : end) - chords[i].time
        }
        self.chords = chords
    }

    /// A note's written length, plus the notes tied on to it (same pitch and staff, later in the bars).
    static func heldLength(midi: Int, tied: Bool, in event: Event, measure m: Int, measures: [Measure], upTo last: Int) -> Rational {
        var length = event.duration
        var end = measures[m].start + event.onset + event.duration
        var continues = tied
        while continues {
            continues = false
            for k in m...last {
                let start = measures[k].start
                let candidates = measures[k].events.filter { $0.staff == event.staff && start + $0.onset == end }
                guard let next = candidates.first(where: { e in e.notes.contains { $0.pitch.midi == midi && $0.tie.stop } }),
                      let note = next.notes.first(where: { $0.pitch.midi == midi }) else { continue }
                length = length + next.duration
                end = end + next.duration
                continues = note.tie.start
                break
            }
        }
        return length
    }
}
