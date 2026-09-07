//
//  CityMapper.swift
//  DoToday
//
//  Data layer — the anti-corruption boundary between wire format and domain model.
//

import Foundation

/// Translates geocoding DTOs into `City` entities.
///
/// Mapping is a separate, pure step (rather than making `City` itself `Decodable`)
/// so that a change to Open-Meteo's JSON can only ever break this one file, and so
/// the domain layer has no `Codable` conformance forced on it.
enum CityMapper {

    static func map(_ dto: GeocodingResponseDTO) -> [City] {
        (dto.results ?? []).map(map)
    }

    static func map(_ dto: GeocodingResponseDTO.PlaceDTO) -> City {
        City(
            id: dto.id,
            name: dto.name,
            admin1: dto.admin1,
            country: dto.country,
            countryCode: dto.countryCode,
            coordinate: Coordinate(latitude: dto.latitude, longitude: dto.longitude),
            elevation: dto.elevation,
            timeZoneIdentifier: dto.timezone
        )
    }
}
