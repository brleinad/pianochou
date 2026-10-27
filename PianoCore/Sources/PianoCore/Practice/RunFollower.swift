/// Follows one run through a snippet and grades it.
///
/// Feed it every note the listener hears (expected or not) with its strike time, and call `tick`
/// regularly. It starts on the first chord's first note, moves on as chords are completed (or when the
/// next chord starts, leaving the rest missed), and ends on the last chord or on silence.
/// Times are seconds on any clock, as long as `hear` and `tick` share it.
public final class RunFollower {
    public enum Mode: Sendable {
        /// Strict: notes must also be on time, relative to the chord before.
        case drill
        /// Rubato: follow the player's tempo; only right/wrong/missed counts.
        case flow
    }

    public enum State: Sendable {
        case waiting, running, finished
    }

    /// For marking the staff while playing: a note (or event) that went well, came early or late (drills
    /// only; the right note at the wrong time), or went wrong (a wrong note or a missed one).
    public enum Outcome: Sendable {
        case good, early, late, bad
    }

    public let snippet: Snippet
    public let tempo: Double
    public let mode: Mode
    public private(set) var state: State = .waiting

    /// Seconds per quarter note.
    private var secondsPerQuarter: Double { 60 / tempo }

    private struct ChordProgress {
        var heard: [Int: Double] = [:]   // midi → strike time
        var wrong: [Int] = []
        var firstHit: Double?
        var timing: RunResult.Timing?
        var closed = false
    }

    private var chordState: [ChordProgress]
    private var current = 0
    private var lastHit = 0.0
    private var finishedAt: Double?

    public init(snippet: Snippet, tempo: Double, mode: Mode) {
        self.snippet = snippet
        self.tempo = tempo
        self.mode = mode
        chordState = Array(repeating: ChordProgress(), count: snippet.chords.count)
        if snippet.chords.isEmpty { state = .finished }
    }

    /// The pitches the listener should watch for: what is left of the current chord, and the next chord.
    public var expectedPitches: Set<Int> {
        guard state != .finished else { return [] }
        var pitches = Set<Int>()
        for i in current..<min(current + 2, snippet.chords.count) {
            for note in snippet.chords[i].notes where chordState[i].heard[note.midi] == nil { pitches.insert(note.midi) }
            pitches.formUnion(snippet.chords[i].graces)
        }
        return pitches
    }

    /// Score time of the chord to play next; nil once the run is over.
    public var currentTime: Rational? {
        state == .finished || current >= snippet.chords.count ? nil : snippet.chords[current].time
    }

    /// How far the line showing the beat has moved, as score time: from the last chord played, at the
    /// tempo, stopping at the next chord until that is played. On the first chord until the run starts;
    /// nil once it's over. `now` is on the same clock as `hear`.
    public func playhead(at now: Double) -> Rational? {
        guard state != .finished, let first = snippet.chords.first else { return nil }
        guard state == .running, let k = (0...min(current, snippet.chords.count - 1)).last(where: { chordState[$0].firstHit != nil }),
              let hit = chordState[k].firstHit else { return first.time }
        let waitAt = (k + 1..<snippet.chords.count).first { chordState[$0].firstHit == nil }.map { snippet.chords[$0].time }
        let elapsed = max(0, now - hit) / secondsPerQuarter
        let moved = snippet.chords[k].time + Rational(Int((elapsed * 960).rounded()), 960)
        return waitAt.map { min(moved, $0) } ?? moved
    }

    /// Fraction of chords done.
    public var progress: Double {
        snippet.chords.isEmpty ? 1 : Double(chordState.filter(\.closed).count) / Double(snippet.chords.count)
    }

    // MARK: Input

    public func hear(_ midi: Int, at time: Double) {
        switch state {
        case .waiting:
            guard snippet.chords[0].notes.contains(where: { $0.midi == midi }) else { return }
            state = .running
            register(midi, chord: 0, at: time)
        case .running:
            route(midi, at: time)
        case .finished:
            // A hand landing just after the last chord was played still counts for its chord.
            if let finishedAt, time - finishedAt <= Tuning.chordSpread { _ = lateArrival(midi, at: time) }
        }
    }

