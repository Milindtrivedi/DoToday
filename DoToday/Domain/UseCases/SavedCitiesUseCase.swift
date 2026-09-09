//
//  SavedCitiesUseCase.swift
//  DoToday
//
//  Domain layer — the rules governing recents and favourites.
//

import Foundation

/// The two projections of the saved-cities collection, plus the mutations the UI can
/// make. Both lists are returned together so the caller can never render a favourites
/// list that disagrees with the recents list it was fetched alongside.
struct SavedCityLists: Equatable, Sendable {
    /// Most-recently visited first, capped.
    let recent: [City]
    /// Most-recently favourited first, uncapped.
    let favourites: [City]

    static let empty = SavedCityLists(recent: [], favourites: [])

    func isFavourite(_ city: City) -> Bool {
        favourites.contains { $0.id == city.id }
    }
}

protocol SavedCitiesUseCase: Sendable {
    func lists() async -> SavedCityLists
    /// Records that the user opened this city's recommendations.
    func recordVisit(to city: City) async -> SavedCityLists
    /// Adds or removes a favourite, leaving recency untouched.
    func toggleFavourite(_ city: City) async -> SavedCityLists
    /// Drops one city from the recents list. If it is favourited it stays a favourite.
    func removeRecent(_ city: City) async -> SavedCityLists
    /// Empties the recents list, preserving favourites.
    func clearRecents() async -> SavedCityLists
}

