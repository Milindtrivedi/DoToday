//
//  RecentCityDTO.swift
//  DoToday
//
//  Data layer — the on-disk shape of a recent city.
//

import Foundation

/// Storage representation of `City`.
///
/// A separate type rather than making `City: Codable`, for the same reason the
/// forecast cache stores its DTO: the persisted schema and the domain entity should
/// be free to change independently. Adding a field to `City` must not make every
/// previously-saved recents list undecodable.
///
/// `schemaVersion` is carried so a future migration has something to branch on; an
/// entry written by an unknown future version is dropped rather than guessed at.
struct RecentCityDTO: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = RecentCityDTO.currentSchemaVersion
    let id: Int
    let name: String
    let admin1: String?
    let country: String?
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let timeZoneIdentifier: String?

    init(_ city: City) {
        self.id = city.id
        self.name = city.name
        self.admin1 = city.admin1
        self.country = city.country
        self.countryCode = city.countryCode
        self.latitude = city.coordinate.latitude
        self.longitude = city.coordinate.longitude
        self.elevation = city.elevation
        self.timeZoneIdentifier = city.timeZoneIdentifier
    }

    /// `nil` when the entry was written by a newer, unknown schema.
    var city: City? {
        guard schemaVersion <= Self.currentSchemaVersion else { return nil }
        return City(
            id: id,
            name: name,
            admin1: admin1,
            country: country,
            countryCode: countryCode,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            elevation: elevation,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
