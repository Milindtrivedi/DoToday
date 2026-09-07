//
//  DoTodayUITests.swift
//  DoTodayUITests
//
//  End-to-end smoke tests over the primary journey: search → pick a city → see a
//  ranking → drill into a day-by-day breakdown.
//
//  These run against a stubbed network (see `UITestSupport.swift`), injected via a
//  launch argument. That keeps them deterministic and runnable offline — a UI test
//  that depends on live weather would fail for reasons that have nothing to do with
//  the code under test.
//

import XCTest

/// `@MainActor` on the whole class: `XCUIApplication` and every `XCUIElement`
/// accessor are main-actor isolated, so without it each call site is a Swift 6
/// concurrency warning. Annotating per-method (as the Xcode template does) works too,
/// but the class-level annotation cannot be forgotten on a newly added test.
@MainActor
final class DoTodayUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Launches the app with the stubbed-network argument.
    ///
    /// Called at the top of each test rather than from `setUpWithError`. XCTestCase
    /// declares those overrides `nonisolated`, and an override cannot add isolation
    /// its superclass does not declare — so touching main-actor `XCUIApplication`
    /// from there is a Swift 6 concurrency error. Launching from a `@MainActor`
    /// member of this `@MainActor` class sidesteps that entirely, and keeps the
    /// launch visible in each test rather than hidden in a lifecycle hook.
    private func launchApp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestStubbedAPI"]
        app.launch()
    }

    func testLaunchesIntoTheIdleSearchState() {
        launchApp()
        XCTAssertTrue(
            element("searchIdleState").waitForExistence(timeout: 5),
            "The app should open on the empty-search prompt, not a spinner or an error"
        )
        XCTAssertTrue(app.searchFields.firstMatch.exists)
    }

    func testSearchingShowsMatchingCities() {
        launchApp()
        search(for: "Chamonix")

        XCTAssertTrue(
            app.buttons["cityRow_1"].waitForExistence(timeout: 5),
            "Search results should appear for a matching query"
        )
    }

    func testShortQueryDoesNotLeaveTheIdleState() {
        launchApp()
        search(for: "C")

        // One character is below the minimum query length, so nothing is dispatched.
        XCTAssertTrue(element("searchIdleState").waitForExistence(timeout: 3))
    }

    func testSelectingACityShowsRankedActivities() {
        launchApp()
        search(for: "Chamonix")
        XCTAssertTrue(app.buttons["cityRow_1"].waitForExistence(timeout: 5))
        app.buttons["cityRow_1"].tap()

        XCTAssertTrue(
            element("activityRankingList").waitForExistence(timeout: 5),
            "Tapping a city should show its activity ranking"
        )
        for activity in ["skiing", "surfing", "outdoorSightseeing", "indoorSightseeing"] {
            XCTAssertTrue(
                element("activityRow_\(activity)").exists,
                "All four activities should always be ranked; \(activity) was missing"
            )
        }
    }

    func testExpandingAnActivityRevealsTheDailyBreakdown() {
        launchApp()
        search(for: "Chamonix")
        XCTAssertTrue(app.buttons["cityRow_1"].waitForExistence(timeout: 5))
        app.buttons["cityRow_1"].tap()

        let skiingRow = element("activityRow_skiing")
        XCTAssertTrue(skiingRow.waitForExistence(timeout: 5))
        let dayRows = app.descendants(matching: .any).matching(identifier: "dayScoreRow")
        XCTAssertEqual(dayRows.count, 0,
                       "Daily rows should be collapsed until the activity is tapped")

        skiingRow.tap()

        // `firstMatch` because seven elements share this identifier, and resolving an
        // ambiguous query would fail for the wrong reason.
        XCTAssertTrue(dayRows.firstMatch.waitForExistence(timeout: 3))
        // The stub returns a seven-day window.
        XCTAssertEqual(dayRows.count, 7)
    }

    // MARK: - Recent searches

    func testVisitingACityAddsItToRecents() {
        launchApp()
        // Fresh launch: no history yet, so the explanatory prompt is showing.
        XCTAssertTrue(element("searchIdleState").waitForExistence(timeout: 5))

        search(for: "Chamonix")
        XCTAssertTrue(app.buttons["cityRow_1"].waitForExistence(timeout: 5))
        app.buttons["cityRow_1"].tap()
        XCTAssertTrue(element("activityRankingList").waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()   // back
        clearSearchField()

        XCTAssertTrue(
            app.buttons["recentCityRow_1"].waitForExistence(timeout: 5),
            "The visited city should appear under Recent once the field is cleared"
        )
    }

    func testClearingRecentsReturnsToTheEmptyPrompt() {
        launchApp()
        search(for: "Chamonix")
        XCTAssertTrue(app.buttons["cityRow_1"].waitForExistence(timeout: 5))
        app.buttons["cityRow_1"].tap()
        XCTAssertTrue(element("activityRankingList").waitForExistence(timeout: 5))

        app.navigationBars.buttons.firstMatch.tap()
        clearSearchField()
        XCTAssertTrue(app.buttons["recentCityRow_1"].waitForExistence(timeout: 5))

        element("clearRecentsButton").tap()

        XCTAssertTrue(
            element("searchIdleState").waitForExistence(timeout: 3),
            "Clearing the last recent should fall back to the explanatory prompt"
        )
    }

    // MARK: - Helpers

    /// Looks an identifier up across every element type.
    ///
    /// SwiftUI does not guarantee which XCUIElement type a given view maps to, and
    /// pinning the wrong one makes a test fail for reasons unrelated to behaviour.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Empties the search field so the screen returns to its idle state.
    private func clearSearchField() {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The clear ("x") button appears inside the field once it has text.
        let clearButton = field.buttons.firstMatch
        if clearButton.exists {
            clearButton.tap()
        } else {
            field.tap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
    }

    private func search(for text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }
}
