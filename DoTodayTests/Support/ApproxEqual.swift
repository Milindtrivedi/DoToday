//
//  ApproxEqual.swift
//  DoTodayTests
//

import Foundation

/// Floating-point comparison helper. Scores are derived from divisions, so exact
/// equality would make the tests brittle for no benefit.
func isApproximately(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
    abs(lhs - rhs) <= tolerance
}
