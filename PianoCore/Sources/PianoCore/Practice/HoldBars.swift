/// How long to hold each note, for drawing: a bar from the notehead to where the note ends, level with it.
public struct HoldBar: Equatable, Sendable {
    public var ref: Engraving.NoteRef
    /// Score time it starts and ends.
    public var start: Rational
    public var end: Rational
    /// In staff spaces, like the engraving it belongs to.
    public var x0: Double
    public var x1: Double
    public var y: Double
}

public enum HoldBars {
    /// One bar per note to play in `snippet`, placed on `engraving` (made from the same score and bars).
    public static func make(engraving: Engraving, snippet: Snippet) -> [HoldBar] {
        var heads: [Engraving.NoteRef: Double] = [:]
        for item in engraving.items where item.role == .notehead {
            if let ref = item.ref { heads[ref] = item.point.y }
        }
        var bars: [HoldBar] = []
        for chord in snippet.chords {
            for note in chord.notes {
                guard let ref = note.refs.first, let y = heads[ref], let x0 = engraving.x(at: chord.time) else { continue }
                let end = min(chord.time + note.duration, engraving.end)
                bars.append(HoldBar(ref: ref, start: chord.time, end: end, x0: x0, x1: engraving.x(at: end) ?? x0, y: y))
            }
        }
        return bars
    }
}
