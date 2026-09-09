//
//  CitySearchViewModelTests.swift
//  DoTodayTests
//
//  The search screen's whole behaviour — state transitions, debouncing and
//  cancellation — is exercised here without any SwiftUI involved. That is the payoff
//  of keeping the view a pure function of `state`.
//

import Foundation
import Testing
@testable import DoToday

@MainActor
@Suite("CitySearchViewModel")
struct CitySearchViewModelTests {

    /// Zero debounce by default: the delay is a UX concern and is tested on its own,
    /// so every other test can run instantly and deterministically.
    ///
    /// The saved-cities collaborator is the *real* use case over an in-memory store
    /// rather than a stub. Its rules are already covered in `SavedCitiesUseCaseTests`,
    /// and wiring the real one here means these tests also prove the ViewModel is
    /// connected to it correctly — which a stub would happily hide.
    private func makeSUT(
        result: Result<[City], Error> = .success([Fixture.city()]),
        debounce: Duration = .zero,
        seeded: [SavedCity] = []
    ) -> (CitySearchViewModel, StubSearchCitiesUseCase) {
        let useCase = StubSearchCitiesUseCase(result: result)
        let saved = DefaultSavedCitiesUseCase(
            store: InMemorySavedCitiesStore(seeded: seeded),
            dateProvider: FixedDateProvider()
        )
        return (
            CitySearchViewModel(searchCities: useCase, savedCities: saved, debounceInterval: debounce),
            useCase
        )
    }

    /// Builds a seeded record. `visitedAt`/`favouritedAt` offsets keep ordering
    /// unambiguous without a real clock.
    private func saved(
        id: Int, name: String, visited: TimeInterval? = nil, favourited: TimeInterval? = nil
    ) -> SavedCity {
        let base = Date(timeIntervalSince1970: 1_757_203_200)
        return SavedCity(
            city: Fixture.city(id: id, name: name),
            lastVisitedAt: visited.map { base.addingTimeInterval($0) },
            favouritedAt: favourited.map { base.addingTimeInterval($0) }
        )
    }

    // MARK: State transitions

    @Test("Starts idle, before the user has asked anything")
    func startsIdle() {
        let (sut, _) = makeSUT()

        #expect(sut.state == .idle)
    }

    @Test("A query below the minimum length returns to idle without searching",
          arguments: ["", "L", " "])
    func shortQueryStaysIdle(query: String) async {
        let (sut, useCase) = makeSUT()

        sut.query = query
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        // Idle, not `.empty`: the user hasn't finished asking a question yet, so
        // telling them "no matches" would be wrong as well as unhelpful.
        #expect(sut.state == .idle)
        #expect(useCase.receivedQueries.isEmpty)
    }

