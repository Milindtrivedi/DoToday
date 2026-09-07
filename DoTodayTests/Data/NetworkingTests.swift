//
//  NetworkingTests.swift
//  DoTodayTests
//
//  Covers URL construction (a wrong query parameter is a silent, hard-to-spot bug)
//  and the transport-error translation that the whole error-handling story rests on.
//

import Foundation
import Testing
@testable import DoToday

@Suite("Endpoint")
struct EndpointTests {

    @Test("Builds a URL with path and query")
    func buildsURL() throws {
        let endpoint = Endpoint(
            baseURL: URL(string: "https://example.com")!,
            path: "v1/search",
            queryItems: [URLQueryItem(name: "name", value: "London"), URLQueryItem(name: "count", value: "5")]
        )

        #expect(endpoint.url?.absoluteString == "https://example.com/v1/search?name=London&count=5")
    }

    @Test("Percent-encodes values that need it")
    func encodesQueryValues() throws {
        let endpoint = Endpoint(
            baseURL: URL(string: "https://example.com")!,
            path: "v1/search",
            queryItems: [URLQueryItem(name: "name", value: "São Paulo")]
        )

        let url = try #require(endpoint.url)
        #expect(url.absoluteString.contains("S%C3%A3o%20Paulo"))
    }

    @Test("Omits the query string entirely when there are no items")
    func omitsEmptyQuery() {
        let endpoint = Endpoint(baseURL: URL(string: "https://example.com")!, path: "v1/ping")

        #expect(endpoint.url?.absoluteString == "https://example.com/v1/ping")
    }

    @Test("Produces a GET request that accepts JSON")
    func buildsGETRequest() throws {
        let request = try Endpoint(baseURL: URL(string: "https://example.com")!, path: "v1/ping").urlRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }
}

@Suite("Open-Meteo request construction")
struct OpenMeteoRequestTests {

    @Test("Coordinates are formatted with a dot, whatever the device locale")
    func coordinateFormattingIsLocaleIndependent() {
        // A comma decimal separator here would make every forecast request 400.
        #expect(OpenMeteoForecastRemoteDataSource.format(48.85341) == "48.8534")
        #expect(OpenMeteoForecastRemoteDataSource.format(-0.1) == "-0.1000")
    }

    @Test("The forecast request asks for exactly the variables the scoring needs")
    func forecastRequestCarriesExpectedParameters() async throws {
        let client = StubHTTPClient(success: try ForecastResponseDTO.stubbed())
        let dataSource = OpenMeteoForecastRemoteDataSource(client: client)

        _ = try await dataSource.forecast(latitude: 51.5, longitude: -0.12, days: 7)

        let endpoint = try #require(client.requestedEndpoints.first)
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })

        #expect(endpoint.path == "v1/forecast")
        #expect(query["latitude"] == "51.5000")
        #expect(query["longitude"] == "-0.1200")
        #expect(query["forecast_days"] == "7")
        // `timezone=auto` is what makes "the next 7 days" mean days at the destination.
        #expect(query["timezone"] == "auto")
        // Units are pinned because the scoring curves' constants assume them.
        #expect(query["temperature_unit"] == "celsius")
        #expect(query["wind_speed_unit"] == "kmh")
        #expect(query["precipitation_unit"] == "mm")

        // Pinned to a literal, deliberately. Comparing the request back against
        // `dailyVariables` would be a tautology — it would pass no matter what that
        // constant contained. Spelling the list out means adding or removing a
        // variable fails here until someone updates it on purpose, which is the only
        // way this test can catch "we fetch a field nothing reads".
        let requested = Set((query["daily"] ?? "").split(separator: ",").map(String.init))
        #expect(requested == [
            "weather_code",
            "temperature_2m_max",
            "apparent_temperature_max",
            "precipitation_sum",
            "rain_sum",
            "snowfall_sum",
            "precipitation_probability_max",
            "wind_speed_10m_max",
            "wind_gusts_10m_max",
            "sunshine_duration",
            "daylight_duration"
        ])
    }

    @Test("Every requested variable is actually consumed by the app")
    func noVariableIsFetchedSpeculatively() {
        // Guards the README's claim that nothing is fetched "just in case". Each
        // requested variable must be read either by a scoring criterion or by the UI.
        let consumedByScoring: Set<String> = [
            "temperature_2m_max",           // skiing limiter, surfing
            "apparent_temperature_max",     // outdoor + indoor comfort
            "precipitation_sum",            // outdoor + indoor
            "rain_sum",                     // skiing, surfing
            "snowfall_sum",                 // skiing
            "precipitation_probability_max",// outdoor + indoor
            "wind_speed_10m_max",           // all four
            "wind_gusts_10m_max",           // surfing
            "sunshine_duration",            // outdoor, via sunshineFraction
            "daylight_duration"             // outdoor, via sunshineFraction
        ]
        let consumedByUI: Set<String> = [
            "weather_code"                  // the day-strip icon and VoiceOver label
        ]

        #expect(Set(OpenMeteoForecastRemoteDataSource.dailyVariables)
                == consumedByScoring.union(consumedByUI))
    }

    @Test("The geocoding request passes the search term and a result limit")
    func geocodingRequestCarriesExpectedParameters() async throws {
        let client = StubHTTPClient(success: GeocodingResponseDTO(results: nil))
        let dataSource = OpenMeteoGeocodingRemoteDataSource(client: client)

        _ = try await dataSource.search(name: "London", count: 15)

        let endpoint = try #require(client.requestedEndpoints.first)
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })

        #expect(endpoint.path == "v1/search")
        #expect(query["name"] == "London")
        #expect(query["count"] == "15")
        #expect(query["format"] == "json")
    }
}

