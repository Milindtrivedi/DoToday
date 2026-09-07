//
//  TestFixtures.swift
//  DoTodayTests
//
//  Shared builders. Every fixture takes defaults for all parameters so a test only
//  states the values it actually cares about — the rest is noise that would otherwise
//  hide the intent of the assertion.
//

import Foundation
@testable import DoToday

enum Fixture {

    static func city(
        id: Int = 1,
        name: String = "Testville",
        admin1: String? = "Test Region",
        country: String? = "Testland",
        countryCode: String? = "TL",
        latitude: Double = 51.5,
        longitude: Double = -0.12,
        elevation: Double? = 10,
        timeZoneIdentifier: String? = "Europe/London"
    ) -> City {
        City(
            id: id,
            name: name,
            admin1: admin1,
            country: country,
            countryCode: countryCode,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            elevation: elevation,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    /// A neutral, fully-populated day. Tests override only the fields under test.
    static func day(
        date: Date = Date(timeIntervalSince1970: 1_757_203_200), // 2025-09-07T00:00:00Z
        weatherCode: WeatherCode = .partlyCloudy,
        temperatureMax: Double? = 18,
        apparentTemperatureMax: Double? = 18,
        precipitationSum: Double? = 0,
        rainSum: Double? = 0,
        snowfallSum: Double? = 0,
        precipitationProbabilityMax: Double? = 5,
        windSpeedMax: Double? = 10,
        windGustsMax: Double? = 20,
        sunshineDuration: Double? = 30_000,
        daylightDuration: Double? = 43_200,
    ) -> DailyWeather {
        DailyWeather(
            date: date,
            weatherCode: weatherCode,
            temperatureMax: temperatureMax,
            apparentTemperatureMax: apparentTemperatureMax,
            precipitationSum: precipitationSum,
            rainSum: rainSum,
            snowfallSum: snowfallSum,
            precipitationProbabilityMax: precipitationProbabilityMax,
            windSpeedMax: windSpeedMax,
            windGustsMax: windGustsMax,
            sunshineDuration: sunshineDuration,
            daylightDuration: daylightDuration
        )
    }

    static func forecast(
        days: [DailyWeather],
        timeZoneIdentifier: String = "Europe/London",
        retrievedAt: Date = Date(timeIntervalSince1970: 1_757_203_200)
    ) -> Forecast {
        Forecast(
            coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
            timeZoneIdentifier: timeZoneIdentifier,
            days: days,
            retrievedAt: retrievedAt
        )
    }

    /// `count` consecutive days built from `template`, one day apart.
    static func days(count: Int, template: DailyWeather = Fixture.day()) -> [DailyWeather] {
        (0..<count).map { offset in
            DailyWeather(
                date: template.date.addingTimeInterval(TimeInterval(offset) * 86_400),
                weatherCode: template.weatherCode,
                temperatureMax: template.temperatureMax,
                apparentTemperatureMax: template.apparentTemperatureMax,
                precipitationSum: template.precipitationSum,
                rainSum: template.rainSum,
                snowfallSum: template.snowfallSum,
                precipitationProbabilityMax: template.precipitationProbabilityMax,
                windSpeedMax: template.windSpeedMax,
                windGustsMax: template.windGustsMax,
                sunshineDuration: template.sunshineDuration,
                daylightDuration: template.daylightDuration
            )
        }
    }

    /// A perfect ski day: deep fresh snow, cold, calm, no rain.
    static let perfectSkiDay = day(
        weatherCode: .snow,
        temperatureMax: -5, apparentTemperatureMax: -9,
        precipitationSum: 8, rainSum: 0, snowfallSum: 20,
        precipitationProbabilityMax: 90, windSpeedMax: 8, windGustsMax: 15,
        sunshineDuration: 10_000, daylightDuration: 30_000
    )

    /// A perfect day to walk around a city: warm, dry, sunny, still.
    static let perfectSightseeingDay = day(
        weatherCode: .clear,
        temperatureMax: 22, apparentTemperatureMax: 21,
        precipitationSum: 0, rainSum: 0, snowfallSum: 0,
        precipitationProbabilityMax: 0, windSpeedMax: 6, windGustsMax: 12,
        sunshineDuration: 40_000, daylightDuration: 45_000
    )

    /// A washout: heavy rain, cold, windy.
    static let miserableDay = day(
        weatherCode: .rain,
        temperatureMax: 4, apparentTemperatureMax: -1,
        precipitationSum: 25, rainSum: 25, snowfallSum: 0,
        precipitationProbabilityMax: 100, windSpeedMax: 55, windGustsMax: 90,
        sunshineDuration: 0, daylightDuration: 30_000
    )
}
