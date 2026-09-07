//
//  TestDoubles.swift
//  DoTodayTests
//
//  Hand-written stubs and spies. No mocking framework: the protocols are small
//  enough that hand-rolled doubles are shorter than the DSL would be, and they make
//  the expected behaviour of each collaborator explicit at the point of use.
//

import Foundation
@testable import DoToday

// MARK: - HTTP

/// `HTTPClient` stub that returns pre-canned values (or throws) per call, and records
/// the endpoints it was asked for.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    /// Queue of results, consumed in order. When exhausted, the last one repeats.
    private var results: [Result<Any, Error>]
    private(set) var requestedEndpoints: [Endpoint] = []

    init(results: [Result<Any, Error>]) {
        self.results = results
    }

    convenience init(success value: Any) {
        self.init(results: [.success(value)])
    }

    convenience init(failure error: Error) {
        self.init(results: [.failure(error)])
    }

    func get<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response {
        requestedEndpoints.append(endpoint)
        guard let result = results.count > 1 ? results.removeFirst() : results.first else {
            throw AppError.unknown(description: "StubHTTPClient has no configured result")
        }
        switch result {
        case let .success(value):
            guard let typed = value as? Response else {
                throw AppError.unknown(description: "StubHTTPClient type mismatch: \(Swift.type(of: value)) is not \(Response.self)")
            }
            return typed
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Data sources

final class StubGeocodingRemoteDataSource: GeocodingRemoteDataSource, @unchecked Sendable {
    var result: Result<GeocodingResponseDTO, Error>
    private(set) var receivedQueries: [String] = []

    init(result: Result<GeocodingResponseDTO, Error>) {
        self.result = result
    }

    func search(name: String, count: Int) async throws -> GeocodingResponseDTO {
        receivedQueries.append(name)
        return try result.get()
    }
}

final class StubForecastRemoteDataSource: ForecastRemoteDataSource, @unchecked Sendable {
    var result: Result<ForecastResponseDTO, Error>
    private(set) var callCount = 0

    init(result: Result<ForecastResponseDTO, Error>) {
        self.result = result
    }

    func forecast(latitude: Double, longitude: Double, days: Int) async throws -> ForecastResponseDTO {
        callCount += 1
        return try result.get()
    }
}

// MARK: - Repositories

final class StubCityRepository: CityRepository, @unchecked Sendable {
    var result: Result<[City], Error>
    private(set) var receivedQueries: [String] = []
    /// Optional gate that lets a test hold a call open to exercise cancellation.
    var beforeReturn: (@Sendable () async -> Void)?

    init(result: Result<[City], Error> = .success([])) {
        self.result = result
    }

    func searchCities(matching query: String, limit: Int) async throws -> [City] {
        receivedQueries.append(query)
        await beforeReturn?()
        return try result.get()
    }
}

final class StubForecastRepository: ForecastRepository, @unchecked Sendable {
    var result: Result<CachedValue<Forecast>, Error>
    private(set) var receivedPolicies: [ForecastCachePolicy] = []
    private(set) var receivedDays: [Int] = []

    init(result: Result<CachedValue<Forecast>, Error>) {
        self.result = result
    }

    func forecast(
        for city: City,
        days: Int,
        cachePolicy: ForecastCachePolicy
    ) async throws -> CachedValue<Forecast> {
        receivedDays.append(days)
        receivedPolicies.append(cachePolicy)
        return try result.get()
    }
}

// MARK: - Use cases

final class StubSearchCitiesUseCase: SearchCitiesUseCase, @unchecked Sendable {
    var result: Result<[City], Error>
    private(set) var receivedQueries: [String] = []

    init(result: Result<[City], Error> = .success([])) {
        self.result = result
    }

    func execute(query: String) async throws -> [City] {
        receivedQueries.append(query)
        return try result.get()
    }
}

final class StubRankActivitiesUseCase: RankActivitiesUseCase, @unchecked Sendable {
    var result: Result<RankedRecommendations, Error>
    private(set) var receivedPolicies: [ForecastCachePolicy] = []

    init(result: Result<RankedRecommendations, Error>) {
        self.result = result
    }

    func execute(city: City, cachePolicy: ForecastCachePolicy) async throws -> RankedRecommendations {
        receivedPolicies.append(cachePolicy)
        return try result.get()
    }
}

// MARK: - Clock

/// Manually advanced clock, so cache-expiry tests never sleep.
final class FixedDateProvider: DateProvider, @unchecked Sendable {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_757_203_200)) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
