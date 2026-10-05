// HabitDetailView.swift
//
// One habit (add-interactive-habits design D6, D7; the owner's ask:
// "streaks, check done or not, log, and a log history"). Top to bottom:
//
//   header     the habit, its dose, schedule and why, where it stands on
//              the ladder (a locked habit says what unlocks it)
//   today      the big control: one check, or minus / ring / plus for a
//              multi-dose habit (2x a day); its state and delivery
//   streak     current and best, with the flame; "Last done ..."; and,
//              when the phone counted them itself, over how many days
//   adherence  7 / 14 / 30 / 84 days against the gate; a window the phone
//              can't know yet shows a dash, with one line saying why
//   calendar   12 weeks, Monday first: done, partly, missed, not planned,
//              no record, today open. Tapping a day selects it; inside the
//              back-fill window (the vault's, 14 days by default) the
//              panel under the calendar marks it done or not done
//   entries    the recent days with their state and, for the phone's own
//              ticks, "Saved on phone" / "Sent" / "Received by the vault"
//   refused    the phone's ticks the vault did not accept, with its reason
//              (shown under that day's control too); hidden when none
//
// Everything shown is TrainingCore's `HabitDetailModel`; the selected
// day's panel is its `dayControl`. A step calls `TrainingModel.applyHabit`
// (a local event, never a network wait; nothing is offered without a
// working vault connection, and the reason is written under the control).
//
// Depended on by: HabitsDestination (Today's card rows, HabitsScreen).

import SwiftUI
import TrainingCore

struct HabitDetailView: View {
    let habitID: String

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedDate: LocalDate?