@Suite("Transport error translation")
struct TransportErrorMappingTests {

    @Test("Connectivity failures map to .offline", arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed
    ])
    func connectivityFailures(code: URLError.Code) {
        #expect(URLSessionHTTPClient.mapTransportError(URLError(code)) as? AppError == .offline)
    }

    @Test("Timeouts map to .timedOut")
    func timeout() {
        #expect(URLSessionHTTPClient.mapTransportError(URLError(.timedOut)) as? AppError == .timedOut)
    }

    @Test("Malformed responses map to .invalidResponse", arguments: [
        URLError.Code.badServerResponse, .cannotParseResponse, .zeroByteResource
    ])
    func malformedResponses(code: URLError.Code) {
        #expect(URLSessionHTTPClient.mapTransportError(URLError(code)) as? AppError == .invalidResponse)
    }

    @Test("Cancellation stays cancellation and is never shown as an error")
    func cancellationIsPreserved() {
        // Both spellings must survive: `CancellationError` from Swift concurrency and
        // `URLError.cancelled` from URLSession.
        #expect(URLSessionHTTPClient.mapTransportError(CancellationError()) is CancellationError)
        #expect(URLSessionHTTPClient.mapTransportError(URLError(.cancelled)) is CancellationError)
    }

    @Test("Anything unrecognised is captured rather than swallowed")
    func unknownErrorsAreCaptured() {
        let mapped = URLSessionHTTPClient.mapTransportError(URLError(.unsupportedURL))

        guard case .unknown = mapped as? AppError else {
            Issue.record("Expected .unknown, got \(mapped)")
            return
        }
    }
}

@Suite("AppError presentation contract")
struct AppErrorTests {

    @Test("Errors that would fail identically on retry do not offer a retry button")
    func retryabilityMatchesRecoverability() {
        #expect(AppError.offline.isRetryable)
        #expect(AppError.timedOut.isRetryable)
        #expect(AppError.server(statusCode: 503).isRetryable)
        #expect(!AppError.invalidResponse.isRetryable)
        #expect(!AppError.noResults.isRetryable)
    }

    @Test("Every error has user-facing copy, and none of it leaks internals", arguments: [
        AppError.offline, .timedOut, .server(statusCode: 500), .invalidResponse, .noResults,
        .unknown(description: "CFNetwork error -1005 in __connection_block_invoke")
    ])
    func copyIsPresentAndClean(error: AppError) {
        #expect(!error.title.isEmpty)
        #expect(!error.message.isEmpty)
        // Status codes and debug descriptions are for logs, not for users.
        #expect(!error.message.contains("500"))
        #expect(!error.message.contains("CFNetwork"))
    }
}

// MARK: - Helpers

extension ForecastResponseDTO {
    /// Minimal well-formed payload for tests that only care about the request side.
    static func stubbed() throws -> ForecastResponseDTO {
        let json = #"{"latitude":0,"longitude":0,"timezone":"UTC","daily":{"time":["2026-09-07"]}}"#
        return try JSONDecoder().decode(ForecastResponseDTO.self, from: Data(json.utf8))
    }
}
