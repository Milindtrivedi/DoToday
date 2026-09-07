//
//  ForecastRemoteDataSource.swift
//  DoToday
//
//  Data layer.
//

import Foundation

protocol ForecastRemoteDataSource: Sendable {
    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> ForecastResponseDTO
}

struct OpenMeteoForecastRemoteDataSource: ForecastRemoteDataSource {
    // Force-unwrapped: a malformed literal here is a programming error that should
    // fail at first launch, not degrade to a silent no-op at runtime.
    static let baseURL = URL(string: "https://api.open-meteo.com")!

    /// The daily variables we request. This list is the contract between the API and
    /// `ForecastMapper` / the scoring profiles — every entry is consumed by at least
    /// one criterion, and nothing is requested "just in case".
    static let dailyVariables = [
        "weather_code",
        "temperature_2m_max",
        "apparent_temperature_max",
        "precipitation_sum",
        "rain_sum",
        "snowfall_sum",
        "precipitation_probability_max",
        "wind_speed_10m_max",
        "wind_gusts_10m_max",
        "sunshine_duration",
        "daylight_duration"
    ]

    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> ForecastResponseDTO {
        let endpoint = Endpoint(
            baseURL: Self.baseURL,
            path: "v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: Self.format(latitude)),
                URLQueryItem(name: "longitude", value: Self.format(longitude)),
                URLQueryItem(name: "daily", value: Self.dailyVariables.joined(separator: ",")),
                URLQueryItem(name: "forecast_days", value: String(days)),
                // `timezone=auto` makes the API resolve calendar days at the *location*,
                // which is what "the next 7 days" means to someone planning a trip there.
                URLQueryItem(name: "timezone", value: "auto"),
                // Units are pinned so the scoring curves' constants are unambiguous.
                URLQueryItem(name: "temperature_unit", value: "celsius"),
                URLQueryItem(name: "wind_speed_unit", value: "kmh"),
                URLQueryItem(name: "precipitation_unit", value: "mm")
            ]
        )
        return try await client.get(endpoint, as: ForecastResponseDTO.self)
    }

    /// Fixed-precision, POSIX-formatted coordinates.
    ///
    /// `String(describing:)` on a `Double` would emit the device's decimal separator
    /// in some locales ("48,85"), which the API rejects. Four decimal places is ~11 m
    /// of precision — plenty — and truncating improves cache-key hit rates.
    static func format(_ coordinate: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), coordinate)
    }
}
