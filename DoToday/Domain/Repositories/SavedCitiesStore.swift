//
//  SavedCitiesStore.swift
//  DoToday
//
//  Domain layer — persistence port for saved cities.
//

import Foundation

/// CRUD over persisted `SavedCity` records, and nothing more.
///
/// The store deliberately knows no policy: not how many recents to keep, not how they
/// are ordered, not when a record becomes orphaned. Those rules live in
/// `SavedCitiesUseCase`, so a second backend inherits them instead of having to
/// re-implement them correctly.
protocol SavedCitiesStore: Sendable {
    /// Every record, in no guaranteed order. Returns empty rather than throwing —
    /// a broken saved list must never be able to block the search screen.
    func load() async -> [SavedCity]

    /// Inserts or replaces the record for this city.
    func upsert(_ saved: SavedCity) async

    /// Removes the record for this city entirely, if present.
    func delete(cityID: Int) async
}
