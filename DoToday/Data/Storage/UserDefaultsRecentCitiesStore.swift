//
//  UserDefaultsRecentCitiesStore.swift
//  DoToday
//
//  Data layer.
//

import Foundation

/// `UserDefaults`-backed recents list.
///
/// `UserDefaults` rather than a file or a database: the payload is at most five small
/// records, it must survive relaunch, and it is not sensitive. A database here would
/// be more machinery than the data justifies — and the `RecentCitiesStore` seam means
/// swapping to SwiftData later touches this one file.
///
/// Every failure path degrades to "no recents". Losing a convenience list is a
/// non-event; failing to open the search screen because of one is not.
/// `@unchecked Sendable` because `UserDefaults` is not marked `Sendable` but is
/// documented as thread-safe. The unchecked conformance is confined to this one type
/// rather than being papered over at the protocol.
struct UserDefaultsRecentCitiesStore: RecentCitiesStore, @unchecked Sendable {
    static let defaultKey = "com.collinson.DoToday.recentCities"

    private let defaults: UserDefaults
    private let key: String

    /// - Parameter defaults: Injected so tests can use an isolated suite rather than
    ///   writing into the app's real preferences.
    init(defaults: UserDefaults = .standard, key: String = UserDefaultsRecentCitiesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() async -> [City] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let stored = try? JSONDecoder().decode([RecentCityDTO].self, from: data) else {
            // Unreadable data is from an older or corrupted write. Clear it so we do
            // not re-attempt the same failing decode on every launch.
            defaults.removeObject(forKey: key)
            return []
        }
        // `compactMap` drops individual entries written by a newer schema while
        // keeping the ones we still understand.
        return stored.compactMap(\.city)
    }

    func save(_ cities: [City]) async {
        guard let data = try? JSONEncoder().encode(cities.map(RecentCityDTO.init)) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Non-persisting store for tests, previews and UI-test runs.
actor InMemoryRecentCitiesStore: RecentCitiesStore {
    private var cities: [City]

    init(cities: [City] = []) {
        self.cities = cities
    }

    func load() async -> [City] { cities }

    func save(_ cities: [City]) async { self.cities = cities }
}
