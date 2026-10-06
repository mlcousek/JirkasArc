// SessionRecordViews.swift
//
// add-training-gates-and-load: what the session detail records beyond the
// RPE and the note. Each view draws a TrainingCore model
// (SessionRecordModels.swift: labels, defaults, what is already recorded,
// and the event payload each Save builds -- with the contract's bounds
// checked there) and holds the owner's edits as state. Every Save is a
// local, durable event through TrainingModel; nothing waits for the
// network and nothing is recorded unless the vault connection can record
// (then the models are not built at all).
//
//   SessionPainBlock  pain during and after the session, per site, two
//                     half-step sliders each -- inside "How did it feel?",
//                     in pain mode only. It is sent WITH the RPE, so Save
//                     waits for a chosen effort. What is recorded is listed
//                     ("during 4/10 · after 6/10", "–" for a score the
//                     vault does not know).
//   ManualDoneCard    "Mark done (no watch)" -> a sheet with the option
//                     (when the session has options), minutes, kilometres
//                     for a run, ride or walk, and a note; and Undo while
//                     this phone still holds the event the session is done
//                     by. Works for a gym session.
//   FuelLogCard       the fuel log of a long run or a race: what the vault
//                     made of it (grams per hour against the plan, a
//                     neutral below / on / above chip -- a symbol and the
//                     words, no judgement colour) and a sheet for carbs,
//                     fluid, an optional duration and a note. 0 g is an
//                     answer.
//
// Number fields are parsed by TrainingCore's `RecordInput` (a blank
// optional field is "not said"; text that is not a number disables Save and
// never becomes 0). Every word comes from the models and is shown verbatim.
//
// Depended on by: SessionDetailView.

import SwiftUI
import UIKit
import TrainingCore

// MARK: - Pain during and after

struct SessionPainBlock: View {
    let model: SessionPainModel

    @Environment(AppEnvironment.self) private var environment
    /// The owner's edits; `nil` = the model's draft untouched.
    @State private var editing: SessionPainDraft?
    /// Opened by hand over a recorded answer.
    @State private var isOpen = false

