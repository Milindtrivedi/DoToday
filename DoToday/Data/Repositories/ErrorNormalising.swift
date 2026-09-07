//
//  ErrorNormalising.swift
//  DoToday
//
//  Data layer — guarantees the repository boundary only ever emits `AppError`.
//

import Foundation

enum ErrorNormalising {
    /// Collapses any thrown value into the domain vocabulary.
    ///
    /// `CancellationError` is passed through untouched: a cancelled task is not a
    /// failure to show the user, and callers rely on being able to distinguish it.
    static func normalise(_ error: Error) -> Error {
        switch error {
        case is CancellationError:
            return error
        case let appError as AppError:
            return appError
        default:
            return URLSessionHTTPClient.mapTransportError(error)
        }
    }
}
