// HabitComponents.swift
//
// The small views every habit surface shares (add-interactive-habits design
// D7): the navigation value that opens the Habits screen or one habit, the
// streak flame, the one-tap check (a tick for a single-dose habit, a ring
// with "1/2" for a multi-dose one), the dose stepper, the note under a
// tick the vault refused, and a calendar day's look. One place, so Today's
// card, the ladder and the detail draw a state the same way.
//
// A state is never colour alone (the app's D9 rule): done is a filled
// check, missed a cross, partly a half mark, unknown a dashed outline, and
// today an accent ring. Colours are Theme tokens only (the design-token
// lint). Text comes from TrainingCore's models, already in the app's
// language, and is shown verbatim.
//
// Nothing here records: a control calls back with the dose count it asks
// for, and the screen hands that to `TrainingModel.applyHabit`.
//
// Depended on by: HabitsTodayCard, HabitsScreen, HabitDetailView.

import SwiftUI
import TrainingCore

/// Pushes the Habits screen (`habitID == nil`) or one habit's detail.
struct HabitsTarget: Hashable, Identifiable {
    let habitID: String?

    var id: String { habitID ?? "habits.ladder" }

    static let ladder = HabitsTarget(habitID: nil)
}

/// What a `HabitsTarget` pushes (Today, Plan and the Habits screen itself).
struct HabitsDestination: View {
    let target: HabitsTarget

    var body: some View {
        if let habitID = target.habitID {
            HabitDetailView(habitID: habitID)
        } else {
            HabitsScreen()
        }
    }
}

enum HabitStyle {
    /// The state's own mark, for the calendar, the legend and the log.
    static func symbol(_ state: HabitDayState) -> String {
        switch state {
        case .done: return "checkmark"
        case .partly: return "circle.lefthalf.filled"
        case .missed: return "xmark"
        case .notExpected: return "minus"
        case .unknown: return "questionmark"
        case .open: return "circle"
        }
    }

    static func tint(_ state: HabitDayState) -> Color {
        switch state {
        case .done, .partly: return Theme.success
        case .missed: return Theme.danger
        case .open: return Theme.accent
        case .notExpected, .unknown: return Color.secondary
        }
    }
}

/// The flame and the streak's number.
struct HabitStreakBadge: View {
    let count: Int
    let isLit: Bool
    /// "5 days in a row", for VoiceOver.
    let text: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: isLit ? "flame.fill" : "flame")
                .foregroundStyle(isLit ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Color.secondary))
            Text(verbatim: "\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(isLit ? Color.primary : Color.secondary)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// The day's mark: a check for a single-dose habit, a ring with the count
/// for a multi-dose one; a small clock while the phone's tick is not
/// uploaded yet.
struct HabitCheckGlyph: View {
    let control: HabitDayControlModel
    var size: CGFloat = 30

    var body: some View {
        Group {
            if control.isMultiDose {
                ProgressRing(
                    fraction: Double(control.done) / Double(max(control.expected, 1)),
                    lineWidth: max(size / 9, 3),
                    tint: Theme.success
                ) {
                    Text(verbatim: "\(control.done)/\(control.expected)")
                        .font(size > 44 ? Font.headline.monospacedDigit() : Font.caption2.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            } else {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(control.isDone ? Theme.success : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if control.isPending {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
        }
        .opacity(control.canRecord || control.isDone ? 1 : 0.55)
    }

    private var symbol: String {
        switch control.state {
        case .done: return "checkmark.circle.fill"
        case .missed: return "xmark.circle"
        default: return "circle"
        }
    }
}

/// One tap: the next dose, or one back from complete.
struct HabitCheckButton: View {
    let control: HabitDayControlModel
    var size: CGFloat = 30
    let onStep: (Int) -> Void

    var body: some View {
        Button {
            Haptics.selection()
            onStep(control.tapTarget)
        } label: {
            HabitCheckGlyph(control: control, size: size)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!control.canRecord)
        .accessibilityLabel(Text(verbatim: control.label))
        .accessibilityValue(Text(verbatim: control.stateText))
        .accessibilityAddTraits(control.isDone ? [.isButton, .isSelected] : .isButton)
    }
}

/// Minus, the day's ring, plus: a multi-dose day in the detail.
struct HabitDoseStepper: View {
    let control: HabitDayControlModel
    var size: CGFloat = 64
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            stepButton("minus.circle.fill", label: control.removeDoseText, target: control.done - 1, enabled: control.done > 0)
            HabitCheckGlyph(control: control, size: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: control.label))
                .accessibilityValue(Text(verbatim: control.stateText))
            stepButton("plus.circle.fill", label: control.addDoseText, target: control.done + 1, enabled: control.done < control.expected)
        }
    }

    private func stepButton(_ symbol: String, label: String, target: Int, enabled: Bool) -> some View {
        Button {
            Haptics.selection()
            onStep(target)
        } label: {
            Image(systemName: symbol)
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || !control.canRecord)
        .opacity(enabled && control.canRecord ? 1 : 0.35)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Why the vault did not accept the phone's tick of a day (its own words,
/// in the app's language): a future day, or one older than its window.
struct HabitRefusedNote: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(Theme.warning)
    }
}

/// A calendar day's look: the state as a fill, an outline and a mark.
/// `state == nil` is a day after today.
struct HabitDayCell: View {
    let state: HabitDayState?
    var dayText: String?
    var isToday = false
    var isSelected = false
    var isPending = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
        ZStack {
            shape.fill(fill)
            shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: isSelected ? 2 : (isToday ? 1.5 : 1), dash: dash))
            if let dayText {
                Text(verbatim: dayText)
                    .font(.caption2.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(state == nil || state == .notExpected || state == .unknown ? Color.secondary : Color.primary)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let state, state == .done || state == .partly || state == .missed {
                Image(systemName: HabitStyle.symbol(state))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(HabitStyle.tint(state))
                    .padding(2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isPending {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .padding(3)
            }
        }
        .opacity(state == nil ? 0.45 : 1)
    }

    private var fill: Color {
        switch state {
        case .done?: return Theme.success.opacity(0.45)
        case .partly?: return Theme.success.opacity(0.18)
        case .missed?: return Theme.danger.opacity(0.16)
        case .notExpected?, .unknown?, .open?, nil: return Color.clear
        }
    }

    private var stroke: Color {
        if isSelected { return Theme.accent }
        if isToday { return Theme.accent.opacity(0.75) }
        switch state {
        case .done?, .partly?: return Theme.success.opacity(0.55)
        case .missed?: return Theme.danger.opacity(0.5)
        case .unknown?: return Theme.stroke
        case .notExpected?: return Theme.stroke.opacity(0.5)
        case .open?, nil: return Color.clear
        }
    }

    private var dash: [CGFloat] {
        state == .unknown && !isSelected && !isToday ? [3, 3] : []
    }
}
