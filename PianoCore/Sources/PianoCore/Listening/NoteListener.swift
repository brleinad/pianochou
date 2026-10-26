import Foundation

/// Score-informed note detection. The caller says which pitches *should* sound next;
/// the listener reports when each of them is struck, and when something else is struck instead.
/// It does not transcribe arbitrary music.
///
/// Feed it mono samples in stream order. Times are seconds since the first sample.
public final class NoteListener {

    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// One of the expected pitches was struck.
            case expected(midi: Int)
            /// A pitched note was struck that matches none of the expected pitches. `guess` is a rough estimate.
            /// Unpitched sounds (knocks, speech bursts) are not reported.
            case unexpected(guess: Int)
        }

        public var kind: Kind
        /// Estimated stream time of the key strike.
        public var onsetTime: Double
        /// Stream time of the frame where the detection was made. `detectedAt - onsetTime` is the algorithm's latency.
        public var detectedAt: Double
    }

    public static let lowestMidi = 21   // A0
    public static let highestMidi = 108 // C8

    public let sampleRate: Double

    /// The pitches that should sound next (MIDI numbers).
    public var expected: Set<Int> = []

    /// Salience in dB above the noise floor, per MIDI note, for the latest frame.
    public func salience(of midi: Int) -> Float {
        guard (Self.lowestMidi...Self.highestMidi).contains(midi) else { return 0 }
        return history[(historyIndex + historyLength - 1) % historyLength][midi - Self.lowestMidi]
    }

    /// Whether `midi` is sounding in the latest frame, including the octave-error guard.
    public func isSounding(_ midi: Int) -> Bool {
        isPresent(midi, salience: salience(of: midi))
    }

    /// Per-frame internals for one pitch, for debugging tools.
    public struct Diagnostics: Sendable {
        public var salience: Float
        /// Salience now minus its minimum over the onset lookback.
        public var rise: Float
        public var sounding: Bool
        /// False while waiting for the salience to level off after an onset.
        public var armed: Bool
        /// Broadband strike measures for the latest frame.
        public var flux: Float
        public var energyRise: Float
        /// Raw level of this pitch's partials now minus its minimum over the onset lookback.
        public var levelRise: Float
    }

    public func diagnostics(for midi: Int) -> Diagnostics {
        let now = salience(of: midi)
        return Diagnostics(salience: now, rise: now - minimumRecent(midi), sounding: isSounding(midi),
                           armed: !disarmed.contains(midi), flux: lastFlux, energyRise: lastEnergyRise,
                           levelRise: levelRise(midi))
    }

    private var lastFlux: Float = 0
    private var lastEnergyRise: Float = 0

    /// Loudest bin in the latest frame, dBFS. For a level meter.
    public private(set) var peakLevelDb: Float = -120

    /// Stream time of the newest analysed sample.
    public var currentTime: Double { analyzer.frameTime }

    private let analyzer: SpectrumAnalyzer
    private let binCount: Int
    private var magDb: [Float]
    private var floorDb: [Float]
    private var aboveFloor: [Float]
    private var smoothScratch: [Float]
    private var previousMagDb: [[Float]]
    private var previousEnergyDb: [Float] = [-120, -120]
    /// Bins covering the piano's main range (60 Hz – 5 kHz), for flux and energy.
    private let bandLo: Int
    private let bandHi: Int
    private var floorInitialized = false

    private let historyLength: Int
    private var history: [[Float]]
    /// Raw partial level per pitch (dB), and its rise versus the lookback before it; same ring as `history`.
    private var levelHistory: [[Float]]
    private var levelRiseHistory: [[Float]]
    private var historyIndex = 0
    private let lookbackFrames: Int

    private var lastOnset: [Int: Double] = [:]
    /// A pitch re-arms for its next onset only once its salience stops climbing, so one strike
    /// (whose salience rises over a whole window length) is not reported twice.
    private var disarmed: Set<Int> = []
    private var lastStrike = -Double.infinity
    private var strikeArmed = true
    private var pendingStrikes: [(time: Double, detectedAt: Double)] = []
    private var recentExpected: [Double] = []

    /// When the app's metronome clicks reach the microphone (stream time), see `clickArrives(at:)`.
    private var clicks: [Double] = []
    /// Each pitch's partial level just before the current click, while one is sounding.
    private var levelBeforeClick: [Float]?
    /// Expected onsets heard during a click, decided once it has died away.
    private var held: [(event: Event, midi: Int, previousOnset: Double?)] = []

    private struct Window {
        var lo: Int
        var hi: Int
    }

    /// Precomputed per pitch, for each usable harmonic: its window, the windows a semitone below and above, its weight.
    private var partials: [[(harmonic: Int, own: Window, below: Window, above: Window, weight: Float)]] = []

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        analyzer = SpectrumAnalyzer(sampleRate: sampleRate)
        binCount = Tuning.fftSize / 2 + 1
        bandLo = max(1, Int(60 / analyzer.binHz))
        bandHi = min(binCount - 1, Int(5000 / analyzer.binHz))
        magDb = Array(repeating: -120, count: binCount)
        floorDb = Array(repeating: -120, count: binCount)
        aboveFloor = Array(repeating: 0, count: binCount)
        smoothScratch = Array(repeating: 0, count: binCount + 1)
        previousMagDb = Array(repeating: Array(repeating: -120, count: binCount), count: 2)

        let hopSeconds = Double(Tuning.hopSize) / sampleRate
        lookbackFrames = max(1, Int((Tuning.onsetLookback / hopSeconds).rounded()))
        historyLength = max(lookbackFrames + 2, Int(((Tuning.onsetLookback + Tuning.unexpectedLateWindow) / hopSeconds).rounded()) + 2)
        let pitchCount = Self.highestMidi - Self.lowestMidi + 1
        history = Array(repeating: Array(repeating: 0, count: pitchCount), count: historyLength)
        levelHistory = Array(repeating: Array(repeating: -120, count: pitchCount), count: historyLength)
        levelRiseHistory = Array(repeating: Array(repeating: 0, count: pitchCount), count: historyLength)

        let semitone = pow(2, 1.0 / 12)
        let topHz = min(Tuning.maxPartialHz, sampleRate / 2 / semitone - analyzer.binHz)
        partials = (Self.lowestMidi...Self.highestMidi).map { midi in
            let f0 = Pitch.frequency(midi: midi)
            var usable: [(harmonic: Int, own: Window, below: Window, above: Window, weight: Float)] = []
            for h in 1...Tuning.maxHarmonicNumber where usable.count < Tuning.maxHarmonics {
                let hd = Double(h)
                let f = hd * f0 * (1 + Tuning.inharmonicity * hd * hd).squareRoot()
                guard f < topHz else { break }
                guard f * (semitone - 1) / analyzer.binHz >= Tuning.minSemitoneBins else { continue }
                // Weight by order among usable partials, so low notes aren't penalised for skipping harmonics.
                usable.append((h, self.window(around: f), self.neighbourWindow(f / semitone),
                               self.neighbourWindow(f * semitone), 1 / Float(usable.count + 1)))
            }
            return usable
        }
    }

    /// Clears onset memory, e.g. when a new run starts. Keeps the learned noise floor.
    public func resetOnsets() {
        lastOnset = [:]
        disarmed = []
        pendingStrikes = []
        recentExpected = []
        held = []
    }

    /// The app's metronome click reaches the microphone at `time` (stream time, like `currentTime`).
    /// Notes heard while it sounds must still be there once it has died away (`Tuning.clickConfirmDb`),
    /// so the click itself, or a ringing note it makes flicker, isn't heard as a strike.
    public func clickArrives(at time: Double) {
        clicks.append(time)
    }

    public func process(_ samples: [Float]) -> [Event] {
        samples.withUnsafeBufferPointer { process($0) }
    }

    public func process(_ samples: UnsafeBufferPointer<Float>) -> [Event] {
        var events: [Event] = []
        analyzer.process(samples) { events += self.analyzeFrame() }
        return events
    }

    // MARK: - Per frame

    private func analyzeFrame() -> [Event] {
        let time = analyzer.frameTime
        let hopSeconds = Double(Tuning.hopSize) / sampleRate
        let magnitudes = analyzer.magnitudes

        var peak: Float = -120
        var energy: Float = 0
        for k in bandLo...bandHi { energy += magnitudes[k] * magnitudes[k] }
        for k in 0..<binCount {
            magDb[k] = 20 * log10(max(magnitudes[k], 1e-6))
            peak = max(peak, magDb[k])
        }
        peakLevelDb = peak

        updateNoiseFloor(rise: Tuning.noiseFloorRiseDbPerSecond * Float(hopSeconds))
        for k in 0..<binCount { aboveFloor[k] = magDb[k] - floorDb[k] }

        let flux = spectralFlux()
        let energyDb = 10 * log10(max(energy, 1e-12))
        let energyRise = energyDb - previousEnergyDb[0]
        lastFlux = flux
        lastEnergyRise = energyRise
        previousEnergyDb = [previousEnergyDb[1], energyDb]
        previousMagDb[0] = previousMagDb[1]
        previousMagDb[1] = magDb

        // Salience for every pitch, so we can both check expected notes and guess unexpected ones.
        let pitchCount = Self.highestMidi - Self.lowestMidi + 1
        let slot = historyIndex
        for i in 0..<pitchCount {
            history[slot][i] = harmonicSalience(i)
            let level = partialLevel(i)
            var lowest = Float.infinity
            for back in 1...lookbackFrames { lowest = min(lowest, levelHistory[(slot + historyLength - back) % historyLength][i]) }
            levelHistory[slot][i] = level
            levelRiseHistory[slot][i] = level - lowest
        }
        historyIndex = (historyIndex + 1) % historyLength

        guard time >= Tuning.listenWarmup else { return [] }
        var events: [Event] = []

        clicks.removeAll { time > $0 + Tuning.clickMaskAfter }
        let duringClick = clicks.contains { time >= $0 - Tuning.clickMaskBefore }
        if duringClick && levelBeforeClick == nil {
            // The frame before this one still predates the click.
            levelBeforeClick = levelHistory[(slot + historyLength - 1) % historyLength]
        } else if !duringClick, let before = levelBeforeClick {
            levelBeforeClick = nil
            for hold in held {
                let i = hold.midi - Self.lowestMidi
                if levelHistory[slot][i] >= before[i] + Tuning.clickConfirmDb {
                    recentExpected.append(hold.event.onsetTime)
                    events.append(Event(kind: hold.event.kind, onsetTime: hold.event.onsetTime, detectedAt: time))
                } else {
                    lastOnset[hold.midi] = hold.previousOnset
                }
            }
            held = []
        }

        // Expected pitches: salience present and rising sharply.
        for midi in expected.sorted() where (Self.lowestMidi...Self.highestMidi).contains(midi) {
            let now = salience(of: midi)
            let rise = now - minimumRecent(midi)
            if disarmed.contains(midi) {
                guard rise < Tuning.onsetRiseDb / 2 else { continue }
                disarmed.remove(midi)
            }
            guard isPresent(midi, salience: now), rise >= Tuning.onsetRiseDb else { continue }
            // Salience recovering from a dip is not a strike; the partials themselves must get louder.
            guard levelRise(midi) >= Tuning.onsetLevelRiseDb else { continue }
            if let last = lastOnset[midi], time - last < Tuning.onsetRefractory { continue }
            let previousOnset = lastOnset[midi]
            lastOnset[midi] = time
            disarmed.insert(midi)
            let onset = time - Tuning.onsetTimeCorrection
            let event = Event(kind: .expected(midi: midi), onsetTime: onset, detectedAt: time)
            if duringClick {
                held.append((event, midi, previousOnset))
                continue
            }
            recentExpected.append(onset)
            events.append(event)
        }

        // Strikes: broadband spectral change. Report the ones no expected onset accounts for.
        // A strike adds energy; a damper release also changes the spectrum but lowers the level.
        if flux >= Tuning.strikeFluxDb && energyRise >= Tuning.strikeEnergyRiseDb {
            if strikeArmed && time - lastStrike >= Tuning.onsetRefractory && !duringClick {
                pendingStrikes.append((time - Tuning.onsetTimeCorrection, time))
                lastStrike = time
            }
            strikeArmed = false
        } else {
            strikeArmed = true
        }
        recentExpected.removeAll { time - $0 > Tuning.unexpectedWindow + Tuning.unexpectedLateWindow + Tuning.onsetLookback }
        while let strike = pendingStrikes.first, time - strike.detectedAt >= Tuning.unexpectedLateWindow {
            pendingStrikes.removeFirst()
            let explained = recentExpected.contains {
                $0 >= strike.time - Tuning.unexpectedWindow && $0 <= strike.time + Tuning.unexpectedLateWindow
            }
            // Without a pitch it was a knock, cough or page turn, not a wrong note.
            if !explained, let guess = guessPitch() {
                events.append(Event(kind: .unexpected(guess: guess), onsetTime: strike.time, detectedAt: time))
            }
        }
        return events
    }

    private func updateNoiseFloor(rise: Float) {
        // Moving average across neighbouring bins steadies the per-bin noise, then track its minimum over time.
        let radius = Tuning.noiseFloorSmoothingBins
        smoothScratch[0] = 0
        for k in 0..<binCount { smoothScratch[k + 1] = smoothScratch[k] + magDb[k] }
        for k in 0..<binCount {
            let lo = max(0, k - radius), hi = min(binCount - 1, k + radius)
            let local = (smoothScratch[hi + 1] - smoothScratch[lo]) / Float(hi - lo + 1)
            floorDb[k] = floorInitialized ? min(local, floorDb[k] + rise) : local
        }
        floorInitialized = true
    }

    /// Mean positive change in dB versus two frames ago, over the piano's main range.
    private func spectralFlux() -> Float {
        var sum: Float = 0
        for k in bandLo...bandHi {
            // Ignore change in bins that are still near the noise floor.
            guard aboveFloor[k] > 6 else { continue }
            sum += max(0, magDb[k] - previousMagDb[0][k])
        }
        return sum / Float(bandHi - bandLo + 1)
    }

    /// Weighted mean of each partial's contrast (negatives count as 0).
    private func harmonicSalience(_ pitchIndex: Int) -> Float {
        var total: Float = 0
        var weights: Float = 0
        for partial in partials[pitchIndex] {
            total += partial.weight * contrast(partial.own, partial.below, partial.above)
            weights += partial.weight
        }
        return weights > 0 ? total / weights : 0
    }

    /// How far a partial stands out: above the noise floor, and above the spots a semitone either side.
    /// Leakage from a loud neighbouring note, and broadband hammer noise, both give low contrast.
    private func contrast(_ own: Window, _ below: Window, _ above: Window) -> Float {
        let peak = peakDb(own)
        let neighbours = max(peakDb(below), peakDb(above))
        return max(0, min(peak - floorDb[(own.lo + own.hi) / 2], peak - neighbours))
    }

    private func isPresent(_ midi: Int, salience: Float) -> Bool {
        guard salience >= Tuning.pitchPresentDb else { return false }
        // The octave above shares all our even partials. Unless it is expected too, an odd partial must show.
        if !expected.contains(midi + 12) {
            let odd = partials[midi - Self.lowestMidi].lazy.filter { $0.harmonic % 2 == 1 }.prefix(3)
            if !odd.isEmpty && !odd.contains(where: { contrast($0.own, $0.below, $0.above) >= Tuning.partialPresentDb }) {
                return false
            }
        }
        // Octave guard: this note's partials are all even partials of the octave below. If the odd ones
        // in between (1.5·f0, 2.5·f0) also stand out, the octave below was played instead.
        let f0 = Pitch.frequency(midi: midi)
        let explainedByChord = expected.contains(midi - 12) || expected.contains(midi + 7) || expected.contains(midi + 16)
        if !explainedByChord && contrast(at: 1.5 * f0) >= Tuning.partialPresentDb
            && contrast(at: 2.5 * f0) >= Tuning.partialPresentDb {
            return false
        }
        return true
    }

    /// Weighted mean of each partial's peak level in dB (no contrast), so a re-strike shows as a jump
    /// even while the note is still ringing.
    private func partialLevel(_ pitchIndex: Int) -> Float {
        var total: Float = 0
        var weights: Float = 0
        for partial in partials[pitchIndex] {
            total += partial.weight * peakDb(partial.own)
            weights += partial.weight
        }
        return weights > 0 ? total / weights : -120
    }

    /// Largest jump in partial level over the latest lookback, each frame measured against the lookback
    /// before it. Taking the largest lets a detection that lands a few frames after the strike still see it.
    private func levelRise(_ midi: Int) -> Float {
        let i = midi - Self.lowestMidi
        var highest = -Float.infinity
        for back in 1...(lookbackFrames + 1) {
            highest = max(highest, levelRiseHistory[(historyIndex + historyLength - back) % historyLength][i])
        }
        return highest
    }

    /// Smallest salience of `midi` over the lookback frames before the latest one.
    private func minimumRecent(_ midi: Int) -> Float {
        let i = midi - Self.lowestMidi
        var lowest = Float.infinity
        for back in 2...(lookbackFrames + 1) {
            lowest = min(lowest, history[(historyIndex + historyLength - back) % historyLength][i])
        }
        return lowest
    }

    /// The most salient non-expected pitch that recently rose and passes the presence checks.
    private func guessPitch() -> Int? {
        var best: (midi: Int, salience: Float)?
        for midi in Self.lowestMidi...Self.highestMidi where !expected.contains(midi) {
            let now = salience(of: midi)
            guard isPresent(midi, salience: now) else { continue }
            let i = midi - Self.lowestMidi
            var lowest = Float.infinity
            for back in 1..<historyLength {
                lowest = min(lowest, history[(historyIndex + historyLength - back) % historyLength][i])
            }
            guard now - lowest >= Tuning.onsetRiseDb else { continue }
            // High notes have only one or two partials, so a single harmonic of a lower note can mimic them.
            let score = now * min(1, Float(partials[i].count) / 3)
            if score > (best?.salience ?? 0) { best = (midi, score) }
        }
        return best?.midi
    }

    private func contrast(at frequency: Double) -> Float {
        let semitone = pow(2, 1.0 / 12)
        guard frequency * semitone < sampleRate / 2 - analyzer.binHz else { return 0 }
        return contrast(window(around: frequency), neighbourWindow(frequency / semitone), neighbourWindow(frequency * semitone))
    }

    private func peakDb(_ window: Window) -> Float {
        var peak = -Float.infinity
        for k in window.lo...window.hi { peak = max(peak, magDb[k]) }
        return peak
    }

    /// Bins within the partial tolerance of `frequency`, at least one bin either side.
    private func window(around frequency: Double) -> Window {
        bins(around: frequency, cents: Tuning.partialToleranceCents, minimumHalfWidth: 1)
    }

    private func neighbourWindow(_ frequency: Double) -> Window {
        bins(around: frequency, cents: Tuning.neighbourToleranceCents, minimumHalfWidth: 0)
    }

    private func bins(around frequency: Double, cents: Double, minimumHalfWidth: Int) -> Window {
        let ratio = pow(2, cents / 1200)
        let binHz = sampleRate / Double(Tuning.fftSize)
        let center = Int((frequency / binHz).rounded())
        let lo = min(center - minimumHalfWidth, Int((frequency / ratio / binHz).rounded()))
        let hi = max(center + minimumHalfWidth, Int((frequency * ratio / binHz).rounded()))
        return Window(lo: max(1, lo), hi: min(binCount - 1, hi))
    }
}
