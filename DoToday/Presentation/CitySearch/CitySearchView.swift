//
//  CitySearchView.swift
//  DoToday
//
//  Presentation layer — a pure rendering of `CitySearchViewModel.state`.
//

import SwiftUI

/// Root screen: search for a city, then drill into its recommendations.
///
/// The view owns navigation but no logic. Every branch below maps one-to-one onto a
/// `ViewState` case, which is what keeps the screen impossible to get into an
/// inconsistent visual state.
struct CitySearchView: View {
    @State private var viewModel: CitySearchViewModel
    @State private var path: [City] = []

    /// Builds the next screen's ViewModel. Injected by the composition root so this
    /// view never constructs a use case or repository itself.
    private let makeRecommendationsViewModel: (City) -> RecommendationsViewModel

    init(
        viewModel: CitySearchViewModel,
        makeRecommendationsViewModel: @escaping (City) -> RecommendationsViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.makeRecommendationsViewModel = makeRecommendationsViewModel
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("DoToday")
                .navigationDestination(for: City.self) { city in
                    RecommendationsView(viewModel: makeRecommendationsViewModel(city))
                }
        }
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search for a city"
        )
        .onChange(of: viewModel.query) {
            viewModel.queryDidChange()
        }
        .task {
            await viewModel.loadRecentCities()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            // The resting state shows recent searches once there are any, and the
            // explanatory prompt until then.
            if viewModel.recentCities.isEmpty {
                ContentUnavailableView {
                    Label("Where are you going?", systemImage: "magnifyingglass")
                } description: {
                    Text("Search for a city to see which activities suit its weather over the next 7 days.")
                }
                // Stable identifiers for UI tests; they never change with copy or locale.
                .accessibilityIdentifier("searchIdleState")
            } else {
                recentCitiesList
            }

        case .loading:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ErrorStateView(error: .noResults, retry: nil)

        case let .failed(error):
            ErrorStateView(error: error) { viewModel.retry() }

        case let .loaded(cities):
            List(cities) { city in
                Button {
                    open(city)
                } label: {
                    CityRow(city: city)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cityRow_\(city.id)")
            }
            .listStyle(.plain)
            .accessibilityIdentifier("cityResultsList")
        }
    }

    private var recentCitiesList: some View {
        List {
            Section {
                ForEach(viewModel.recentCities) { city in
                    Button {
                        open(city)
                    } label: {
                        CityRow(city: city)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("recentCityRow_\(city.id)")
                    // Swipe-to-delete rather than an edit mode: one entry at a time is
                    // the only removal anyone actually wants here.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.removeRecentCity(city)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") {
                        viewModel.clearRecentCities()
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                    .accessibilityIdentifier("clearRecentsButton")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("recentCitiesList")
    }

    /// The single path into the detail screen.
    ///
    /// Navigation and recording go together by construction, so a future entry point
    /// cannot navigate without also updating the recents list.
    private func open(_ city: City) {
        viewModel.didSelect(city)
        path.append(city)
    }
}

/// One search result or recent city.
private struct CityRow: View {
    let city: City

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(.body)
                if !city.subtitle.isEmpty {
                    Text(city.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        // Combine into one element so VoiceOver reads "Chamonix, Auvergne-Rhône-Alpes,
        // France" rather than three separate stops.
        .accessibilityElement(children: .combine)
    }
}
