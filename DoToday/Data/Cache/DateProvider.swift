//
//  DateProvider.swift
//  DoToday
//
//  Data layer — injectable clock.
//

import Foundation

/// Supplies "now".
///
/// Injected everywhere time is read so that cache-expiry and staleness behaviour can
/// be driven deterministically from tests instead of by sleeping.
protocol DateProvider: Sendable {
    var now: Date { get }
}

struct SystemDateProvider: DateProvider {
    var now: Date { Date() }
}
