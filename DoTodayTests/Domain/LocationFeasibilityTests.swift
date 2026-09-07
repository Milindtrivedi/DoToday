//
//  LocationFeasibilityTests.swift
//  DoTodayTests
//
//  Pins the elevation heuristic, which is the main guard against the app cheerfully
//  recommending surfing in a landlocked mountain town.
//

import Testing
@testable import DoToday

@Suite("LocationFeasibility")
struct LocationFeasibilityTests {

    @Test("Surfing is suppressed well above sea level")
    func surfingNeedsLowElevation() {
        let seaside = LocationFeasibility.multiplier(for: .surfing, at: Fixture.city(elevation: 5))
        let inlandCity = LocationFeasibility.multiplier(for: .surfing, at: Fixture.city(elevation: 300))
        let mountainTown = LocationFeasibility.multiplier(for: .surfing, at: Fixture.city(elevation: 1_200))

        #expect(seaside == 1)
        #expect(inlandCity > 0 && inlandCity < 1)
        #expect(mountainTown == 0)
    }

    @Test("Skiing is damped at low altitude but never vetoed outright")
    func skiingIsDampedNotVetoed() {
        let lowland = LocationFeasibility.multiplier(for: .skiing, at: Fixture.city(elevation: 20))
        let alpine = LocationFeasibility.multiplier(for: .skiing, at: Fixture.city(elevation: 1_500))

        // Deliberately not zero: a hard winter at sea level can still deliver snow.
        #expect(lowland > 0)
        #expect(lowland < alpine)
        #expect(alpine == 1)
    }

    @Test("Sightseeing is possible at any elevation", arguments: [Activity.outdoorSightseeing, .indoorSightseeing])
    func sightseeingIsAlwaysFeasible(activity: Activity) {
        for elevation in [0.0, 500, 3_000] {
            #expect(LocationFeasibility.multiplier(for: activity, at: Fixture.city(elevation: elevation)) == 1)
        }
    }

    @Test("Without elevation data we make no claim and apply no penalty", arguments: Activity.allCases)
    func unknownElevationIsNeutral(activity: Activity) {
        #expect(LocationFeasibility.multiplier(for: activity, at: Fixture.city(elevation: nil)) == 1)
    }

    @Test("Multipliers are always within 0...1", arguments: Activity.allCases)
    func multipliersAreNormalised(activity: Activity) {
        for elevation in stride(from: -400.0, through: 9_000, by: 250) {
            let multiplier = LocationFeasibility.multiplier(for: activity, at: Fixture.city(elevation: elevation))
            #expect(multiplier >= 0 && multiplier <= 1)
        }
    }
}
