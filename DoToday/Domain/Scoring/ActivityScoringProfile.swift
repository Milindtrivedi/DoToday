//
//  ActivityScoringProfile.swift
//  DoToday
//
//  Domain layer — the tunable "rules of the game". All product judgement about what
//  makes a good day for an activity lives here and nowhere else.
//

import Foundation

/// The weighted criteria that define one activity's daily suitability.
struct ActivityScoringProfile: Sendable {
    let activity: Activity
    /// Contributing factors, combined as a weighted average. More of a good thing
    /// raises the score; a bad one lowers it.
    let criteria: [ScoringCriterion]

    /// Necessary conditions, applied as *multipliers* on the weighted result.
    ///
    /// Some factors are not "nice to have" — they are prerequisites. A calm, dry week
    /// at 25 °C is a fine week, but it is not a skiing week, and a purely additive
    /// model would still award skiing the points it earned for low wind and no rain.
    /// A limiting criterion that scores 0 drives the whole activity to 0, which is the
    /// only honest answer.
    ///
    /// A limiting criterion whose measurement is missing is treated as 1 (no
    /// evidence to limit on), consistent with how missing weighted criteria are dropped.
    let limitingCriteria: [ScoringCriterion]
    /// Floor applied to the weighted result: `baseline + (1 - baseline) * weighted`.
    ///
    /// Only indoor sightseeing uses a non-zero baseline — a museum is a decent plan
    /// in any weather, so its score should never collapse to zero on a nice day; it
    /// should merely lose to the outdoor options.
    let baseline: Double

    init(
        activity: Activity,
        baseline: Double = 0,
        criteria: [ScoringCriterion],
        limitingCriteria: [ScoringCriterion] = []
    ) {
        self.activity = activity
        self.baseline = baseline
        self.criteria = criteria
        self.limitingCriteria = limitingCriteria
    }
}

// MARK: - The four profiles

extension ActivityScoringProfile {

    /// Registry of every profile. Built from `Activity.allCases` with an exhaustive
    /// `switch`, so adding a case to `Activity` is a compile error until it is scored.
    static let all: [Activity: ActivityScoringProfile] = Dictionary(
        uniqueKeysWithValues: Activity.allCases.map { ($0, profile(for: $0)) }
    )

    static func profile(for activity: Activity) -> ActivityScoringProfile {
        switch activity {
        case .skiing: return .skiing
        case .surfing: return .surfing
        case .outdoorSightseeing: return .outdoorSightseeing
        case .indoorSightseeing: return .indoorSightseeing
        }
    }

    /// Skiing wants fresh snow, calm-enough weather to keep lifts running, and no rain
    /// (which ruins the surface).
    ///
    /// Temperature is a *limiting* criterion rather than a contributing one: snow does
    /// not survive a 25 °C afternoon, so a warm week must score near zero however
    /// pleasant it is in every other respect. Fresh snowfall stays a contributing
    /// factor, not a prerequisite — resorts run on an existing base, so a cold, dry
    /// week is a plausible ski week even with no new snow in the forecast.
    static let skiing = ActivityScoringProfile(
        activity: .skiing,
        criteria: [
            ScoringCriterion("Fresh snowfall", weight: 0.45,
                             curve: .increasing(zeroAt: 0, oneAt: 5)) { $0.snowfallSum },
            ScoringCriterion("Wind", weight: 0.30,
                             curve: .decreasing(oneAt: 15, zeroAt: 55)) { $0.windSpeedMax },
            // Rain, not total precipitation: snow is the point, rain is the problem.
            ScoringCriterion("Rain", weight: 0.25,
                             curve: .decreasing(oneAt: 0, zeroAt: 8)) { $0.rainSum }
        ],
        limitingCriteria: [
            ScoringCriterion("Cold enough to hold snow", weight: 1,
                             curve: .band(zeroBelow: -25, idealFrom: -12, idealTo: 2, zeroAbove: 8)) { $0.temperatureMax }
        ]
    )

    /// The forecast API carries no wave data, so sustained wind is our swell proxy:
    /// too little means flat, too much means blown out. See README for this trade-off.
    static let surfing = ActivityScoringProfile(
        activity: .surfing,
        criteria: [
            ScoringCriterion("Wind (swell proxy)", weight: 0.35,
                             curve: .band(zeroBelow: 2, idealFrom: 11, idealTo: 26, zeroAbove: 45)) { $0.windSpeedMax },
            ScoringCriterion("Air temperature", weight: 0.25,
                             curve: .band(zeroBelow: 2, idealFrom: 16, idealTo: 30, zeroAbove: 40)) { $0.temperatureMax },
            // Gusts are what make a swell messy, so they are penalised separately.
            ScoringCriterion("Gusts", weight: 0.20,
                             curve: .decreasing(oneAt: 30, zeroAt: 75)) { $0.windGustsMax },
            ScoringCriterion("Rain", weight: 0.20,
                             curve: .decreasing(oneAt: 0, zeroAt: 12)) { $0.rainSum }
        ],
        limitingCriteria: [
            // Nobody paddles out through ice. Below this the water is unusable
            // whatever the swell is doing.
            ScoringCriterion("Warm enough to paddle out", weight: 1,
                             curve: .increasing(zeroAt: 0, oneAt: 8)) { $0.temperatureMax }
        ]
    )

    /// Walking around outside: comfortable "feels like" temperature, dry, sunny, calm.
    static let outdoorSightseeing = ActivityScoringProfile(
        activity: .outdoorSightseeing,
        criteria: [
            ScoringCriterion("Feels-like temperature", weight: 0.30,
                             curve: .band(zeroBelow: -8, idealFrom: 15, idealTo: 26, zeroAbove: 38)) { $0.apparentTemperatureMax },
            ScoringCriterion("Chance of precipitation", weight: 0.25,
                             curve: .decreasing(oneAt: 10, zeroAt: 80)) { $0.precipitationProbabilityMax },
            ScoringCriterion("Precipitation amount", weight: 0.20,
                             curve: .decreasing(oneAt: 0, zeroAt: 10)) { $0.precipitationSum },
            ScoringCriterion("Sunshine", weight: 0.15,
                             curve: .increasing(zeroAt: 0.1, oneAt: 0.7)) { $0.sunshineFraction },
            ScoringCriterion("Wind", weight: 0.10,
                             curve: .decreasing(oneAt: 14, zeroAt: 50)) { $0.windSpeedMax }
        ]
    )

    /// The mirror image of outdoor sightseeing: the worse it is outside, the better a
    /// gallery looks. Curves are literally `.inverted` versions of the outdoor ones so
    /// the two profiles cannot disagree about what "bad weather" means.
    static let indoorSightseeing = ActivityScoringProfile(
        activity: .indoorSightseeing,
        // A museum is never a *bad* idea; it just shouldn't beat a perfect blue-sky day.
        baseline: 0.45,
        criteria: [
            ScoringCriterion("Precipitation amount", weight: 0.35,
                             curve: .increasing(zeroAt: 0, oneAt: 8)) { $0.precipitationSum },
            ScoringCriterion("Chance of precipitation", weight: 0.25,
                             curve: .increasing(zeroAt: 20, oneAt: 85)) { $0.precipitationProbabilityMax },
            ScoringCriterion("Uncomfortable temperature", weight: 0.25,
                             curve: .inverted(.band(zeroBelow: -8, idealFrom: 15, idealTo: 26, zeroAbove: 38))) { $0.apparentTemperatureMax },
            ScoringCriterion("Wind", weight: 0.15,
                             curve: .increasing(zeroAt: 18, oneAt: 55)) { $0.windSpeedMax }
        ]
    )
}
