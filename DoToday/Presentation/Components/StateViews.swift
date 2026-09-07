//
//  StateViews.swift
//  DoToday
//
//  Presentation layer — the shared renderings of the non-content `ViewState` cases.
//

import SwiftUI

/// Failure state. The retry affordance is driven by `AppError.isRetryable`, so we
/// never invite the user to retry something that will deterministically fail again.
struct ErrorStateView: View {
    let error: AppError
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: symbolName)
        } description: {
            Text(error.message)
        } actions: {
            if error.isRetryable, let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var symbolName: String {
        switch error {
        case .offline: return "wifi.slash"
        case .timedOut: return "clock.badge.exclamationmark"
        case .noResults: return "magnifyingglass"
        case .server, .invalidResponse, .unknown: return "exclamationmark.triangle"
        }
    }
}

/// Non-blocking banner for a refresh that failed while content is still on screen.
struct InlineErrorBanner: View {
    let error: AppError
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't refresh")
                    .font(.subheadline.weight(.semibold))
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Small "showing saved data" chip used when a forecast came from cache.
struct StaleDataBadge: View {
    let retrievedAt: Date

    var body: some View {
        Label(
            "Saved forecast · updated \(Formatters.relativeUpdated(retrievedAt))",
            systemImage: "externaldrive.badge.checkmark"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
