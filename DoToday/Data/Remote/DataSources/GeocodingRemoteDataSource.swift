//
//  GeocodingRemoteDataSource.swift
//  DoToday
//
//  Data layer — owns the shape of one remote API and nothing else.
//

import Foundation

protocol GeocodingRemoteDataSource: Sendable {
    func search(name: String, count: Int) async throws -> GeocodingResponseDTO
}

struct OpenMeteoGeocodingRemoteDataSource: GeocodingRemoteDataSource {
    // Force-unwrapped: a malformed literal here is a programming error that should
    // fail at first launch, not degrade to a silent no-op at runtime.
    static let baseURL = URL(string: "https://geocoding-api.open-meteo.com")!

    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func search(name: String, count: Int) async throws -> GeocodingResponseDTO {
        let endpoint = Endpoint(
            baseURL: Self.baseURL,
            path: "v1/search",
            queryItems: [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "count", value: String(count)),
                // `language` affects the localised place names returned. We follow the
                // device language so results read naturally, falling back to English.
                URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
                URLQueryItem(name: "format", value: "json")
            ]
        )
        return try await client.get(endpoint, as: GeocodingResponseDTO.self)
    }
}
