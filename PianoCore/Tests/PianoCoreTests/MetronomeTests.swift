import Testing
@testable import PianoCore

/// The practice metronome: where it clicks, and that the listener doesn't hear its clicks as notes.
struct MetronomeTests {
    @Test func beatsOfSimpleAndCompoundMeters() {
        #expect(Metronome.beats(TimeSignature(beats: 4, beatType: 4)) == .init(count: 4, length: 1))
        #expect(Metronome.beats(TimeSignature(beats: 3, beatType: 4)) == .init(count: 3, length: 1))
        #expect(Metronome.beats(TimeSignature(beats: 2, beatType: 2)) == .init(count: 2, length: 2))
        // 6/8 and 12/8 click on the dotted quarter; 3/8 clicks in eighths.
        #expect(Metronome.beats(TimeSignature(beats: 6, beatType: 8)) == .init(count: 2, length: Rational(3, 2)))
        #expect(Metronome.beats(TimeSignature(beats: 12, beatType: 8)) == .init(count: 4, length: Rational(3, 2)))
        #expect(Metronome.beats(TimeSignature(beats: 3, beatType: 8)) == .init(count: 3, length: Rational(1, 2)))
    }

    @Test func bundledSoundsLoad() throws {
        let sound = try Metronome.Sound.bundled()
        #expect(sound.sampleRate == 48_000)
        #expect(sound.accent.count > 2_000 && sound.beat.count > 2_000)
        #expect(sound.accent.map(abs).max()! > 0.9)
        #expect(sound.duration < Tuning.clickMaskAfter - 0.085)   // the mask covers a click plus one FFT window
    }

    @Test func oneBarOfClicksStartsEachBeat() throws {
        let sound = try Metronome.Sound.bundled()
        // 6/8 at 90 quarters per minute: a bar is 3 quarters = 2 s, a click every 1 s, claves first.
        let bar = Metronome.bar(TimeSignature(beats: 6, beatType: 8), tempo: 90, sampleRate: 48_000, sound: sound)
        #expect(bar.count == 96_000)
        #expect(Array(bar[0..<sound.accent.count]) == sound.accent.map { $0 * Float(Tuning.metronomeVolume) })
        #expect(Array(bar[48_000..<48_000 + sound.beat.count]) == sound.beat.map { $0 * Float(Tuning.metronomeVolume) })
        #expect(bar[20_000..<46_000].allSatisfy { $0 == 0 })
        // At 44.1 kHz output the clicks are resampled, the bar keeps its length in seconds.
        #expect(Metronome.bar(TimeSignature(beats: 6, beatType: 8), tempo: 90, sampleRate: 44_100, sound: sound).count == 88_200)
    }

    @Test func tempoSteps() {
        #expect(Metronome.step(72, by: 1) == 77)
        #expect(Metronome.step(72, by: -1) == 67)
        #expect(Metronome.step(Tuning.tempoRange.lowerBound, by: -1) == Tuning.tempoRange.lowerBound)
        #expect(Metronome.step(Tuning.tempoRange.upperBound, by: 1) == Tuning.tempoRange.upperBound)
        #expect(Metronome.slower(72) == 60)   // ~10% slower, down to a multiple of 5
        #expect(Metronome.slower(32) == Tuning.tempoRange.lowerBound)
    }

    // MARK: Listening with the clicks

    let rate = 48_000.0

    /// Clicks at `times`, at `level` × full scale, added to `samples` (4/4: claves every 4th).
    func withClicks(_ samples: [Float], at times: [Double], level: Float) throws -> [Float] {
        let sound = try Metronome.Sound.bundled()
        var out = samples
        for (k, time) in times.enumerated() {
            let click = k % 4 == 0 ? sound.accent : sound.beat
            let start = Int(time * rate)
            for (i, sample) in click.enumerated() where start + i < out.count { out[start + i] += level * sample }
        }
        return out
    }

    func listen(_ samples: [Float], expecting expected: Set<Int>, clicks: [Double]) -> [NoteListener.Event] {
        let listener = NoteListener(sampleRate: rate)
        listener.expected = expected
        clicks.forEach(listener.clickArrives)
        var events: [NoteListener.Event] = []
        var i = 0
        while i < samples.count {
            events += listener.process(Array(samples[i..<min(i + 256, samples.count)]))
            i += 256
        }
        return events
    }

    /// Recorded clicks louder than the piano, over notes still ringing: the listener that knows when the
    /// clicks come hears exactly what it hears without them; one that doesn't know hears extra notes.
    @Test(arguments: [[60], [72, 76, 79], [48, 55]])
    func clicksOverRingingNotesAreNotNotes(expected: Set<Int>) throws {
        let strikes = expected.sorted().enumerated().map { PianoSynth.Strike(midi: $0.element, time: 0.5 + 0.3 * Double($0.offset), duration: 3) }
        let piano = PianoSynth().render(strikes, length: 4)
        let clicks = stride(from: 1.35, to: 3.8, by: 0.5).map { $0 }
        let mixed = try withClicks(piano, at: clicks, level: 0.6)
        let alone = listen(piano, expecting: expected, clicks: []).map { "\($0.kind)" }
        #expect(!alone.isEmpty)
        #expect(listen(mixed, expecting: expected, clicks: clicks).map { "\($0.kind)" } == alone)
        #expect(listen(mixed, expecting: expected, clicks: []).count > alone.count, "the clicks alone should fool an uninformed listener")
    }

    @Test func clicksAloneAreNothing() throws {
        let clicks = stride(from: 0.5, to: 3.5, by: 0.5).map { $0 }
        let samples = try withClicks(PianoSynth().render([], length: 4), at: clicks, level: 0.6)
        #expect(listen(samples, expecting: [60, 64, 67, 81], clicks: clicks).isEmpty)
    }

    /// Notes played right on the click, as a player following the metronome does, are all heard, about on
    /// time; also when each strike lands on notes still ringing (pedal down).
    @Test(arguments: [0.45, 2.0])
    func notesOnTheClickAreHeard(duration: Double) throws {
        let times = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        let melody = [64, 67, 64, 67, 64, 67]
        let piano = PianoSynth().render(zip(melody, times).map { .init(midi: $0, time: $1, duration: duration) }, length: 4)
        let clicks = times.map { $0 + 0.005 }
        let events = listen(try withClicks(piano, at: clicks, level: 0.6), expecting: [64, 67], clicks: clicks)
        #expect(events.compactMap(\.expectedMidi) == melody, "\(events)")
        for (event, time) in zip(events, times) { #expect(abs(event.onsetTime - time) < 0.05, "\(event.onsetTime) vs \(time)") }
    }
}
