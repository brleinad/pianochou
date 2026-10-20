/// An exact fraction. Score times are Rationals in quarter notes, so triplets stay exact (1/3, not 0.333).
public struct Rational: Hashable, Comparable, Sendable {
    public let numerator: Int
    public let denominator: Int

    public static let zero = Rational(0)

    public init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator != 0, "Rational with zero denominator")
        let divisor = max(Self.gcd(abs(numerator), abs(denominator)), 1)
        let sign = denominator < 0 ? -1 : 1
        self.numerator = sign * numerator / divisor
        self.denominator = sign * denominator / divisor
    }

    public var doubleValue: Double { Double(numerator) / Double(denominator) }

    public static func + (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator)
    }

    public static func - (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.denominator - b.numerator * a.denominator, a.denominator * b.denominator)
    }

    public static func * (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.numerator, a.denominator * b.denominator)
    }

    public static func / (a: Rational, b: Rational) -> Rational {
        Rational(a.numerator * b.denominator, a.denominator * b.numerator)
    }

    public static func < (a: Rational, b: Rational) -> Bool {
        a.numerator * b.denominator < b.numerator * a.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

extension Rational: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self.init(value) }
}

extension Rational: CustomStringConvertible {
    public var description: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }
}
