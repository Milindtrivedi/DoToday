//
//  SavedCitiesUseCaseTests.swift
//  DoTodayTests
//
//  The recents/favourites rules live in the domain, so they are tested once here
//  against an in-memory store rather than being re-verified per persistence backend.
//  The interesting cases are all about the two lists overlapping.
//

import Foundation
import Testing
@testable import DoToday

@Suite("SavedCitiesUseCase")
struct SavedCitiesUseCaseTests {

    private func makeSUT(
        seeded: [SavedCity] = []
    ) -> (DefaultSavedCitiesUseCase, InMemorySavedCitiesStore, FixedDateProvider) {
        let store = InMemorySavedCitiesStore(seeded: seeded)
        let clock = FixedDateProvider()
        return (DefaultSavedCitiesUseCase(store: store, dateProvider: clock), store, clock)
    }

    /// Visits a sequence of cities, advancing the clock between each so the resulting
    /// recency order is unambiguous.
    private func visit(_ sut: DefaultSavedCitiesUseCase, _ clock: FixedDateProvider, _ cities: [City]) async {
        for city in cities {
            _ = await sut.recordVisit(to: city)
            clock.advance(by: 60)
        }
    }

    // MARK: Recents

    @Test("Both lists start empty")
    func startsEmpty() async {
        let (sut, _, _) = makeSUT()

        #expect(await sut.lists() == .empty)
    }

    @Test("The most recently visited city is first")
    func mostRecentFirst() async {
        let (sut, _, clock) = makeSUT()

        await visit(sut, clock, [Fixture.city(id: 1, name: "London"),
                                 Fixture.city(id: 2, name: "Paris"),
                                 Fixture.city(id: 3, name: "Tokyo")])

        #expect(await sut.lists().recent.map(\.name) == ["Tokyo", "Paris", "London"])
    }

    @Test("Re-visiting promotes rather than duplicating")
    func revisitPromotes() async {
        let (sut, _, clock) = makeSUT()
        await visit(sut, clock, [Fixture.city(id: 1, name: "London"), Fixture.city(id: 2, name: "Paris")])

        let lists = await sut.recordVisit(to: Fixture.city(id: 1, name: "London"))

        #expect(lists.recent.map(\.name) == ["London", "Paris"])
    }

    @Test("Recents are capped, dropping the oldest")
    func recentsAreCapped() async {
        let (sut, _, clock) = makeSUT()
        let limit = DefaultSavedCitiesUseCase.recentLimit

        await visit(sut, clock, (1...(limit + 3)).map { Fixture.city(id: $0, name: "City \($0)") })
        let recent = await sut.lists().recent

        #expect(recent.count == limit)
        #expect(recent.first?.name == "City \(limit + 3)")
        #expect(!recent.contains { $0.name == "City 1" })
    }

    @Test("Removing a recent leaves the rest in order")
    func removeRecent() async {
        let (sut, _, clock) = makeSUT()
        await visit(sut, clock, [Fixture.city(id: 1, name: "London"),
                                 Fixture.city(id: 2, name: "Paris"),
                                 Fixture.city(id: 3, name: "Tokyo")])

        let lists = await sut.removeRecent(Fixture.city(id: 2, name: "Paris"))

        #expect(lists.recent.map(\.name) == ["Tokyo", "London"])
    }

    @Test("Clearing empties recents")
    func clearRecents() async {
        let (sut, _, clock) = makeSUT()
        await visit(sut, clock, [Fixture.city(id: 1), Fixture.city(id: 2)])

        #expect(await sut.clearRecents().recent.isEmpty)
    }

    // MARK: Favourites

    @Test("Favouriting a city adds it to favourites only")
    func favouritingAddsToFavourites() async {
        let (sut, _, _) = makeSUT()

        let lists = await sut.toggleFavourite(Fixture.city(id: 1, name: "Kyoto"))

        #expect(lists.favourites.map(\.name) == ["Kyoto"])
        // Favouriting from search is not a visit — it should not pollute recents.
        #expect(lists.recent.isEmpty)
    }

    @Test("Toggling twice removes the favourite again")
    func toggleIsReversible() async {
        let (sut, _, _) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")

        _ = await sut.toggleFavourite(city)
        let lists = await sut.toggleFavourite(city)

        #expect(lists.favourites.isEmpty)
    }

    @Test("Favourites are most-recently-favourited first and are not capped")
    func favouritesOrderAndNoCap() async {
        let (sut, _, clock) = makeSUT()
        let limit = DefaultSavedCitiesUseCase.recentLimit

        for id in 1...(limit + 3) {
            _ = await sut.toggleFavourite(Fixture.city(id: id, name: "City \(id)"))
            clock.advance(by: 60)
        }
        let favourites = await sut.lists().favourites

        // Deliberately uncapped: the user curated this list, so trimming it behind
        // their back would be wrong.
        #expect(favourites.count == limit + 3)
        #expect(favourites.first?.name == "City \(limit + 3)")
    }

