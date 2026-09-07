//
//  RecentCitiesStore.swift
//  DoToday
//
//  Domain layer — persistence port for the recent-search list.
//

import Foundation

/// Dumb storage for the recently-viewed cities.
///
/// Deliberately minimal: it loads and saves a list and knows nothing about ordering,
/// de-duplication or how many entries to keep. Those are product rules, so they live
/// in `RecentCitiesUseCase` where they can be tested without touching persistence —
/// and so a future SwiftData or CloudKit implementation inherits them for free rather
/// than having to re-implement them correctly.
protocol RecentCitiesStore: Sendable {
    /// Most-recent-first. Returns an empty array when nothing is stored, when the
    /// stored data is unreadable, or on first launch — never throws. A broken recents
    /// list must not be able to block the search screen.
    func load() async -> [City]

    /// Replaces the stored list wholesale.
    func save(_ cities: [City]) async
}
