//
//  RecommendationsViewModel.swift
//  DoToday
//
//  Presentation layer.
//

import Foundation
import Observation

@MainActor
@Observable
final class RecommendationsViewModel {

    let city: City

    /// Everything the screen renders, as one explicit state.
    private(set) var state: ViewState<RankedRecommendations> = .idle

    /// True only for a user-initiated pull-to-refresh, so the view can keep the
    /// existing content on screen instead of replacing it with a full-screen spinner.
    private(set) var isRefreshing = false

    /// Set when a *refresh* fails while usable content is already on screen.
    ///
    /// We keep the stale content rather than replacing it with an error screen, but
    /// the user still needs to know the refresh did not land — so the view shows this
    /// as a dismissible inline banner.
    private(set) var refreshError: AppError?

    private let rankActivities: RankActivitiesUseCase
    private var loadTask: Task<Void, Never>?

    init(city: City, rankActivities: RankActivitiesUseCase) {
        self.city = city
        self.rankActivities = rankActivities
    }

    /// Initial load. Idempotent: re-entering the screen (or a SwiftUI `.task`
    /// re-running on reappear) will not restart a load that already succeeded.
    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load(cachePolicy: .useCache)
    }

    /// Pull-to-refresh: bypass cache freshness and go to the network.
    func refresh() async {
        refreshError = nil
        isRefreshing = true
        defer { isRefreshing = false }
        await load(cachePolicy: .revalidate)
    }

    /// Dismisses the inline refresh-failure banner.
    func dismissRefreshError() {
        refreshError = nil
    }

    /// Retry after a failure.
    func retry() async {
        refreshError = nil
        state = .loading
        await load(cachePolicy: .revalidate)
    }

    private func load(cachePolicy: ForecastCachePolicy) async {
        // Only show the blocking spinner when there is nothing underneath it.
        if state.value == nil { state = .loading }

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let recommendations = try await self.rankActivities.execute(
                    city: self.city,
                    cachePolicy: cachePolicy
                )
                guard !Task.isCancelled else { return }
                self.state = .loaded(recommendations)
            } catch is CancellationError {
                return
            } catch let error as AppError {
                guard !Task.isCancelled else { return }
                // A failure that arrives while we already have content keeps the
                // content: losing a usable forecast to a transient network blip is a
                // worse outcome than showing slightly older data.
                if self.state.value == nil {
                    self.state = .failed(error)
                } else {
                    self.refreshError = error
                }
            } catch {
                guard !Task.isCancelled else { return }
                let appError = AppError.unknown(description: String(describing: error))
                if self.state.value == nil {
                    self.state = .failed(appError)
                } else {
                    self.refreshError = appError
                }
            }
        }
        loadTask = task
        await task.value
    }
}