    public func tick(now: Double) {
        guard state == .running, current < snippet.chords.count else { return }
        // When the current chord was due, judging by the last chord played.
        let lastPlayed = (0..<current).last { chordState[$0].firstHit != nil }
        var due = lastHit
        if let k = lastPlayed, let hit = chordState[k].firstHit, chordState[current].firstHit == nil {
            due = max(lastHit, hit + (snippet.chords[current].time - snippet.chords[k].time).doubleValue * secondsPerQuarter)
        }
        if now - due > Tuning.silenceGrace { finish(at: now) }
    }

    private func route(_ midi: Int, at time: Double) {
        // A second detection of a pitch just played is the same strike.
        for i in max(0, current - 1)...min(current, snippet.chords.count - 1) {
            if let heard = chordState[i].heard[midi], time - heard < Tuning.chordSpread { return }
        }
        if wants(midi, chord: current) {
            register(midi, chord: current, at: time)
        } else if current + 1 < snippet.chords.count && wants(midi, chord: current + 1) {
            close(current)
            current += 1
            register(midi, chord: current, at: time)
        } else if lateArrival(midi, at: time) {
            return
        } else if (current..<min(current + 2, snippet.chords.count)).contains(where: { snippet.chords[$0].graces.contains(midi) }) {
            return // grace notes are optional
        } else {
            chordState[current].wrong.append(midi)
            lastHit = time
        }
    }

    private func wants(_ midi: Int, chord i: Int) -> Bool {
        snippet.chords[i].notes.contains { $0.midi == midi } && chordState[i].heard[midi] == nil
    }

    /// A missing note of a chord just passed, arriving within the chord spread: count it there.
    private func lateArrival(_ midi: Int, at time: Double) -> Bool {
        for i in stride(from: current - 1, through: max(0, current - 2), by: -1) {
            guard let first = chordState[i].firstHit, time - first <= Tuning.chordSpread, wants(midi, chord: i) else { continue }
            chordState[i].heard[midi] = time
            return true
        }
        return false
    }

    private func register(_ midi: Int, chord i: Int, at time: Double) {
        if chordState[i].firstHit == nil {
            chordState[i].firstHit = time
            chordState[i].timing = timing(of: i, at: time)
        }
        chordState[i].heard[midi] = time
        lastHit = time
        if snippet.chords[i].notes.allSatisfy({ chordState[i].heard[$0.midi] != nil }) {
            close(i)
            current = i + 1
            if current == snippet.chords.count { finish(at: time) }
        }
    }

    /// On time if it fits the beat counted from the last on-time chord (forgives coming back after a rush),
    /// or from the chord just before (forgives carrying on steadily after a hesitation).
    private func timing(of i: Int, at time: Double) -> RunResult.Timing {
        func deviation(from k: Int) -> (Double, Double)? {
            guard let hit = chordState[k].firstHit else { return nil }
            let gap = (snippet.chords[i].time - snippet.chords[k].time).doubleValue * secondsPerQuarter
            return (time - (hit + gap), max(Tuning.timingToleranceSeconds, Tuning.timingToleranceFraction * gap))
        }
        let played = (0..<i).filter { chordState[$0].firstHit != nil }
        guard let previous = played.last, let local = deviation(from: previous) else { return .onTime }
        let anchor = played.last { chordState[$0].timing == .onTime }.flatMap(deviation) ?? local
        if abs(anchor.0) <= anchor.1 || abs(local.0) <= local.1 { return .onTime }
        return local.0 < 0 ? .early : .late
    }

    private func close(_ i: Int) {
        chordState[i].closed = true
    }

    private func finish(at time: Double) {
        for i in current..<snippet.chords.count { close(i) }
        current = snippet.chords.count
        state = .finished
        finishedAt = time
    }

    // MARK: Output

    /// How a note (ref with `note`) or a whole event (ref without) went; nil while it is still to come.
    public func outcome(for ref: Engraving.NoteRef) -> Outcome? {
        var worst: Outcome?
        for (i, chord) in snippet.chords.enumerated() {
            for note in chord.notes where note.refs.contains(where: { ref.note == nil ? $0.eventRef == ref : $0 == ref }) {
                guard let grade = grade(note, chord: i) else { continue }
                let outcome: Outcome = switch (grade.grade, mode == .drill ? grade.timing : .onTime) {
                case (.right, .early?): .early
                case (.right, .late?): .late
                case (.right, _): .good
                default: .bad
                }
                // A wrong note outweighs a timing slip, which outweighs a good note.
                if worst == nil || outcome == .bad || (worst == .good && outcome != .good) { worst = outcome }
            }
        }
        return worst
    }

