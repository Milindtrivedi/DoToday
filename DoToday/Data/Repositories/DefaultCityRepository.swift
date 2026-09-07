//
//  DefaultCityRepository.swift
//  DoToday
//
//  Data layer — implements the domain's `CityRepository` port.
//

import Foundation

struct DefaultCityRepository: CityRepository {
    private let remote: GeocodingRemoteDataSource

    init(remote: GeocodingRemoteDataSource) {
        self.remote = remote
    }

    func searchCities(matching query: String, limit: Int) async throws -> [City] {
        do {
            let dto = try await remote.search(name: query, count: limit)
            // An absent `results` key means "no matches" — a normal outcome that the
            // presentation layer renders as an empty state, not an error banner.
            return CityMapper.map(dto)
        } catch {
            throw ErrorNormalising.normalise(error)
        }
    }
}
