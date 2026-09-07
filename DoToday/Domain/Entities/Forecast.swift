//
//  Forecast.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// A location's multi-day forecast, plus the metadata needed to display it correctly.
struct Forecast: Equatable {
    let coordinate: Coordinate
    /// IANA time zone the `days` were resolved in, e.g. "Europe/Paris".
    let timeZoneIdentifier: String
    let days: [DailyWeather]
    /// When this forecast was retrieved. Drives cache expiry and the "updated" label.
    let retrievedAt: Date
}
