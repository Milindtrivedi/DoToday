//
//  SwiftDataSavedCitiesStore.swift
//  DoToday
//
//  Data layer.
//

import Foundation
import SwiftData

/// SwiftData-backed `SavedCitiesStore`.
///
/// `@ModelActor` because `ModelContext` is not `Sendable` and must not be touched from
/// two tasks at once. The macro gives this actor its own context bound to the shared
/// container, so every read and write is serialised, and only `Sendable` domain values
/// (`SavedCity`) ever cross the actor boundary — `SavedCityRecord` instances never
/// escape, which is what keeps SwiftData's threading rules unbreakable from outside.
///
/// Every failure path degrades to "no saved cities". Losing this list is a
/// convenience regression; failing to open the search screen is not.
@ModelActor
actor SwiftDataSavedCitiesStore: SavedCitiesStore {

    func load() async -> [SavedCity] {
        let descriptor = FetchDescriptor<SavedCityRecord>()
        guard let records = try? modelContext.fetch(descriptor) else { return [] }
        return records.map(\.savedCity)
    }

    func upsert(_ saved: SavedCity) async {
        let cityID = saved.city.id
        // `cityID` is a unique attribute, so at most one row can match.
        let descriptor = FetchDescriptor<SavedCityRecord>(
            predicate: #Predicate { $0.cityID == cityID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(saved)
        } else {
            modelContext.insert(SavedCityRecord(saved))
        }
        try? modelContext.save()
    }

    func delete(cityID: Int) async {
        let descriptor = FetchDescriptor<SavedCityRecord>(
            predicate: #Predicate { $0.cityID == cityID }
        )
        guard let records = try? modelContext.fetch(descriptor) else { return }
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}

extension ModelContainer {
    /// The app's on-disk container.
    ///
    /// - Parameter inMemory: used by tests and UI-test runs so they never read or
    ///   write the developer's real database.
    static func doToday(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: SavedCityRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
