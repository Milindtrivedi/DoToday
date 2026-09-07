//
//  MappingTests.swift
//  DoTodayTests
//
//  Decoding + mapping are tested together against realistic payloads, because the
//  bugs worth catching here (a renamed key, a null in an array, a time-zone slip)
//  only show up when both halves run against real JSON.
//

import Foundation
import Testing
@testable import DoToday

@Suite("Geocoding decoding and mapping")
struct GeocodingMappingTests {

    private let json = """
    {
      "results": [
        {
          "id": 2988507,
          "name": "Paris",
          "latitude": 48.85341,
          "longitude": 2.3488,
          "elevation": 42.0,
          "feature_code": "PPLC",
          "country_code": "FR",
          "timezone": "Europe/Paris",
          "country": "France",
          "admin1": "Île-de-France"
        }
      ],
      "generationtime_ms": 0.51
    }
    """

    private func decode(_ string: String) throws -> GeocodingResponseDTO {
        try JSONDecoder().decode(GeocodingResponseDTO.self, from: Data(string.utf8))
    }

    @Test("Every field the app relies on survives decoding and mapping")
    func mapsAllFields() throws {
        let city = try #require(CityMapper.map(decode(json)).first)

        #expect(city.id == 2988507)
        #expect(city.name == "Paris")
        #expect(city.admin1 == "Île-de-France")
        #expect(city.country == "France")
        // Verifies the snake_case CodingKey; a silent nil here would break nothing
        // visible until someone tried to show a flag.
        #expect(city.countryCode == "FR")
        #expect(city.coordinate.latitude == 48.85341)
        #expect(city.coordinate.longitude == 2.3488)
        #expect(city.elevation == 42)
        #expect(city.timeZoneIdentifier == "Europe/Paris")
    }

    @Test("An absent results key means no matches, not a decoding failure")
    func absentResultsKeyMapsToEmpty() throws {
        // This is what Open-Meteo actually returns for an unknown place name.
        let dto = try decode(#"{"generationtime_ms": 0.2}"#)

        #expect(CityMapper.map(dto).isEmpty)
    }

    @Test("Optional fields missing from the payload do not fail the whole response")
    func toleratesMissingOptionalFields() throws {
        let minimal = #"{"results":[{"id":1,"name":"Nowhere","latitude":0,"longitude":0}]}"#

        let city = try #require(CityMapper.map(decode(minimal)).first)

        #expect(city.name == "Nowhere")
        #expect(city.country == nil)
        #expect(city.elevation == nil)
        #expect(city.subtitle.isEmpty)
    }

    @Test("Subtitle joins the parts that exist, skipping the ones that don't")
    func subtitleComposition() {
        #expect(Fixture.city(admin1: "Bavaria", country: "Germany").subtitle == "Bavaria, Germany")
        #expect(Fixture.city(admin1: nil, country: "Germany").subtitle == "Germany")
        #expect(Fixture.city(admin1: "Bavaria", country: nil).subtitle == "Bavaria")
        #expect(Fixture.city(admin1: nil, country: nil).subtitle.isEmpty)
    }
}

@Suite("Forecast decoding and mapping")
struct ForecastMappingTests {

    private let retrievedAt = Date(timeIntervalSince1970: 1_757_203_200)

    private func decode(_ string: String) throws -> ForecastResponseDTO {
        try JSONDecoder().decode(ForecastResponseDTO.self, from: Data(string.utf8))
    }

    private let twoDayJSON = """
    {
      "latitude": 48.86,
      "longitude": 2.34,
      "utc_offset_seconds": 7200,
      "timezone": "Europe/Paris",
      "daily": {
        "time": ["2026-09-07", "2026-09-08"],
        "weather_code": [61, 0],
        "temperature_2m_max": [18.4, 24.1],
        "temperature_2m_min": [11.2, 13.0],
        "apparent_temperature_max": [17.0, 23.5],
        "precipitation_sum": [6.2, 0.0],
        "rain_sum": [6.2, 0.0],
        "snowfall_sum": [0.0, 0.0],
        "precipitation_probability_max": [80, 5],
        "wind_speed_10m_max": [22.3, 9.1],
        "wind_gusts_10m_max": [48.6, 20.2],
        "sunshine_duration": [7200.0, 39600.0],
        "daylight_duration": [45000.0, 44900.0],
        "uv_index_max": [3.2, 6.1]
      }
    }
    """

