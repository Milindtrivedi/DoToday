//
//  DefaultForecastRepository.swift
//  DoToday
//
//  Data layer — implements the domain's `ForecastRepository` port and owns the
//  network/cache policy.
//

import Foundation

/// Cache-aware forecast repository.
///
/// Policy, in one place:
/// - `.useCache`      → a cache entry younger than `timeToLive` is served directly.
/// - `.revalidate`    → always try the network first (pull-to-refresh).
/// - Either way, if the network fails and *any* cache entry exists — even an expired
///   one — it is served and flagged `isStale`, so an offline user sees yesterday's
///   forecast with a label rather than an error screen.
struct DefaultForecastRepository: ForecastRepository {
    /// Open-Meteo refreshes its models hourly, so a 30-minute window keeps data
    /// current while collapsing the repeated fetches of normal browsing.
    static let defaultTimeToLive: TimeInterval = 30 * 60

    private let remote: ForecastRemoteDataSource
    private let cache: ForecastCache
    private let dateProvider: DateProvider
    private let timeToLive: TimeInterval

    init(
        remote: ForecastRemoteDataSource,
        cache: ForecastCache,
        dateProvider: DateProvider = SystemDateProvider(),
        timeToLive: TimeInterval = DefaultForecastRepository.defaultTimeToLive
    ) {
        self.remote = remote
        self.cache = cache
        self.dateProvider = dateProvider
        self.timeToLive = timeToLive
    }

    func forecast(
        for city: City,
        days: Int,
        cachePolicy: ForecastCachePolicy
    ) async throws -> CachedValue<Forecast> {
        let key = ForecastCacheKey(coordinate: city.coordinate, days: days)
        let cached = await cache.entry(for: key)

        if cachePolicy == .useCache,
           let cached,
           isFresh(cached),
           let forecast = try? ForecastMapper.map(cached.payload, retrievedAt: cached.storedAt) {
            return CachedValue(value: forecast, isStale: false)
        }

        do {
            let dto = try await remote.forecast(
                latitude: city.coordinate.latitude,
                longitude: city.coordinate.longitude,
                days: days
            )
            let now = dateProvider.now
            let forecast = try ForecastMapper.map(dto, retrievedAt: now)
            // Only a payload we could actually map is worth persisting.
            await cache.store(dto, for: key, at: now)
            return CachedValue(value: forecast, isStale: false)
        } catch {
            let normalised = ErrorNormalising.normalise(error)
            // Cancellation must not be masked by a cache hit: the caller asked us to
            // stop, and returning a value would resurrect work it already abandoned.
            if normalised is CancellationError { throw normalised }

            if let cached,
               let forecast = try? ForecastMapper.map(cached.payload, retrievedAt: cached.storedAt) {
                return CachedValue(value: forecast, isStale: true)
            }
            throw normalised
        }
    }

    private func isFresh(_ entry: CachedForecastEntry) -> Bool {
        dateProvider.now.timeIntervalSince(entry.storedAt) < timeToLive
    }
}
