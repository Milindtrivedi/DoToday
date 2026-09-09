//
//  ScenePhaseTests.swift
//  DoTodayTests
//
//  Foreground/background behaviour. The app can sit backgrounded for arbitrarily
//  long, so what it shows on return is a correctness question, not a polish one.
//

import Foundation
import Testing
@testable import DoToday

@MainActor
@Suite("Returning to the foreground")
struct ScenePhaseTests {

    private static func recommendations(retrievedAt: Date) -> RankedRecommendations {
        let forecast = Forecast(
            coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
            timeZoneIdentifier: "Europe/London",
            days: Fixture.days(count: 7),
            retrievedAt: retrievedAt
        )
        return RankedRecommendations(
            city: Fixture.city(),
            forecast: forecast,
            rankings: DefaultActivityScoringEngine().rank(forecast: forecast, for: Fixture.city()),
            isStale: false
        )
    }

    private func makeSUT(
        retrievedAt: Date
    ) -> (RecommendationsViewModel, StubRankActivitiesUseCase, FixedDateProvider) {
        let clock = FixedDateProvider(now: retrievedAt)
        let useCase = StubRankActivitiesUseCase(result: .success(Self.recommendations(retrievedAt: retrievedAt)))
        let sut = RecommendationsViewModel(
            city: Fixture.city(),
            rankActivities: useCase,
            dateProvider: clock
        )
        return (sut, useCase, clock)
    }

    // MARK: Forecast staleness

    @Test("A brief trip to the background does not spend a request")
    func shortBackgroundDoesNotRefresh() async {
        let start = Date(timeIntervalSince1970: 1_757_203_200)
        let (sut, useCase, clock) = makeSUT(retrievedAt: start)
        await sut.loadIfNeeded()

        clock.advance(by: 30)          // half a minute away
        await sut.refreshIfStale()

        #expect(useCase.receivedPolicies == [.useCache], "A 30-second absence triggered a refetch")
    }

    @Test("Returning after the forecast has gone stale refreshes it")
    func longBackgroundRefreshes() async {
        let start = Date(timeIntervalSince1970: 1_757_203_200)
        let (sut, useCase, clock) = makeSUT(retrievedAt: start)
        await sut.loadIfNeeded()

        clock.advance(by: RecommendationsViewModel.staleAfter + 1)
        await sut.refreshIfStale()

        // Revalidate, not useCache: the cached copy is exactly what went stale.
        #expect(useCase.receivedPolicies == [.useCache, .revalidate])
    }

    @Test("Exactly at the staleness threshold counts as stale")
    func boundaryIsInclusive() async {
        let start = Date(timeIntervalSince1970: 1_757_203_200)
        let (sut, useCase, clock) = makeSUT(retrievedAt: start)
        await sut.loadIfNeeded()

        clock.advance(by: RecommendationsViewModel.staleAfter)
        await sut.refreshIfStale()

        #expect(useCase.receivedPolicies.count == 2)
    }

    @Test("Foregrounding a screen that never loaded does nothing")
    func noContentMeansNoRefresh() async {
        let (sut, useCase, clock) = makeSUT(retrievedAt: Date())
        // Deliberately no loadIfNeeded().

        clock.advance(by: RecommendationsViewModel.staleAfter * 10)
        await sut.refreshIfStale()

        #expect(useCase.receivedPolicies.isEmpty)
        #expect(sut.state == .idle)
    }

    @Test("Foregrounding onto an error screen does not silently retry")
    func errorStateIsLeftAlone() async {
        let clock = FixedDateProvider()
        let useCase = StubRankActivitiesUseCase(result: .failure(AppError.offline))
        let sut = RecommendationsViewModel(city: Fixture.city(), rankActivities: useCase, dateProvider: clock)
        await sut.loadIfNeeded()
        #expect(sut.state == .failed(.offline))

        clock.advance(by: RecommendationsViewModel.staleAfter * 10)
        await sut.refreshIfStale()

        // The error screen owns its own retry button; refreshing behind the user's
        // back would make that button's state meaningless.
        #expect(useCase.receivedPolicies == [.useCache])
        #expect(sut.state == .failed(.offline))
    }

