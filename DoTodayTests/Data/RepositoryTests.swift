//
//  RepositoryTests.swift
//  DoTodayTests
//
//  The cache policy is the part of the data layer most likely to be wrong in a way
//  users notice (stale forecasts, wasted requests, an error screen when perfectly
//  good cached data was available), so every branch of it is pinned here.
//

import Foundation
import Testing
@testable import DoToday

@Suite("DefaultForecastRepository")
struct DefaultForecastRepositoryTests {

    private let city = Fixture.city()
    private let timeToLive: TimeInterval = 1_800  // 30 minutes

    private func makeSUT(
        remoteResult: Result<ForecastResponseDTO, Error>,
        clock: FixedDateProvider
    ) -> (DefaultForecastRepository, StubForecastRemoteDataSource, InMemoryForecastCache) {
        let remote = StubForecastRemoteDataSource(result: remoteResult)
        let cache = InMemoryForecastCache()
        let sut = DefaultForecastRepository(
            remote: remote,
            cache: cache,
            dateProvider: clock,
            timeToLive: timeToLive
        )
        return (sut, remote, cache)
    }

    @Test("A fresh cache entry is served without touching the network")
    func freshCacheAvoidsNetwork() async throws {
        let clock = FixedDateProvider()
        let (sut, remote, cache) = makeSUT(remoteResult: .success(try .stubbedWeek()), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)

        clock.advance(by: timeToLive - 1)
        let result = try await sut.forecast(for: city, days: 7, cachePolicy: .useCache)

        #expect(remote.callCount == 0)
        #expect(!result.isStale, "A cache entry inside its TTL is current, not stale")
    }

    @Test("An expired cache entry triggers a refetch")
    func expiredCacheRefetches() async throws {
        let clock = FixedDateProvider()
        let (sut, remote, cache) = makeSUT(remoteResult: .success(try .stubbedWeek()), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)

        clock.advance(by: timeToLive + 1)
        let result = try await sut.forecast(for: city, days: 7, cachePolicy: .useCache)

        #expect(remote.callCount == 1)
        #expect(!result.isStale)
    }

    @Test("Pull-to-refresh bypasses a perfectly fresh cache entry")
    func revalidateAlwaysHitsNetwork() async throws {
        let clock = FixedDateProvider()
        let (sut, remote, cache) = makeSUT(remoteResult: .success(try .stubbedWeek()), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)

        _ = try await sut.forecast(for: city, days: 7, cachePolicy: .revalidate)

        #expect(remote.callCount == 1)
    }

    @Test("A successful fetch is written to the cache for next time")
    func successfulFetchIsCached() async throws {
        let clock = FixedDateProvider()
        let (sut, _, cache) = makeSUT(remoteResult: .success(try .stubbedWeek()), clock: clock)

        _ = try await sut.forecast(for: city, days: 7, cachePolicy: .useCache)

        let entry = await cache.entry(for: ForecastCacheKey(coordinate: city.coordinate, days: 7))
        #expect(entry?.storedAt == clock.now)
    }

    @Test("Going offline falls back to expired cached data, flagged as stale")
    func offlineFallsBackToStaleCache() async throws {
        let clock = FixedDateProvider()
        let (sut, _, cache) = makeSUT(remoteResult: .failure(AppError.offline), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)

        clock.advance(by: timeToLive * 10)
        let result = try await sut.forecast(for: city, days: 7, cachePolicy: .revalidate)

        #expect(result.isStale, "Old data with a label beats an error screen")
        #expect(result.value.days.count == 7)
    }

