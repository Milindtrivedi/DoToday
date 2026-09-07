//
//  Activity.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// The fixed set of activities the app ranks.
///
/// A closed enum (rather than data-driven config) is deliberate: the brief specifies
/// exactly four activities, and an enum gives us exhaustive `switch` checks whenever
/// a new one is added — including a compile error in the scoring profile registry.
enum Activity: String, CaseIterable, Identifiable, Equatable, Hashable {
    case skiing
    case surfing
    case outdoorSightseeing
    case indoorSightseeing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skiing: return "Skiing"
        case .surfing: return "Surfing"
        case .outdoorSightseeing: return "Outdoor sightseeing"
        case .indoorSightseeing: return "Indoor sightseeing"
        }
    }

    var systemImageName: String {
        switch self {
        case .skiing: return "figure.skiing.downhill"
        case .surfing: return "figure.surfing"
        case .outdoorSightseeing: return "binoculars"
        case .indoorSightseeing: return "building.columns"
        }
    }
}
