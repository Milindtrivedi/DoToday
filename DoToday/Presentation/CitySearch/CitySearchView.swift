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
    @Environment(\.scenePhase) private var scenePhase
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
        // Recording a visit is driven by the navigation path rather than by each row's
        // tap handler. The rows are `NavigationLink`s now, so there is no single place
        // a tap passes through — and this way any future route into the detail screen
        // updates recents automatically instead of having to remember to.
        .onChange(of: path) { previous, current in
            guard current.count > previous.count, let city = current.last else { return }
            viewModel.didSelect(city)
        }
        .task {
            await viewModel.loadSavedCities()
        }
        // Re-read the saved lists on foreground. Today only this process writes them,
        // but the store is a database rather than in-process state — a share
        // extension, a widget, or CloudKit sync would all change it behind our back.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.reloadSavedCities() }
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
                Section {
                    ForEach(cities) { city in
                    CityRow(
                        city: city,
                        isFavourite: viewModel.isFavourite(city),
                        identifier: "\(tab.rawValue)CityRow_\(city.id)",
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

                // Clearing lives at the foot of the list it acts on, as a full-width
                // destructive row — the same shape Safari uses for clearing history.
                // Previously this was a small "Clear" floating above the list in a
                // safe-area inset, which had no padding of its own, belonged to
                // nothing visually, and read as a stray label rather than an action.
                if tab == .recent {
                    Section {
                        Button(role: .destructive) {
                            viewModel.clearRecentCities()
                        } label: {
                            Text("Clear Recent Searches")
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .contentShape(.rect)
                        }
                        .accessibilityIdentifier("clearRecentsButton")
                        // The row's separators inherit the list's leading inset from
                        // the rows above, which leaves them starting under the star
                        // column and looking like a mistake. This row is a footer
                        // action, not another city, so it gets none.
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("\(tab.rawValue)CitiesList")
        }
    }

}

/// One city row: tap the body to open it, tap the star to favourite it.
///
/// The star is a sibling button rather than something nested inside the row button —
/// a button inside a button gives SwiftUI two overlapping tap targets and the wrong
/// one usually wins. Keeping them siblings in an `HStack` makes each hit area
/// unambiguous, and lets VoiceOver expose two distinct actions.
/// One city row: a `NavigationLink` for the whole row, with the favourite star as a
/// *sibling* button beside it.
///
/// This shape is deliberate. The first version drew the disclosure chevron as a bare
/// `Image` sitting after the star, which meant it belonged to no control at all —
/// tapping the arrow landed in dead space and SwiftUI routed it to the nearest
/// interactive view, the star. So the arrow toggled the favourite instead of opening
/// the city, which is the opposite of what it looks like it does.
///
/// `NavigationLink` supplies its own chevron and owns the hit area up to it, so the
/// arrow navigates by construction rather than by hoping the geometry lines up. The
/// star sits at the leading edge, outside the link, with `.borderless` so it takes
/// only its own taps — inside the link's label it would be swallowed by the link.
private struct CityRow: View {
    let city: City
    let isFavourite: Bool
    /// Applied to the link, not to the enclosing `HStack`. An identifier on a
    /// container that is not itself one accessibility element is inherited by every
    /// descendant, which makes `app.buttons["cityRow_1"]` ambiguous.
    let identifier: String
    let toggleFavourite: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleFavourite) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(isFavourite ? .yellow : .secondary)
                    // A 17pt glyph is well under the 44pt minimum touch target.
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            // `.borderless` rather than `.plain`: inside a List row, a plain-styled
            // button lets the row's own tap handling win.
            .buttonStyle(.borderless)
            .accessibilityIdentifier("favouriteButton_\(city.id)")
            .accessibilityLabel(isFavourite ? "Remove \(city.name) from favourites" : "Add \(city.name) to favourites")
            // The star is a toggle, so expose it as one rather than as a plain button
            // whose meaning flips silently between taps.
            .accessibilityAddTraits(isFavourite ? [.isButton, .isSelected] : .isButton)

            NavigationLink(value: city) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.name)
                        .font(.body)
                    if !city.subtitle.isEmpty {
                        Text(city.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityName)
                .accessibilityHint("Opens activity recommendations")
            }
            .accessibilityIdentifier(identifier)
        }
    }

    private var accessibilityName: String {
        let name = city.subtitle.isEmpty ? city.name : "\(city.name), \(city.subtitle)"
        return isFavourite ? "\(name). Favourite" : name
    }
}
