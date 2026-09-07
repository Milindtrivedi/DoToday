//
//  RankActivitiesUseCase.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

protocol RankActivitiesUseCase: Sendable {
    /// Fetches the forecast for `city` and ranks the four activities over it.
    /// - Throws: `AppError`.
    func execute(city: City, cachePolicy: ForecastCachePolicy) async throws -> RankedRecommendations
}

/// Composes the forecast repository with the (pure) scoring engine. Keeping the
/// composition here means the ViewModel depends on one collaborator, not two, and
/// the scoring rules stay independently testable.
struct DefaultRankActivitiesUseCase: RankActivitiesUseCase {
    /// The brief asks for the next 7 days.
    static let forecastDays = 7

    private let repository: ForecastRepository
    private let engine: ActivityScoringEngine

    init(repository: ForecastRepository, engine: ActivityScoringEngine = DefaultActivityScoringEngine()) {
        self.repository = repository
        self.engine = engine
    }

    func execute(city: City, cachePolicy: ForecastCachePolicy) async throws -> RankedRecommendations {
        let cached = try await repository.forecast(
            for: city,
            days: Self.forecastDays,
            cachePolicy: cachePolicy
        )

        // A 200 response with an empty daily array is well-formed but useless; we
        // surface it as a parse-level failure rather than rendering an empty screen.
        guard !cached.value.days.isEmpty else { throw AppError.invalidResponse }

        return RankedRecommendations(
            city: city,
            forecast: cached.value,
            rankings: engine.rank(forecast: cached.value, for: city),
            isStale: cached.isStale
        )
    }
}
