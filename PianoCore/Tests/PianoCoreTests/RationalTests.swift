import Testing
@testable import PianoCore

@Suite struct RationalTests {
    @Test func reducesAndNormalizesSign() {
        #expect(Rational(2, 4) == Rational(1, 2))
        #expect(Rational(3, -6) == Rational(-1, 2))
        #expect(Rational(0, 5) == .zero)
    }

    @Test func arithmetic() {
        #expect(Rational(1, 3) + Rational(1, 6) == Rational(1, 2))
        #expect(Rational(1, 2) - Rational(3, 4) == Rational(-1, 4))
        #expect(Rational(2, 3) * Rational(3, 4) == Rational(1, 2))
        #expect(Rational(1, 2) / Rational(1, 4) == 2)
    }

    @Test func ordering() {
        #expect(Rational(1, 3) < Rational(1, 2))
        #expect(Rational(2, 3).doubleValue == 2.0 / 3.0)
    }
}
