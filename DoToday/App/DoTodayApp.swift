//
//  DoTodayApp.swift
//  DoToday
//
//  App layer — entry point. Owns the composition root and nothing else.
//

import SwiftUI

@main
struct DoTodayApp: App {
    /// Single, app-lifetime object graph. Held here (not in a global singleton) so
    /// dependencies flow downward explicitly and stay swappable in tests.
    @State private var container = DoTodayApp.makeContainer()

    /// Production builds always get the real graph. Debug builds additionally honour
    /// the UI-test launch argument, which swaps in a stubbed network so UI tests are
    /// deterministic and offline-safe. See `UITestSupport.swift`.
    private static func makeContainer() -> AppContainer {
        #if DEBUG
        if AppContainer.isRunningUITestsWithStubbedAPI {
            return .makeForUITests()
        }
        #endif
        return AppContainer()
    }

    var body: some Scene {
        WindowGroup {
            CitySearchView(
                viewModel: container.makeCitySearchViewModel(),
                makeRecommendationsViewModel: container.makeRecommendationsViewModel(for:)
            )
        }
    }
}
