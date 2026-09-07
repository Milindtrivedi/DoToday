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
    /// The recents collaborator is the *real* use case over an in-memory store rather
    /// than a stub. Its rules are already covered in `RecentCitiesUseCaseTests`, and
    /// wiring the real one here means these tests also prove the ViewModel is
    /// connected to it correctly — which a stub would happily hide.
    private func makeSUT(
        result: Result<[City], Error> = .success([Fixture.city()]),
        debounce: Duration = .zero,
        seededRecents: [City] = []
    ) -> (CitySearchViewModel, StubSearchCitiesUseCase) {
        let useCase = StubSearchCitiesUseCase(result: result)
        let recents = DefaultRecentCitiesUseCase(
            store: InMemoryRecentCitiesStore(cities: seededRecents)
        )
        return (
            CitySearchViewModel(searchCities: useCase, recentCities: recents, debounceInterval: debounce),
            useCase
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
            recentCities: DefaultRecentCitiesUseCase(store: InMemoryRecentCitiesStore()),
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

    // MARK: Recent searches

    @Test("Recents start empty and hydrate from storage on appear")
    func recentsHydrateOnAppear() async {
        let seeded = [Fixture.city(id: 1, name: "London"), Fixture.city(id: 2, name: "Paris")]
        let (sut, _) = makeSUT(seededRecents: seeded)
        #expect(sut.recentCities.isEmpty)

        await sut.loadRecentCities()

        #expect(sut.recentCities.map(\.name) == ["London", "Paris"])
    }

    @Test("Selecting a city records it at the top of the recents list")
    func selectingRecordsRecent() async {
        let (sut, _) = makeSUT()
        await sut.loadRecentCities()

        sut.didSelect(Fixture.city(id: 1, name: "London"))
        await sut.awaitPendingRecentsUpdate()
        sut.didSelect(Fixture.city(id: 2, name: "Paris"))
        await sut.awaitPendingRecentsUpdate()

        #expect(sut.recentCities.map(\.name) == ["Paris", "London"])
    }

    @Test("Re-selecting a city promotes it without duplicating it")
    func reselectingPromotesWithoutDuplicating() async {
        let (sut, _) = makeSUT(seededRecents: [
            Fixture.city(id: 1, name: "London"),
            Fixture.city(id: 2, name: "Paris")
        ])
        await sut.loadRecentCities()

        sut.didSelect(Fixture.city(id: 2, name: "Paris"))
        await sut.awaitPendingRecentsUpdate()

        #expect(sut.recentCities.map(\.name) == ["Paris", "London"])
    }

    @Test("Removing one recent leaves the others alone")
    func removingOneRecent() async {
        let (sut, _) = makeSUT(seededRecents: [
            Fixture.city(id: 1, name: "London"),
            Fixture.city(id: 2, name: "Paris")
        ])
        await sut.loadRecentCities()

        sut.removeRecentCity(Fixture.city(id: 1, name: "London"))
        await sut.awaitPendingRecentsUpdate()

        #expect(sut.recentCities.map(\.name) == ["Paris"])
    }

    @Test("Clearing empties the recents list")
    func clearingRecents() async {
        let (sut, _) = makeSUT(seededRecents: [Fixture.city(id: 1), Fixture.city(id: 2)])
        await sut.loadRecentCities()

        sut.clearRecentCities()
        await sut.awaitPendingRecentsUpdate()

        #expect(sut.recentCities.isEmpty)
    }

    @Test("Recents survive a search and the return to idle")
    func recentsSurviveASearchCycle() async {
        let (sut, _) = makeSUT(seededRecents: [Fixture.city(id: 1, name: "London")])
        await sut.loadRecentCities()

        sut.query = "Paris"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()
        #expect(sut.state.value != nil)

        sut.query = ""
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        // Back at idle, and the list the idle state renders is still intact.
        #expect(sut.state == .idle)
        #expect(sut.recentCities.map(\.name) == ["London"])
    }

    @Test("Recording a selection does not disturb the search state")
    func recordingDoesNotAffectSearchState() async {
        let cities = [Fixture.city(id: 1, name: "London")]
        let (sut, _) = makeSUT(result: .success(cities))
        sut.query = "London"
        sut.queryDidChange()
        await sut.awaitCurrentSearch()

        sut.didSelect(cities[0])
        await sut.awaitPendingRecentsUpdate()

        // Navigating away must leave the results on screen for the back journey.
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
