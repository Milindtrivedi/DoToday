//
//  SavedCityTab.swift
//  DoToday
//
//  Presentation layer.
//

import Foundation

/// The segmented control beneath the search field.
enum SavedCityTab: String, CaseIterable, Identifiable, Equatable {
    case recent
    case favourites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent"
        case .favourites: return "Favourites"
        }
    }

    /// Headline shown when this tab's list is empty.
    var emptyTitle: String {
        switch self {
        case .recent: return "No data"
        case .favourites: return "No favourite places"
        }
    }

    /// Guidance shown under the headline. Each tells the user the specific action
    /// that would fill *this* list, rather than a generic "nothing here".
    var emptyMessage: String {
        switch self {
        case .recent:
            return "Try searching for a city. The ones you open will show up here."
        case .favourites:
            return "Try favouriting your preferred locations for quick access."
        }
    }

    var emptyImageName: String {
        switch self {
        case .recent: return "clock.arrow.circlepath"
        case .favourites: return "star"
        }
    }
}
