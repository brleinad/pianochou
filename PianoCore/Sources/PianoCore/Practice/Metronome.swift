import Foundation

/// The practice metronome: a recorded click on every beat (claves on the first beat of the bar, a
/// mechanical metronome's tick on the others), and the tempo steps the practice screens use.
/// Tempos are quarter notes per minute.
public enum Metronome {
    public struct Beats: Equatable, Sendable {
        public var count: Int
        /// Length of one beat, in quarter notes.
        public var length: Rational
    }

    /// The two clicks, mono.
    public struct Sound: Sendable {
        public var accent: [Float]
        public var beat: [Float]
        public var sampleRate: Double

        /// The public-domain samples bundled with PianoCore (see Resources/Metronome/SOURCE.md).
        public static func bundled() throws -> Sound {
            func load(_ name: String) throws -> (samples: [Float], rate: Double) {
                guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Metronome")
                    ?? Bundle.module.url(forResource: name, withExtension: "wav") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                return try readWav(Data(contentsOf: url))
            }
            let accent = try load("accent"), beat = try load("beat")
            return Sound(accent: accent.samples, beat: resample(beat.samples, from: beat.rate, to: accent.rate),
                         sampleRate: accent.rate)
        }

        /// Longest click, in seconds: how long the listener must allow for one.
        public var duration: Double { Double(max(accent.count, beat.count)) / sampleRate }
    }

    /// The beats of one bar. 6/8, 9/8 and 12/8 are counted in dotted quarters.
    public static func beats(_ time: TimeSignature) -> Beats {
        if time.beatType == 8 && time.beats % 3 == 0 && time.beats > 3 {
            return Beats(count: time.beats / 3, length: Rational(3, 2))
        }
        return Beats(count: time.beats, length: Rational(4, time.beatType))
    }

    /// Seconds from one click to the next.
    public static func beatSeconds(_ time: TimeSignature, tempo: Double) -> Double {
        beats(time).length.doubleValue * 60 / tempo
    }

    /// One bar of clicks at `tempo`, at `sampleRate`, to loop. Each beat starts with its click.
    public static func bar(_ time: TimeSignature, tempo: Double, sampleRate: Double, sound: Sound) -> [Float] {
        let beats = beats(time)
        let beatSamples = Int((beatSeconds(time, tempo: tempo) * sampleRate).rounded())
        let accent = resample(sound.accent, from: sound.sampleRate, to: sampleRate)
        let beat = resample(sound.beat, from: sound.sampleRate, to: sampleRate)
        var out = [Float](repeating: 0, count: beatSamples * beats.count)
        for b in 0..<beats.count {
            let click = b == 0 ? accent : beat
            for (i, sample) in click.prefix(beatSamples).enumerated() {
                out[b * beatSamples + i] = sample * Float(Tuning.metronomeVolume)
            }
        }
        return out
    }

    /// One `Tuning.tempoStep` faster (+1) or slower (-1), within `Tuning.tempoRange`.
    public static func step(_ tempo: Double, by steps: Int) -> Double {
        clamp(tempo + Double(steps) * Tuning.tempoStep)
    }

    private static func clamp(_ tempo: Double) -> Double {
        min(max(tempo, Tuning.tempoRange.lowerBound), Tuning.tempoRange.upperBound)
    }

    /// Linear interpolation; plenty for a click.
    static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !samples.isEmpty else { return samples }
        let count = Int((Double(samples.count) * to / from).rounded())
        return (0..<count).map { i in
            let position = Double(i) * from / to
            let k = Int(position), frac = Float(position - Double(k))
            let a = samples[min(k, samples.count - 1)], b = samples[min(k + 1, samples.count - 1)]
            return a + (b - a) * frac
        }
    }

    /// 16-bit PCM WAV, first channel.
    static func readWav(_ data: Data) throws -> (samples: [Float], rate: Double) {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard bytes.count > 12, String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF" else { throw CocoaError(.fileReadCorruptFile) }
        var offset = 12, channels = 1, rate = 48_000, bits = 16
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self), size = u32(offset + 4), body = offset + 8
            if id == "fmt " {
                channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if id == "data" {
                guard bits == 16 else { throw CocoaError(.fileReadCorruptFile) }
                let frames = min(size, bytes.count - body) / (2 * channels)
                let samples = (0..<frames).map { f -> Float in
                    Float(Int16(truncatingIfNeeded: u16(body + f * 2 * channels))) / 32768
                }
                return (samples, Double(rate))
            }
            offset = body + size + (size & 1)
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
