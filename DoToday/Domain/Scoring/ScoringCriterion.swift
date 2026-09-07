//
//  ScoringCriterion.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// One weighted weather input contributing to an activity's daily score.
///
/// `measurement` is a closure rather than a `KeyPath` so a criterion can read a
/// derived value (e.g. `sunshineFraction`) as easily as a stored one.
struct ScoringCriterion: Sendable {
    /// Developer-facing label, surfaced in test failures and debug output.
    let name: String
    /// Relative importance within the activity's profile. Weights need not sum to 1;
    /// the engine normalises them, which is what allows missing inputs to be dropped.
    let weight: Double
    /// Extracts the raw measurement. Returns `nil` when the API omitted the value.
    let measurement: @Sendable (DailyWeather) -> Double?
    let curve: ScoringCurve

    init(
        _ name: String,
        weight: Double,
        curve: ScoringCurve,
        measurement: @escaping @Sendable (DailyWeather) -> Double?
    ) {
        self.name = name
        self.weight = weight
        self.curve = curve
        self.measurement = measurement
    }

    /// The criterion's contribution, or `nil` when its input is unavailable.
    func score(for weather: DailyWeather) -> Double? {
        measurement(weather).map(curve.score(for:))
    }
}