    private var current: SessionPainDraft { editing ?? model.draft }
    private var showsEditor: Bool { isOpen || !model.isRecorded }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: model.title)
                } icon: {
                    Image(systemName: "bandage")
                }
                .font(.subheadline.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                if let delivery = model.deliveryLine {
                    Text(verbatim: delivery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.recordedLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsEditor {
                editor
            } else {
                Button {
                    editing = nil
                    isOpen = true
                } label: {
                    Text(verbatim: model.editTitle)
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if current.isEmpty {
                Text(verbatim: model.nothingHurtsText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(current.rows) { row in
                SessionPainSiteRow(
                    row: row,
                    model: model,
                    onDuring: { score in mutate { $0.setDuring(score, for: row.site) } },
                    onAfter: { score in mutate { $0.setAfter(score, for: row.site) } },
                    onRemove: { mutate { $0.remove(row.site) } }
                )
            }
            if !current.addableSites.isEmpty {
                Menu {
                    ForEach(current.addableSites, id: \.self) { site in
                        Button {
                            mutate { $0.add(site) }
                        } label: {
                            Text(verbatim: model.siteName(site))
                        }
                    }
                } label: {
                    Label {
                        Text(verbatim: model.addSiteTitle)
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                    .font(.subheadline)
                }
            }
            if let needsRPE = model.needsRPEText {
                Label {
                    Text(verbatim: needsRPE)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.sm) {
                if model.isRecorded {
                    Button {
                        editing = nil
                        isOpen = false
                    } label: {
                        Text(verbatim: model.cancelTitle)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
                Button {
                    guard let payload = model.payload(current) else { return }
                    Haptics.success()
                    Task { await environment.training.recordSessionPain(payload) }
                    editing = nil
                    isOpen = false
                } label: {
                    Text(verbatim: model.saveTitle)
                        .fontWeight(.semibold)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(model.rpe == nil)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
    }

    private func mutate(_ change: (inout SessionPainDraft) -> Void) {
        var draft = current
        change(&draft)
        editing = draft
    }
}

/// One site: its name, remove, and two 0-10 half-step sliders (during,
/// after), each one VoiceOver element with its value spoken.
private struct SessionPainSiteRow: View {
    let row: SessionPainDraftRow
    let model: SessionPainModel
    let onDuring: (Double) -> Void
    let onAfter: (Double) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(verbatim: model.siteName(row.site))
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: Theme.Spacing.xs)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: model.removeLabels[row.site] ?? model.siteName(row.site)))
            }
            slider(label: model.duringLabel, score: row.during, onChange: onDuring)
            slider(label: model.afterLabel, score: row.after, onChange: onAfter)
        }
    }

    private func slider(label: String, score: Double, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(verbatim: model.scoreText(score))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityHidden(true)
            }
            Slider(
                value: Binding(get: { score }, set: { onChange($0) }),
                in: PainEntry.scoreRange,
                step: PainEntry.scoreStep
            )
            .tint(Theme.accent)
            .accessibilityLabel(Text(verbatim: "\(model.siteName(row.site)), \(label)"))
            .accessibilityValue(Text(verbatim: model.scoreAccessibilityValue(score)))
        }
    }
}

// MARK: - Done without a watch

struct ManualDoneCard: View {
    let model: ManualDoneModel

    @Environment(AppEnvironment.self) private var environment
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if model.canMark {
                Button {
                    showSheet = true
                } label: {
                    Label {
                        Text(verbatim: model.actionTitle)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
            if model.canUndo {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: model.sheetTitle)
                            .font(.subheadline.weight(.semibold))
                        if let delivery = model.deliveryLine {
                            Text(verbatim: delivery)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    Button {
                        let ids = model.undoEventIDs
                        Task { await environment.training.retractEvents(ids) }
                    } label: {
                        Label {
                            Text(verbatim: model.undoTitle)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $showSheet) {
            ManualDoneSheet(model: model) { payload in
                Task { await environment.training.markDone(payload) }
            }
        }
    }
}

private struct ManualDoneSheet: View {
    let model: ManualDoneModel
    let onSave: (SessionDonePayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var option: OptionCode?
    @State private var minutes = ""
    @State private var km = ""
    @State private var note = ""
    @State private var didLoad = false

    private var typedMinutes: TypedNumber<Int> { RecordInput.whole(minutes) }
    private var typedKm: TypedNumber<Double> { RecordInput.decimal(km) }

    /// `nil` while a field holds something the contract does not take.
    private var payload: SessionDonePayload? {
        if typedMinutes.isInvalid || typedKm.isInvalid { return nil }
        return model.payload(option: option, minutes: typedMinutes.value, km: typedKm.value, note: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !model.optionCodes.isEmpty {
                    Picker(model.optionLabel, selection: $option) {
                        ForEach(model.optionCodes, id: \.self) { code in
                            Text(verbatim: model.optionNames[code] ?? code.rawValue).tag(OptionCode?.some(code))
                        }
                    }
                }
                Section {
                    LabeledContent {
                        TextField(model.minutesLabel, text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(verbatim: model.minutesLabel)
                    }
                    if model.asksDistance {
                        LabeledContent {
                            TextField(model.distanceLabel, text: $km)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text(verbatim: model.distanceLabel)
                        }
                    }
                }
                Section {
                    TextField(model.notePlaceholder, text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(Text(verbatim: model.sheetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: model.cancelTitle)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let ready = payload else { return }
                        onSave(ready)
                        dismiss()
                    } label: {
                        Text(verbatim: model.saveTitle)
                    }
                    .disabled(payload == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            option = model.initialOption
            minutes = RecordInput.text(model.initialMinutes)
            km = RecordInput.text(model.initialKm)
        }
    }
}

// MARK: - Fuel log

struct FuelLogCard: View {
    let model: SessionFuelModel

    @Environment(AppEnvironment.self) private var environment
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: model.title, trailing: model.deliveryLine)
            ForEach(model.lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.subheadline.monospacedDigit())
            }
            if let verdict = model.vsPlanText {
                // Neutral: a symbol and the words, no judgement colour.
                Label {
                    Text(verbatim: verdict)
                } icon: {
                    Image(systemName: symbol(model.vsPlan))
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Theme.stroke))
            }
            if let note = model.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hint = model.hintText {
                Label {
                    Text(verbatim: hint)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if model.canRecord {
                Button {
                    showSheet = true
                } label: {
                    Label {
                        Text(verbatim: model.actionTitle)
                    } icon: {
                        Image(systemName: "fork.knife")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $showSheet) {
            FuelLogSheet(model: model) { payload in
                Task { await environment.training.logFuel(payload) }
            }
        }
    }

    private func symbol(_ verdict: FuelVsPlan?) -> String {
        switch verdict {
        case .below?: return "arrow.down"
        case .on?: return "equal"
        case .above?: return "arrow.up"
        case nil: return "minus"
        }
    }
}

private struct FuelLogSheet: View {
    let model: SessionFuelModel
    let onSave: (SessionFuelPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var carbs = ""
    @State private var fluid = ""
    @State private var duration = ""
    @State private var note = ""
    @State private var didLoad = false

    private var typedCarbs: TypedNumber<Double> { RecordInput.decimal(carbs) }
    private var typedFluid: TypedNumber<Int> { RecordInput.whole(fluid) }
    private var typedDuration: TypedNumber<Int> { RecordInput.whole(duration) }

    /// Carbs are required (0 is an answer); the rest may stay blank.
    private var payload: SessionFuelPayload? {
        guard let grams = typedCarbs.value, !typedFluid.isInvalid, !typedDuration.isInvalid else { return nil }
        return model.payload(carbs: grams, fluidMl: typedFluid.value, durationMin: typedDuration.value, note: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field(model.carbsLabel, text: $carbs, keyboard: .decimalPad)
                    field(model.fluidLabel, text: $fluid, keyboard: .numberPad)
                    field(model.durationLabel, text: $duration, keyboard: .numberPad)
                }
                Section {
                    TextField(model.notePlaceholder, text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(Text(verbatim: model.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: model.cancelTitle)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let ready = payload else { return }
                        Haptics.success()
                        onSave(ready)
                        dismiss()
                    } label: {
                        Text(verbatim: model.saveTitle)
                    }
                    .disabled(payload == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            carbs = RecordInput.text(model.initialCarbs)
            fluid = RecordInput.text(model.initialFluidMl)
            duration = RecordInput.text(model.initialDurationMin)
            note = model.initialNote
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        LabeledContent {
            TextField(label, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: label)
        }
    }
}