    @Test("Going offline with nothing cached surfaces the error")
    func offlineWithoutCacheThrows() async {
        let clock = FixedDateProvider()
        let (sut, _, _) = makeSUT(remoteResult: .failure(AppError.offline), clock: clock)

        await #expect(throws: AppError.offline) {
            _ = try await sut.forecast(for: self.city, days: 7, cachePolicy: .useCache)
        }
    }

    @Test("Cancellation is propagated, never masked by a cache hit")
    func cancellationIsNotMaskedByCache() async throws {
        let clock = FixedDateProvider()
        let (sut, _, cache) = makeSUT(remoteResult: .failure(CancellationError()), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)
        clock.advance(by: timeToLive * 10)

        // Returning cached data here would resurrect work the caller already abandoned.
        await #expect(throws: CancellationError.self) {
            _ = try await sut.forecast(for: self.city, days: 7, cachePolicy: .revalidate)
        }
    }

    @Test("A malformed live response falls back to cache rather than failing")
    func malformedResponseFallsBackToCache() async throws {
        let clock = FixedDateProvider()
        let empty = try ForecastResponseDTO.decode(#"{"latitude":0,"longitude":0}"#)
        let (sut, _, cache) = makeSUT(remoteResult: .success(empty), clock: clock)
        await cache.store(try .stubbedWeek(), for: ForecastCacheKey(coordinate: city.coordinate, days: 7), at: clock.now)
        clock.advance(by: timeToLive * 2)

        let result = try await sut.forecast(for: city, days: 7, cachePolicy: .useCache)

        #expect(result.isStale)
    }

    @Test("Cache keys are per location and per window size")
    func cacheKeysAreScopedCorrectly() {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)

        #expect(ForecastCacheKey(coordinate: london, days: 7) == ForecastCacheKey(coordinate: london, days: 7))
        #expect(ForecastCacheKey(coordinate: london, days: 7) != ForecastCacheKey(coordinate: paris, days: 7))
        #expect(ForecastCacheKey(coordinate: london, days: 7) != ForecastCacheKey(coordinate: london, days: 14))
        // Coordinates are rounded to the request's precision, so two searches that
        // resolve to sub-metre-different coordinates still share a cache entry.
        #expect(ForecastCacheKey(coordinate: london, days: 7)
                == ForecastCacheKey(coordinate: Coordinate(latitude: 51.50741, longitude: -0.12783), days: 7))
        // And the derived filename must never contain a path separator.
        #expect(!ForecastCacheKey(coordinate: paris, days: 7).storageIdentifier.contains("/"))
    }
}

@Suite("DefaultCityRepository")
struct DefaultCityRepositoryTests {

    @Test("Maps a successful response into domain entities")
    func mapsResults() async throws {
        let dto = try GeocodingResponseDTO.decode(
            #"{"results":[{"id":1,"name":"London","latitude":51.5,"longitude":-0.12,"country_code":"GB"}]}"#
        )
        let sut = DefaultCityRepository(remote: StubGeocodingRemoteDataSource(result: .success(dto)))

        let cities = try await sut.searchCities(matching: "London", limit: 10)

        #expect(cities.map(\.name) == ["London"])
        #expect(cities.first?.countryCode == "GB")
    }

    @Test("No matches is an empty array, not a thrown error")
    func noMatchesIsEmpty() async throws {
        let dto = try GeocodingResponseDTO.decode(#"{"generationtime_ms":0.1}"#)
        let sut = DefaultCityRepository(remote: StubGeocodingRemoteDataSource(result: .success(dto)))

        #expect(try await sut.searchCities(matching: "Xyzzy", limit: 10).isEmpty)
    }

    @Test("Raw transport errors are normalised into the domain vocabulary")
    func normalisesTransportErrors() async {
        // The domain must never see a URLError; that is the whole point of the boundary.
        let sut = DefaultCityRepository(
            remote: StubGeocodingRemoteDataSource(result: .failure(URLError(.notConnectedToInternet)))
        )

        await #expect(throws: AppError.offline) {
            _ = try await sut.searchCities(matching: "London", limit: 10)
        }
    }

    @Test("Domain errors pass through unchanged")
    func passesThroughAppErrors() async {
        let sut = DefaultCityRepository(
            remote: StubGeocodingRemoteDataSource(result: .failure(AppError.server(statusCode: 503)))
        )

        await #expect(throws: AppError.server(statusCode: 503)) {
            _ = try await sut.searchCities(matching: "London", limit: 10)
        }
    }
}

// MARK: - Helpers

extension ForecastResponseDTO {
    static func decode(_ json: String) throws -> ForecastResponseDTO {
        try JSONDecoder().decode(ForecastResponseDTO.self, from: Data(json.utf8))
    }

    /// A well-formed seven-day payload.
    static func stubbedWeek() throws -> ForecastResponseDTO {
        let days = (7...13).map { #""2026-09-\#($0 < 10 ? "0" : "")\#($0)""# }.joined(separator: ",")
        return try decode("""
        {
          "latitude": 51.5, "longitude": -0.12, "timezone": "Europe/London", "utc_offset_seconds": 3600,
          "daily": {
            "time": [\(days)],
            "temperature_2m_max": [18,19,20,17,16,21,22],
            "precipitation_sum": [0,1,0,5,0,0,2]
          }
        }
        """)
    }
}

extension GeocodingResponseDTO {
    static func decode(_ json: String) throws -> GeocodingResponseDTO {
        try JSONDecoder().decode(GeocodingResponseDTO.self, from: Data(json.utf8))
    }
}
