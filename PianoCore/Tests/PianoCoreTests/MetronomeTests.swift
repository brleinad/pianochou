import Testing
@testable import PianoCore

/// The practice metronome: where it clicks, and that the listener doesn't hear its clicks as notes.
struct MetronomeTests {
    @Test func beatsOfSimpleAndCompoundMeters() {
        #expect(Metronome.beats(TimeSignature(beats: 4, beatType: 4)) == .init(count: 4, length: 1))
        #expect(Metronome.beats(TimeSignature(beats: 3, beatType: 4)) == .init(count: 3, length: 1))
        #expect(Metronome.beats(TimeSignature(beats: 2, beatType: 2)) == .init(count: 2, length: 2))
        // 6/8 and 12/8 click on the dotted quarter; 3/8 is felt in one, but clicks in eighths.
        #expect(Metronome.beats(TimeSignature(beats: 6, beatType: 8)) == .init(count: 2, length: Rational(3, 2)))
        #expect(Metronome.beats(TimeSignature(beats: 12, beatType: 8)) == .init(count: 4, length: Rational(3, 2)))
        #expect(Metronome.beats(TimeSignature(beats: 3, beatType: 8)) == .init(count: 3, length: Rational(1, 2)))
    }

    @Test func oneBarOfClicksStartsEachBeat() {
        let rate = 48_000.0
        // 6/8 at 90 quarters per minute: a bar is 3 quarters = 2 s, a click every 1 s, the first louder.
        let bar = Metronome.bar(TimeSignature(beats: 6, beatType: 8), tempo: 90, sampleRate: rate)
        #expect(bar.count == 96_000)
        let peaks = [0, 48_000].map { start in bar[start..<start + 2_400].map(abs).max()! }
        #expect(peaks[0] > peaks[1] * 1.5)
        #expect(bar[20_000..<46_000].allSatisfy { $0 == 0 })
    }

    @Test func tempoSteps() {
        #expect(Metronome.step(72, by: 1) == 77)
        #expect(Metronome.step(72, by: -1) == 67)
        #expect(Metronome.step(Tuning.tempoRange.lowerBound, by: -1) == Tuning.tempoRange.lowerBound)
        #expect(Metronome.step(Tuning.tempoRange.upperBound, by: 1) == Tuning.tempoRange.upperBound)
        #expect(Metronome.slower(72) == 60)   // ~10% slower, down to a multiple of 5
        #expect(Metronome.slower(32) == Tuning.tempoRange.lowerBound)
    }

    /// The click is pitched above everything the listener analyses, so a loud click on every beat
    /// neither adds notes nor hides the ones played (measured on two real recordings too: none).
    @Test(arguments: [[60], [72, 76, 79], [96, 100]])
    func clicksAreNotHeardAsNotes(expected: Set<Int>) {
        let rate = 48_000.0
        let synth = PianoSynth()
        let strikes = expected.sorted().enumerated().map { PianoSynth.Strike(midi: $0.element, time: 0.5 + 0.7 * Double($0.offset), duration: 2) }
        let piano = synth.render(strikes, length: 3.5)
        let bar = Metronome.bar(TimeSignature(beats: 4, beatType: 4), tempo: 100, sampleRate: rate)
        var mixed = piano
        for i in mixed.indices { mixed[i] += 1.5 * bar[(i + 7_000) % bar.count] }   // clicks louder than the piano, off the notes
        let alone = listen(piano, expecting: expected).map { "\($0.kind)" }
        #expect(!alone.isEmpty)
        #expect(listen(mixed, expecting: expected).map { "\($0.kind)" } == alone)
        #expect(listen(bar + bar, expecting: expected).isEmpty)
    }
}
