//
//  CitySearchViewModel.swift
//  DoToday
//
//  Presentation layer — holds all search-screen logic so the SwiftUI view stays a
//  pure function of `state`.
//

import Foundation
import Observation

@MainActor
@Observable
final class CitySearchViewModel {

    /// The single source of truth for what the search screen renders.
    private(set) var state: ViewState<[City]> = .idle

    /// The two saved lists shown beneath the search field while it is empty, so the
    /// resting state of the app is useful rather than blank. Held together because
    /// they are two projections of one collection and must never disagree.
    private(set) var savedLists: SavedCityLists = .empty

    /// Which saved list the segmented control is showing. Recents is the default:
    /// it is the one that fills itself without the user having to do anything.
    var savedTab: SavedCityTab = .recent

    /// Bound to the search field. Mutating it does nothing on its own; the view calls
    /// `queryDidChange()` so that the (debounced, cancellable) search is an explicit,
    /// testable step rather than a hidden `didSet` side effect.
    var query: String = ""

    private let searchCities: SearchCitiesUseCase
    private let savedCities: SavedCitiesUseCase
    private let debounceInterval: Duration
    /// The in-flight search. Retained so each keystroke can cancel the previous one.
    private var searchTask: Task<Void, Never>?
    /// The in-flight saved-list mutation. Retained only so callers can await it;
    /// unlike searches these are never cancelled — a dropped write would silently
    /// lose an entry the user expects to see.
    private var savedTask: Task<Void, Never>?

    /// - Parameter debounceInterval: Injected so tests can run with zero delay.
    ///   250 ms is roughly a fast typist's inter-key gap: long enough to collapse a
    ///   burst of keystrokes into one request, short enough to feel immediate.
    init(
        searchCities: SearchCitiesUseCase,
        savedCities savedCitiesUseCase: SavedCitiesUseCase,
        debounceInterval: Duration = .milliseconds(250)
    ) {
        self.searchCities = searchCities
        self.savedCities = savedCitiesUseCase
        self.debounceInterval = debounceInterval
    }

    /// Call whenever the query text changes.
    func queryDidChange() {
        // Cancel first: the previous query's result is now obsolete, and letting it
        // land would overwrite newer state with older results.
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= DefaultSearchCitiesUseCase.minimumQueryLength else {
            // Below the threshold we show the resting state rather than "no results",
            // because the user hasn't finished asking a question yet.
            state = .idle
            searchTask = nil
            return
        }

        state = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Debounce. A cancelled sleep throws, which is our signal to bail out
            // without touching state — a newer keystroke already owns the screen.
            do {
                try await Task.sleep(for: self.debounceInterval)
            } catch {
                return
            }
            await self.performSearch(trimmed)
        }
    }

    // MARK: - Saved cities

    /// Hydrates recents and favourites. Called when the screen appears.
    ///
    /// Idempotent and cheap: the use case caches in memory after the first read, so
    /// SwiftUI re-running `.task` on reappear costs nothing.
    func loadSavedCities() async {
        savedLists = await savedCities.lists()
    }

    /// Records that the user opened this city.
    ///
    /// Synchronous from the view's point of view so navigation is never gated on a
    /// database write; the lists update when the write completes.
    func didSelect(_ city: City) {
        mutateSavedCities { await $0.recordVisit(to: city) }
    }

    /// Adds or removes a favourite. Recency is untouched either way.
    func toggleFavourite(_ city: City) {
        mutateSavedCities { await $0.toggleFavourite(city) }
    }

    func isFavourite(_ city: City) -> Bool {
        savedLists.isFavourite(city)
    }

    func removeRecentCity(_ city: City) {
        mutateSavedCities { await $0.removeRecent(city) }
    }

    func clearRecentCities() {
        mutateSavedCities { await $0.clearRecents() }
    }

    /// Awaits the in-flight saved-list mutation, if any. Used by tests to synchronise
    /// without sleeping — the same idiom as `awaitCurrentSearch()`.
    func awaitPendingSavedCitiesUpdate() async {
        await savedTask?.value
    }

    /// Runs a mutation and adopts the lists it returns.
    ///
    /// The use case returns the full post-mutation state rather than the ViewModel
    /// re-deriving it, so the screen can never render a recents list computed from a
    /// different moment than its favourites list.
    private func mutateSavedCities(
        _ mutation: @escaping @Sendable (SavedCitiesUseCase) async -> SavedCityLists
    ) {
        savedTask = Task { [weak self] in
            guard let self else { return }
            self.savedLists = await mutation(self.savedCities)
        }
    }

    // MARK: - Search

    /// Retries the current query after a failure.
    func retry() {
        queryDidChange()
    }

    /// Awaits the debounced search currently in flight, if any.
    ///
    /// Used by tests to synchronise without sleeping; also lets the view await
    /// completion when it needs to (e.g. for accessibility announcements).
    func awaitCurrentSearch() async {
        await searchTask?.value
    }

    private func performSearch(_ trimmedQuery: String) async {
        do {
            let cities = try await searchCities.execute(query: trimmedQuery)
            // Re-check cancellation after the await: the task may have been cancelled
            // while the request was in flight.
            guard !Task.isCancelled else { return }
            state = cities.isEmpty ? .empty : .loaded(cities)
        } catch is CancellationError {
            // Superseded by a newer query — leave state to the newer task.
            return
        } catch let error as AppError {
            guard !Task.isCancelled else { return }
            state = .failed(error)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(.unknown(description: String(describing: error)))
        }
    }
}
