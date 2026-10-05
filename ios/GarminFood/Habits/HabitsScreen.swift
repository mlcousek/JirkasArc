// HabitsScreen.swift
//
// The Habits screen (add-interactive-habits design D6; it replaces the
// read-only HabitLadderView of add-training-today-and-plan): the ladder as
// steps, top to bottom --
//
//   established   an active habit with a later step active too: a check
//   current       the highest active step: where he stands
//   locked        next or later, with what unlocks it ("Unlocks when Gym
//                 twice a week holds 80 % over a 14-day window", "Gate
//                 met: ...", "Unlocks after: ...") and its earliest start
//
// An active step shows its streak flame, its 14-day window against the
// gate and, when today's plan expects it, the same one-tap check as
// Today's card. A row opens that habit's detail (HabitDetailView): today's
// control, streaks, adherence, the 12-week calendar with back-fill, the
// recent entries.
//
// Reached from Today's Habits card (its header and next step), from Plan's
// toolbar, and from a `garminfood://habits` link (AppRouter -> PlanTabView).
// Everything shown is TrainingCore's `HabitsScreenModel`; a check calls
// `TrainingModel.applyHabit` (a local event, never a network wait).
// Starting or pausing a step stays a desk decision: no control for it here.
//
// Depended on by: HabitsDestination (TodayView, PlanTabView).

import SwiftUI
import TrainingCore

struct HabitsScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var detail: HabitsTarget?

    var body: some View {
        let training = environment.training
        let model = training.habitsBuilder().screen()
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if let empty = model.emptyText {
                    TrainingEmptyStateView(state: TrainingEmptyState(kind: .noActivePlan, symbol: "stairs", title: empty, message: nil))
                        .card()
                } else {
                    HabitsSummaryCard(model: model)
                }
                ForEach(model.steps) { step in
                    HabitStepCard(
                        step: step,
                        onOpen: { detail = HabitsTarget(habitID: step.id) },
                        onStep: { control, target in
                            Task { await training.applyHabit(control, to: target) }
                        }
                    )
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Habits")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detail) { target in
            HabitsDestination(target: target)
        }
        .task {
            if !training.hasLoaded { await training.reload() }
        }
    }
}

/// Where he stands: the step, today's progress, the gate.
private struct HabitsSummaryCard: View {
    let model: HabitsScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                if let step = model.stepText {
                    Text(verbatim: step)
                        .font(.title3.weight(.bold))
                }
                Spacer(minLength: Theme.Spacing.sm)
                if let progress = model.progressText {
                    Text(verbatim: progress)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let gate = model.gateText {
                Label {
                    Text(verbatim: gate)
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One step of the ladder.
private struct HabitStepCard: View {
    let step: HabitStepModel
    let onOpen: () -> Void
    let onStep: (HabitDayControlModel, Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Button(action: onOpen) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: step.accessibilityLabel))
            .accessibilityHint("Opens the habit's history")
            if let control = step.today {
                HabitCheckButton(control: control) { target in
                    onStep(control, target)
                }
            }
        }
        .card()
        .opacity(step.kind == .locked ? 0.8 : 1)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: markerSymbol)
                .font(.title3)
                .foregroundStyle(markerTint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    if let icon = step.icon {
                        Text(verbatim: icon)
                    }
                    Text(verbatim: step.label)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Theme.Spacing.xs)
                    if let streak = step.streak {
                        HabitStreakBadge(count: streak.current, isLit: streak.isLit, text: streak.currentText)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(verbatim: "\(step.stepText) · \(step.kindText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(markerTint)
                let details = [step.dose, step.schedule, step.dateText].compactMap { $0 }
                if !details.isEmpty {
                    Text(verbatim: details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                if let adherence = step.adherence {
                    HStack(spacing: Theme.Spacing.sm) {
                        if let fraction = step.fraction {
                            ProgressView(value: min(max(fraction, 0), 1))
                                .tint(Theme.accent)
                                .frame(maxWidth: 96)
                        }
                        Text(verbatim: adherence)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let unlock = step.unlockText {
                    Label {
                        Text(verbatim: unlock)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let gateMet = step.gateMetText {
                    Label {
                        Text(verbatim: gateMet)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var markerSymbol: String {
        switch step.kind {
        case .established: return "checkmark.circle.fill"
        case .current: return "play.circle.fill"
        case .locked: return "lock.circle"
        }
    }

    private var markerTint: Color {
        switch step.kind {
        case .established: return Theme.success
        case .current: return Theme.accent
        case .locked: return Color.secondary
        }
    }
}