    @Test("isFavourite reflects the current list")
    func isFavouriteReflectsState() async {
        let (sut, _, _) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")

        #expect(await sut.lists().isFavourite(city) == false)
        _ = await sut.toggleFavourite(city)
        #expect(await sut.lists().isFavourite(city) == true)
    }

    // MARK: Where the two lists overlap

    @Test("A city can be both recent and favourite at once")
    func cityCanBeBoth() async {
        let (sut, _, clock) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")

        await visit(sut, clock, [city])
        let lists = await sut.toggleFavourite(city)

        #expect(lists.recent.map(\.id) == [1])
        #expect(lists.favourites.map(\.id) == [1])
    }

    @Test("Favouriting does not disturb recency order")
    func favouritingDoesNotReorderRecents() async {
        let (sut, _, clock) = makeSUT()
        await visit(sut, clock, [Fixture.city(id: 1, name: "London"), Fixture.city(id: 2, name: "Paris")])

        let lists = await sut.toggleFavourite(Fixture.city(id: 1, name: "London"))

        // London is favourited but was visited first, so Paris stays on top.
        #expect(lists.recent.map(\.name) == ["Paris", "London"])
    }

    @Test("Removing a recent keeps the city if it is favourited")
    func removingRecentPreservesFavourite() async {
        let (sut, _, clock) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")
        await visit(sut, clock, [city])
        _ = await sut.toggleFavourite(city)

        let lists = await sut.removeRecent(city)

        #expect(lists.recent.isEmpty)
        #expect(lists.favourites.map(\.name) == ["Kyoto"], "Swiping a recent away deleted a favourite")
    }

    @Test("Clearing recents never clears favourites")
    func clearingRecentsPreservesFavourites() async {
        let (sut, _, clock) = makeSUT()
        let favourite = Fixture.city(id: 1, name: "Kyoto")
        await visit(sut, clock, [favourite, Fixture.city(id: 2, name: "Oslo")])
        _ = await sut.toggleFavourite(favourite)

        let lists = await sut.clearRecents()

        #expect(lists.recent.isEmpty)
        #expect(lists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("Aging out of the recents cap does not lose a favourite")
    func favouriteSurvivesRecentsOverflow() async {
        let (sut, _, clock) = makeSUT()
        let favourite = Fixture.city(id: 99, name: "Kyoto")
        await visit(sut, clock, [favourite])
        _ = await sut.toggleFavourite(favourite)

        // Push it well past the cap.
        await visit(sut, clock, (1...DefaultSavedCitiesUseCase.recentLimit + 2).map {
            Fixture.city(id: $0, name: "City \($0)")
        })
        let lists = await sut.lists()

        #expect(!lists.recent.contains { $0.id == 99 }, "It should have aged out of recents")
        #expect(lists.favourites.map(\.name) == ["Kyoto"], "Ageing out of recents deleted a favourite")
    }

    // MARK: Persistence

    @Test("A record referenced by neither list is deleted, not left orphaned")
    func orphanedRecordsAreDeleted() async {
        let (sut, store, _) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")

        _ = await sut.toggleFavourite(city)
        #expect(await store.load().count == 1)

        _ = await sut.toggleFavourite(city)

        // Un-favouriting something never visited leaves nothing worth keeping.
        #expect(await store.load().isEmpty, "An orphaned row was left behind in storage")
    }

    @Test("Every mutation is written through to the store")
    func mutationsArePersisted() async {
        let (sut, store, clock) = makeSUT()
        let city = Fixture.city(id: 1, name: "Kyoto")

        await visit(sut, clock, [city])
        #expect(await store.load().first?.isRecent == true)

        _ = await sut.toggleFavourite(city)
        #expect(await store.load().first?.isFavourite == true)

        _ = await sut.removeRecent(city)
        let stored = await store.load().first
        #expect(stored?.isRecent == false)
        #expect(stored?.isFavourite == true)
    }

    @Test("State survives a new use case over the same store")
    func stateIsRehydrated() async {
        let store = InMemorySavedCitiesStore()
        let clock = FixedDateProvider()
        let first = DefaultSavedCitiesUseCase(store: store, dateProvider: clock)
        _ = await first.recordVisit(to: Fixture.city(id: 1, name: "London"))
        _ = await first.toggleFavourite(Fixture.city(id: 2, name: "Kyoto"))

        // A fresh use case, as if the app had relaunched.
        let second = DefaultSavedCitiesUseCase(store: store, dateProvider: clock)
        let lists = await second.lists()

        #expect(lists.recent.map(\.name) == ["London"])
        #expect(lists.favourites.map(\.name) == ["Kyoto"])
    }

    @Test("Concurrent mutations do not lose updates")
    func concurrentMutationsAreSerialised() async {
        let (sut, _, _) = makeSUT()

        await withTaskGroup(of: Void.self) { group in
            for id in 1...5 {
                group.addTask { _ = await sut.toggleFavourite(Fixture.city(id: id, name: "City \(id)")) }
            }
        }

        #expect(await sut.lists().favourites.count == 5)
    }
}
