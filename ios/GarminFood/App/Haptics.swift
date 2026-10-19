// Haptics.swift
//
// One place that decides whether to buzz, so the haptics preference is
// honoured everywhere. Views that react to a value change use
// `.sensoryFeedback(_:trigger:condition:)` with `Haptics.isEnabled` as the
// condition; imperative call sites use the helpers below.

import UIKit

@MainActor
enum Haptics {
    /// Mirrors `AppPreferences.hapticsEnabled`; kept in sync by
    /// `AppEnvironment`.
    static var isEnabled = true

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// add-partner-love-theme D4: two soft taps, like a heartbeat -- the
    /// partner theme's log confirmation.
    static func heartbeat() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            generator.impactOccurred(intensity: 1.0)
        }
    }
}
