//
//  RecommendationsView.swift
//  DoToday
//
//  Presentation layer — a pure rendering of `RecommendationsViewModel.state`.
//

import SwiftUI

/// Ranked activities for one city over the next 7 days.
struct RecommendationsView: View {
    @State private var viewModel: RecommendationsViewModel
    /// Which activity's day-by-day breakdown is expanded. Purely visual, so it lives
    /// in the view rather than the ViewModel.
    @State private var expandedActivity: Activity?

    init(viewModel: RecommendationsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .navigationTitle(viewModel.city.name)
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading forecast…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            // The use case converts an empty forecast into `.invalidResponse`, so this
            // case is unreachable today. It is still handled explicitly: an
            // exhaustive switch is the point of modelling state as an enum.
            ErrorStateView(error: .invalidResponse, retry: nil)

        case let .failed(error):
            ErrorStateView(error: error) {
                Task { await viewModel.retry() }
            }

        case let .loaded(recommendations):
            loadedList(recommendations)
        }
    }

    private func loadedList(_ recommendations: RankedRecommendations) -> some View {
        List {
            if let refreshError = viewModel.refreshError {
                Section {
                    InlineErrorBanner(error: refreshError) { viewModel.dismissRefreshError() }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(recommendations.rankings) { ranking in
                    ActivityRankingRow(
                        ranking: ranking,
                        timeZoneIdentifier: recommendations.forecast.timeZoneIdentifier,
                        isExpanded: expandedActivity == ranking.activity,
                        toggle: {
                            withAnimation(.snappy) {
                                expandedActivity = expandedActivity == ranking.activity ? nil : ranking.activity
                            }
                        }
                    )
                }
            } header: {
                Text("Best bets for the next \(recommendations.forecast.days.count) days")
            } footer: {
                if recommendations.isStale {
                    StaleDataBadge(retrievedAt: recommendations.forecast.retrievedAt)
                } else {
                    Text("Scores combine the week's average with its best single day.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("activityRankingList")
        // Pull-to-refresh forces a network revalidation (bonus requirement).
        .refreshable {
            await viewModel.refresh()
        }
    }
}

/// One ranked activity: headline score, best day, and an expandable 7-day breakdown.
private struct ActivityRankingRow: View {
    let ranking: ActivityRanking
    let timeZoneIdentifier: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ForEach(ranking.dailyScores) { day in
                    DayScoreRow(day: day, timeZoneIdentifier: timeZoneIdentifier)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: ranking.activity.systemImageName)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(ScoreTint.color(for: ranking.overallScore))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ranking.activity.title)
                        .font(.headline)
                    Text(bestDaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Formatters.percentage(ranking.overallScore))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(ScoreTint.color(for: ranking.overallScore))

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }

            ScoreBar(score: ranking.overallScore)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ranking.activity.title), \(ScoreTint.label(for: ranking.overallScore)), \(Formatters.percentage(ranking.overallScore)). \(bestDaySummary)"
        )
        .accessibilityHint(isExpanded ? "Collapse daily breakdown" : "Expand daily breakdown")
        .accessibilityAddTraits(.isButton)
        // Set on the header, not the enclosing VStack: an identifier on a container
        // that is not itself a single accessibility element is inherited by every
        // descendant, which would mask the day rows' own identifiers.
        .accessibilityIdentifier("activityRow_\(ranking.activity.rawValue)")
    }

    private var bestDaySummary: String {
        guard let bestDay = ranking.bestDay else { return "No forecast available" }
        let label = Formatters.fullDayLabel(for: bestDay.date, timeZoneIdentifier: timeZoneIdentifier)
        return "Best day: \(label) · \(Formatters.percentage(bestDay.score))"
    }
}

/// One day inside an expanded activity, with the weather that produced the score.
private struct DayScoreRow: View {
    let day: DailyActivityScore
    let timeZoneIdentifier: String

    var body: some View {
        HStack(spacing: 12) {
            Text(Formatters.weekdayLabel(for: day.date, timeZoneIdentifier: timeZoneIdentifier))
                .font(.caption.weight(.medium))
                .frame(width: 62, alignment: .leading)

            Image(systemName: day.weather.weatherCode.systemImageName)
                .font(.caption)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(Formatters.temperature(day.weather.temperatureMax))
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.secondary)

            ScoreBar(score: day.score)

            Text(Formatters.percentage(day.score))
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dayScoreRow")
        .accessibilityLabel(
            "\(Formatters.fullDayLabel(for: day.date, timeZoneIdentifier: timeZoneIdentifier)), \(day.weather.weatherCode.shortDescription), high \(Formatters.temperature(day.weather.temperatureMax)), \(Formatters.percentage(day.score))"
        )
    }
}
