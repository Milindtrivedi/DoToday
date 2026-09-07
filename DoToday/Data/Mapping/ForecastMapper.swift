//
//  ForecastMapper.swift
//  DoToday
//
//  Data layer — the anti-corruption boundary for forecast data.
//

import Foundation

/// Converts Open-Meteo's parallel arrays into an ordered list of `DailyWeather`.
///
/// Two wire-format hazards are handled here so the domain never sees them:
///
/// 1. **Ragged arrays.** Each daily variable arrives as its own array. They are
///    normally the same length as `time`, but nothing in the contract guarantees it,
///    so every read goes through a bounds-checked lookup and a short array simply
///    yields `nil` for the missing tail rather than crashing.
/// 2. **Local calendar days.** `time` holds bare dates ("2026-09-07") that mean
///    *midnight in the location's own time zone*. Parsing them in the device's time
///    zone would shift the whole week for anyone travelling, so we resolve them using
///    the time zone the response itself reports.
enum ForecastMapper {

    /// - Parameter retrievedAt: Injected rather than read from `Date()` so that
    ///   cache-expiry behaviour is deterministic under test.
    static func map(_ dto: ForecastResponseDTO, retrievedAt: Date) throws -> Forecast {
        guard let daily = dto.daily, !daily.time.isEmpty else {
            throw AppError.invalidResponse
        }

        let timeZone = resolveTimeZone(identifier: dto.timezone, offsetSeconds: dto.utcOffsetSeconds)
        let formatter = dayFormatter(in: timeZone)

        let days: [DailyWeather] = daily.time.enumerated().compactMap { index, dayString in
            // A day we cannot place on the calendar is dropped rather than guessed at.
            guard let date = formatter.date(from: dayString) else { return nil }

            return DailyWeather(
                date: date,
                weatherCode: WeatherCode(rawCode: daily.weatherCode?[safe: index].flatMap { $0 } ?? -1),
                temperatureMax: daily.temperature2mMax?[safe: index].flatMap { $0 },
                apparentTemperatureMax: daily.apparentTemperatureMax?[safe: index].flatMap { $0 },
                precipitationSum: daily.precipitationSum?[safe: index].flatMap { $0 },
                rainSum: daily.rainSum?[safe: index].flatMap { $0 },
                snowfallSum: daily.snowfallSum?[safe: index].flatMap { $0 },
                precipitationProbabilityMax: daily.precipitationProbabilityMax?[safe: index].flatMap { $0 },
                windSpeedMax: daily.windSpeed10mMax?[safe: index].flatMap { $0 },
                windGustsMax: daily.windGusts10mMax?[safe: index].flatMap { $0 },
                sunshineDuration: daily.sunshineDuration?[safe: index].flatMap { $0 },
                daylightDuration: daily.daylightDuration?[safe: index].flatMap { $0 }
            )
        }

        guard !days.isEmpty else { throw AppError.invalidResponse }

        return Forecast(
            coordinate: Coordinate(latitude: dto.latitude, longitude: dto.longitude),
            timeZoneIdentifier: timeZone.identifier,
            days: days,
            retrievedAt: retrievedAt
        )
    }

    /// Prefers the IANA identifier; falls back to the raw UTC offset, then to GMT.
    private static func resolveTimeZone(identifier: String?, offsetSeconds: Int?) -> TimeZone {
        if let identifier, let zone = TimeZone(identifier: identifier) { return zone }
        if let offsetSeconds, let zone = TimeZone(secondsFromGMT: offsetSeconds) { return zone }
        return TimeZone(secondsFromGMT: 0) ?? .current
    }

    private static func dayFormatter(in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        // POSIX locale: the API's format is fixed, so it must not follow user settings.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

extension Collection {
    /// Bounds-checked lookup, returning `nil` instead of trapping.
    /// Used to survive the ragged-array case described above.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
