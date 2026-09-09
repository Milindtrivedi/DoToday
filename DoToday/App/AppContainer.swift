//
//  AppContainer.swift
//  DoToday
//
//  App layer — the composition root.
//

import Foundation
import SwiftData

/// Builds and wires the object graph.
///
/// Manual, protocol-based dependency injection rather than a DI framework: the graph
/// is small, the wiring is explicit and greppable, and there is no runtime resolution
/// that can fail. This is also the *only* place that names concrete implementations —
/// every other type depends on protocols, which is what makes them mockable.
@MainActor
final class AppContainer {

    // MARK: Domain

    // Infrastructure is not retained: it is consumed while building the graph below,
    // and the use cases hold the only references that outlive `init`.

    private let searchCitiesUseCase: SearchCitiesUseCase
    private let rankActivitiesUseCase: RankActivitiesUseCase
    private let savedCitiesUseCase: SavedCitiesUseCase

    /// - Parameters are pre-seeded with production implementations but remain
    ///   injectable, so an integration test or a SwiftUI preview can swap in stubs
    ///   without duplicating the wiring below.
    init(
        httpClient: HTTPClient = URLSessionHTTPClient(session: .doTodayDefault),
        forecastCache: ForecastCache = FileForecastCache(),
        savedCitiesStore: SavedCitiesStore = AppContainer.makeSavedCitiesStore(),
        dateProvider: DateProvider = SystemDateProvider()
    ) {
        let cityRepository = DefaultCityRepository(
            remote: OpenMeteoGeocodingRemoteDataSource(client: httpClient)
        )
        let forecastRepository = DefaultForecastRepository(
            remote: OpenMeteoForecastRemoteDataSource(client: httpClient),
            cache: forecastCache,
            dateProvider: dateProvider
        )

        self.searchCitiesUseCase = DefaultSearchCitiesUseCase(repository: cityRepository)
        self.rankActivitiesUseCase = DefaultRankActivitiesUseCase(
            repository: forecastRepository,
            engine: DefaultActivityScoringEngine()
        )
        self.savedCitiesUseCase = DefaultSavedCitiesUseCase(
            store: savedCitiesStore,
            dateProvider: dateProvider
        )
    }

    // MARK: ViewModel factories

    func makeCitySearchViewModel() -> CitySearchViewModel {
        CitySearchViewModel(searchCities: searchCitiesUseCase, savedCities: savedCitiesUseCase)
    }

    func makeRecommendationsViewModel(for city: City) -> RecommendationsViewModel {
        RecommendationsViewModel(city: city, rankActivities: rankActivitiesUseCase)
    }
}

extension AppContainer {
    /// Builds the SwiftData-backed store, falling back to an in-memory one if the
    /// container cannot be opened (a corrupt store, or a device with no free space).
    ///
    /// Recents and favourites are a convenience: losing them across a launch is a
    /// regression, but refusing to start the app over them would be far worse.
    static func makeSavedCitiesStore() -> SavedCitiesStore {
        do {
            return SwiftDataSavedCitiesStore(modelContainer: try .doToday())
        } catch {
            return InMemorySavedCitiesStore()
        }
    }
}

extension URLSession {
    /// Session tuned for this app's usage.
    ///
    /// The default 60 s timeout is far too patient for a search-as-you-type field; 15 s
    /// gets the user to an actionable error while they still care. `waitsForConnectivity`
    /// stays off so an offline device fails fast into our cached/offline path instead
    /// of hanging on a spinner.
    static var doTodayDefault: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        // We do our own explicit, inspectable caching in `FileForecastCache`; leaving
        // URLCache on as well would make staleness impossible to reason about.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}
