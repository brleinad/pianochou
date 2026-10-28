import Testing
@testable import PianoCore

/// Hearing the bars before playing them.
struct PlaybackTests {
    let rate = 48_000.0

    func scale() throws -> Snippet {
        let score = try Fixture.score("c-major-scale")
        return Snippet(score: score, measures: 0...1, hands: .both)
    }

    @Test func notesFollowTheTempo() throws {
        let notes = Playback.notes(of: try scale(), tempo: 120)
        #expect(notes.map(\.midi) == [60, 62, 64, 65, 67, 69, 71, 72])
        #expect(notes.map(\.start) == [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5])
        #expect(notes.allSatisfy { $0.length == 0.5 })
        #expect(Playback.duration(of: notes) == 4)
    }

    @Test func eachNoteSoundsFromItsStart() throws {
        let notes = [Playback.Sounding(midi: 69, start: 0, length: 0.5), Playback.Sounding(midi: 72, start: 1, length: 0.5)]
        let samples = Playback.render(notes, sampleRate: rate)
        // Long enough for the last note to die away, and never clipping.
        #expect(Double(samples.count) >= 1.5 * rate)
        #expect(samples.allSatisfy { abs($0) <= 1 })
        func level(_ from: Double, _ to: Double) -> Float {
            samples[Int(from * rate)..<Int(to * rate)].map(abs).max() ?? 0
        }
        #expect(level(0.01, 0.1) > 0.1)    // A4 sounding
        #expect(level(0.9, 0.99) < 0.001)  // released, silent before C5
        #expect(level(1.01, 1.1) > 0.1)    // C5 sounding
    }

    @Test func pitchIsRight() {
        // A4: the waveform repeats every 1/440 s.
        let samples = Playback.render([.init(midi: 69, start: 0, length: 1)], sampleRate: rate)
        let window = Array(samples[4_800..<9_600])
        func correlation(_ lag: Int) -> Float {
            zip(window.dropLast(lag), window.dropFirst(lag)).map(*).reduce(0, +)
        }
        let best = (80...140).max { correlation($0) < correlation($1) }!
        #expect(abs(Double(best) - rate / 440) < 1.5)
    }

    @Test func playheadMovesAtTheTempo() throws {
        let snippet = try scale()
        #expect(Playback.time(at: 0, in: snippet, tempo: 120) == 0)
        #expect(Playback.time(at: 1.25, in: snippet, tempo: 120) == Rational(5, 2))
    }
}
