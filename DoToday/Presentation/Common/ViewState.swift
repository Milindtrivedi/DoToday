//
//  ViewState.swift
//  DoToday
//
//  Presentation layer — explicit state modelling.
//

import Foundation

/// The complete set of states a data-driven screen can be in.
///
/// Modelling state as one enum (rather than the usual `isLoading` / `data` / `error`
/// triple) makes impossible states unrepresentable: the app cannot be loading *and*
/// failed, and a view can never render a spinner over stale content by accident.
/// Every `switch` in the UI is exhaustive, so a new state forces the UI to handle it.
enum ViewState<Value: Equatable>: Equatable {
    /// Nothing requested yet — the initial, pre-interaction state.
    case idle
    /// A request is in flight and there is nothing to show underneath it.
    case loading
    /// Loaded successfully with content.
    case loaded(Value)
    /// Loaded successfully, but the result is empty (no matching cities).
    case empty
    /// The request failed. Carries the error so the view can offer the right recovery.
    case failed(AppError)

    var value: Value? {
        if case let .loaded(value) = self { return value }
        return nil
    }

    var isLoading: Bool { self == .loading }
}