    @Test("A complete payload maps to fully populated days")
    func mapsCompletePayload() throws {
        let forecast = try ForecastMapper.map(decode(twoDayJSON), retrievedAt: retrievedAt)

        #expect(forecast.days.count == 2)
        #expect(forecast.timeZoneIdentifier == "Europe/Paris")
        #expect(forecast.retrievedAt == retrievedAt)

        let first = forecast.days[0]
        #expect(first.weatherCode == .rain)
        #expect(first.temperatureMax == 18.4)
        #expect(first.apparentTemperatureMax == 17.0)
        #expect(first.precipitationSum == 6.2)
        #expect(first.rainSum == 6.2)
        #expect(first.snowfallSum == 0)
        #expect(first.precipitationProbabilityMax == 80)
        #expect(first.windSpeedMax == 22.3)
        #expect(first.windGustsMax == 48.6)
        #expect(isApproximately(try #require(first.sunshineFraction), 7200 / 45000))
    }

    @Test("Days are resolved in the location's time zone, not the device's")
    func resolvesDatesInResponseTimeZone() throws {
        let forecast = try ForecastMapper.map(decode(twoDayJSON), retrievedAt: retrievedAt)

        // 2026-09-07 00:00 in Paris (UTC+2 in September) is 2026-09-06 22:00 UTC.
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 6
        components.hour = 22; components.minute = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        #expect(forecast.days[0].date == calendar.date(from: components))
    }

    @Test("Nulls inside the daily arrays become nil, not zero")
    func nullsBecomeNil() throws {
        let json = """
        {
          "latitude": 0, "longitude": 0, "timezone": "UTC", "utc_offset_seconds": 0,
          "daily": {
            "time": ["2026-09-07"],
            "weather_code": [3],
            "temperature_2m_max": [null],
            "snowfall_sum": [null],
            "uv_index_max": [null]
          }
        }
        """

        let day = try #require(ForecastMapper.map(decode(json), retrievedAt: retrievedAt).days.first)

        #expect(day.temperatureMax == nil)
        #expect(day.snowfallSum == nil)
        #expect(day.apparentTemperatureMax == nil)
        #expect(day.weatherCode == .overcast)
    }

    @Test("A variable array shorter than time yields nil for the missing tail")
    func toleratesRaggedArrays() throws {
        let json = """
        {
          "latitude": 0, "longitude": 0, "timezone": "UTC", "utc_offset_seconds": 0,
          "daily": {
            "time": ["2026-09-07", "2026-09-08", "2026-09-09"],
            "temperature_2m_max": [10.0]
          }
        }
        """

        let days = try ForecastMapper.map(decode(json), retrievedAt: retrievedAt).days

        #expect(days.count == 3)
        #expect(days[0].temperatureMax == 10)
        #expect(days[1].temperatureMax == nil)
        #expect(days[2].temperatureMax == nil)
    }

    @Test("An unrecognised weather code degrades gracefully rather than failing")
    func unknownWeatherCode() throws {
        let json = """
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":["2026-09-07"],"weather_code":[999]}}
        """

        let day = try #require(ForecastMapper.map(decode(json), retrievedAt: retrievedAt).days.first)

        #expect(day.weatherCode == .unknown(999))
    }

    @Test("A day whose date cannot be parsed is dropped, not guessed at")
    func dropsUnparseableDates() throws {
        let json = """
        {"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":["not-a-date","2026-09-08"]}}
        """

        let days = try ForecastMapper.map(decode(json), retrievedAt: retrievedAt).days

        #expect(days.count == 1)
    }

    @Test("A payload with no usable days is an invalid response", arguments: [
        #"{"latitude":0,"longitude":0}"#,
        #"{"latitude":0,"longitude":0,"daily":{"time":[]}}"#,
        #"{"latitude":0,"longitude":0,"daily":{"time":["nonsense"]}}"#
    ])
    func rejectsUnusablePayloads(json: String) throws {
        let dto = try decode(json)

        #expect(throws: AppError.invalidResponse) {
            _ = try ForecastMapper.map(dto, retrievedAt: retrievedAt)
        }
    }

    @Test("Falls back to the UTC offset when the time zone identifier is missing")
    func fallsBackToUTCOffset() throws {
        let json = """
        {"latitude":0,"longitude":0,"utc_offset_seconds":3600,"daily":{"time":["2026-09-07"]}}
        """

        let forecast = try ForecastMapper.map(decode(json), retrievedAt: retrievedAt)

        #expect(TimeZone(identifier: forecast.timeZoneIdentifier)?.secondsFromGMT() == 3600)
    }

    @Test("Sunshine fraction is nil when daylight is zero rather than dividing by zero")
    func sunshineFractionGuardsAgainstZeroDaylight() {
        #expect(Fixture.day(sunshineDuration: 100, daylightDuration: 0).sunshineFraction == nil)
        #expect(Fixture.day(sunshineDuration: nil, daylightDuration: 40_000).sunshineFraction == nil)
    }
}