    private func grade(_ note: Snippet.Note, chord i: Int) -> (grade: RunResult.Grade, timing: RunResult.Timing?)? {
        let p = chordState[i]
        if p.heard[note.midi] != nil { return (.right, p.timing) }
        guard p.closed else { return nil }
        // Missing notes in a chord where wrong notes were played count as wrong, one for one.
        let missing = snippet.chords[i].notes.filter { p.heard[$0.midi] == nil }
        let position = missing.firstIndex { $0.midi == note.midi } ?? 0
        return (position < p.wrong.count ? .wrong : .missed, nil)
    }

    /// The graded run; nil until it has finished.
    public var result: RunResult? {
        guard state == .finished else { return nil }
        var notes: [RunResult.GradedNote] = []
        var extra = 0
        for (i, chord) in snippet.chords.enumerated() {
            let missing = chord.notes.filter { chordState[i].heard[$0.midi] == nil }.count
            extra += max(0, chordState[i].wrong.count - missing)
            for note in chord.notes {
                let (grade, timing) = self.grade(note, chord: i) ?? (.missed, nil)
                notes.append(.init(midi: note.midi, refs: note.refs, staff: note.staff, fingering: note.fingering,
                                   chord: i, measureNumber: chord.measureNumber, grade: grade, timing: timing))
            }
        }
        return RunResult(notes: notes, extraNotes: extra, mode: mode)
    }
}

public struct RunResult: Sendable {
    public enum Grade: Sendable {
        case right, wrong, missed
    }

    public enum Timing: Sendable {
        case early, onTime, late
    }

    public struct GradedNote: Sendable {
        public var midi: Int
        public var refs: [Engraving.NoteRef]
        public var staff: Int
        public var fingering: Int?
        /// Index into the snippet's chords.
        public var chord: Int
        public var measureNumber: String
        public var grade: Grade
        /// Nil for notes not played.
        public var timing: Timing?

        /// Right, and on time when timing counts.
        func isGood(_ mode: RunFollower.Mode) -> Bool {
            grade == .right && (mode == .flow || timing == .onTime)
        }
    }

    public struct Spot: Sendable {
        public var measureNumber: String
        public var chord: Int
        /// A few words, e.g. "Left thumb early".
        public var summary: String
    }

    /// In snippet order, each chord low to high.
    public var notes: [GradedNote]
    /// Wrong notes played on top of the right ones.
    public var extraNotes: Int
    public var mode: RunFollower.Mode

    public var total: Int { notes.count }
    public var good: Int { notes.filter { $0.isGood(mode) }.count }

    /// Per note, whether it went well: for the strip on the result screen.
    public var strip: [Bool] { notes.map { $0.isGood(mode) } }

    /// The single worst place: the chord with the most trouble (missed and wrong count double), earliest first.
    public var worst: Spot? {
        var scores: [Int: Int] = [:]
        for note in notes where !note.isGood(mode) {
            scores[note.chord, default: 0] += note.grade == .right ? 1 : 2
        }
        guard let chord = scores.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key else { return nil }
        let bad = notes.filter { $0.chord == chord && !$0.isGood(mode) }
        let first = bad[0]
        return Spot(measureNumber: first.measureNumber, chord: chord, summary: Self.describe(bad))
    }

    static func describe(_ bad: [GradedNote]) -> String {
        let note = bad[0]
        let hand = note.staff == 1 ? "Right" : "Left"
        let fingers = ["thumb", "index finger", "middle finger", "ring finger", "pinky"]
        let who: String
        if Set(bad.map(\.staff)).count > 1 {
            who = "Both hands"
        } else if bad.count > 1 {
            who = "\(hand) hand"
        } else if let finger = note.fingering, (1...5).contains(finger) {
            who = "\(hand) \(fingers[finger - 1])"
        } else {
            who = "\(hand) \(Pitch.name(midi: note.midi))"
        }
        switch (note.grade, note.timing) {
        case (.wrong, _): return "\(who): wrong note"
        case (.missed, _): return "\(who) missed"
        case (_, .early): return "\(who) early"
        case (_, .late): return "\(who) late"
        default: return who
        }
    }
}
