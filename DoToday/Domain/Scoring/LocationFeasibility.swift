//
//  LocationFeasibility.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// A coarse, location-based sanity check applied on top of the weather score.
///
/// Weather alone will happily rank surfing highly for a warm, breezy day in Madrid,
/// which is 600 km from the sea. Open-Meteo's geocoding response gives us exactly one
/// terrain signal — `elevation` — so we use it as a deliberately crude proxy:
/// high ground makes skiing plausible, and anything well above sea level makes
/// surfing implausible.
///
/// This is a heuristic, not a fact, and it is isolated here so it can be replaced by a
/// real coastline/resort lookup without touching the weather scoring. See README.
enum LocationFeasibility {

    /// Multiplier in 0...1 applied to an activity's weather score for a given place.
    static func multiplier(for activity: Activity, at city: City) -> Double {
        // Without elevation we make no claim either way.
        guard let elevation = city.elevation else { return 1 }

        switch activity {
        case .surfing:
            // Sea level surfs; 500 m up does not.
            return ScoringCurve.decreasing(oneAt: 60, zeroAt: 500).score(for: elevation)

        case .skiing:
            // Lowland skiing is possible in a hard winter, so we damp rather than veto.
            let altitudeBonus = ScoringCurve.increasing(zeroAt: 150, oneAt: 900).score(for: elevation)
            return 0.65 + 0.35 * altitudeBonus

        case .outdoorSightseeing, .indoorSightseeing:
            // Sightseeing is possible anywhere people live.
            return 1
        }
    }
}
