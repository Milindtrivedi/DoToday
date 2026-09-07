//
//  ForecastCache.swift
//  DoToday
//
//  Data layer — persistence seam for offline support.
//

import Foundation

/// Identifies a cached forecast. Coordinates are rounded to the same precision the
/// request uses, so two searches for the same city share a cache entry.
struct ForecastCacheKey: Hashable {
    let latitude: String
    let longitude: String
    let days: Int

    init(coordinate: Coordinate, days: Int) {
        self.latitude = OpenMeteoForecastRemoteDataSource.format(coordinate.latitude)
        self.longitude = OpenMeteoForecastRemoteDataSource.format(coordinate.longitude)
        self.days = days
    }

    /// Filename-safe representation. `-` in a negative coordinate is fine on disk;
    /// `.` is replaced so the extension stays meaningful.
    var storageIdentifier: String {
        "\(latitude)_\(longitude)_\(days)".replacingOccurrences(of: ".", with: "-")
    }
}

/// A cached payload plus the moment it was written.
struct CachedForecastEntry: Codable, Equatable {
    let payload: ForecastResponseDTO
    let storedAt: Date
}

/// Read/write access to persisted forecasts.
///
/// The cache deliberately stores the *DTO*, not the mapped `Forecast`. Persisting the
/// raw payload means a change to our mapping rules takes effect on the next read
/// rather than being frozen into whatever was cached by an older build.
protocol ForecastCache: Sendable {
    func entry(for key: ForecastCacheKey) async -> CachedForecastEntry?
    func store(_ payload: ForecastResponseDTO, for key: ForecastCacheKey, at date: Date) async
}
