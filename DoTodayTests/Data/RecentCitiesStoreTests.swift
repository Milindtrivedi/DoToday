//
//  RecentCitiesStoreTests.swift
//  DoTodayTests
//
//  Covers the persistence boundary: that a city survives a round trip intact, and
//  that every corruption path degrades to an empty list rather than to a failure.
//

import Foundation
import Testing
@testable import DoToday

@Suite("UserDefaultsRecentCitiesStore")
struct UserDefaultsRecentCitiesStoreTests {

    /// A throwaway suite per test, so nothing touches the app's real preferences and
    /// tests cannot leak state into one another.
    private func makeSUT() -> (UserDefaultsRecentCitiesStore, UserDefaults, String) {
        let suiteName = "DoTodayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let key = "recents"
        return (UserDefaultsRecentCitiesStore(defaults: defaults, key: key), defaults, key)
    }

    @Test("An empty store loads as an empty list, not a failure")
    func emptyStore() async {
        let (sut, _, _) = makeSUT()

        #expect(await sut.load().isEmpty)
    }

    @Test("A city survives the round trip with every field intact")
    func roundTripsAllFields() async throws {
        let (sut, _, _) = makeSUT()
        let city = Fixture.city(
            id: 2988507, name: "Paris", admin1: "Île-de-France",
            country: "France", countryCode: "FR",
            latitude: 48.85341, longitude: 2.3488,
            elevation: 42, timeZoneIdentifier: "Europe/Paris"
        )

        await sut.save([city])
        let loaded = try #require(await sut.load().first)

        #expect(loaded == city)
    }

    @Test("Order is preserved across a save and load")
    func preservesOrder() async {
        let (sut, _, _) = makeSUT()
        let cities = (1...5).map { Fixture.city(id: $0, name: "City \($0)") }

        await sut.save(cities)

        #expect(await sut.load().map(\.id) == cities.map(\.id))
    }

    @Test("Saving replaces the previous list rather than appending to it")
    func saveReplaces() async {
        let (sut, _, _) = makeSUT()

        await sut.save([Fixture.city(id: 1, name: "London")])
        await sut.save([Fixture.city(id: 2, name: "Paris")])

        #expect(await sut.load().map(\.name) == ["Paris"])
    }

    @Test("Cities with missing optional fields round-trip as nil, not as empty strings")
    func roundTripsOptionalFields() async throws {
        let (sut, _, _) = makeSUT()
        let sparse = Fixture.city(
            id: 7, name: "Nowhere", admin1: nil, country: nil, countryCode: nil,
            elevation: nil, timeZoneIdentifier: nil
        )

        await sut.save([sparse])
        let loaded = try #require(await sut.load().first)

        #expect(loaded == sparse)
        #expect(loaded.elevation == nil)
        #expect(loaded.timeZoneIdentifier == nil)
    }

    @Test("Unreadable stored data yields an empty list and is cleared")
    func corruptDataIsDiscarded() async {
        let (sut, defaults, key) = makeSUT()
        defaults.set(Data("this is not JSON".utf8), forKey: key)

        #expect(await sut.load().isEmpty)
        // Cleared, so we do not re-attempt the same failing decode on every launch.
        #expect(defaults.data(forKey: key) == nil)
    }

    @Test("Data of the wrong shape is treated as corrupt rather than crashing")
    func wrongShapeIsDiscarded() async {
        let (sut, defaults, key) = makeSUT()
        defaults.set(try! JSONEncoder().encode(["unexpected": "object"]), forKey: key)

        #expect(await sut.load().isEmpty)
    }

    @Test("An entry from a newer schema is skipped, and its siblings still load")
    func futureSchemaEntriesAreSkipped() async {
        let (sut, defaults, key) = makeSUT()
        // Hand-rolled payload: one readable entry, one written by a hypothetical
        // future version of the app.
        let json = """
        [
          {"schemaVersion":1,"id":1,"name":"London","latitude":51.5,"longitude":-0.12},
          {"schemaVersion":99,"id":2,"name":"From The Future","latitude":0,"longitude":0}
        ]
        """
        defaults.set(Data(json.utf8), forKey: key)

        let loaded = await sut.load()

        #expect(loaded.map(\.name) == ["London"])
    }
}

@Suite("InMemoryRecentCitiesStore")
struct InMemoryRecentCitiesStoreTests {

    @Test("Behaves like the real store for the operations the use case relies on")
    func matchesTheContract() async {
        let sut = InMemoryRecentCitiesStore()

        #expect(await sut.load().isEmpty)

        await sut.save([Fixture.city(id: 1, name: "London")])
        #expect(await sut.load().map(\.name) == ["London"])

        await sut.save([])
        #expect(await sut.load().isEmpty)
    }

    @Test("Can be seeded, so tests can start from a populated list")
    func canBeSeeded() async {
        let sut = InMemoryRecentCitiesStore(cities: [Fixture.city(id: 1, name: "Seeded")])

        #expect(await sut.load().map(\.name) == ["Seeded"])
    }
}
