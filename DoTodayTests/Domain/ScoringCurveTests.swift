//
//  ScoringCurveTests.swift
//  DoTodayTests
//
//  `ScoringCurve` is the primitive every activity score is built from, so it is
//  tested exhaustively — including the clamping and degenerate cases that would
//  otherwise silently produce out-of-range scores further up the stack.
//

import Testing
@testable import DoToday

@Suite("ScoringCurve")
struct ScoringCurveTests {

    // MARK: increasing

    @Test("Increasing curve ramps linearly and clamps at both ends", arguments: [
        (value: -5.0, expected: 0.0),   // below the zero point
        (value: 0.0, expected: 0.0),    // at the zero point
        (value: 5.0, expected: 0.5),    // midpoint
        (value: 10.0, expected: 1.0),   // at the one point
        (value: 50.0, expected: 1.0)    // far beyond: clamped, never > 1
    ])
    func increasing(value: Double, expected: Double) {
        let curve = ScoringCurve.increasing(zeroAt: 0, oneAt: 10)
        #expect(isApproximately(curve.score(for: value), expected))
    }

    // MARK: decreasing

    @Test("Decreasing curve is the mirror of increasing", arguments: [
        (value: -5.0, expected: 1.0),
        (value: 0.0, expected: 1.0),
        (value: 5.0, expected: 0.5),
        (value: 10.0, expected: 0.0),
        (value: 99.0, expected: 0.0)
    ])
    func decreasing(value: Double, expected: Double) {
        let curve = ScoringCurve.decreasing(oneAt: 0, zeroAt: 10)
        #expect(isApproximately(curve.score(for: value), expected))
    }

    // MARK: band

    @Test("Band curve scores 1 across its plateau and falls away on both sides", arguments: [
        (value: -30.0, expected: 0.0),  // far below
        (value: -10.0, expected: 0.0),  // at the lower zero
        (value: 0.0, expected: 0.5),    // rising edge midpoint
        (value: 10.0, expected: 1.0),   // start of plateau
        (value: 15.0, expected: 1.0),   // inside plateau
        (value: 20.0, expected: 1.0),   // end of plateau
        (value: 25.0, expected: 0.5),   // falling edge midpoint
        (value: 30.0, expected: 0.0),   // at the upper zero
        (value: 99.0, expected: 0.0)    // far above
    ])
    func band(value: Double, expected: Double) {
        let curve = ScoringCurve.band(zeroBelow: -10, idealFrom: 10, idealTo: 20, zeroAbove: 30)
        #expect(isApproximately(curve.score(for: value), expected))
    }

    // MARK: inverted

    @Test("Inverted curve returns exactly 1 minus the wrapped curve")
    func inverted() {
        let base = ScoringCurve.band(zeroBelow: 0, idealFrom: 10, idealTo: 20, zeroAbove: 30)
        let inverted = ScoringCurve.inverted(base)

        for value in stride(from: -10.0, through: 40.0, by: 2.5) {
            #expect(isApproximately(inverted.score(for: value), 1 - base.score(for: value)))
        }
    }

    // MARK: edge cases

    @Test("A zero-width ramp degenerates to a step instead of dividing by zero")
    func zeroWidthRange() {
        let curve = ScoringCurve.increasing(zeroAt: 5, oneAt: 5)
        #expect(curve.score(for: 4.9) == 0)
        #expect(curve.score(for: 5) == 1)
        #expect(curve.score(for: 5.1) == 1)
    }

    @Test("Every curve stays within 0...1 across a wide input sweep")
    func alwaysNormalised() {
        let curves: [ScoringCurve] = [
            .increasing(zeroAt: 0, oneAt: 5),
            .decreasing(oneAt: 0, zeroAt: 8),
            .band(zeroBelow: -20, idealFrom: 0, idealTo: 10, zeroAbove: 40),
            .inverted(.band(zeroBelow: -20, idealFrom: 0, idealTo: 10, zeroAbove: 40))
        ]

        for curve in curves {
            for value in stride(from: -1_000.0, through: 1_000.0, by: 37) {
                let score = curve.score(for: value)
                #expect(score >= 0 && score <= 1, "\(curve) produced \(score) for \(value)")
            }
        }
    }
}
