//
//  RecentCitiesUseCaseTests.swift
//  DoTodayTests
//
//  The recent-list rules — ordering, de-duplication and the cap — live in the domain,
//  so they are tested here once against an in-memory store rather than being
//  re-verified against every persistence backend.
//

import Foundation
import Testing
@testable import DoToday

@Suite("RecentCitiesUseCase")
struct RecentCitiesUseCaseTests {

    private func makeSUT(seeded: [City] = []) -> (DefaultRecentCitiesUseCase, InMemoryRecentCitiesStore) {
        let store = InMemoryRecentCitiesStore(cities: seeded)
        return (DefaultRecentCitiesUseCase(store: store), store)
    }

    @Test("Starts empty on a first launch")
    func startsEmpty() async {
        let (sut, _) = makeSUT()

        #expect(await sut.load().isEmpty)
    }

    @Test("Hydrates from whatever the store already holds")
    func loadsPersistedList() async {
        let seeded = [Fixture.city(id: 1, name: "London"), Fixture.city(id: 2, name: "Paris")]
        let (sut, _) = makeSUT(seeded: seeded)

        #expect(await sut.load().map(\.name) == ["London", "Paris"])
    }

    @Test("The most recently selected city goes to the front")
    func mostRecentFirst() async {
        let (sut, _) = makeSUT()

        _ = await sut.record(Fixture.city(id: 1, name: "London"))
        _ = await sut.record(Fixture.city(id: 2, name: "Paris"))
        let result = await sut.record(Fixture.city(id: 3, name: "Tokyo"))

        #expect(result.map(\.name) == ["Tokyo", "Paris", "London"])
    }

    @Test("Re-selecting a city moves it up instead of duplicating it")
    func reselectionDeduplicates() async {
        let (sut, _) = makeSUT()
        _ = await sut.record(Fixture.city(id: 1, name: "London"))
        _ = await sut.record(Fixture.city(id: 2, name: "Paris"))

        let result = await sut.record(Fixture.city(id: 1, name: "London"))

        #expect(result.map(\.name) == ["London", "Paris"])
        #expect(result.count == 2, "The list grew — de-duplication is not working")
    }

    @Test("The list is capped, dropping the oldest entry")
    func listIsCapped() async {
        let (sut, _) = makeSUT()

        for id in 1...(DefaultRecentCitiesUseCase.limit + 3) {
            _ = await sut.record(Fixture.city(id: id, name: "City \(id)"))
        }
        let result = await sut.load()

        #expect(result.count == DefaultRecentCitiesUseCase.limit)
        // Newest first, and the earliest entries are gone.
        #expect(result.first?.name == "City \(DefaultRecentCitiesUseCase.limit + 3)")
        #expect(!result.contains { $0.name == "City 1" })
    }

    @Test("Removing an entry leaves the rest in order")
    func removeSingleEntry() async {
        let (sut, _) = makeSUT(seeded: [
            Fixture.city(id: 1, name: "London"),
            Fixture.city(id: 2, name: "Paris"),
            Fixture.city(id: 3, name: "Tokyo")
        ])

        let result = await sut.remove(Fixture.city(id: 2, name: "Paris"))

        #expect(result.map(\.name) == ["London", "Tokyo"])
    }

    @Test("Removing a city that is not in the list is a no-op, not a crash")
    func removeAbsentEntry() async {
        let (sut, _) = makeSUT(seeded: [Fixture.city(id: 1, name: "London")])

        let result = await sut.remove(Fixture.city(id: 99, name: "Nowhere"))

        #expect(result.map(\.name) == ["London"])
    }

    @Test("Clearing empties the list")
    func clearEmptiesList() async {
        let (sut, _) = makeSUT(seeded: [Fixture.city(id: 1), Fixture.city(id: 2)])

        await sut.clear()

        #expect(await sut.load().isEmpty)
    }

    // MARK: Persistence

    @Test("Every mutation is written through to the store, not just held in memory")
    func mutationsArePersisted() async {
        let (sut, store) = makeSUT()

        _ = await sut.record(Fixture.city(id: 1, name: "London"))
        #expect(await store.load().map(\.name) == ["London"])

        _ = await sut.record(Fixture.city(id: 2, name: "Paris"))
        #expect(await store.load().map(\.name) == ["Paris", "London"])

        _ = await sut.remove(Fixture.city(id: 2, name: "Paris"))
        #expect(await store.load().map(\.name) == ["London"])

        await sut.clear()
        #expect(await store.load().isEmpty)
    }

    @Test("Concurrent selections do not lose entries")
    func concurrentRecordsDoNotLoseUpdates() async {
        // Actor isolation should serialise these. A plain struct doing
        // read-modify-write here would drop entries under a lost update.
        let (sut, _) = makeSUT()

        await withTaskGroup(of: Void.self) { group in
            for id in 1...5 {
                group.addTask { _ = await sut.record(Fixture.city(id: id, name: "City \(id)")) }
            }
        }

        let result = await sut.load()
        #expect(result.count == 5)
        #expect(Set(result.map(\.id)) == Set(1...5))
    }
}
