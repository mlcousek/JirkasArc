// RaceResultViews.swift
//
// add-training-gates-and-load: how a race ended, on the Race screen. THE
// VAULT DECIDES what the result is (the race report once it states a
// status, else the app's accepted result), whether the goal was reached and
// whether it is a personal record; these views draw TrainingCore's
// `RaceResultModel` (RaceResultModels.swift) and record the owner's own
// `race.result`.
//
//   RaceResultCard   the result in neutral words with a symbol ("Finished",
//                    "Did not finish", "Did not start" and why). TWO TIMES:
//                    when the organiser's results time is another one than
//                    the clock, it is the big number and the elapsed time
//                    is the line under it; with one time, that time alone.
//                    Then distance and laps, "Goal reached" / "Personal
//                    record" only when the vault says so, where the record
//                    came from and the note. This phone's own result shows
//                    "Saved on phone" / "Sent" until the vault has read it;
//                    a result the vault refused shows the vault's reason.
//                    "How did it go?" opens the sheet; "Withdraw this
//                    result" retracts this phone's own.
//   RaceResultSheet  status (only "Did not start" before race day), a
//                    reason for a race not finished or not started (with
//                    "Stopped by the stop rule"), the elapsed time and an
//                    optional results time as h:mm:ss, distance, laps for a
//                    lap race, a note. Save is enabled only while
//                    TrainingCore can build a payload the contract takes.
//
// Every word comes from the model and is shown verbatim; every Save is a
// local, durable event through TrainingModel. Depended on by:
// RaceDetailView.

import SwiftUI
import UIKit
import TrainingCore

struct RaceResultCard: View {
    let model: RaceResultModel

    @Environment(AppEnvironment.self) private var environment
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: model.title, trailing: model.deliveryLine)
            if model.hasRecord {
                record
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.accessibilityLabel)
            }
            if let hint = model.pendingHint {
                Text(verbatim: hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let refusal = model.refusalText {
                Label {
                    Text(verbatim: refusal)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $showSheet) {
            if let editor = model.editor {
                RaceResultSheet(editor: editor) { payload in
                    Task { await environment.training.recordRaceResult(payload) }
                }
            }
        }
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let status = model.statusText {
                Label {
                    Text(verbatim: [status, model.reasonText].compactMap { $0 }.joined(separator: " · "))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol(model.status))
                }
                .font(.subheadline.weight(.semibold))
            }
            if let time = model.timeText {
                Text(verbatim: time)
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            if let elapsed = model.elapsedText {
                Text(verbatim: elapsed)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !model.factLines.isEmpty {
                Text(verbatim: model.factLines.joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
            }
            let marks = [model.goalReachedText, model.personalRecordText].compactMap { $0 }
            if !marks.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(marks, id: \.self) { mark in
                        Label {
                            Text(verbatim: mark)
                        } icon: {
                            Image(systemName: "checkmark.seal")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().strokeBorder(Theme.stroke))
                    }
                }
            }
            if let note = model.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source = model.sourceText {
                Text(verbatim: source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.editor != nil || !model.withdrawEventIDs.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                if model.editor != nil {
                    Button {
                        showSheet = true
                    } label: {
                        Text(verbatim: model.actionTitle)
                            .fontWeight(.semibold)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
                Spacer(minLength: 0)
                if !model.withdrawEventIDs.isEmpty {
                    Button {
                        let ids = model.withdrawEventIDs
                        Task { await environment.training.retractEvents(ids) }
                    } label: {
                        Text(verbatim: model.withdrawTitle)
                            .font(.caption)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    /// A flag for a finish, plain marks for the rest: neutral, and never
    /// colour alone.
    private func symbol(_ status: RaceOutcome?) -> String {
        switch status {
        case .finished?: return "flag.checkered"
        case .dnf?: return "flag.slash"
        case .dns?: return "minus.circle"
        case nil: return "flag"
        }
    }
}

private struct RaceResultSheet: View {
    let editor: RaceResultEditorModel
    let onSave: (RaceResultPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: RaceOutcome = .finished
    @State private var reason: RaceResultReason?
    @State private var time = ""
    @State private var officialTime = ""
    @State private var distance = ""
    @State private var laps = ""
    @State private var note = ""
    @State private var didLoad = false

    private var typedDistance: TypedNumber<Double> { RecordInput.decimal(distance) }
    private var typedLaps: TypedNumber<Int> { RecordInput.whole(laps) }

    /// `nil` while a field holds something the contract does not take.
    private var payload: RaceResultPayload? {
        if editor.asksTimes(status), typedDistance.isInvalid || typedLaps.isInvalid { return nil }
        return editor.payload(
            status: status,
            reason: reason,
            time: time,
            officialTime: officialTime,
            distanceKm: typedDistance.value,
            laps: typedLaps.value,
            note: note
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(editor.statusLabel, selection: $status) {
                        ForEach(editor.statuses, id: \.self) { candidate in
                            Text(verbatim: editor.statusName(candidate)).tag(candidate)
                        }
                    }
                    if editor.asksReason(status) {
                        Picker(editor.reasonLabel, selection: $reason) {
                            Text(verbatim: editor.noReasonTitle).tag(RaceResultReason?.none)
                            ForEach(editor.reasons, id: \.self) { candidate in
                                Text(verbatim: editor.reasonName(candidate)).tag(RaceResultReason?.some(candidate))
                            }
                        }
                    }
                } footer: {
                    if let before = editor.beforeRaceText {
                        Text(verbatim: before)
                    }
                }
                if editor.asksTimes(status) {
                    Section {
                        field(editor.timeLabel, text: $time, keyboard: .numbersAndPunctuation)
                        field(editor.officialTimeLabel, text: $officialTime, keyboard: .numbersAndPunctuation)
                    } footer: {
                        Text(verbatim: editor.timeHint)
                    }
                    Section {
                        field(editor.distanceLabel, text: $distance, keyboard: .decimalPad)
                        if editor.asksLaps {
                            field(editor.lapsLabel, text: $laps, keyboard: .numberPad)
                        }
                    }
                }
                Section {
                    TextField(editor.notePlaceholder, text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(Text(verbatim: editor.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: editor.cancelTitle)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let ready = payload else { return }
                        Haptics.success()
                        onSave(ready)
                        dismiss()
                    } label: {
                        Text(verbatim: editor.saveTitle)
                    }
                    .disabled(payload == nil)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            status = editor.initialStatus
            reason = editor.initialReason
            time = editor.initialTime
            officialTime = editor.initialOfficialTime
            distance = RecordInput.text(editor.initialDistanceKm)
            laps = RecordInput.text(editor.initialLaps)
            note = editor.initialNote
        }
    }

    /// The label above its field: the time labels are too long to share a
    /// row with what is typed.
    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
        }
    }
}
