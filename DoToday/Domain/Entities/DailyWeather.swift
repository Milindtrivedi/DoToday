//
//  DailyWeather.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// One day of the forecast, in fixed units, for one location.
///
/// Every measurement is optional on purpose: Open-Meteo returns `null` inside the
/// daily arrays when a variable is unavailable for a given model/location (this is
/// common for `snowfall_sum` and `precipitation_probability_max`). Rather than substituting zero —
/// which would silently claim "no snow" when we actually mean "no data" — the
/// scoring engine drops criteria whose input is `nil` and re-normalises the
/// remaining weights. See `ActivityScoringEngine`.
struct DailyWeather: Equatable {
    /// Local calendar day of the forecast, resolved in the location's own time zone.
    let date: Date
    let weatherCode: WeatherCode

    /// °C
    let temperatureMax: Double?
    /// °C — "feels like", used for outdoor comfort because it folds in wind and humidity.
    let apparentTemperatureMax: Double?
    /// mm — total liquid-equivalent precipitation (rain + showers + melted snow).
    let precipitationSum: Double?
    /// mm — liquid rain only. Distinguished from `snowfallSum` so skiing is not
    /// penalised for the very precipitation that makes it possible.
    let rainSum: Double?
    /// cm — fresh snow.
    let snowfallSum: Double?
    /// % (0...100)
    let precipitationProbabilityMax: Double?
    /// km/h — sustained wind.
    let windSpeedMax: Double?
    /// km/h — gusts. Separated from sustained wind because gusts, not averages,
    /// are what make a day unpleasant or unsafe.
    let windGustsMax: Double?
    /// seconds of direct sunshine.
    let sunshineDuration: Double?
    /// seconds between sunrise and sunset.
    let daylightDuration: Double?

    /// Fraction of available daylight that was sunny (0...1), or `nil` if either
    /// input is missing or the day has no daylight (polar night).
    var sunshineFraction: Double? {
        guard let sunshineDuration, let daylightDuration, daylightDuration > 0 else { return nil }
        return min(1, max(0, sunshineDuration / daylightDuration))
    }
}
