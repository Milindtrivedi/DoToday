//
//  Endpoint.swift
//  DoToday
//
//  Data layer — declarative request description, decoupled from URLSession.
//

import Foundation

/// A single HTTP request expressed as data.
///
/// Building requests as a value type (rather than assembling `URLRequest`s inline)
/// keeps URL construction testable: a test can assert on the produced URL string
/// without spinning up a network stack.
struct Endpoint: Equatable {
    let baseURL: URL
    let path: String
    let queryItems: [URLQueryItem]

    init(baseURL: URL, path: String, queryItems: [URLQueryItem] = []) {
        self.baseURL = baseURL
        self.path = path
        self.queryItems = queryItems
    }

    /// - Returns: The fully-formed URL, or `nil` if the components are invalid
    ///   (which would indicate a programming error, not a runtime condition).
    var url: URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    func urlRequest() throws -> URLRequest {
        guard let url else { throw AppError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