    var body: some View {
        let training = environment.training
        let builder = training.habitsBuilder()
        let detail = builder.detail(habitID: habitID)
        let step: (HabitDayControlModel, Int) -> Void = { control, target in
            Task { await training.applyHabit(control, to: target) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if let detail {
                    HabitHeaderCard(detail: detail)
                    if let control = detail.today {
                        HabitTodayControlCard(control: control, onStep: step)
                    }
                    HabitStreakCard(streak: detail.streak)
                    HabitAdherenceCard(detail: detail)
                    HabitCalendarCard(
                        calendar: detail.calendar,
                        selectedDate: selectedDate,
                        selectedControl: selectedDate.flatMap { builder.dayControl(habitID: habitID, date: $0) },
                        onSelect: { date in
                            Haptics.selection()
                            selectedDate = selectedDate == date ? nil : date
                        },
                        onStep: step
                    )
                    HabitLogCard(detail: detail)
                    if !detail.refusals.isEmpty {
                        HabitRefusalsCard(detail: detail)
                    }
                } else {
                    TrainingEmptyStateView(state: builder.format.emptyState(.noActivePlan))
                        .card()
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle(Text(verbatim: detail?.label ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !training.hasLoaded { await training.reload() }
        }
    }
}

// MARK: - Header

private struct HabitHeaderCard: View {
    let detail: HabitDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                if let icon = detail.icon {
                    Text(verbatim: icon)
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: detail.label)
                        .font(.title3.weight(.bold))
                    Label {
                        Text(verbatim: detail.kindText)
                    } icon: {
                        Image(systemName: kindSymbol)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kindTint)
                }
            }
            let details = [detail.dose, detail.schedule, detail.dateText].compactMap { $0 }
            if !details.isEmpty {
                Text(verbatim: details.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let why = detail.why {
                Text(verbatim: why)
                    .font(.subheadline)
            }
            if let unlock = detail.unlockText {
                Label {
                    Text(verbatim: unlock)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let gateMet = detail.gateMetText {
                Label {
                    Text(verbatim: gateMet)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var kindSymbol: String {
        switch detail.kind {
        case .established: return "checkmark.circle.fill"
        case .current: return "play.circle.fill"
        case .locked: return "lock.circle"
        }
    }

    private var kindTint: Color {
        switch detail.kind {
        case .established: return Theme.success
        case .current: return Theme.accent
        case .locked: return Color.secondary
        }
    }
}

// MARK: - Today

private struct HabitTodayControlCard: View {
    let control: HabitDayControlModel
    let onStep: (HabitDayControlModel, Int) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SectionHeader(title: control.dateText, trailing: control.deliveryText)
            if control.isMultiDose {
                HabitDoseStepper(control: control, size: 76) { target in
                    onStep(control, target)
                }
            } else {
                HabitCheckButton(control: control, size: 76) { target in
                    onStep(control, target)
                }
            }
            Text(verbatim: control.stateText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(control.isDone ? Theme.success : Color.primary)
                .contentTransition(.opacity)
            if let locked = control.lockedText {
                Text(verbatim: locked)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let refused = control.refusedText {
                HabitRefusedNote(text: refused)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
        .sensoryFeedback(.success, trigger: control.isDone) { old, new in
            !old && new && Haptics.isEnabled
        }
    }
}

// MARK: - Streak

private struct HabitStreakCard: View {
    let streak: HabitStreakModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                figure(
                    symbol: streak.isLit ? "flame.fill" : "flame",
                    style: streak.isLit ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Color.secondary),
                    number: streak.current,
                    caption: streak.currentCaption,
                    spoken: streak.currentText
                )
                Divider()
                figure(
                    symbol: "trophy.fill",
                    style: AnyShapeStyle(Theme.accent),
                    number: streak.best,
                    caption: streak.bestCaption,
                    spoken: streak.bestRunText
                )
            }
            Text(verbatim: streak.currentText)
                .font(.subheadline.weight(.semibold))
            let notes = [streak.lastDoneText, streak.estimateText, streak.mayBeLongerText].compactMap { $0 }
            ForEach(notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func figure(symbol: String, style: AnyShapeStyle, number: Int, caption: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(style)
                Text(verbatim: "\(number)")
                    .font(Font.system(.largeTitle, design: ThemeRuntime.shared.numberDesign).weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Text(verbatim: caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(caption): \(spoken)"))
    }
}

// MARK: - Adherence

private struct HabitAdherenceCard: View {
    let detail: HabitDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: detail.adherenceTitle, trailing: detail.gateText)
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(detail.adherence) { tile in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: tile.valueText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(tile.fraction == nil ? Color.secondary : Color.primary)
                        ProgressView(value: min(max(tile.fraction ?? 0, 0), 1))
                            .tint(tile.meetsGate == true ? Theme.success : Theme.accent)
                            .opacity(tile.fraction == nil ? 0.35 : 1)
                        Text(verbatim: tile.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: tile.accessibilityLabel))
                }
            }
            if let note = detail.adherenceNote {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

// MARK: - Calendar

private struct HabitCalendarCard: View {
    let calendar: HabitCalendarModel
    let selectedDate: LocalDate?
    let selectedControl: HabitDayControlModel?
    let onSelect: (LocalDate) -> Void
    let onStep: (HabitDayControlModel, Int) -> Void

    private let legendColumns = [GridItem(.adaptive(minimum: 104), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: calendar.title)
            Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(calendar.weekdayHeaders, id: \.self) { name in
                        Text(verbatim: name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                ForEach(calendar.weeks) { week in
                    GridRow {
                        Text(verbatim: week.label)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .gridColumnAlignment(.leading)
                            .accessibilityHidden(true)
                        ForEach(week.cells) { cell in
                            Button {
                                onSelect(cell.date)
                            } label: {
                                HabitDayCell(
                                    state: cell.state,
                                    dayText: cell.dayText,
                                    isToday: cell.isToday,
                                    isSelected: selectedDate == cell.date,
                                    isPending: cell.isPending
                                )
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(cell.state == nil)
                            .accessibilityLabel(Text(verbatim: cell.accessibilityLabel))
                            .accessibilityAddTraits(selectedDate == cell.date ? .isSelected : [])
                        }
                    }
                }
            }
            if let control = selectedControl {
                HabitDayPanel(control: control, onStep: onStep)
            }
            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(calendar.legend) { item in
                    HStack(spacing: Theme.Spacing.xs) {
                        HabitDayCell(state: item.state)
                            .frame(width: 16, height: 16)
                        Text(verbatim: item.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let hint = calendar.hint {
                Text(verbatim: hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// The selected day: what it was, and -- inside the back-fill window --
/// done or not done.
private struct HabitDayPanel: View {
    let control: HabitDayControlModel
    let onStep: (HabitDayControlModel, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: control.dateText)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                Label {
                    Text(verbatim: control.stateText)
                } icon: {
                    Image(systemName: HabitStyle.symbol(control.state))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(HabitStyle.tint(control.state))
            }
            if let locked = control.lockedText {
                Text(verbatim: locked)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if control.isMultiDose {
                HabitDoseStepper(control: control, size: 52) { target in
                    onStep(control, target)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Haptics.selection()
                        onStep(control, max(control.expected, 1))
                    } label: {
                        Label {
                            Text(verbatim: control.markDoneText)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.success)
                    .disabled(!control.canMarkDone)
                    Button {
                        Haptics.selection()
                        onStep(control, 0)
                    } label: {
                        Label {
                            Text(verbatim: control.markNotDoneText)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!control.canMarkNotDone)
                }
                .font(.subheadline.weight(.semibold))
            }
            if let refused = control.refusedText {
                HabitRefusedNote(text: refused)
            }
            if let delivery = control.deliveryText {
                Text(verbatim: delivery)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
    }
}

// MARK: - Recent entries

private struct HabitLogCard: View {
    let detail: HabitDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: detail.logTitle)
            if let empty = detail.logEmptyText {
                Text(verbatim: empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(detail.log) { entry in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: HabitStyle.symbol(entry.state))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HabitStyle.tint(entry.state))
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(verbatim: entry.dateText)
                        .font(.subheadline)
                    Spacer(minLength: Theme.Spacing.xs)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: entry.stateText)
                            .font(.subheadline.weight(.semibold))
                        if let delivery = entry.deliveryText {
                            Text(verbatim: delivery)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Refused ticks

/// The phone's ticks the vault did not accept (a day that hadn't come, or
/// one older than its 14 days), each with the vault's reason. They changed
/// nothing in the vault, so the calendar above doesn't show them as done.
private struct HabitRefusalsCard: View {
    let detail: HabitDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: detail.refusalsTitle)
            ForEach(detail.refusals) { refusal in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: refusal.dateText)
                        .font(.subheadline.weight(.semibold))
                    HabitRefusedNote(text: refusal.reasonText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
