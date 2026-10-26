import Foundation

/// The practice metronome: a short tick on every beat, louder and a little higher on the first beat of
/// the bar, and the tempo steps the practice screens use. Tempos are quarter notes per minute.
public enum Metronome {
    public struct Beats: Equatable, Sendable {
        public var count: Int
        /// Length of one beat, in quarter notes.
        public var length: Rational
    }

    /// The beats of one bar. 6/8, 9/8 and 12/8 are counted in dotted quarters.
    public static func beats(_ time: TimeSignature) -> Beats {
        if time.beatType == 8 && time.beats % 3 == 0 && time.beats > 3 {
            return Beats(count: time.beats / 3, length: Rational(3, 2))
        }
        return Beats(count: time.beats, length: Rational(4, time.beatType))
    }

    /// One click as samples: a sine burst with a smooth start, pitched above everything the listener
    /// analyses (`Tuning.maxPartialHz`), so the microphone hearing it doesn't count as a note.
    public static func click(sampleRate: Double, accent: Bool) -> [Float] {
        let hz = accent ? Tuning.metronomeAccentHz : Tuning.metronomeClickHz
        let peak = Tuning.metronomeVolume * (accent ? 1 : Tuning.metronomeOffbeatLevel)
        let count = Int(Tuning.metronomeClickSeconds * sampleRate)
        let attack = max(1, Int(Tuning.metronomeClickAttack * sampleRate))
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            var envelope = exp(-t / Tuning.metronomeClickDecay)
            if i < attack { envelope *= 0.5 - 0.5 * cos(Double.pi * Double(i) / Double(attack)) }
            return Float(peak * envelope * sin(2 * Double.pi * hz * t))
        }
    }

    /// One bar of clicks at `tempo`, to loop.
    public static func bar(_ time: TimeSignature, tempo: Double, sampleRate: Double) -> [Float] {
        let beats = beats(time)
        let beatSamples = Int((beats.length.doubleValue * 60 / tempo * sampleRate).rounded())
        var out = [Float](repeating: 0, count: beatSamples * beats.count)
        for beat in 0..<beats.count {
            let click = click(sampleRate: sampleRate, accent: beat == 0)
            for (i, sample) in click.prefix(beatSamples).enumerated() { out[beat * beatSamples + i] = sample }
        }
        return out
    }

    /// One `Tuning.tempoStep` faster (+1) or slower (-1), within `Tuning.tempoRange`.
    public static func step(_ tempo: Double, by steps: Int) -> Double {
        clamp(tempo + Double(steps) * Tuning.tempoStep)
    }

    /// About 10% slower, down to a whole step: what "Slower" after a run does.
    public static func slower(_ tempo: Double) -> Double {
        clamp(((tempo * Tuning.slowerFactor) / Tuning.tempoStep).rounded(.down) * Tuning.tempoStep)
    }

    private static func clamp(_ tempo: Double) -> Double {
        min(max(tempo, Tuning.tempoRange.lowerBound), Tuning.tempoRange.upperBound)
    }
}
