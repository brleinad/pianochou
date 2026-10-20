/// A few bars laid out for drawing. Everything is in staff spaces, y down, origin at the top left.
/// The app scales it to points and draws each item; overlays (played, mistakes, the current beat)
/// are applied by the renderer using each item's `ref` and `time`.
public struct Engraving: Sendable {
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Identifies what an item belongs to: an event in a measure, and optionally one note of it.
    public struct NoteRef: Hashable, Sendable {
        /// Index into `Part.measures`.
        public var measure: Int
        /// Index into `Measure.events`.
        public var event: Int
        /// Index into `Event.notes`; nil for parts shared by the whole event (stem, beam, flag, rest).
        public var note: Int?

        public init(measure: Int, event: Int, note: Int? = nil) {
            self.measure = measure
            self.event = event
            self.note = note
        }

        /// The event this belongs to, without the note.
        public var eventRef: NoteRef { NoteRef(measure: measure, event: event) }
    }

    public enum Role: Sendable {
        case staffLine, barline, brace, clef, keySignature, timeSignature
        case notehead, accidental, dot, ledger, stem, flag, beam, rest, tie, tuplet
        /// Overlays: finger numbers and beat counts.
        case finger, count
    }

    public enum Shape: Equatable, Sendable {
        /// A font glyph, origin at `at`, scaled from the normal staff size.
        case glyph(Glyph, at: Point, scale: Double)
        case line(from: Point, to: Point, thickness: Double)
        /// A parallelogram whose top edge runs `from`–`to`, `thickness` deep.
        case beam(from: Point, to: Point, thickness: Double)
        /// A tie between two noteheads, curving up or down.
        case tie(from: Point, to: Point, above: Bool)
        /// Text centred on `at`. `size` is the font size in staff spaces.
        case text(String, at: Point, size: Double)

        public var glyph: Glyph? {
            if case let .glyph(glyph, _, _) = self { glyph } else { nil }
        }

        public var text: String? {
            if case let .text(text, _, _) = self { text } else { nil }
        }
    }

    public struct Item: Sendable {
        public var shape: Shape
        public var role: Role
        public var ref: NoteRef?
        /// Score time (quarter notes from the start, in written order) of the event this belongs to,
        /// or of the beat a count marks.
        public var time: Rational?

        /// A representative point: a glyph's origin, a text's centre, a line's start.
        public var point: Point {
            switch shape {
            case let .glyph(_, at, _), let .text(_, at, _): at
            case let .line(from, _, _), let .beam(from, _, _), let .tie(from, _, _): from
            }
        }
    }

    public var width: Double
    public var height: Double
    /// y of each staff's top line, by staff number − 1.
    public var staffTops: [Double]
    public var items: [Item]
    /// The written score time span shown, from the first bar's start to the last bar's end.
    public var start: Rational
    public var end: Rational
    /// x where the music starts, after clefs and signatures.
    public var contentStart: Double

    /// Note positions along time: each onset's notehead centre, plus each barline.
    var timeline: [(time: Rational, x: Double, isOnset: Bool)]

    /// The x of a score time inside the window: an onset's notehead centre, or interpolated between them.
    public func x(at time: Rational) -> Double? {
        guard time >= start, time <= end else { return nil }
        if let onset = timeline.first(where: { $0.isOnset && $0.time == time }) { return onset.x }
        guard let after = timeline.firstIndex(where: { $0.time > time }) else { return timeline.last?.x }
        guard after > 0 else { return timeline[after].x }
        let a = timeline[after - 1], b = timeline[after]
        let fraction = ((time - a.time) / (b.time - a.time)).doubleValue
        return a.x + (b.x - a.x) * fraction
    }
}
