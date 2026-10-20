import Foundation
import Testing
@testable import PianoCore

@Suite struct NoteListenerTests {
    let synth = PianoSynth()

    @Test func fftFindsASine() {
        var fft = FFT(size: 1024)
        let input = (0..<1024).map { Float(sin(2 * Double.pi * 64 * Double($0) / 1024)) }
        var out = [Float](repeating: 0, count: 513)
        fft.magnitudes(of: input, into: &out)
        #expect(out.firstIndex(of: out.max()!) == 64)
        #expect(abs(out[64] - 512) < 0.01)
    }

    @Test func silenceAndNoiseProduceNothing() {
        let quiet = synth.render([], length: 2)
        #expect(listen(quiet, expecting: [60]).isEmpty)
        var noisy = PianoSynth()
        noisy.noiseAmplitude = 0.01 // loud room, -40 dBFS
        #expect(listen(noisy.render([], length: 2), expecting: [60, 64, 67]).isEmpty)
    }

    @Test(arguments: [48, 55, 60, 64, 69, 72, 79, 84])
    func singleNoteIsDetectedOnceWithLowLatency(midi: Int) {
        let samples = synth.render([.init(midi: midi, time: 0.5)], length: 1.5)
        let events = listen(samples, expecting: [midi])
        #expect(events.count == 1, "\(Pitch.name(midi: midi)): \(events)")
        guard let event = events.first else { return }
        #expect(event.expectedMidi == midi)
        #expect(abs(event.onsetTime - 0.5) < 0.03, "onset estimate \(event.onsetTime)")
        #expect(event.detectedAt - 0.5 < 0.06, "algorithm latency \(event.detectedAt - 0.5)")
    }

    @Test func threeNoteChordIsDetected() {
        let chord = [60, 64, 67]
        let samples = synth.render(chord.map { .init(midi: $0, time: 0.5, amplitude: 0.12) }, length: 1.5)
        let events = listen(samples, expecting: Set(chord))
        #expect(Set(events.compactMap(\.expectedMidi)) == Set(chord), "\(events)")
        #expect(events.count == 3)
        #expect(events.allSatisfy { abs($0.onsetTime - 0.5) < 0.03 })
    }

    @Test func wrongNoteIsReportedAsUnexpected() {
        let samples = synth.render([.init(midi: 62, time: 0.5)], length: 1.5) // D4 instead of C4
        let events = listen(samples, expecting: [60])
        #expect(events.allSatisfy { $0.expectedMidi == nil }, "\(events)")
        #expect(events.count == 1)
        #expect(events.first?.kind == .unexpected(guess: 62))
    }

    @Test func octaveAboveDoesNotCountForTheLowerNote() {
        let samples = synth.render([.init(midi: 72, time: 0.5)], length: 1.5) // C5 when C4 expected
        let events = listen(samples, expecting: [60])
        #expect(events.allSatisfy { $0.expectedMidi == nil }, "\(events)")
    }

    @Test func octaveBelowDoesNotCountForTheUpperNote() {
        let samples = synth.render([.init(midi: 60, time: 0.5)], length: 1.5) // C4 when C5 expected
        let events = listen(samples, expecting: [72])
        #expect(events.allSatisfy { $0.expectedMidi == nil }, "\(events)")
    }

    @Test func repeatedNoteIsHeardEachTime() {
        let times = [0.5, 0.8, 1.1, 1.4]
        let samples = synth.render(times.map { .init(midi: 64, time: $0, duration: 0.28) }, length: 2)
        let events = listen(samples, expecting: [64])
        #expect(events.compactMap(\.expectedMidi).count == 4, "\(events)")
        for (event, time) in zip(events, times) {
            #expect(abs(event.onsetTime - time) < 0.03)
        }
    }

    @Test func repeatedNoteWithoutDampers() {
        // Pedal down: each strike rings on under the next one.
        let times = [0.5, 0.9, 1.3]
        let samples = synth.render(times.map { .init(midi: 67, time: $0, duration: 2) }, length: 2.5)
        let events = listen(samples, expecting: [67])
        #expect(events.compactMap(\.expectedMidi).count == 3, "\(events)")
    }

    @Test func melodyFollowsTheExpectedNote() {
        // C D E played; listener told one note at a time, as the follower will.
        let notes = [(60, 0.5), (62, 0.9), (64, 1.3)]
        let samples = synth.render(notes.map { .init(midi: $0.0, time: $0.1, duration: 0.4) }, length: 2)
        let listener = NoteListener(sampleRate: 48_000)
        var heard: [Int] = []
        var next = 0
        listener.expected = [notes[0].0]
        var i = 0
        while i < samples.count {
            let events = listener.process(Array(samples[i..<min(samples.count, i + 256)]))
            for event in events {
                guard let midi = event.expectedMidi else { continue }
                heard.append(midi)
                next += 1
                listener.expected = next < notes.count ? [notes[next].0] : []
            }
            i += 256
        }
        #expect(heard == [60, 62, 64])
    }

    @Test func lowBassNoteIsDetected() {
        // A1 (55 Hz). Expected to be hard: weak fundamental, wide partial spacing vs. bin size.
        let samples = synth.render([.init(midi: 33, time: 0.5)], length: 1.5)
        let events = listen(samples, expecting: [33])
        #expect(events.compactMap(\.expectedMidi) == [33], "\(events)")
    }
}
