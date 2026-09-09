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
            await viewModel.loadSavedCities()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            savedCitiesSection

        case .loading:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ErrorStateView(error: .noResults, retry: nil)

        case let .failed(error):
            ErrorStateView(error: error) { viewModel.retry() }

        case let .loaded(cities):
            List(cities) { city in
                CityRow(
                    city: city,
                    isFavourite: viewModel.isFavourite(city),
                    identifier: "cityRow_\(city.id)",
                    open: { open(city) },
                    toggleFavourite: { viewModel.toggleFavourite(city) }
                )
            }
            .listStyle(.plain)
            .accessibilityIdentifier("cityResultsList")
        }
    }

    /// The resting state: a segmented control over the two saved lists.
    private var savedCitiesSection: some View {
        VStack(spacing: 0) {
            Picker("Saved cities", selection: $viewModel.savedTab) {
                ForEach(SavedCityTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("savedCitiesPicker")

            savedCitiesList(for: viewModel.savedTab)
        }
    }

    @ViewBuilder
    private func savedCitiesList(for tab: SavedCityTab) -> some View {
        let cities = tab == .recent ? viewModel.savedLists.recent : viewModel.savedLists.favourites

        if cities.isEmpty {
            // Each tab gets its own empty state naming the action that would fill it.
            ContentUnavailableView {
                Label(tab.emptyTitle, systemImage: tab.emptyImageName)
            } description: {
                Text(tab.emptyMessage)
            }
            .accessibilityIdentifier("savedEmptyState_\(tab.rawValue)")
        } else {
            List {
                ForEach(cities) { city in
                    CityRow(
                        city: city,
                        isFavourite: viewModel.isFavourite(city),
                        identifier: "\(tab.rawValue)CityRow_\(city.id)",
                        open: { open(city) },
                        toggleFavourite: { viewModel.toggleFavourite(city) }
                    )
                    .swipeActions(edge: .trailing) {
                        // Recents are automatic, so removing one is housekeeping.
                        // Favourites are deliberate, so the destructive action there
                        // is un-favouriting, not deleting some other list's entry.
                        if tab == .recent {
                            Button(role: .destructive) {
                                viewModel.removeRecentCity(city)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                viewModel.toggleFavourite(city)
                            } label: {
                                Label("Unfavourite", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("\(tab.rawValue)CitiesList")
            .safeAreaInset(edge: .top) {
                if tab == .recent {
                    HStack {
                        Spacer()
                        Button("Clear") { viewModel.clearRecentCities() }
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("clearRecentsButton")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
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

/// One city row: tap the body to open it, tap the star to favourite it.
///
/// The star is a sibling button rather than something nested inside the row button —
/// a button inside a button gives SwiftUI two overlapping tap targets and the wrong
/// one usually wins. Keeping them siblings in an `HStack` makes each hit area
/// unambiguous, and lets VoiceOver expose two distinct actions.
private struct CityRow: View {
    let city: City
    let isFavourite: Bool
    /// Applied to the *open* button, not to the enclosing `HStack`. An identifier on
    /// a container that is not itself one accessibility element is inherited by every
    /// descendant, which makes `app.buttons["cityRow_1"]` ambiguous.
    let identifier: String
    let open: () -> Void
    let toggleFavourite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
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
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(accessibilityName)
            .accessibilityHint("Opens activity recommendations")

            Button(action: toggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavourite ? .yellow : .secondary)
                    // A larger hit area than the glyph: a 17pt star is well under the
                    // 44pt minimum touch target on its own.
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favouriteButton_\(city.id)")
            .accessibilityLabel(isFavourite ? "Remove \(city.name) from favourites" : "Add \(city.name) to favourites")
            // The star is a toggle, so expose it as one rather than as a plain button
            // whose meaning flips silently between taps.
            .accessibilityAddTraits(isFavourite ? [.isButton, .isSelected] : .isButton)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityName: String {
        let name = city.subtitle.isEmpty ? city.name : "\(city.name), \(city.subtitle)"
        return isFavourite ? "\(name). Favourite" : name
    }
}
