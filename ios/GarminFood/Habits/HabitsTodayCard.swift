// HabitsTodayCard.swift
//
// Today's Habits card, interactive (add-interactive-habits design D8; it
// replaces the card polish-training-today put in TrainingTodayCards.swift,
// whose rows only listed a habit beside a small toggle). Every habit the
// shown day expects is a checklist row:
//
//   [check]  icon  Holds                    flame 5   >
//                  5 x 45 s · 2x a day
//                  1 of 2 · 18 of 24 · 75 %
//
//   - the check leads the row and is one tap: a tick for a single-dose
//     habit, the next dose for a multi-dose one (a ring with "1/2"); a tap
//     on a complete day takes one dose back, so a mis-tap never wipes it;
//   - the flame carries the streak, lit while it runs;
//   - the rest of the row opens that habit's detail (history, back-fill),
//     and so does a long press on the row ("History");
//   - the header and the next step open the whole ladder;
//   - when the last expected habit is ticked the progress line turns into
//     "All of today's habits done" with a success haptic and one bounce
//     (none under Reduce Motion). The gamification moments overlay is not
//     reused: it is the XP engine's queue, and a habit tick earns no XP
//     here.
//
// The rows, step and next step are TrainingCore's `HabitsCardModel`; the
// checks, streaks and the day's progress its `HabitChecksModel` (which
// counts a multi-dose habit only once every dose is done). The card only calls back;
// TodayView turns a step into `TrainingModel.applyHabit` (a local event,
// never a network wait).
//
// Depended on by: TodayView.

import SwiftUI
import TrainingCore

struct HabitsTodayCard: View {
    let model: HabitsCardModel
    let checks: HabitChecksModel
    let onOpen: (HabitsTarget) -> Void
    /// A check was tapped: the day's control and the dose count asked for.
    var onStep: (HabitDayControlModel, Int) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    /// The celebration fires when THIS day becomes complete, not when the
    /// day switcher lands on a day that already was.
    private struct Completion: Equatable {
        let date: LocalDate
        let allDone: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                onOpen(.ladder)
            } label: {
                HStack {
                    SectionHeader(
                        title: String(localized: "Habits", comment: "polish-training-today: Layout editor row and title of the Habits card on Today (the habit ladder)."),
                        trailing: model.stepText
                    )
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the habit ladder")

            if let progress = checks.progressText {
                progressLine(progress)
            }
            ForEach(model.rows) { row in
                HabitTodayRow(
                    row: row,
                    check: checks.check(row.id),
                    onOpen: { onOpen(HabitsTarget(habitID: row.id)) },
                    onStep: onStep
                )
            }
            if let next = model.next {
                Button {
                    onOpen(.ladder)
                } label: {
                    HabitNextStepRow(next: next)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the habit ladder")
            }
        }
        .card()
        .onChange(of: Completion(date: checks.date, allDone: checks.allDone)) { old, new in
            guard old.date == new.date, !old.allDone, new.allDone else { return }
            Haptics.success()
            if !reduceMotion { bounce += 1 }
        }
    }

    private func progressLine(_ progress: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView(value: Double(checks.doneCount), total: Double(max(checks.expectedCount, 1)))
                .tint(checks.allDone ? Theme.success : Theme.accent)
                .accessibilityHidden(true)
            if checks.allDone {
                Label {
                    Text(verbatim: checks.allDoneText)
                } icon: {
                    Image(systemName: "party.popper.fill")
                        .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
                .fixedSize()
                .transition(.opacity)
            } else {
                Text(verbatim: progress)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: checks.allDone)
        .accessibilityElement(children: .combine)
    }
}

/// One habit of the shown day: the check, what it is, its streak.
private struct HabitTodayRow: View {
    let row: HabitRowModel
    let check: HabitCheckModel?
    let onOpen: () -> Void
    let onStep: (HabitDayControlModel, Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            if let control = check?.control {
                HabitCheckButton(control: control) { target in
                    onStep(control, target)
                }
            } else {
                // Not on the shown day's plan: no check, the same width.
                Image(systemName: "minus")
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
            }
            Button(action: onOpen) {
                info
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the habit's history")
        }
        // A long press anywhere on the row (the check included) offers the
        // habit's history too.
        .contextMenu {
            Button(action: onOpen) {
                Label("History", systemImage: "calendar")
            }
        }
    }

    private var info: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            if let icon = row.icon {
                Text(verbatim: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.label)
                    .font(.subheadline.weight(.semibold))
                let detail = [row.dose, row.schedule].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let status = [check?.control?.stateText ?? row.notTodayText, row.adherence].compactMap { $0 }.joined(separator: " · ")
                Text(verbatim: status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let check {
                HabitStreakBadge(count: check.streakCount, isLit: check.streakIsLit, text: check.streakText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The ladder's next step and what unlocks it (polish-training-today D2).
private struct HabitNextStepRow: View {
    let next: HabitNextStepModel

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            if let icon = next.icon {
                Text(verbatim: icon)
                    .font(.title3)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: next.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let unlock = next.unlockText {
                    Text(verbatim: unlock)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let earliest = next.earliestText {
                    Text(verbatim: earliest)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: next.accessibilityLabel))
    }
}
