//
//  SwiftDataSavedCitiesStoreTests.swift
//  DoTodayTests
//
//  Covers the SwiftData boundary itself: that a record round-trips with every field
//  intact, that upsert genuinely updates rather than inserting a duplicate, and that
//  the two independent timestamps survive persistence.
//
//  Each test gets its own in-memory container, so nothing touches the developer's
//  real database and no test can leak state into another.
//

import Foundation
import SwiftData
import Testing
@testable import DoToday

@Suite("SwiftDataSavedCitiesStore")
struct SwiftDataSavedCitiesStoreTests {

    private func makeSUT() throws -> SwiftDataSavedCitiesStore {
        SwiftDataSavedCitiesStore(modelContainer: try .doToday(inMemory: true))
    }

    @Test("An empty store loads as an empty list, not a failure")
    func emptyStore() async throws {
        let sut = try makeSUT()

        #expect(await sut.load().isEmpty)
    }

    @Test("A record round-trips with every field intact")
    func roundTripsAllFields() async throws {
        let sut = try makeSUT()
        let city = Fixture.city(
            id: 2988507, name: "Paris", admin1: "Île-de-France",
            country: "France", countryCode: "FR",
            latitude: 48.85341, longitude: 2.3488,
            elevation: 42, timeZoneIdentifier: "Europe/Paris"
        )
        let visited = Date(timeIntervalSince1970: 1_757_203_200)
        let favourited = Date(timeIntervalSince1970: 1_757_289_600)

        await sut.upsert(SavedCity(city: city, lastVisitedAt: visited, favouritedAt: favourited))
        let loaded = try #require(await sut.load().first)

        #expect(loaded.city == city)
        #expect(loaded.lastVisitedAt == visited)
        #expect(loaded.favouritedAt == favourited)
    }

    @Test("Cities with missing optional fields round-trip as nil")
    func roundTripsOptionalFields() async throws {
        let sut = try makeSUT()
        let sparse = Fixture.city(
            id: 7, name: "Nowhere", admin1: nil, country: nil, countryCode: nil,
            elevation: nil, timeZoneIdentifier: nil
        )

        await sut.upsert(SavedCity(city: sparse, lastVisitedAt: Date()))
        let loaded = try #require(await sut.load().first)

        #expect(loaded.city == sparse)
        #expect(loaded.city.elevation == nil)
        #expect(loaded.favouritedAt == nil)
    }

    @Test("Upserting the same city updates the row instead of duplicating it")
    func upsertUpdatesInPlace() async throws {
        let sut = try makeSUT()
        let city = Fixture.city(id: 1, name: "London")
        let first = Date(timeIntervalSince1970: 1_000_000)
        let second = Date(timeIntervalSince1970: 2_000_000)

        await sut.upsert(SavedCity(city: city, lastVisitedAt: first))
        await sut.upsert(SavedCity(city: city, lastVisitedAt: second, favouritedAt: second))

        let all = await sut.load()
        #expect(all.count == 1, "cityID is a unique attribute; a second row should be impossible")
        #expect(all.first?.lastVisitedAt == second)
        #expect(all.first?.favouritedAt == second)
    }

    @Test("Upsert can clear a timestamp back to nil")
    func upsertCanClearTimestamps() async throws {
        let sut = try makeSUT()
        let city = Fixture.city(id: 1)
        await sut.upsert(SavedCity(city: city, lastVisitedAt: Date(), favouritedAt: Date()))

        // This is how un-favouriting a still-recent city is persisted; if `apply`
        // skipped nils the favourite would silently survive.
        await sut.upsert(SavedCity(city: city, lastVisitedAt: Date(), favouritedAt: nil))

        #expect(await sut.load().first?.favouritedAt == nil)
    }

    @Test("Deleting removes the row")
    func deleteRemovesRow() async throws {
        let sut = try makeSUT()
        await sut.upsert(SavedCity(city: Fixture.city(id: 1), lastVisitedAt: Date()))
        await sut.upsert(SavedCity(city: Fixture.city(id: 2), lastVisitedAt: Date()))

        await sut.delete(cityID: 1)

        #expect(await sut.load().map(\.id) == [2])
    }

    @Test("Deleting a city that is not stored is a no-op, not a crash")
    func deleteAbsentIsNoOp() async throws {
        let sut = try makeSUT()
        await sut.upsert(SavedCity(city: Fixture.city(id: 1), lastVisitedAt: Date()))

        await sut.delete(cityID: 99)

        #expect(await sut.load().count == 1)
    }

    @Test("Data persists across a new store over the same container")
    func persistsAcrossStoreInstances() async throws {
        let container = try ModelContainer.doToday(inMemory: true)
        let first = SwiftDataSavedCitiesStore(modelContainer: container)
        await first.upsert(SavedCity(city: Fixture.city(id: 1, name: "London"), lastVisitedAt: Date()))

        // A second store over the same container, as if the app had relaunched.
        let second = SwiftDataSavedCitiesStore(modelContainer: container)

        #expect(await second.load().map(\.city.name) == ["London"])
    }

    @Test("The store satisfies the use case's rules end to end")
    func integratesWithTheUseCase() async throws {
        // The domain rules are unit-tested against the in-memory store; this proves
        // the real backend satisfies the same contract rather than only the fake.
        let sut = DefaultSavedCitiesUseCase(store: try makeSUT(), dateProvider: FixedDateProvider())
        let city = Fixture.city(id: 1, name: "Kyoto")

        _ = await sut.recordVisit(to: city)
        _ = await sut.toggleFavourite(city)
        let lists = await sut.removeRecent(city)

        #expect(lists.recent.isEmpty)
        #expect(lists.favourites.map(\.name) == ["Kyoto"])
    }
}
