//
//  ScoringEdgeCaseTests.swift
//  DoTodayTests
//
//  Hostile inputs for the scoring pipeline. Weather data arrives from a third party;
//  it can be absurd, and a score outside 0...1 would render as a bar wider than its
//  track or a percentage over 100.
//

import Foundation
import Testing
@testable import DoToday

@Suite("Scoring edge cases and fuzzing")
struct ScoringEdgeCaseTests {

    private let engine = DefaultActivityScoringEngine()

    @Test("Absurd but finite values still produce a valid score", arguments: [
        -300.0, -100.0, 0.0, 100.0, 1_000.0, 1_000_000.0
    ])
    func extremeValuesStayNormalised(value: Double) {
        let day = Fixture.day(
            temperatureMax: value, apparentTemperatureMax: value,
            precipitationSum: value, rainSum: value, snowfallSum: value,
            precipitationProbabilityMax: value,
            windSpeedMax: value, windGustsMax: value,
            sunshineDuration: value, daylightDuration: abs(value) + 1
        )

        for profile in ActivityScoringProfile.all.values {
            let score = engine.dailyScore(for: day, profile: profile)
            #expect(score >= 0 && score <= 1, "\(profile.activity) scored \(score) for \(value)")
            #expect(!score.isNaN, "\(profile.activity) produced NaN for \(value)")
        }
    }

    @Test("Non-finite values never leak a NaN score into the UI")
    func nonFiniteValuesAreHandled() {
        // A malformed payload could decode as infinity; NaN poisons every comparison
        // it touches, so a NaN score would silently break sorting too.
        for value in [Double.infinity, -.infinity, .nan] {
            let day = Fixture.day(
                temperatureMax: value, apparentTemperatureMax: value,
                precipitationSum: value, rainSum: value, snowfallSum: value,
                precipitationProbabilityMax: value,
                windSpeedMax: value, windGustsMax: value
            )

            for profile in ActivityScoringProfile.all.values {
                let score = engine.dailyScore(for: day, profile: profile)
                #expect(!score.isNaN, "\(profile.activity) produced NaN for \(value)")
                #expect(score >= 0 && score <= 1, "\(profile.activity) scored \(score) for \(value)")
            }
        }
    }

    @Test("Randomised weather never produces an out-of-range ranking")
    func fuzzedForecastsStayValid() {
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<400 {
            let days = (0..<Int.random(in: 1...14, using: &generator)).map { offset in
                Fixture.day(
                    date: Date(timeIntervalSince1970: 1_757_203_200 + Double(offset) * 86_400),
                    temperatureMax: Bool.random(using: &generator) ? nil : .random(in: -80...80, using: &generator),
                    apparentTemperatureMax: Bool.random(using: &generator) ? nil : .random(in: -80...80, using: &generator),
                    precipitationSum: Bool.random(using: &generator) ? nil : .random(in: 0...500, using: &generator),
                    rainSum: Bool.random(using: &generator) ? nil : .random(in: 0...500, using: &generator),
                    snowfallSum: Bool.random(using: &generator) ? nil : .random(in: 0...300, using: &generator),
                    precipitationProbabilityMax: Bool.random(using: &generator) ? nil : .random(in: 0...100, using: &generator),
                    windSpeedMax: Bool.random(using: &generator) ? nil : .random(in: 0...400, using: &generator),
                    windGustsMax: Bool.random(using: &generator) ? nil : .random(in: 0...500, using: &generator),
                    sunshineDuration: Bool.random(using: &generator) ? nil : .random(in: 0...86_400, using: &generator),
                    daylightDuration: Bool.random(using: &generator) ? nil : .random(in: 0...86_400, using: &generator)
                )
            }
            guard !days.isEmpty else { continue }

            let city = Fixture.city(elevation: Bool.random(using: &generator) ? nil : .random(in: -500...9_000, using: &generator))
            let rankings = engine.rank(forecast: Fixture.forecast(days: days), for: city)

            #expect(rankings.count == Activity.allCases.count)
            for ranking in rankings {
                #expect(ranking.overallScore >= 0 && ranking.overallScore <= 1)
                #expect(!ranking.overallScore.isNaN)
                #expect(ranking.dailyScores.allSatisfy { $0.score >= 0 && $0.score <= 1 && !$0.score.isNaN })
            }
            // Sorting must survive whatever the scores turned out to be.
            #expect(rankings.map(\.overallScore) == rankings.map(\.overallScore).sorted(by: >))
        }
    }

    @Test("A single-day forecast ranks without special-casing")
    func singleDayForecast() {
        let rankings = engine.rank(
            forecast: Fixture.forecast(days: [Fixture.perfectSightseeingDay]),
            for: Fixture.city()
        )

        #expect(rankings.count == Activity.allCases.count)
        #expect(rankings.allSatisfy { $0.dailyScores.count == 1 })
    }

    @Test("An empty forecast produces zeroed rankings rather than crashing")
    func emptyForecast() {
        // The use case rejects this before it reaches the UI, but the engine must not
        // be the thing that crashes if that guard is ever moved or removed.
        let rankings = engine.rank(forecast: Fixture.forecast(days: []), for: Fixture.city())

        #expect(rankings.count == Activity.allCases.count)
        #expect(rankings.allSatisfy { $0.overallScore == 0 })
        #expect(rankings.allSatisfy { $0.bestDay == nil })
    }

    @Test("A forecast far longer than a week is handled without truncation surprises")
    func longForecast() {
        let rankings = engine.rank(
            forecast: Fixture.forecast(days: Fixture.days(count: 60)),
            for: Fixture.city()
        )

        #expect(rankings.allSatisfy { $0.dailyScores.count == 60 })
    }

    @Test("Extreme elevations still yield a usable multiplier", arguments: [
        -500.0, 0.0, 8_849.0, 100_000.0
    ])
    func extremeElevations(elevation: Double) {
        let rankings = engine.rank(
            forecast: Fixture.forecast(days: Fixture.days(count: 7)),
            for: Fixture.city(elevation: elevation)
        )

        #expect(rankings.allSatisfy { $0.overallScore >= 0 && $0.overallScore <= 1 })
    }

    @Test("Ranking the same forecast twice gives byte-identical results")
    func rankingIsDeterministic() {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7))
        let city = Fixture.city()

        let first = engine.rank(forecast: forecast, for: city)
        let second = engine.rank(forecast: forecast, for: city)

        #expect(first == second)
    }
}
