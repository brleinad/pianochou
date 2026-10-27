import Testing
@testable import PianoCore

/// Showing how long to hold each note: its length, the line that moves through it, and where it's drawn.
struct HoldBarsTests {
    @Test func noteLengthsRunThroughTies() throws {
        let score = try Fixture.score("engraving-sampler")
        let snippet = Snippet(score: score, measures: 1...2, hands: .right)
        // A4 in bar 2's last chord (a quarter) is tied to a half note in bar 3: held three beats.
        let chord = try #require(snippet.chords.first { $0.measure == 1 && $0.notes.map(\.midi) == [67, 69] })
        #expect(chord.notes.map(\.duration) == [1, 3])
        #expect(snippet.chords.first?.notes.first?.duration == Rational(1, 4))
    }

    /// C D E F G A B C in quarters at 60: one note a second.
    func scale() throws -> (Snippet, RunFollower) {
        let score = try Fixture.score("c-major-scale")
        let snippet = Snippet(score: score, measures: 0...1, hands: .right)
        return (snippet, RunFollower(snippet: snippet, tempo: 60, mode: .drill))
    }

    @Test func playheadWaitsAtTheNextNote() throws {
        let (_, follower) = try scale()
        // Before the first note it sits on it.
        #expect(follower.playhead(at: 5) == 0)
        follower.hear(60, at: 10)
        // It moves at the tempo from where the note was played…
        #expect(follower.playhead(at: 10.5) == Rational(1, 2))
        // …and waits at the next note until it's played.
        #expect(follower.playhead(at: 13) == 1)
        follower.hear(62, at: 13)
        #expect(follower.playhead(at: 13.25) == Rational(5, 4))
        // Played early, it starts again from there.
        follower.hear(64, at: 13.5)
        #expect(follower.playhead(at: 13.5) == 2)
    }

    @Test func noPlayheadOnceTheRunIsOver() throws {
        let (_, follower) = try scale()
        for (i, midi) in [60, 62, 64, 65, 67, 69, 71, 72].enumerated() { follower.hear(midi, at: Double(i)) }
        #expect(follower.state == .finished)
        #expect(follower.playhead(at: 20) == nil)
    }

    @Test func barsRunFromEachNoteToWhereItEnds() throws {
        let score = try Fixture.score("c-major-scale")
        let snippet = Snippet(score: score, measures: 0...1, hands: .right)
        let engraving = Engraver.engrave(score, measures: 0..<2)
        let bars = HoldBars.make(engraving: engraving, snippet: snippet)
        #expect(bars.count == 8)
        #expect(bars[0].start == 0 && bars[0].end == 1)
        #expect(bars[0].x0 == engraving.x(at: 0) && bars[0].x1 == engraving.x(at: 1))
        // Level with its notehead: C4 sits lower than D4.
        #expect(bars[0].y > bars[1].y)
        let head = try #require(engraving.items.first { $0.role == .notehead && $0.ref == snippet.chords[0].notes[0].refs[0] })
        #expect(bars[0].y == head.point.y)
        // The last one stops at the end of the bar.
        #expect(bars[7].x1 == engraving.x(at: 8))
    }
}
