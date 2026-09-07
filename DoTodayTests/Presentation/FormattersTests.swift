//
//  FormattersTests.swift
//  DoTodayTests
//
//  The README makes a point of resolving forecast days in the *location's* time zone
//  rather than the device's. `ForecastMapper` is tested for the parsing half of that;
//  this covers the display half, which is where the mistake would actually be visible.
//

import Foundation
import Testing
@testable import DoToday

@Suite("Formatters")
struct FormattersTests {

    /// 2026-01-05T23:30:00Z. In Tokyo (UTC+9) that is already the 6th; in Los Angeles
    /// (UTC-8) it is still the 5th. Any formatter that ignores the supplied zone will
    /// disagree with at least one of these.
    private let instant = Date(timeIntervalSince1970: 1_767_655_800)

    @Test("A day is labelled in the location's time zone, not the device's")
    func weekdayLabelUsesSuppliedTimeZone() {
        let tokyo = Formatters.weekdayLabel(for: instant, timeZoneIdentifier: "Asia/Tokyo")
        let losAngeles = Formatters.weekdayLabel(for: instant, timeZoneIdentifier: "America/Los_Angeles")

        #expect(tokyo.contains("6"))
        #expect(losAngeles.contains("5"))
        #expect(tokyo != losAngeles, "The label ignored the time zone it was given")
    }

    @Test("The long day label is time-zone aware too")
    func fullDayLabelUsesSuppliedTimeZone() {
        let tokyo = Formatters.fullDayLabel(for: instant, timeZoneIdentifier: "Asia/Tokyo")
        let losAngeles = Formatters.fullDayLabel(for: instant, timeZoneIdentifier: "America/Los_Angeles")

        #expect(tokyo != losAngeles)
    }

    @Test("An unknown time zone identifier falls back instead of crashing")
    func unknownTimeZoneFallsBack() {
        let label = Formatters.weekdayLabel(for: instant, timeZoneIdentifier: "Not/AZone")

        #expect(!label.isEmpty)
    }

    @Test("Scores render as whole percentages", arguments: [
        (score: 0.0, expected: "0%"),
        (score: 0.5, expected: "50%"),
        (score: 0.944, expected: "94%"),
        (score: 1.0, expected: "100%")
    ])
    func percentageFormatting(score: Double, expected: String) {
        #expect(Formatters.percentage(score) == expected)
    }

    @Test("Out-of-range scores are clamped rather than shown as nonsense", arguments: [
        (score: -0.5, expected: "0%"),
        (score: 1.8, expected: "100%")
    ])
    func percentageClamps(score: Double, expected: String) {
        #expect(Formatters.percentage(score) == expected)
    }

    @Test("A missing temperature shows a dash, not a fabricated zero")
    func missingTemperature() {
        // Substituting "0°" for "no reading" would be a lie the user cannot detect.
        #expect(Formatters.temperature(nil) == "—")
    }

    @Test("A temperature renders with a value and no fractional digits")
    func temperatureFormatting() {
        let formatted = Formatters.temperature(18.6)

        #expect(formatted.contains("19"))
        #expect(!formatted.contains("."))
    }
}