/// Owns the saved-city policy: the recents cap, both orderings, and when a record
/// stops being referenced by either list and should be deleted.
///
/// An `actor`, but note carefully *what that does and does not buy*. Actors serialise
/// execution, but they are **reentrant**: at every `await` another task may run. So
/// holding a computed snapshot across an `await` on the store and then assigning it
/// back would reinstate a stale value over a newer one — a lost update, which an
/// earlier version of this type had and `concurrentMutationsAreSerialised` caught.
///
/// Every mutation therefore follows the same shape:
///
/// 1. `await hydrated()` — the only suspension before the state is read.
/// 2. Compute the new records **synchronously**, and commit them to `cache`
///    immediately. No `await` may appear between the read and that commit.
/// 3. Persist afterwards, and return `project(cache)` — the *current* committed
///    state, never the local snapshot, which by then may be out of date.
actor DefaultSavedCitiesUseCase: SavedCitiesUseCase {
    /// Five is enough to be useful and short enough that recents never compete with
    /// the search results for attention. Favourites are deliberately uncapped: the
    /// user curates them, so trimming them behind their back would be wrong.
    static let recentLimit = 5

    /// A pending write, queued during the synchronous phase and flushed afterwards.
    private enum StoreWrite {
        case upsert(SavedCity)
        case delete(Int)
    }

    private let store: SavedCitiesStore
    private let dateProvider: DateProvider
    /// Authoritative in-memory copy, hydrated on first access. `nil` means "not
    /// loaded yet", which is distinct from "loaded and empty".
    private var cache: [SavedCity]?

    init(store: SavedCitiesStore, dateProvider: DateProvider = SystemDateProvider()) {
        self.store = store
        self.dateProvider = dateProvider
    }

    func lists() async -> SavedCityLists {
        project(await hydrated())
    }

    func recordVisit(to city: City) async -> SavedCityLists {
        let now = dateProvider.now
        var records = await hydrated()

        let existing = records.first { $0.id == city.id }
        // Re-save the city as it arrived from search, so a renamed or re-geocoded
        // place updates rather than staying pinned to whatever we first stored.
        let updated = SavedCity(city: city, lastVisitedAt: now, favouritedAt: existing?.favouritedAt)
        records.removeAll { $0.id == city.id }
        records.append(updated)

        var writes: [StoreWrite] = [.upsert(updated)]
        records = trimRecents(records, writes: &writes)

        return await commit(records, writes: writes)
    }

    func toggleFavourite(_ city: City) async -> SavedCityLists {
        let now = dateProvider.now
        var records = await hydrated()

        let existing = records.first { $0.id == city.id }
        let updated = SavedCity(
            city: city,
            lastVisitedAt: existing?.lastVisitedAt,
            // Toggling off clears the timestamp; toggling on stamps it now, so the
            // favourites list orders by when each was favourited.
            favouritedAt: existing?.isFavourite == true ? nil : now
        )
        records.removeAll { $0.id == city.id }

        var writes: [StoreWrite] = []
        if updated.isOrphaned {
            // Un-favouriting something never visited leaves nothing worth keeping.
            writes.append(.delete(city.id))
        } else {
            records.append(updated)
            writes.append(.upsert(updated))
        }

        return await commit(records, writes: writes)
    }

    func removeRecent(_ city: City) async -> SavedCityLists {
        var records = await hydrated()
        guard let existing = records.first(where: { $0.id == city.id }) else {
            return project(records)
        }

        records.removeAll { $0.id == city.id }
        let forgotten = existing.forgettingVisit()

        var writes: [StoreWrite] = []
        // Swiping a recent away must not silently discard a favourite.
        if forgotten.isOrphaned {
            writes.append(.delete(city.id))
        } else {
            records.append(forgotten)
            writes.append(.upsert(forgotten))
        }

        return await commit(records, writes: writes)
    }

    func clearRecents() async -> SavedCityLists {
        let records = await hydrated()
        var remaining: [SavedCity] = []
        var writes: [StoreWrite] = []

        for record in records {
            guard record.isRecent else {
                remaining.append(record)   // never in the recents list; untouched
                continue
            }
            let forgotten = record.forgettingVisit()
            if forgotten.isOrphaned {
                writes.append(.delete(record.id))
            } else {
                remaining.append(forgotten)
                writes.append(.upsert(forgotten))
            }
        }

        return await commit(remaining, writes: writes)
    }

    // MARK: - Policy

    /// Trims the recents list to `recentLimit`, oldest first. A trimmed record that is
    /// still favourited is kept with its visit forgotten; one that is not is deleted.
    /// Synchronous by design — see the type comment.
    private func trimRecents(_ records: [SavedCity], writes: inout [StoreWrite]) -> [SavedCity] {
        let recents = records
            .filter(\.isRecent)
            .sorted { ($0.lastVisitedAt ?? .distantPast) > ($1.lastVisitedAt ?? .distantPast) }
        guard recents.count > Self.recentLimit else { return records }

        let overflow = Set(recents.dropFirst(Self.recentLimit).map(\.id))
        var result: [SavedCity] = []

        for record in records {
            guard overflow.contains(record.id) else {
                result.append(record)
                continue
            }
            let forgotten = record.forgettingVisit()
            if forgotten.isOrphaned {
                writes.append(.delete(record.id))
            } else {
                result.append(forgotten)
                writes.append(.upsert(forgotten))
            }
        }
        return result
    }

    /// Commits new state in memory, then flushes the queued writes.
    ///
    /// The `cache` assignment happens *before* any `await`, so no other task can
    /// observe or overwrite a half-applied mutation. The value returned afterwards is
    /// read back from `cache` rather than from the local, because a task that ran
    /// during the flush may have committed on top of ours — and its state already
    /// includes ours, since it hydrated from the cache we just wrote.
    private func commit(_ records: [SavedCity], writes: [StoreWrite]) async -> SavedCityLists {
        cache = records

        for write in writes {
            switch write {
            case let .upsert(saved): await store.upsert(saved)
            case let .delete(id): await store.delete(cityID: id)
            }
        }

        return project(cache ?? records)
    }

    /// Derives the two ordered lists the UI renders from the flat record collection.
    private func project(_ records: [SavedCity]) -> SavedCityLists {
        let recent = records
            .filter(\.isRecent)
            .sorted { ($0.lastVisitedAt ?? .distantPast) > ($1.lastVisitedAt ?? .distantPast) }
            .prefix(Self.recentLimit)
            .map(\.city)

        let favourites = records
            .filter(\.isFavourite)
            .sorted { ($0.favouritedAt ?? .distantPast) > ($1.favouritedAt ?? .distantPast) }
            .map(\.city)

        return SavedCityLists(recent: Array(recent), favourites: favourites)
    }

    private func hydrated() async -> [SavedCity] {
        if let cache { return cache }

        let loaded = await store.load()
        // Reentrancy again: another call may have hydrated us while we were suspended
        // on the store. If so that value wins — adopting `loaded` here would discard
        // whatever it committed in the meantime.
        if let cache { return cache }

        cache = loaded
        return loaded
    }
}