    @Test("Results move the screen to loaded")
    func successfulSearchLoadsResults() async {
        let cities = [Fixture.city(id: 1, name: "London"), Fixture.city(id: 2, name: "Londonderry")]
        let (sut, _) = makeSUT(result: .success(cities))

        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state == .loaded(cities))
    }

    @Test("Enters the loading state synchronously, so the spinner appears immediately")
    func showsLoadingWhileSearching() {
        let (sut, _) = makeSUT()

        sut.query = "London"
        sut.queryDidChange()

        // Asserted before awaiting: a loading state that only appears after the
        // request resolves is useless to the user.
        #expect(sut.state == .loading)
    }

    @Test("No matches produces the dedicated empty state, not an error")
    func noMatchesProducesEmptyState() async {
        let (sut, _) = makeSUT(result: .success([]))

        sut.query = "Xyzzy"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state == .empty)
    }

    @Test("Failures are surfaced with the underlying error preserved",
          arguments: [AppError.offline, .timedOut, .server(statusCode: 500), .invalidResponse])
    func failuresAreSurfaced(error: AppError) async {
        let (sut, _) = makeSUT(result: .failure(error))

        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state == .failed(error))
    }

    @Test("An unrecognised error still leaves the screen in a renderable state")
    func unknownErrorsAreWrapped() async {
        struct Weird: Error {}
        let (sut, _) = makeSUT(result: .failure(Weird()))

        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        guard case .failed(.unknown) = sut.state else {
            Issue.record("Expected .failed(.unknown), got \(sut.state)")
            return
        }
    }

    @Test("Retry re-runs the current query")
    func retryRepeatsTheQuery() async {
        let (sut, useCase) = makeSUT(result: .failure(AppError.offline))

        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()
        #expect(sut.state == .failed(.offline))

        useCase.result = .success([Fixture.city(name: "London")])
        sut.retry()
        await sut.awaitCurrentSearch()

        #expect(sut.state.value?.map(\.name) == ["London"])
        #expect(useCase.receivedQueries == ["London", "London"])
    }

    // MARK: Debouncing and cancellation

    @Test("A burst of keystrokes results in a single request for the final query")
    func debounceCollapsesKeystrokes() async {
        let (sut, useCase) = makeSUT(debounce: .milliseconds(60))

        for text in ["Lo", "Lon", "Lond", "London"] {
            sut.query = text
            sut.queryDidChange()
        }
        await sut.awaitCurrentSearch()

        #expect(useCase.receivedQueries == ["London"], "Every keystroke fired its own request")
    }

    @Test("The query is trimmed before dispatch")
    func trimsQueryBeforeDispatch() async {
        let (sut, useCase) = makeSUT()

        sut.query = "  London  "
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(useCase.receivedQueries == ["London"])
    }

    @Test("A superseded search cannot overwrite newer state")
    func supersededSearchDoesNotClobberNewerResults() async {
        let useCase = StubSearchCitiesUseCase(result: .success([Fixture.city(name: "Stale")]))
        let sut = CitySearchViewModel(
            searchCities: useCase,
            savedCities: DefaultSavedCitiesUseCase(store: InMemorySavedCitiesStore()),
            debounceInterval: .milliseconds(40)
        )

        sut.query = "Sta"
        sut.queryDidChange()               // starts, then is cancelled mid-debounce
        useCase.result = .success([Fixture.city(name: "Fresh")])
        sut.query = "Fre"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state.value?.map(\.name) == ["Fresh"])
        #expect(useCase.receivedQueries == ["Fre"])
    }

    // MARK: Saved cities

    @Test("Both lists start empty and hydrate from storage on appear")
    func savedListsHydrateOnAppear() async {
        let (sut, _) = makeSUT(seeded: [
            saved(id: 1, name: "London", visited: 0),
            saved(id: 2, name: "Kyoto", favourited: 0)
        ])
        #expect(sut.savedLists == .empty)

        await sut.loadSavedCities()

        #expect(sut.savedLists.recent.map(\.name) == ["London"])
        #expect(sut.savedLists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("The Recent tab is the default")
    func recentTabIsDefault() {
        let (sut, _) = makeSUT()

        // Recents fill themselves; favourites need deliberate action, so the list
        // that is useful without any setup is the one shown first.
        #expect(sut.savedTab == .recent)
    }

    @Test("Selecting a city records it as recent")
    func selectingRecordsRecent() async {
        let (sut, _) = makeSUT()
        await sut.loadSavedCities()

        sut.didSelect(Fixture.city(id: 1, name: "London"))
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.savedLists.recent.map(\.name) == ["London"])
    }

    @Test("Favouriting from search adds a favourite without creating a recent")
    func favouritingDoesNotCreateARecent() async {
        let (sut, _) = makeSUT()
        await sut.loadSavedCities()

        sut.toggleFavourite(Fixture.city(id: 1, name: "Kyoto"))
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.savedLists.favourites.map(\.name) == ["Kyoto"])
        // Starring a search result is not the same as opening it.
        #expect(sut.savedLists.recent.isEmpty)
    }

    @Test("Toggling twice removes the favourite")
    func toggleIsReversible() async {
        let (sut, _) = makeSUT()
        await sut.loadSavedCities()
        let city = Fixture.city(id: 1, name: "Kyoto")

        sut.toggleFavourite(city)
        await sut.awaitPendingSavedCitiesUpdate()
        sut.toggleFavourite(city)
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.savedLists.favourites.isEmpty)
    }

    @Test("isFavourite drives the star and tracks the toggle")
    func isFavouriteTracksState() async {
        let (sut, _) = makeSUT()
        await sut.loadSavedCities()
        let city = Fixture.city(id: 1, name: "Kyoto")
        #expect(!sut.isFavourite(city))

        sut.toggleFavourite(city)
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.isFavourite(city))
    }

    @Test("Removing a recent keeps the city when it is also favourited")
    func removingRecentPreservesFavourite() async {
        let (sut, _) = makeSUT(seeded: [saved(id: 1, name: "Kyoto", visited: 0, favourited: 0)])
        await sut.loadSavedCities()

        sut.removeRecentCity(Fixture.city(id: 1, name: "Kyoto"))
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.savedLists.recent.isEmpty)
        #expect(sut.savedLists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("Clearing recents leaves favourites alone")
    func clearingRecentsPreservesFavourites() async {
        let (sut, _) = makeSUT(seeded: [
            saved(id: 1, name: "Kyoto", visited: 0, favourited: 0),
            saved(id: 2, name: "Oslo", visited: 60)
        ])
        await sut.loadSavedCities()

        sut.clearRecentCities()
        await sut.awaitPendingSavedCitiesUpdate()

        #expect(sut.savedLists.recent.isEmpty)
        #expect(sut.savedLists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("Saved lists survive a search and the return to idle")
    func savedListsSurviveASearchCycle() async {
        let (sut, _) = makeSUT(seeded: [saved(id: 1, name: "London", visited: 0)])
        await sut.loadSavedCities()

        sut.query = "Paris"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()
        #expect(sut.state.value != nil)

        sut.query = ""
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state == .idle)
        #expect(sut.savedLists.recent.map(\.name) == ["London"])
    }

    @Test("Favouriting does not disturb the search results on screen")
    func favouritingDoesNotAffectSearchState() async {
        let cities = [Fixture.city(id: 1, name: "London")]
        let (sut, _) = makeSUT(result: .success(cities))
        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        sut.toggleFavourite(cities[0])
        await sut.awaitPendingSavedCitiesUpdate()

        // The star is an in-place action; it must not collapse the results list.
        #expect(sut.state == .loaded(cities))
    }

    @Test("Clearing the field after a search returns the screen to idle")
    func clearingQueryResetsToIdle() async {
        let (sut, _) = makeSUT()

        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()
        #expect(sut.state.value != nil)

        sut.query = ""
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        #expect(sut.state == .idle)
    }
}
