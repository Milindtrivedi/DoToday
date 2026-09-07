//
//  Formatters.swift
//  DoToday
//
//  Presentation layer — display formatting kept out of the ViewModels so they stay
//  assertable on values rather than on localised strings.
//

import Foundation

enum Formatters {

    /// "Mon 8" — short weekday plus day number, rendered in the *location's* time zone.
    ///
    /// Using the forecast's own zone matters: a day boundary in Tokyo is not a day
    /// boundary in London, and showing the device's interpretation would slide the
    /// whole week by one for a user planning a trip.
    static func weekdayLabel(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEd")
        return formatter.string(from: date)
    }

    /// "Monday 8 September"
    static func fullDayLabel(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// A 0...1 score as a whole percentage, e.g. "83%".
    static func percentage(_ score: Double) -> String {
        let clamped = min(1, max(0, score))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// Temperature in whole degrees Celsius, or an em dash when unavailable.
    static func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        return measurement.formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    /// Relative "updated" stamp, e.g. "2 minutes ago".
    static func relativeUpdated(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
