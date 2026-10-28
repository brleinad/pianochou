import Foundation

/// Plays the bars so you can hear them first: the snippet's notes at the practice tempo, rendered to
/// samples with a simple piano-like tone (a few harmonics, a quick attack, a decay that's longer for low notes).
public enum Playback {
    /// One note to sound, in seconds from the first chord.
    public struct Sounding: Equatable, Sendable {
        public var midi: Int
        public var start: Double
        public var length: Double

        public init(midi: Int, start: Double, length: Double) {
            self.midi = midi
            self.start = start
            self.length = length
        }
    }

    /// Every note of the snippet, held for its written length (ties included).
    public static func notes(of snippet: Snippet, tempo: Double) -> [Sounding] {
        let spq = 60 / tempo
        return snippet.chords.flatMap { chord in
            chord.notes.map { note in
                Sounding(midi: note.midi, start: (chord.time - snippet.start).doubleValue * spq,
                         length: (note.duration > .zero ? note.duration : chord.duration).doubleValue * spq)
            }
        }
    }

    /// Seconds from the first note until the last one is released.
    public static func duration(of notes: [Sounding]) -> Double {
        notes.map { $0.start + $0.length }.max() ?? 0
    }

    /// Score time reached `seconds` after the first chord, for the line that follows the playback.
    public static func time(at seconds: Double, in snippet: Snippet, tempo: Double) -> Rational {
        snippet.start + Rational(Int((max(0, seconds) * tempo / 60 * 960).rounded()), 960)
    }

    /// Mono samples at `sampleRate`, starting at the first note, never above full scale.
    public static func render(_ notes: [Sounding], sampleRate: Double) -> [Float] {
        let release = Tuning.playbackRelease
        let count = Int(((duration(of: notes)) + release * 4) * sampleRate)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let table = waveTable
        let attack = 0.005 * sampleRate
        for note in notes {
            let frequency = Tuning.referencePitchHz * pow(2, Double(note.midi - 69) / 12)
            let step = frequency * Double(table.count) / sampleRate
            // Low strings ring longer than high ones.
            let decay = min(4, max(0.4, Tuning.playbackDecay * pow(2, Double(60 - note.midi) / 24)))
            let first = Int(note.start * sampleRate)
            let held = note.length * sampleRate
            let end = min(count, first + Int(held + release * 4 * sampleRate))
            var phase = 0.0
            for i in first..<end {
                let t = Double(i - first)
                var level = min(1, t / attack) * exp(-t / (decay * sampleRate))
                if t > held { level *= exp(-(t - held) / (release * sampleRate)) }
                out[i] += Float(level * Tuning.playbackVolume) * table[Int(phase) & (table.count - 1)]
                phase += step
                if phase >= Double(table.count) { phase -= Double(table.count) }
            }
        }
        // Many notes at once could clip: scale the whole thing down instead.
        let peak = out.lazy.map(abs).max() ?? 0
        if peak > 0.9 {
            let gain = 0.9 / peak
            for i in out.indices { out[i] *= gain }
        }
        return out
    }

    /// One cycle of the tone: a fundamental and a few softer harmonics.
    private static let waveTable: [Float] = {
        let size = 2048
        let harmonics: [Double] = [1, 0.5, 0.3, 0.18, 0.1, 0.06]
        let total = harmonics.reduce(0, +)
        return (0..<size).map { i in
            let x = 2 * Double.pi * Double(i) / Double(size)
            return Float(harmonics.enumerated().reduce(0) { $0 + $1.element * sin(Double($1.offset + 1) * x) } / total)
        }
    }()
}
