//
//  SearchCitiesUseCase.swift
//  DoToday
//
//  Domain layer — application logic that belongs to no single screen.
//

import Foundation

protocol SearchCitiesUseCase: Sendable {
    /// - Returns: Matching cities, or an empty array when the query is too short or
    ///   nothing matched. Emptiness is a legitimate outcome, not an error.
    func execute(query: String) async throws -> [City]
}

struct DefaultSearchCitiesUseCase: SearchCitiesUseCase {
    /// Open-Meteo's geocoding index returns noise for one-character queries, and a
    /// per-keystroke request for "a" is wasted traffic, so we gate below this length.
    static let minimumQueryLength = 2
    private static let resultLimit = 15

    private let repository: CityRepository

    init(repository: CityRepository) {
        self.repository = repository
    }

    func execute(query: String) async throws -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else { return [] }
        return try await repository.searchCities(matching: trimmed, limit: Self.resultLimit)
    }
}
