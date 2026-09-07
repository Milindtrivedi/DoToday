//
//  WeatherCode.swift
//  DoToday
//
//  Domain layer.
//

import Foundation

/// WMO 4677 weather interpretation code, grouped into the buckets the UI cares about.
///
/// Open-Meteo returns the raw integer; we collapse it here so that presentation code
/// never switches on magic numbers. Unknown codes degrade to `.unknown` rather than
/// failing the whole forecast — a forecast is still useful without an icon.
enum WeatherCode: Equatable, Hashable {
    case clear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case freezingRain
    case snow
    case snowGrains
    case rainShowers
    case snowShowers
    case thunderstorm
    case unknown(Int)

    init(rawCode: Int) {
        switch rawCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61, 63, 65: self = .rain
        case 71, 73, 75: self = .snow
        case 77: self = .snowGrains
        case 80, 81, 82: self = .rainShowers
        case 85, 86: self = .snowShowers
        case 95, 96, 99: self = .thunderstorm
        default: self = .unknown(rawCode)
        }
    }

    /// SF Symbol used by the day strip. Presentation detail, but kept beside the
    /// code mapping so the two never drift apart.
    var systemImageName: String {
        switch self {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .overcast: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .freezingRain: return "cloud.sleet"
        case .snow, .snowGrains: return "snowflake"
        case .rainShowers: return "cloud.heavyrain"
        case .snowShowers: return "cloud.snow"
        case .thunderstorm: return "cloud.bolt.rain"
        case .unknown: return "questionmark.circle"
        }
    }

    var shortDescription: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .freezingRain: return "Freezing rain"
        case .snow: return "Snow"
        case .snowGrains: return "Snow grains"
        case .rainShowers: return "Rain showers"
        case .snowShowers: return "Snow showers"
        case .thunderstorm: return "Thunderstorm"
        case .unknown: return "Unknown"
        }
    }
}
