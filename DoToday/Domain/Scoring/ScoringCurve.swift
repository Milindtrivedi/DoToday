//
//  ScoringCurve.swift
//  DoToday
//
//  Domain layer — pure functions, no dependencies. The most heavily unit-tested
//  type in the app because everything else in the ranking is built from it.
//

import Foundation

/// Maps a raw measurement (°C, mm, km/h …) onto a normalised suitability in 0...1.
///
/// Piecewise-linear rather than a smooth curve: linear ramps are easy to reason
/// about, easy to tune from a product conversation ("surfing should start scoring
/// at 12 km/h"), and easy to assert on in tests.
enum ScoringCurve: Equatable, Sendable {
    /// Ramps up: `zeroAt` scores 0, `oneAt` and above scores 1.
    /// Use for "more is better" inputs such as fresh snowfall.
    case increasing(zeroAt: Double, oneAt: Double)

    /// Ramps down: `oneAt` and below scores 1, `zeroAt` and above scores 0.
    /// Use for "less is better" inputs such as rainfall.
    case decreasing(oneAt: Double, zeroAt: Double)

    /// Trapezoid: 0 below `zeroBelow`, ramping to 1 across `idealFrom...idealTo`,
    /// then back to 0 at `zeroAbove`. Use for "there is a sweet spot" inputs such
    /// as temperature, where both extremes are bad.
    case band(zeroBelow: Double, idealFrom: Double, idealTo: Double, zeroAbove: Double)

    /// `1 - other`. Lets the indoor profile reuse the outdoor comfort definitions
    /// instead of restating them with the numbers flipped, so the two can never
    /// drift apart.
    indirect case inverted(ScoringCurve)

    /// Evaluates the curve, always returning a value clamped to 0...1.
    func score(for value: Double) -> Double {
        switch self {
        case let .increasing(zeroAt, oneAt):
            return Self.ramp(value, from: zeroAt, to: oneAt)

        case let .decreasing(oneAt, zeroAt):
            return 1 - Self.ramp(value, from: oneAt, to: zeroAt)

        case let .band(zeroBelow, idealFrom, idealTo, zeroAbove):
            if value < idealFrom {
                return Self.ramp(value, from: zeroBelow, to: idealFrom)
            } else if value > idealTo {
                return 1 - Self.ramp(value, from: idealTo, to: zeroAbove)
            } else {
                return 1
            }

        case let .inverted(curve):
            return 1 - curve.score(for: value)
        }
    }

    /// Linear interpolation of `value` across `from...to`, clamped to 0...1.
    ///
    /// A zero-width range would divide by zero, so it degenerates to a step:
    /// anything at or beyond the boundary scores 1.
    private static func ramp(_ value: Double, from: Double, to: Double) -> Double {
        let span = to - from
        guard span != 0 else { return value >= to ? 1 : 0 }
        return min(1, max(0, (value - from) / span))
    }
}
