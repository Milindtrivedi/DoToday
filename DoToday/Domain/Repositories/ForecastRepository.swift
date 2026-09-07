//
//  ForecastRepository.swift
//  DoToday
//
//  Domain layer — dependency inversion boundary.
//

import Foundation

/// How a caller wants the cache to be treated.
enum ForecastCachePolicy: Equatable {
    /// Serve a fresh cached forecast if one exists, otherwise fetch.
    case useCache
    /// Always hit the network; fall back to cache only if the network fails.
    /// Used by pull-to-refresh.
    case revalidate
}

protocol ForecastRepository: Sendable {
    /// Fetches the daily forecast for a location.
    ///
    /// - Parameter days: Number of forecast days requested (the app asks for 7).
    /// - Throws: `AppError`.
    func forecast(
        for city: City,
        days: Int,
        cachePolicy: ForecastCachePolicy
    ) async throws -> CachedValue<Forecast>
}

/// Wraps a value with its provenance so the UI can say "showing saved data".
struct CachedValue<Value: Equatable>: Equatable {
    let value: Value
    /// True when served from cache instead of a live network response.
    let isStale: Bool
}
