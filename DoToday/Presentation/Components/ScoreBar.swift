//
//  ScoreBar.swift
//  DoToday
//
//  Presentation layer — small, stateless view components.
//

import SwiftUI

/// Horizontal 0...1 meter used for activity scores.
///
/// Colour alone never carries the meaning: the numeric percentage is always shown
/// beside it, and the accessibility value reads the score aloud.
struct ScoreBar: View {
    let score: Double

    private var clamped: Double { min(1, max(0, score)) }

    /// Green / amber / red banding. Thresholds are shared with `ScoreTint` so the
    /// bar and the label can never disagree.
    private var tint: Color { ScoreTint.color(for: clamped) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * clamped))
                    .animation(.easeOut(duration: 0.25), value: clamped)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Suitability")
        .accessibilityValue(Formatters.percentage(clamped))
    }
}

/// Shared score-to-colour banding.
enum ScoreTint {
    static func color(for score: Double) -> Color {
        switch score {
        case ..<0.35: return .red
        case ..<0.65: return .orange
        default: return .green
        }
    }

    /// Plain-language band, used for VoiceOver and the summary line.
    static func label(for score: Double) -> String {
        switch score {
        case ..<0.35: return "Poor"
        case ..<0.65: return "Fair"
        case ..<0.8: return "Good"
        default: return "Excellent"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ScoreBar(score: 0.15)
        ScoreBar(score: 0.5)
        ScoreBar(score: 0.9)
    }
    .padding()
}
