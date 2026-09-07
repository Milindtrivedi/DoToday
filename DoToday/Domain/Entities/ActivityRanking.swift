//
//  ActivityRanking.swift
//  DoToday
//
//  Domain layer — the output of the ranking use case.
//

import Foundation

/// How suitable an activity is on one specific day.
struct DailyActivityScore: Equatable, Identifiable {
    let date: Date
    /// 0...1, where 1 is a perfect day for the activity.
    let score: Double
    /// The weather this score was derived from, so the UI can explain itself
    /// without a second lookup.
    let weather: DailyWeather

    var id: Date { date }
}

/// An activity's suitability across the whole forecast window.
struct ActivityRanking: Equatable, Identifiable {
    let activity: Activity
    /// 0...1 aggregate over the window. See `ActivityScoringEngine.weeklyScore`.
    let overallScore: Double
    /// Per-day scores in chronological order.
    let dailyScores: [DailyActivityScore]

    var id: Activity { activity }

    /// The single best day in the window, used for the "Best day" summary line.
    var bestDay: DailyActivityScore? {
        dailyScores.max { $0.score < $1.score }
    }
}

/// Everything the recommendations screen needs: the place, the forecast it was
/// derived from, and the activities ordered best-first.
struct RankedRecommendations: Equatable {
    let city: City
    let forecast: Forecast
    /// Sorted by `overallScore`, descending.
    let rankings: [ActivityRanking]
    /// True when the forecast came from cache rather than the network.
    let isStale: Bool
}
