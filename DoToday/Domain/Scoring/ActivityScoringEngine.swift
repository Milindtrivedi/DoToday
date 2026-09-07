//
//  ActivityScoringEngine.swift
//  DoToday
//
//  Domain layer — turns a forecast into a ranking. Pure and synchronous, which makes
//  it exhaustively unit-testable without any test doubles at all.
//

import Foundation

protocol ActivityScoringEngine: Sendable {
    /// Ranks every activity for a city over the supplied forecast, best first.
    func rank(forecast: Forecast, for city: City) -> [ActivityRanking]
}

struct DefaultActivityScoringEngine: ActivityScoringEngine {

    /// How much the week's *best* day counts relative to its average.
    ///
    /// A pure average buries a location that has one perfect powder day in an
    /// otherwise mild week; a pure maximum treats a single good day as a great week.
    /// 60/40 keeps consistency in front while still rewarding a standout day.
    private let bestDayWeight: Double
    private let profiles: [Activity: ActivityScoringProfile]

    init(
        profiles: [Activity: ActivityScoringProfile] = ActivityScoringProfile.all,
        bestDayWeight: Double = 0.4
    ) {
        self.profiles = profiles
        self.bestDayWeight = min(1, max(0, bestDayWeight))
    }

    func rank(forecast: Forecast, for city: City) -> [ActivityRanking] {
        Activity.allCases
            .map { ranking(for: $0, forecast: forecast, city: city) }
            .sorted { lhs, rhs in
                // Ties are broken by title so the order is stable across launches —
                // an unstable sort would make the list jitter on refresh.
                if lhs.overallScore == rhs.overallScore {
                    return lhs.activity.title < rhs.activity.title
                }
                return lhs.overallScore > rhs.overallScore
            }
    }

    private func ranking(for activity: Activity, forecast: Forecast, city: City) -> ActivityRanking {
        let profile = profiles[activity] ?? ActivityScoringProfile.profile(for: activity)
        let feasibility = LocationFeasibility.multiplier(for: activity, at: city)

        let dailyScores = forecast.days.map { day in
            DailyActivityScore(
                date: day.date,
                score: dailyScore(for: day, profile: profile) * feasibility,
                weather: day
            )
        }

        return ActivityRanking(
            activity: activity,
            overallScore: weeklyScore(from: dailyScores.map(\.score)),
            dailyScores: dailyScores
        )
    }

    /// Scores one day for one activity:
    ///
    ///     score = (baseline + (1 - baseline) x weightedAverage) x limiters
    ///
    /// The weighted average is re-normalised over the criteria that actually had data.
    /// That matters: if `snowfall_sum` is missing, skiing is judged on the remaining
    /// weights rather than being handed a silent penalty for a value we never received.
    ///
    /// Limiters then apply the profile's necessary conditions multiplicatively, so an
    /// activity that is simply not possible cannot accumulate points from the factors
    /// it does happen to satisfy.
    func dailyScore(for weather: DailyWeather, profile: ActivityScoringProfile) -> Double {
        var weightedSum = 0.0
        var totalWeight = 0.0

        for criterion in profile.criteria {
            guard let score = criterion.score(for: weather) else { continue }
            weightedSum += score * criterion.weight
            totalWeight += criterion.weight
        }

        // No usable measurements at all: we have no evidence for the activity, so we
        // fall back to the profile's baseline rather than inventing a score.
        let weighted = totalWeight > 0 ? weightedSum / totalWeight : 0
        let base = totalWeight > 0
            ? profile.baseline + (1 - profile.baseline) * weighted
            : profile.baseline

        // A missing limiter measurement is 1: we have no evidence on which to rule the
        // activity out, and guessing 0 would hide the activity for a data gap alone.
        let limiter = profile.limitingCriteria.reduce(1.0) { product, criterion in
            product * (criterion.score(for: weather) ?? 1)
        }

        return base * limiter
    }

    /// Blends the mean and the maximum of the daily scores.
    func weeklyScore(from dailyScores: [Double]) -> Double {
        guard !dailyScores.isEmpty else { return 0 }
        let mean = dailyScores.reduce(0, +) / Double(dailyScores.count)
        let best = dailyScores.max() ?? 0
        return (1 - bestDayWeight) * mean + bestDayWeight * best
    }
}
