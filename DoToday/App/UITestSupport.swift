//
//  UITestSupport.swift
//  DoToday
//
//  App layer — DEBUG-only wiring that lets UI tests run against deterministic data.
//

#if DEBUG
import Foundation

/// `HTTPClient` that answers from canned payloads instead of the network.
///
/// This exists so UI tests can assert on real behaviour (search → results →
/// ranking → day breakdown) without depending on Open-Meteo being reachable, fast,
/// or seasonally cooperative — a UI test that fails because it is summer in the Alps
/// is worse than no UI test at all.
///
/// It is compiled out of release builds, and is only reachable when the app is
/// launched with `-UITestStubbedAPI`. It is also the clearest demonstration that the
/// `HTTPClient` seam makes every layer above it substitutable.
struct StubbedHTTPClient: HTTPClient {
    static let launchArgument = "-UITestStubbedAPI"

    private let decoder = JSONDecoder()

    func get<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response {
        let json: String
        switch endpoint.path {
        case "v1/search": json = Self.geocodingJSON
        case "v1/forecast": json = Self.forecastJSON
        default: throw AppError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: Data(json.utf8))
        } catch {
            throw AppError.invalidResponse
        }
    }

    private static let geocodingJSON = """
    {"results":[
      {"id":1,"name":"Chamonix","latitude":45.9237,"longitude":6.8694,"elevation":1035.0,
       "country_code":"FR","country":"France","admin1":"Auvergne-Rhône-Alpes","timezone":"Europe/Paris"},
      {"id":2,"name":"Chamonix-Mont-Blanc","latitude":45.9160,"longitude":6.8700,"elevation":1040.0,
       "country_code":"FR","country":"France","admin1":"Auvergne-Rhône-Alpes","timezone":"Europe/Paris"}
    ]}
    """

    /// A cold, snowy alpine week, so the expected top-ranked activity is stable.
    private static let forecastJSON = """
    {
      "latitude": 45.92, "longitude": 6.87, "timezone": "Europe/Paris", "utc_offset_seconds": 3600,
      "daily": {
        "time": ["2026-01-05","2026-01-06","2026-01-07","2026-01-08","2026-01-09","2026-01-10","2026-01-11"],
        "weather_code": [75,73,71,3,71,75,2],
        "temperature_2m_max": [-4.0,-6.0,-3.0,-1.0,-5.0,-7.0,-2.0],
        "apparent_temperature_max": [-9.0,-12.0,-7.0,-4.0,-10.0,-14.0,-6.0],
        "precipitation_sum": [12.0,9.0,6.0,0.0,7.0,14.0,0.0],
        "rain_sum": [0.0,0.0,0.0,0.0,0.0,0.0,0.0],
        "snowfall_sum": [22.0,16.0,11.0,0.0,13.0,25.0,0.0],
        "precipitation_probability_max": [95,90,80,10,85,95,5],
        "wind_speed_10m_max": [9.0,11.0,7.0,5.0,8.0,12.0,6.0],
        "wind_gusts_10m_max": [18.0,22.0,15.0,11.0,17.0,26.0,12.0],
        "sunshine_duration": [3600.0,5400.0,9000.0,28000.0,7200.0,1800.0,30000.0],
        "daylight_duration": [31000.0,31000.0,31100.0,31100.0,31200.0,31200.0,31300.0]
      }
    }
    """
}

extension AppContainer {
    /// Builds the graph a UI test expects: stubbed network, throwaway in-memory cache.
    static func makeForUITests() -> AppContainer {
        AppContainer(
            httpClient: StubbedHTTPClient(),
            forecastCache: InMemoryForecastCache(),
            // In-memory saved cities too, so a UI test never inherits recents or
            // favourites from a previous run or from the developer's own use.
            savedCitiesStore: InMemorySavedCitiesStore()
        )
    }

    /// Whether this launch was started by a UI test that wants stubbed data.
    static var isRunningUITestsWithStubbedAPI: Bool {
        ProcessInfo.processInfo.arguments.contains(StubbedHTTPClient.launchArgument)
    }
}
#endif