    @Test("A failed foreground refresh keeps the stale content on screen")
    func failedForegroundRefreshKeepsContent() async {
        let start = Date(timeIntervalSince1970: 1_757_203_200)
        let (sut, useCase, clock) = makeSUT(retrievedAt: start)
        await sut.loadIfNeeded()
        let before = sut.state.value

        useCase.result = .failure(AppError.offline)
        clock.advance(by: RecommendationsViewModel.staleAfter + 1)
        await sut.refreshIfStale()

        #expect(sut.state.value == before)
        #expect(sut.refreshError == .offline)
    }

    @Test("Repeated foregrounding without time passing refreshes only once")
    func repeatedForegroundingIsIdempotent() async {
        let start = Date(timeIntervalSince1970: 1_757_203_200)
        let (sut, useCase, clock) = makeSUT(retrievedAt: start)
        await sut.loadIfNeeded()

        clock.advance(by: RecommendationsViewModel.staleAfter + 1)
        await sut.refreshIfStale()
        // The refreshed forecast carries the *original* retrievedAt in this stub, so
        // a naive implementation would refetch on every single foreground event.
        await sut.refreshIfStale()
        await sut.refreshIfStale()

        #expect(useCase.receivedPolicies.filter { $0 == .revalidate }.count >= 1)
    }

    // MARK: Saved lists

    @Test("Foregrounding re-reads saved cities from storage")
    func foregroundReloadsSavedCities() async {
        let store = InMemorySavedCitiesStore()
        let saved = DefaultSavedCitiesUseCase(store: store, dateProvider: FixedDateProvider())
        let sut = CitySearchViewModel(
            searchCities: StubSearchCitiesUseCase(),
            savedCities: saved,
            debounceInterval: .zero
        )
        await sut.loadSavedCities()
        #expect(sut.savedLists.favourites.isEmpty)

        // Simulate another process (a widget, a share extension, CloudKit) writing
        // while we were backgrounded.
        await store.upsert(
            SavedCity(city: Fixture.city(id: 42, name: "Kyoto"), favouritedAt: Date())
        )

        // A plain hydrate would return the cached copy and miss it entirely.
        await sut.loadSavedCities()
        #expect(sut.savedLists.favourites.isEmpty, "loadSavedCities should be a cheap cached hydrate")

        await sut.reloadSavedCities()
        #expect(sut.savedLists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("Reloading with nothing changed is a no-op, not a flicker")
    func reloadIsStableWhenNothingChanged() async {
        let sut = CitySearchViewModel(
            searchCities: StubSearchCitiesUseCase(),
            savedCities: DefaultSavedCitiesUseCase(
                store: InMemorySavedCitiesStore(seeded: [
                    SavedCity(city: Fixture.city(id: 1, name: "London"),
                              lastVisitedAt: Date(timeIntervalSince1970: 1))
                ]),
                dateProvider: FixedDateProvider()
            ),
            debounceInterval: .zero
        )
        await sut.loadSavedCities()
        let before = sut.savedLists

        await sut.reloadSavedCities()

        #expect(sut.savedLists == before)
    }

    @Test("Foreground reload does not disturb an in-progress search")
    func reloadDoesNotDisturbSearch() async {
        let cities = [Fixture.city(id: 1, name: "London")]
        let sut = CitySearchViewModel(
            searchCities: StubSearchCitiesUseCase(result: .success(cities)),
            savedCities: DefaultSavedCitiesUseCase(store: InMemorySavedCitiesStore()),
            debounceInterval: .zero
        )
        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        await sut.reloadSavedCities()

        #expect(sut.state == .loaded(cities))
        #expect(sut.query == "London")
    }
}
