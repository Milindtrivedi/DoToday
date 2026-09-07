//
//  AppError.swift
//  DoToday
//
//  Domain layer — the single error vocabulary the presentation layer understands.
//

import Foundation

/// The exhaustive set of failures the UI can render.
///
/// Data-layer errors (`URLError`, `DecodingError`, HTTP status codes) are translated
/// into this type at the repository boundary, so ViewModels never switch on transport
/// details and every failure has a defined, user-facing presentation.
enum AppError: Error, Equatable {
    /// No usable network connection.
    case offline
    /// The request took too long.
    case timedOut
    /// The server answered, but not with success. `statusCode` is kept for logging.
    case server(statusCode: Int)
    /// We got a 2xx response we could not parse — a contract change on their side
    /// or a bug on ours. Never retryable by the user.
    case invalidResponse
    /// The request completed but there was nothing to show (e.g. unknown city name).
    case noResults
    /// Anything we failed to classify. `description` is developer-facing only.
    case unknown(description: String)

    /// Short, user-facing headline.
    var title: String {
        switch self {
        case .offline: return "You're offline"
        case .timedOut: return "This is taking too long"
        case .server: return "Service unavailable"
        case .invalidResponse: return "Something went wrong"
        case .noResults: return "No matches"
        case .unknown: return "Something went wrong"
        }
    }

    /// User-facing explanation. Deliberately free of jargon and status codes.
    var message: String {
        switch self {
        case .offline:
            return "Check your connection and try again."
        case .timedOut:
            return "The forecast service didn't respond in time. Try again in a moment."
        case .server:
            return "The forecast service is having trouble right now. Please try again shortly."
        case .invalidResponse:
            return "We couldn't read the forecast data. Please try again."
        case .noResults:
            return "We couldn't find a place with that name. Try a different spelling."
        case .unknown:
            return "An unexpected problem occurred. Please try again."
        }
    }

    /// Whether offering a "Try again" button makes sense. A parse failure will fail
    /// identically on retry, so we don't invite the user into a loop.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .server, .unknown: return true
        case .invalidResponse, .noResults: return false
        }
    }
}
