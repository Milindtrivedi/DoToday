//
//  CityRepository.swift
//  DoToday
//
//  Domain layer — dependency inversion boundary. The domain declares what it needs;
//  `Data` supplies an implementation. This is what makes the layer mockable in tests.
//

import Foundation

protocol CityRepository: Sendable {
    /// Searches places matching a free-text query.
    ///
    /// - Returns: Up to `limit` matches, most relevant first. An empty array is a
    ///   valid result and is *not* an error — the caller decides how to present it.
    /// - Throws: `AppError`.
    func searchCities(matching query: String, limit: Int) async throws -> [City]
}
