//
//  UseCaseTests.swift
//  DoTodayTests
//
//  The use cases hold the rules that sit between the screens and the repositories:
//  query gating, forecast window size, and the empty-forecast guard.
//

import Foundation
import Testing
@testable import DoToday

@Suite("SearchCitiesUseCase")
struct SearchCitiesUseCaseTests {

    @Test("Queries shorter than the minimum never reach the network", arguments: ["", " ", "a", "  b  "])
    func shortQueriesAreNotDispatched(query: String) async throws {
        let repository = StubCityRepository(result: .success([Fixture.city()]))
        let useCase = DefaultSearchCitiesUseCase(repository: repository)

        let results = try await useCase.execute(query: query)

        #expect(results.isEmpty)
        #expect(repository.receivedQueries.isEmpty, "A one-character query wasted a request")
    }

    @Test("Whitespace is trimmed before the query is sent")
    func queryIsTrimmed() async throws {
        let repository = StubCityRepository(result: .success([Fixture.city()]))
        let useCase = DefaultSearchCitiesUseCase(repository: repository)

        _ = try await useCase.execute(query: "  London \n")

        #expect(repository.receivedQueries == ["London"])
    }

    @Test("No matches is an empty result, not an error")
    func emptyResultsAreNotAnError() async throws {
        let repository = StubCityRepository(result: .success([]))
        let useCase = DefaultSearchCitiesUseCase(repository: repository)

        let results = try await useCase.execute(query: "Xyzzy")

        #expect(results.isEmpty)
    }

    @Test("Repository failures propagate unchanged")
    func errorsPropagate() async {
        let repository = StubCityRepository(result: .failure(AppError.offline))
        let useCase = DefaultSearchCitiesUseCase(repository: repository)

        await #expect(throws: AppError.offline) {
            _ = try await useCase.execute(query: "London")
        }
    }
}

@Suite("RankActivitiesUseCase")
struct RankActivitiesUseCaseTests {

    @Test("Requests exactly seven days, as the brief specifies")
    func requestsSevenDays() async throws {
        let repository = StubForecastRepository(
            result: .success(CachedValue(value: Fixture.forecast(days: Fixture.days(count: 7)), isStale: false))
        )
        let useCase = DefaultRankActivitiesUseCase(repository: repository)

        _ = try await useCase.execute(city: Fixture.city(), cachePolicy: .useCache)

        #expect(repository.receivedDays == [7])
    }

    @Test("Passes the caller's cache policy through untouched", arguments: [ForecastCachePolicy.useCache, .revalidate])
    func forwardsCachePolicy(policy: ForecastCachePolicy) async throws {
        let repository = StubForecastRepository(
            result: .success(CachedValue(value: Fixture.forecast(days: Fixture.days(count: 7)), isStale: false))
        )
        let useCase = DefaultRankActivitiesUseCase(repository: repository)

        _ = try await useCase.execute(city: Fixture.city(), cachePolicy: policy)

        #expect(repository.receivedPolicies == [policy])
    }

    @Test("Ranks every activity and carries the staleness flag through to the UI")
    func producesFullRankingAndPropagatesStaleness() async throws {
        let repository = StubForecastRepository(
            result: .success(CachedValue(value: Fixture.forecast(days: Fixture.days(count: 7)), isStale: true))
        )
        let useCase = DefaultRankActivitiesUseCase(repository: repository)

        let result = try await useCase.execute(city: Fixture.city(), cachePolicy: .useCache)

        #expect(result.rankings.count == Activity.allCases.count)
        #expect(result.isStale)
        #expect(result.city == Fixture.city())
    }

    @Test("A well-formed but empty forecast is treated as an invalid response")
    func emptyForecastIsRejected() async {
        let repository = StubForecastRepository(
            result: .success(CachedValue(value: Fixture.forecast(days: []), isStale: false))
        )
        let useCase = DefaultRankActivitiesUseCase(repository: repository)

        await #expect(throws: AppError.invalidResponse) {
            _ = try await useCase.execute(city: Fixture.city(), cachePolicy: .useCache)
        }
    }
}
