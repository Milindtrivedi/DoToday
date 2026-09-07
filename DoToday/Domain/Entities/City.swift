//
//  City.swift
//  DoToday
//
//  Domain layer — pure value type, no knowledge of JSON, networking or SwiftUI.
//

import Foundation

/// A geographic place the user can request recommendations for.
///
/// Produced by the geocoding search. `elevation` is retained because it is the only
/// terrain signal Open-Meteo gives us, and the ranking engine uses it as a coarse
/// feasibility proxy (see `LocationFeasibility`).
struct City: Equatable, Identifiable, Hashable {
    /// Open-Meteo's stable numeric id for the place.
    let id: Int
    let name: String
    /// First-level administrative area, e.g. "California". Optional in the API.
    let admin1: String?
    let country: String?
    let countryCode: String?
    let coordinate: Coordinate
    /// Metres above sea level. `nil` when the API omits it.
    let elevation: Double?
    /// IANA identifier, e.g. "Europe/London". Used to request a localised forecast.
    let timeZoneIdentifier: String?

    /// Human-readable disambiguator, e.g. "Chamonix, Auvergne-Rhône-Alpes, France".
    var subtitle: String {
        [admin1, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// A WGS-84 coordinate pair. Kept separate from `CLLocationCoordinate2D` so the
/// domain layer has no CoreLocation dependency and stays trivially testable.
struct Coordinate: Equatable, Hashable {
    let latitude: Double
    let longitude: Double
}
