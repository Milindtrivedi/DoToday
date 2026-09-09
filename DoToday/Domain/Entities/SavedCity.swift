//
//  SavedCity.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// A city the user has some persisted relationship with.
///
/// One record per city, carrying two *independent* timestamps, rather than two
/// separate lists. A city is very often both recently visited and favourited, and
/// modelling that as two lists means storing it twice and keeping the copies in
/// agreement — the sort of duplication that eventually disagrees with itself.
///
/// The two lists the UI shows are just projections of this one collection:
/// recents are records with a `lastVisitedAt`, favourites are records with a
/// `favouritedAt`.
struct SavedCity: Equatable, Sendable, Identifiable {
    let city: City
    /// When the user last opened this city's recommendations. `nil` means it is
    /// favourited but has not been opened (or has aged out of the recents cap).
    let lastVisitedAt: Date?
    /// When the user favourited it. `nil` means it is not a favourite.
    let favouritedAt: Date?

    var id: Int { city.id }

    var isRecent: Bool { lastVisitedAt != nil }
    var isFavourite: Bool { favouritedAt != nil }

    /// A record no longer referenced by either list, and therefore safe to delete.
    var isOrphaned: Bool { lastVisitedAt == nil && favouritedAt == nil }

    init(city: City, lastVisitedAt: Date? = nil, favouritedAt: Date? = nil) {
        self.city = city
        self.lastVisitedAt = lastVisitedAt
        self.favouritedAt = favouritedAt
    }

    func visited(at date: Date) -> SavedCity {
        SavedCity(city: city, lastVisitedAt: date, favouritedAt: favouritedAt)
    }

    func favourited(at date: Date?) -> SavedCity {
        SavedCity(city: city, lastVisitedAt: lastVisitedAt, favouritedAt: date)
    }

    /// Drops this record out of the recents list without touching its favourite status.
    func forgettingVisit() -> SavedCity {
        SavedCity(city: city, lastVisitedAt: nil, favouritedAt: favouritedAt)
    }
}
