//
//  RecentCitiesUseCase.swift
//  DoToday
//
//  Domain layer — the rules governing the recent-search list.
//

import Foundation

protocol RecentCitiesUseCase: Sendable {
    /// The current list, most-recent-first.
    func load() async -> [City]
    /// Records a visit and returns the updated list.
    func record(_ city: City) async -> [City]
    /// Removes one entry and returns the updated list.
    func remove(_ city: City) async -> [City]
    /// Empties the list.
    func clear() async
}

/// Owns the recent-list policy: most-recent-first, de-duplicated by city id, capped.
///
/// An `actor` because every operation is a read-modify-write over shared state. Two
/// concurrent `record` calls against a plain struct could each read the old list and
/// write back a version missing the other's entry — a classic lost update. Actor
/// isolation serialises them, and the in-memory copy means no mutation is ever split
/// across an `await`.
actor DefaultRecentCitiesUseCase: RecentCitiesUseCase {
    /// Five is enough to be useful and short enough that the list never competes with
    /// the search results for attention.
    static let limit = 5

    private let store: RecentCitiesStore
    /// Authoritative in-memory copy, hydrated from the store on first access. `nil`
    /// means "not loaded yet", which is distinct from "loaded and empty".
    private var cities: [City]?

    init(store: RecentCitiesStore) {
        self.store = store
    }

    func load() async -> [City] {
        await hydrated()
    }

    func record(_ city: City) async -> [City] {
        var updated = await hydrated()
        // Re-selecting a city moves it to the top rather than duplicating it.
        updated.removeAll { $0.id == city.id }
        updated.insert(city, at: 0)
        updated = Array(updated.prefix(Self.limit))

        cities = updated
        await store.save(updated)
        return updated
    }

    func remove(_ city: City) async -> [City] {
        var updated = await hydrated()
        updated.removeAll { $0.id == city.id }

        cities = updated
        await store.save(updated)
        return updated
    }

    func clear() async {
        cities = []
        await store.save([])
    }

    /// Returns the in-memory list, loading it from the store the first time.
    private func hydrated() async -> [City] {
        if let cities { return cities }

        let loaded = await store.load()
        // Actors are reentrant: another call may have hydrated us while we were
        // suspended on the store. If so, that value wins — adopting `loaded` here
        // would discard whatever it recorded in the meantime.
        if let cities { return cities }

        cities = loaded
        return loaded
    }
}
