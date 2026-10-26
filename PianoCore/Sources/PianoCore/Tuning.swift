import Foundation

/// Every tunable number in the app lives here, with a comment saying what it does.
/// It sits in PianoCore so both the pure logic and the app (audio, UI) can read it.
/// Values are starting guesses until tested on a real piano; change them here, nowhere else.
public enum Tuning {

    // MARK: Session

    /// Target length of a daily practice session, in minutes (CLAUDE.md: ~15–25).
    public static let sessionMinutes: ClosedRange<Double> = 15...25

    /// Snippets alternated in one session, not counting the opening review.
    public static let snippetsPerSession: ClosedRange<Int> = 2...3

    // MARK: Listening (M2)

    /// Concert pitch of A4. Home pianos are often a little flat; the partial tolerance absorbs ~±40 cents.
    public static let referencePitchHz: Double = 440

    /// FFT window in samples. 4096 at 48 kHz = 85 ms, 11.7 Hz per bin. Bigger resolves bass better but reacts slower.
    public static let fftSize = 4096

    /// Samples between analysis frames. 512 at 48 kHz ≈ 10.7 ms, the time resolution of onsets.
    public static let hopSize = 512

    /// Partials summed per pitch, the highest harmonic number tried, and the highest frequency considered.
    public static let maxHarmonics = 8
    public static let maxHarmonicNumber = 24
    public static let maxPartialHz: Double = 6000

    /// A partial is only used when a semitone at its frequency spans at least this many FFT bins;
    /// closer than that, neighbouring notes blur together. Low notes therefore rely on higher harmonics.
    public static let minSemitoneBins: Double = 2.5

    /// Width of the "neighbour" windows a semitone either side, used to measure a partial's contrast.
    public static let neighbourToleranceCents: Double = 20

    /// How far from the ideal harmonic frequency a peak may sit (detuning + string inharmonicity).
    public static let partialToleranceCents: Double = 40

    /// Piano string inharmonicity B: partial h sits at h·f0·√(1 + B·h²). Mid-range typical value.
    public static let inharmonicity: Double = 0.0004

    /// Neighbouring bins averaged into the noise floor estimate (each side).
    public static let noiseFloorSmoothingBins = 12

    /// How fast the noise floor may rise when the room gets louder (it falls instantly).
    public static let noiseFloorRiseDbPerSecond: Float = 3

    /// A partial counts as present when it stands this far above both the noise floor and the spots
    /// a semitone either side of it (its contrast).
    public static let partialPresentDb: Float = 12

    /// A pitch "sounds" when its salience (weighted mean partial contrast, dB) reaches this.
    public static let pitchPresentDb: Float = 10

    /// An onset needs the pitch's salience to jump by this much within `onsetLookback`.
    public static let onsetRiseDb: Float = 6
    public static let onsetLookback: Double = 0.06

    /// …and the raw level of its partials must have jumped by this much (peak over the lookback versus
    /// the lookback before it). Salience alone wavers while a note rings (beating, dampers, pedal noise)
    /// and dips-and-recovers look like onsets; a real hammer strike adds 20–35 dB, wavering adds ~1–2 dB.
    public static let onsetLevelRiseDb: Float = 4

    /// No second onset of the same pitch within this time. Limits how fast a repeated note can be heard.
    public static let onsetRefractory: Double = 0.1

    /// Mean positive spectral change (dB per bin) that counts as "something was struck".
    public static let strikeFluxDb: Float = 2.5

    /// …and the band energy must rise at least this much versus two frames earlier (rules out damper releases).
    public static let strikeEnergyRiseDb: Float = 2

    /// A strike with no expected onset within this window is reported as an unexpected note.
    public static let unexpectedWindow: Double = 0.08

    /// Expected onsets this long after a strike still explain it. A key click comes ~50 ms before the
    /// hammer, and the expected pitch is confirmed a few frames after that.
    public static let unexpectedLateWindow: Double = 0.16

    /// Ignore the first moments after listening starts while the noise floor settles.
    public static let listenWarmup: Double = 0.25

    /// Detection fires part-way through the attack; subtract this to estimate when the key was struck.
    /// Calibrated against synthetic tones in NoteListenerTests.
    public static let onsetTimeCorrection: Double = 0.04

    // MARK: Staff drawing (M3). Lengths in staff spaces (the gap between two staff lines).

    /// Horizontal room after a quarter note; other values scale by (duration in quarters)^exponent,
    /// so a half note gets ~1.7× a quarter's room rather than 2×.
    public static let quarterNoteSpace: Double = 3.6
    public static let noteSpaceExponent: Double = 0.75
    /// Never less room than this after a note (fast 16ths).
    public static let minimumNoteSpace: Double = 2.0

    /// Normal stem length, measured from the notehead centre.
    public static let stemLength: Double = 3.5
    /// Shortest stem allowed under a beam.
    public static let minimumBeamedStem: Double = 2.75
    /// Steepest beam, as total rise across the group.
    public static let maximumBeamRise: Double = 1.0
    public static let beamThickness: Double = 0.5
    /// Distance between stacked beams (8th to 16th), edge to edge.
    public static let beamGap: Double = 0.25

    /// Empty space between the two staves of a grand staff, beyond what notes and stems need.
    public static let staffGapMin: Double = 6

    /// Finger numbers and beat counts, as font sizes.
    public static let fingerTextSize: Double = 1.4
    public static let countTextSize: Double = 1.3

    // MARK: Grading (M4)

    /// Notes of one chord may arrive this far apart (rolled chords, hands not quite together)
    /// and still count as one chord. Also: a repeat of a just-played pitch within this time is an echo.
    public static let chordSpread: Double = 0.12

    /// Drills only: a chord is early or late when it is off by more than this fraction of the gap
    /// since the previous chord, and by at least `timingToleranceSeconds`. Timing is judged from the
    /// previous chord actually played, so one hesitation doesn't make everything after it late.
    public static let timingToleranceFraction: Double = 0.25
    public static let timingToleranceSeconds: Double = 0.12

    /// A run ends when nothing has been played for this long after the next note was due.
    public static let silenceGrace: Double = 1.5

    // MARK: Tempo and metronome

    /// Practice tempos, in quarter notes per minute, and the step of the − / + buttons.
    public static let tempoRange: ClosedRange<Double> = 30...240
    public static let tempoStep: Double = 5
    /// "Slower" after a run: about this much of the tempo, rounded down to a step.
    public static let slowerFactor: Double = 0.9

    /// The click: a short sine burst well above `maxPartialHz` (and the 5 kHz strike band), so the
    /// listener ignores it. Mixed into two real piano recordings at up to -3 dBFS, 8–10 kHz clicks added
    /// no detections and hid none; low "woodblock" or noise clicks added many.
    public static let metronomeClickHz: Double = 9000
    /// The first beat of the bar: higher and louder.
    public static let metronomeAccentHz: Double = 10000
    /// Peak level of the accented click (full scale = 1), and the other beats relative to it.
    public static let metronomeVolume: Double = 0.5
    public static let metronomeOffbeatLevel: Double = 0.55
    /// Length, fade-in and decay time constant of a click, in seconds. The fade-in keeps the burst's
    /// energy out of the analysed band (a hard start splatters across all frequencies).
    public static let metronomeClickSeconds: Double = 0.04
    public static let metronomeClickAttack: Double = 0.0015
    public static let metronomeClickDecay: Double = 0.006

    // MARK: Analyzer weights (M5)

    // MARK: Tempo ladder and hint fading (M7)
}
