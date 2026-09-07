//
//  URLSessionHTTPClient.swift
//  DoToday
//
//  Data layer.
//

import Foundation

/// `URLSession`-backed `HTTPClient`.
///
/// Its one real responsibility beyond issuing the request is *error translation*:
/// everything `URLSession` and `JSONDecoder` can throw is funnelled into `AppError`
/// here, so no transport type ever escapes the data layer.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func get<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response {
        let request = try endpoint.urlRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.server(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            // A decoding failure means the API contract changed or we misread it.
            // It is a bug, not a user-facing retryable condition.
            throw AppError.invalidResponse
        }
    }

    /// Translates `URLError` (and task cancellation) into the domain vocabulary.
    static func mapTransportError(_ error: Error) -> Error {
        // Cancellation is propagated untouched: it is control flow, not a failure,
        // and callers must be able to tell the two apart (see `CitySearchViewModel`,
        // which cancels its in-flight search on every keystroke).
        if error is CancellationError { return error }

        guard let urlError = error as? URLError else {
            return AppError.unknown(description: String(describing: error))
        }

        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return AppError.offline
        case .timedOut:
            return AppError.timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return AppError.offline
        case .badServerResponse, .cannotParseResponse, .zeroByteResource:
            return AppError.invalidResponse
        default:
            return AppError.unknown(description: urlError.localizedDescription)
        }
    }
}
