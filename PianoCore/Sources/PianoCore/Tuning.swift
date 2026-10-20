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

    /// No second onset of the same pitch within this time. Limits how fast a repeated note can be heard.
    public static let onsetRefractory: Double = 0.1

    /// Mean positive spectral change (dB per bin) that counts as "something was struck".
    public static let strikeFluxDb: Float = 2.5

    /// …and the band energy must rise at least this much versus two frames earlier (rules out damper releases).
    public static let strikeEnergyRiseDb: Float = 2

    /// A strike with no expected onset within this window is reported as an unexpected note.
    public static let unexpectedWindow: Double = 0.08

    /// Ignore the first moments after listening starts while the noise floor settles.
    public static let listenWarmup: Double = 0.25

    /// Detection fires part-way through the attack; subtract this to estimate when the key was struck.
    /// Calibrated against synthetic tones in NoteListenerTests.
    public static let onsetTimeCorrection: Double = 0.04

    // MARK: Grading (M4)

    // MARK: Analyzer weights (M5)

    // MARK: Tempo ladder and hint fading (M7)
}
