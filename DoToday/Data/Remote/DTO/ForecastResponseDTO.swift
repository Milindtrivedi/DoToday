//
//  ForecastResponseDTO.swift
//  DoToday
//
//  Data layer — wire format for https://api.open-meteo.com/v1/forecast
//

import Foundation

/// Mirrors the forecast payload.
///
/// Open-Meteo returns *parallel arrays* rather than an array of objects, and any
/// element may be `null` when the underlying model has no value. Both facts are
/// preserved faithfully here and normalised by `ForecastMapper`.
struct ForecastResponseDTO: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let utcOffsetSeconds: Int?
    let daily: DailyDTO?

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, daily
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    struct DailyDTO: Codable, Equatable {
        /// ISO-8601 calendar days ("2026-09-07") in the response's time zone.
        let time: [String]
        let weatherCode: [Int?]?
        let temperature2mMax: [Double?]?
        let apparentTemperatureMax: [Double?]?
        let precipitationSum: [Double?]?
        let rainSum: [Double?]?
        let snowfallSum: [Double?]?
        let precipitationProbabilityMax: [Double?]?
        let windSpeed10mMax: [Double?]?
        let windGusts10mMax: [Double?]?
        let sunshineDuration: [Double?]?
        let daylightDuration: [Double?]?

        private enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case apparentTemperatureMax = "apparent_temperature_max"
            case precipitationSum = "precipitation_sum"
            case rainSum = "rain_sum"
            case snowfallSum = "snowfall_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeed10mMax = "wind_speed_10m_max"
            case windGusts10mMax = "wind_gusts_10m_max"
            case sunshineDuration = "sunshine_duration"
            case daylightDuration = "daylight_duration"
        }
    }
}
