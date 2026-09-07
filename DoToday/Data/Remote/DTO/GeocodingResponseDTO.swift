//
//  GeocodingResponseDTO.swift
//  DoToday
//
//  Data layer — wire format for https://geocoding-api.open-meteo.com/v1/search
//

import Foundation

/// Mirrors the geocoding payload exactly. DTOs stay dumb: no computed values, no
/// defaults, no business rules — that is the mapper's job.
struct GeocodingResponseDTO: Decodable, Equatable {
    /// Absent (not empty) when the query matched nothing, hence the optional.
    let results: [PlaceDTO]?

    struct PlaceDTO: Decodable, Equatable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let elevation: Double?
        let country: String?
        let countryCode: String?
        let admin1: String?
        let timezone: String?

        private enum CodingKeys: String, CodingKey {
            case id, name, latitude, longitude, elevation, country, admin1, timezone
            case countryCode = "country_code"
        }
    }
}
