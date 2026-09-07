//
//  RecommendationsViewModelTests.swift
//  DoTodayTests
//
//  Focuses on the state rules that are easy to get subtly wrong: not re-fetching on
//  every reappear, not blanking good content when a refresh fails, and using the
//  right cache policy for each entry point.
//

import Foundation
import Testing
@testable import DoToday

@MainActor
@Suite("RecommendationsViewModel")
struct RecommendationsViewModelTests {

    private static func recommendations(isStale: Bool = false) -> RankedRecommendations {
        let forecast = Fixture.forecast(days: Fixture.days(count: 7))
        return RankedRecommendations(
            city: Fixture.city(),
            forecast: forecast,
            rankings: DefaultActivityScoringEngine().rank(forecast: forecast, for: Fixture.city()),
            isStale: isStale
        )
    }

    private func makeSUT(
        result: Result<RankedRecommendations, Error> = .success(recommendations())
    ) -> (RecommendationsViewModel, StubRankActivitiesUseCase) {
        let useCase = StubRankActivitiesUseCase(result: result)
        return (RecommendationsViewModel(city: Fixture.city(), rankActivities: useCase), useCase)
    }

    // MARK: Loading

    @Test("Starts idle and loads on first appearance")
    func loadsOnFirstAppearance() async {
        let (sut, useCase) = makeSUT()
        #expect(sut.state == .idle)

        await sut.loadIfNeeded()

        #expect(sut.state.value?.rankings.count == Activity.allCases.count)
        // The initial load may use cached data; only an explicit refresh revalidates.
        #expect(useCase.receivedPolicies == [.useCache])
    }

    @Test("Reappearing does not refetch what we already have")
    func loadIfNeededIsIdempotent() async {
        let (sut, useCase) = makeSUT()

        await sut.loadIfNeeded()
        await sut.loadIfNeeded()
        await sut.loadIfNeeded()

        #expect(useCase.receivedPolicies.count == 1, "SwiftUI re-running .task caused a duplicate fetch")
    }

    @Test("A first-load failure shows the error screen")
    func firstLoadFailureShowsError() async {
        let (sut, _) = makeSUT(result: .failure(AppError.offline))

        await sut.loadIfNeeded()

        #expect(sut.state == .failed(.offline))
    }

    @Test("Cached results are flagged so the UI can say so")
    func staleFlagIsPropagated() async {
        let (sut, _) = makeSUT(result: .success(Self.recommendations(isStale: true)))

        await sut.loadIfNeeded()

        #expect(sut.state.value?.isStale == true)
    }

    // MARK: Refresh

    @Test("Pull-to-refresh forces a revalidation")
    func refreshRevalidates() async {
        let (sut, useCase) = makeSUT()

        await sut.loadIfNeeded()
        await sut.refresh()

        #expect(useCase.receivedPolicies == [.useCache, .revalidate])
        #expect(!sut.isRefreshing)
    }

    @Test("A failed refresh keeps the content on screen and reports the failure separately")
    func failedRefreshKeepsExistingContent() async {
        let (sut, useCase) = makeSUT()
        await sut.loadIfNeeded()
        let loaded = sut.state.value

        useCase.result = .failure(AppError.timedOut)
        await sut.refresh()

        // Throwing away a usable forecast because a refresh blipped is a worse
        // outcome than showing slightly older data with a warning.
        #expect(sut.state.value == loaded)
        #expect(sut.refreshError == .timedOut)
    }

    @Test("The refresh warning can be dismissed and does not survive the next attempt")
    func refreshErrorIsClearable() async {
        let (sut, useCase) = makeSUT()
        await sut.loadIfNeeded()
        useCase.result = .failure(AppError.timedOut)
        await sut.refresh()
        #expect(sut.refreshError != nil)

        sut.dismissRefreshError()
        #expect(sut.refreshError == nil)

        useCase.result = .failure(AppError.offline)
        await sut.refresh()
        #expect(sut.refreshError == .offline)

        useCase.result = .success(Self.recommendations())
        await sut.refresh()
        #expect(sut.refreshError == nil, "A successful refresh must clear the previous warning")
    }

    // MARK: Retry

    @Test("Retry after a first-load failure revalidates and can recover")
    func retryRecoversFromFailure() async {
        let (sut, useCase) = makeSUT(result: .failure(AppError.offline))
        await sut.loadIfNeeded()
        #expect(sut.state == .failed(.offline))

        useCase.result = .success(Self.recommendations())
        await sut.retry()

        #expect(sut.state.value != nil)
        #expect(useCase.receivedPolicies == [.useCache, .revalidate])
    }

    @Test("The city is exposed unchanged for the navigation title")
    func exposesCity() {
        let (sut, _) = makeSUT()

        #expect(sut.city == Fixture.city())
    }
}

@Suite("ViewState")
struct ViewStateTests {

    @Test("Only the loaded case carries a value")
    func valueAccessor() {
        #expect(ViewState<[Int]>.loaded([1, 2]).value == [1, 2])
        #expect(ViewState<[Int]>.idle.value == nil)
        #expect(ViewState<[Int]>.loading.value == nil)
        #expect(ViewState<[Int]>.empty.value == nil)
        #expect(ViewState<[Int]>.failed(.offline).value == nil)
    }

    @Test("Loading is a state of its own, never a flag alongside content")
    func loadingIsExclusive() {
        #expect(ViewState<[Int]>.loading.isLoading)
        #expect(!ViewState<[Int]>.loaded([1]).isLoading)
        #expect(!ViewState<[Int]>.failed(.offline).isLoading)
    }

    @Test("Equality distinguishes different failures")
    func equality() {
        #expect(ViewState<[Int]>.failed(.offline) == .failed(.offline))
        #expect(ViewState<[Int]>.failed(.offline) != .failed(.timedOut))
        #expect(ViewState<[Int]>.loaded([1]) != .loaded([2]))
    }
}
