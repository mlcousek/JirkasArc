// FoodDayCloseCard.swift
//
// improve-food-day-flow (A2): the card under the last meal card. On a day
// that can be closed it is one button, "That's everything today"; on a
// closed day it says so, offers Undo, and says "Edited after closing" when
// an entry changed since. Both states show the complete-days streak when
// there is one -- beside, never instead of, the logging streak on the
// progress strip.
//
// Draws only: the state comes from FoodLogCore's `FoodDayCloseRules` and
// the count from `CompleteDaysStreak`, both through FoodDayCloseController.
// A day with nothing to offer (no entry, or a day after today) draws
// nothing at all.
//
// Depends on: FoodLogCore, the design system. Depended on by: TodayView
// (the `.meals` slot).

import SwiftUI
import FoodLogCore

struct FoodDayCloseCard: View {
    let state: FoodDayCloseRules.State
    /// Picks the button's wording: today, or the past day on screen.
    let isToday: Bool
    /// Closed days in a row; the line is hidden at 0.
    let streak: Int
    let onClose: () -> Void
    let onUndo: () -> Void

    var body: some View {
        switch state {
        case .notOffered:
            EmptyView()
        case .open:
            openCard
        case .closed(let editedAfterClosing):
            closedCard(editedAfterClosing: editedAfterClosing)
        }
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onClose) {
                closeLabel
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityHint("Marks this day's food log as complete")

            streakLine
        }
        .card()
    }

    /// Two literals, not one interpolated string: each is its own key.
    @ViewBuilder
    private var closeLabel: some View {
        if isToday {
            Label("That's everything today", systemImage: "checkmark.circle")
        } else {
            Label("That's everything for this day", systemImage: "checkmark.circle")
        }
    }

    private func closedCard(editedAfterClosing: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Label("Food log closed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.success)
                Spacer(minLength: Theme.Spacing.sm)
                Button("Undo", action: onUndo)
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                    .tint(Theme.accent)
            }
            if editedAfterClosing {
                Text("Edited after closing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            streakLine
        }
        .card()
    }

    @ViewBuilder
    private var streakLine: some View {
        if streak > 0 {
            Label {
                Text("\(streak) complete days in a row")
            } icon: {
                Image(systemName: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
