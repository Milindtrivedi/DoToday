//
//  ActivityScoringEngineTests.swift
//  DoTodayTests
//
//  Tests the ranking rules themselves: that the right activity wins for the right
//  weather, that missing data is handled without distorting the result, and that the
//  weekly aggregation behaves as specified.
//

import Foundation
import Testing
@testable import DoToday

@Suite("ActivityScoringEngine")
struct ActivityScoringEngineTests {

    private let engine = DefaultActivityScoringEngine()

    // MARK: Behaviour that matters to a user

    @Test("A cold, snowy week in the mountains ranks skiing first")
    func snowyMountainWeekFavoursSkiing() {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7, template: Fixture.perfectSkiDay))
        let alpineTown = Fixture.city(name: "Chamonix", elevation: 1_035)

        let rankings = engine.rank(forecast: forecast, for: alpineTown)

        #expect(rankings.first?.activity == .skiing)
    }

    @Test("A warm, dry, sunny week ranks outdoor sightseeing first")
    func fineWeekFavoursOutdoorSightseeing() {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7, template: Fixture.perfectSightseeingDay))

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())

        #expect(rankings.first?.activity == .outdoorSightseeing)
    }

    @Test("A cold, wet, windy week ranks indoor sightseeing above outdoor")
    func miserableWeekFavoursIndoorOverOutdoor() throws {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7, template: Fixture.miserableDay))

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())
        let indoor = try #require(rankings.first { $0.activity == .indoorSightseeing })
        let outdoor = try #require(rankings.first { $0.activity == .outdoorSightseeing })

        #expect(indoor.overallScore > outdoor.overallScore)
    }

    @Test("Indoor sightseeing never drops below its baseline, even in perfect weather")
    func indoorHasAFloor() throws {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7, template: Fixture.perfectSightseeingDay))

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())
        let indoor = try #require(rankings.first { $0.activity == .indoorSightseeing })

        #expect(indoor.overallScore >= ActivityScoringProfile.indoorSightseeing.baseline)
    }

    @Test("Every activity is always ranked, and always within 0...1")
    func rankingIsCompleteAndNormalised() {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7))

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())

        #expect(rankings.count == Activity.allCases.count)
        #expect(Set(rankings.map(\.activity)) == Set(Activity.allCases))
        for ranking in rankings {
            #expect(ranking.overallScore >= 0 && ranking.overallScore <= 1)
            #expect(ranking.dailyScores.allSatisfy { $0.score >= 0 && $0.score <= 1 })
        }
    }

    @Test("Rankings come back sorted best-first")
    func rankingsAreSortedDescending() {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7, template: Fixture.perfectSkiDay))

        let scores = engine.rank(forecast: forecast, for: Fixture.city(elevation: 1_500)).map(\.overallScore)

        #expect(scores == scores.sorted(by: >))
    }

    @Test("One score per forecast day, in the forecast's own order")
    func producesOneScorePerDay() {
        let days = Fixture.days(count: 7)
        let forecast = Fixture.forecast(days: days)

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())

        for ranking in rankings {
            #expect(ranking.dailyScores.map(\.date) == days.map(\.date))
        }
    }

    @Test("Best day reports the highest-scoring day in the window")
    func bestDayIsTheHighestScoringDay() throws {
        // Six washouts and one glorious day in the middle.
        var days = Fixture.days(count: 7, template: Fixture.miserableDay)
        let standoutDate = days[3].date
        days[3] = Fixture.day(
            date: standoutDate,
            weatherCode: .clear,
            temperatureMax: 22, apparentTemperatureMax: 21,
            precipitationSum: 0, rainSum: 0, snowfallSum: 0,
            precipitationProbabilityMax: 0, windSpeedMax: 5, windGustsMax: 10,
            sunshineDuration: 40_000, daylightDuration: 45_000
        )
        let forecast = Fixture.forecast(days: days)

        let rankings = engine.rank(forecast: forecast, for: Fixture.city())
        let outdoor = try #require(rankings.first { $0.activity == .outdoorSightseeing })

        #expect(outdoor.bestDay?.date == standoutDate)
    }

    // MARK: Missing data

    @Test("A missing measurement is dropped, not treated as zero")
    func missingDataIsExcludedRatherThanPenalised() {
        // Two identical perfect ski days, except one has no snowfall reading at all.
        let withSnowfall = Fixture.perfectSkiDay
        let withoutSnowfall = Fixture.day(
            weatherCode: .snow,
            temperatureMax: -5, apparentTemperatureMax: -9,
            precipitationSum: 8, rainSum: 0, snowfallSum: nil,
            precipitationProbabilityMax: 90, windSpeedMax: 8, windGustsMax: 15,
            sunshineDuration: 10_000, daylightDuration: 30_000
        )

        let profile = ActivityScoringProfile.skiing
        let scoreWithData = engine.dailyScore(for: withSnowfall, profile: profile)
        let scoreWithoutData = engine.dailyScore(for: withoutSnowfall, profile: profile)

        // The remaining criteria are all perfect, so dropping snowfall must leave the
        // score at 1 — a zero-substitution bug would drag it down to ~0.55.
        #expect(isApproximately(scoreWithData, 1.0))
        #expect(isApproximately(scoreWithoutData, 1.0))
    }

    @Test("A day with no usable measurements falls back to the profile's baseline")
    func noDataFallsBackToBaseline() {
        let empty = Fixture.day(
            temperatureMax: nil, apparentTemperatureMax: nil,
            precipitationSum: nil, rainSum: nil, snowfallSum: nil,
            precipitationProbabilityMax: nil, windSpeedMax: nil, windGustsMax: nil,
            sunshineDuration: nil, daylightDuration: nil
        )

        #expect(engine.dailyScore(for: empty, profile: .outdoorSightseeing) == 0)
        #expect(engine.dailyScore(for: empty, profile: .indoorSightseeing)
                == ActivityScoringProfile.indoorSightseeing.baseline)
    }

    // MARK: Limiting criteria (necessary conditions)

    @Test("A warm week scores skiing at zero, however good the other conditions are")
    func warmWeatherRulesOutSkiing() {
        // Calm, dry, 25 C. Every contributing skiing criterion except snowfall is
        // perfect, so a purely additive model would still award it ~55%.
        let warmAndCalm = Fixture.day(
            temperatureMax: 25, apparentTemperatureMax: 24,
            precipitationSum: 0, rainSum: 0, snowfallSum: 0,
            precipitationProbabilityMax: 0, windSpeedMax: 5, windGustsMax: 10
        )

        #expect(engine.dailyScore(for: warmAndCalm, profile: .skiing) == 0)
    }

    @Test("A freezing week scores surfing at zero, however good the swell looks")
    func freezingWaterRulesOutSurfing() {
        let freezingButBreezy = Fixture.day(
            temperatureMax: -2, apparentTemperatureMax: -6,
            precipitationSum: 0, rainSum: 0, snowfallSum: 0,
            precipitationProbabilityMax: 0, windSpeedMax: 18, windGustsMax: 28
        )

        #expect(engine.dailyScore(for: freezingButBreezy, profile: .surfing) == 0)
    }

    @Test("A cold, snowless week still allows skiing on the existing base")
    func coldButSnowlessWeekIsStillPlausibleSkiing() {
        // Deliberately not zero: resorts run on a base, so "no fresh snow" is a
        // reduction, not a disqualification. Only warmth disqualifies.
        let coldAndDry = Fixture.day(
            temperatureMax: -4, apparentTemperatureMax: -8,
            precipitationSum: 0, rainSum: 0, snowfallSum: 0,
            precipitationProbabilityMax: 0, windSpeedMax: 8, windGustsMax: 15
        )

        let score = engine.dailyScore(for: coldAndDry, profile: .skiing)
        #expect(score > 0.4 && score < 0.7)
    }

    @Test("A limiter with no data does not silently zero the activity")
    func missingLimiterDataIsNeutral() {
        // Temperature is skiing's limiter. Without it we cannot rule skiing out, so
        // the score must come from the contributing criteria alone.
        let noTemperature = Fixture.day(
            temperatureMax: nil, apparentTemperatureMax: nil,
            precipitationSum: 6, rainSum: 0, snowfallSum: 15,
            precipitationProbabilityMax: 90, windSpeedMax: 8, windGustsMax: 15
        )

        #expect(isApproximately(engine.dailyScore(for: noTemperature, profile: .skiing), 1.0))
    }

    @Test("Limiters scale continuously rather than switching hard at a threshold")
    func limitersDegradeSmoothly() {
        let profile = ActivityScoringProfile.skiing
        let scores = [0.0, 3.0, 5.0, 7.0].map { temperature in
            engine.dailyScore(
                for: Fixture.day(temperatureMax: temperature, rainSum: 0, snowfallSum: 10, windSpeedMax: 5),
                profile: profile
            )
        }

        // 0 C is inside the ideal band; the score then tapers away towards 8 C.
        #expect(scores == scores.sorted(by: >))
        #expect(scores.first! > 0.9)
        #expect(scores.last! < 0.2)
    }

    // MARK: Weekly aggregation

    @Test("Weekly score blends the mean with the best day at 60/40")
    func weeklyScoreBlendsMeanAndBest() {
        let engine = DefaultActivityScoringEngine(bestDayWeight: 0.4)
        let daily = [0.0, 0.0, 0.0, 0.0, 1.0]   // mean 0.2, best 1.0

        // 0.6 * 0.2 + 0.4 * 1.0
        #expect(isApproximately(engine.weeklyScore(from: daily), 0.52))
    }

    @Test("Weekly score of an empty window is zero rather than a crash")
    func weeklyScoreOfEmptyWindow() {
        #expect(engine.weeklyScore(from: []) == 0)
    }

    @Test("A consistently good week beats a week with one great day and six poor ones")
    func consistencyIsRewarded() {
        let consistent = Array(repeating: 0.7, count: 7)
        let spiky = [1.0] + Array(repeating: 0.1, count: 6)

        #expect(engine.weeklyScore(from: consistent) > engine.weeklyScore(from: spiky))
    }

    // MARK: Determinism

    @Test("Equal scores break ties by title so list order is stable across refreshes")
    func tiesAreBrokenDeterministically() {
        // A profile registry where every activity scores identically.
        let flatProfiles = Dictionary(uniqueKeysWithValues: Activity.allCases.map {
            ($0, ActivityScoringProfile(activity: $0, baseline: 0.5, criteria: []))
        })
        let engine = DefaultActivityScoringEngine(profiles: flatProfiles)
        let forecast = Fixture.forecast(days: Fixture.days(count: 7))
        // Elevation is nil so `LocationFeasibility` applies no multiplier and the
        // scores really are identical — otherwise this would not be testing ties.
        let city = Fixture.city(elevation: nil)

        let first = engine.rank(forecast: forecast, for: city).map(\.activity)
        let second = engine.rank(forecast: forecast, for: city).map(\.activity)

        #expect(first == second)
        #expect(first == first.sorted { $0.title < $1.title })
    }
}
