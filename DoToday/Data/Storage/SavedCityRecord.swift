//
//  SavedCityRecord.swift
//  DoToday
//
//  Data layer — the SwiftData persistence model.
//

import Foundation
import SwiftData

/// SwiftData row for a saved city.
///
/// A storage type, kept separate from the `SavedCity` domain entity for the same
/// reason the forecast cache stores its DTO: the persisted schema and the domain model
/// must be free to change independently, and the domain layer stays free of any
/// framework import. Nothing outside this file and its store ever sees a
/// `SavedCityRecord`.
///
/// `cityID` is Open-Meteo's stable place id and is the natural key; it is marked
/// `@Attribute(.unique)` so an upsert can never produce two rows for one city.
@Model
final class SavedCityRecord {
    @Attribute(.unique) var cityID: Int
    var name: String
    var admin1: String?
    var country: String?
    var countryCode: String?
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var timeZoneIdentifier: String?
    /// `nil` when this city is not in the recents list.
    var lastVisitedAt: Date?
    /// `nil` when this city is not favourited.
    var favouritedAt: Date?

    init(_ saved: SavedCity) {
        self.cityID = saved.city.id
        self.name = saved.city.name
        self.admin1 = saved.city.admin1
        self.country = saved.city.country
        self.countryCode = saved.city.countryCode
        self.latitude = saved.city.coordinate.latitude
        self.longitude = saved.city.coordinate.longitude
        self.elevation = saved.city.elevation
        self.timeZoneIdentifier = saved.city.timeZoneIdentifier
        self.lastVisitedAt = saved.lastVisitedAt
        self.favouritedAt = saved.favouritedAt
    }

    /// Applies an updated domain value onto this row in place.
    func apply(_ saved: SavedCity) {
        name = saved.city.name
        admin1 = saved.city.admin1
        country = saved.city.country
        countryCode = saved.city.countryCode
        latitude = saved.city.coordinate.latitude
        longitude = saved.city.coordinate.longitude
        elevation = saved.city.elevation
        timeZoneIdentifier = saved.city.timeZoneIdentifier
        lastVisitedAt = saved.lastVisitedAt
        favouritedAt = saved.favouritedAt
    }

    var savedCity: SavedCity {
        SavedCity(
            city: City(
                id: cityID,
                name: name,
                admin1: admin1,
                country: country,
                countryCode: countryCode,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                elevation: elevation,
                timeZoneIdentifier: timeZoneIdentifier
            ),
            lastVisitedAt: lastVisitedAt,
            favouritedAt: favouritedAt
        )
    }
}
