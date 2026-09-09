//
//  InMemorySavedCitiesStore.swift
//  DoToday
//
//  Data layer — non-persisting store for tests, previews, and as the last-resort
//  fallback when SwiftData cannot open its container.
//

import Foundation

actor InMemorySavedCitiesStore: SavedCitiesStore {
    private var records: [Int: SavedCity]

    init(seeded: [SavedCity] = []) {
        self.records = Dictionary(uniqueKeysWithValues: seeded.map { ($0.id, $0) })
    }

    func load() async -> [SavedCity] {
        Array(records.values)
    }

    func upsert(_ saved: SavedCity) async {
        records[saved.id] = saved
    }

    func delete(cityID: Int) async {
        records[cityID] = nil
    }
}
