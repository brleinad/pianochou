import Foundation
@testable import PianoCore

/// Rough piano-like test signals: decaying inharmonic partials, a short hammer-noise burst,
/// and background noise. Real pianos are messier; these only pin down the logic.
struct PianoSynth {
    struct Strike {
        var midi: Int
        var time: Double
        var duration: Double = 1.0
        var amplitude: Double = 0.2
    }

    var sampleRate: Double = 48_000
    var noiseAmplitude: Double = 0.0005 // about -66 dBFS
    var seed: UInt64 = 42
    /// Detune the whole instrument, e.g. -30 for a piano a bit flat.
    var detuneCents: Double = 0

    func render(_ strikes: [Strike], length: Double) -> [Float] {
        let count = Int(length * sampleRate)
        var out = [Double](repeating: 0, count: count)
        var rng = SplitMix(seed: seed)

        for strike in strikes {
            let f0 = Pitch.frequency(midi: strike.midi) * pow(2, detuneCents / 1200)
            let start = Int(strike.time * sampleRate)
            let end = min(count, start + Int(strike.duration * sampleRate))
            let b = 0.0004
            let partials: [(f: Double, a: Double, tau: Double)] = (1...12).compactMap { h in
                let hd = Double(h)
                let f = hd * f0 * (1 + b * hd * hd).squareRoot()
                guard f < sampleRate / 2.2 else { return nil }
                // Bass fundamentals are weak on real pianos.
                let a = (h == 1 && strike.midi < 45 ? 0.3 : 1.0) / pow(hd, 1.1)
                return (f, a, 1.2 / hd.squareRoot())
            }
            for i in start..<max(start, end) {
                let t = Double(i - start) / sampleRate
                let attack = min(1, t / 0.004)
                let release = min(1, Double(end - i) / (0.03 * sampleRate)) // dampers
                var v = 0.0
                for p in partials { v += p.a * exp(-t / p.tau) * sin(2 * .pi * p.f * t) }
                v *= strike.amplitude * attack * release
                if t < 0.01 { v += strike.amplitude * 0.3 * (1 - t / 0.01) * rng.nextSigned() }
                out[i] += v
            }
        }
        for i in 0..<count { out[i] += noiseAmplitude * rng.nextSigned() }
        return out.map { Float($0) }
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextSigned() -> Double { Double(next() >> 11) / Double(1 << 53) * 2 - 1 }
}

/// Runs a listener over samples in small chunks, like the audio callback would.
func listen(_ samples: [Float], expecting expected: Set<Int>, sampleRate: Double = 48_000, chunk: Int = 256) -> [NoteListener.Event] {
    let listener = NoteListener(sampleRate: sampleRate)
    listener.expected = expected
    var events: [NoteListener.Event] = []
    var i = 0
    while i < samples.count {
        let j = min(samples.count, i + chunk)
        events += listener.process(Array(samples[i..<j]))
        i = j
    }
    return events
}

extension NoteListener.Event {
    var expectedMidi: Int? {
        if case .expected(let midi) = kind { return midi }
        return nil
    }

    var isUnexpected: Bool {
        if case .unexpected = kind { return true }
        return false
    }
}
