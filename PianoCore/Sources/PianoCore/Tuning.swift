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

    // MARK: Detection (M2)

    // MARK: Grading (M4)

    // MARK: Analyzer weights (M5)

    // MARK: Tempo ladder and hint fading (M7)
}
