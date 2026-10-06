// GateAndLoadViews.swift
//
// add-training-gates-and-load: what Today's training card shows of the
// vault's training load and gates. THE VAULT COMPUTES every number and
// verdict here; these views draw TrainingCore's models (GateModels.swift)
// and hold the owner's edits as state. Every word comes from those models
// (already in the app's language) and is shown verbatim.
//
//   GateTestCard      the weekly gate test, pain mode only: the vault's
//                     verdict in words (a lock or a check AND the words,
//                     greyed when the vault calls the test stale), the
//                     neutral physio line, this phone's own test while the
//                     vault has not judged it, and the editor -- two
//                     half-step sliders (walking, 20 single-leg hops), the
//                     tested site, an optional note. On Saturday and
//                     Sunday it is a card of its own under the training
//                     card; on other days one link in the card's pain
//                     area that unfolds the same block. Nothing is
//                     recorded until Save.
//   WeekLoadLine      "the plan is the ceiling": the week's run km of its
//                     target, then what is over the plan or above the
//                     longest-run cap in the warning tint WITH a symbol
//                     (never colour alone, never praise), then the rest.
//                     Also the Plan week header's line.
//   RecoveryChipView  "Recovery day 10 of 14 · until 27 Oct", a bar that
//                     divides by the window's own length, and one line of
//                     what it means. Information only.
//   VaultNoticeLines  the vault's data-gap notices, as quiet lines.
//
// Colours are Theme tokens only (the design-token lint). Depended on by:
// TrainingTodayCards (TrainingDayCard), WeekAgendaView.

import SwiftUI
import TrainingCore

// MARK: - Notices

struct VaultNoticeLines: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(lines, id: \.self) { line in
                    Label {
                        Text(verbatim: line)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Recovery window

struct RecoveryChipView: View {
    let model: RecoveryChipModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label {
                Text(verbatim: model.text)
            } icon: {
                Image(systemName: "bed.double")
            }
            .font(.subheadline.weight(.semibold))
            ProgressView(value: model.fraction)
                .tint(Theme.accent)
            let details = [model.raceText, model.meaningText].compactMap { $0 }
            ForEach(details, id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

// MARK: - The plan is the ceiling

struct WeekLoadLine: View {
    let model: WeekLoadModel

    var body: some View {
        let lead = model.segments.first { $0.kind == .run }
        let warnings = model.segments.filter { $0.isWarning }
        let rest = model.segments.filter { $0.kind != .run && !$0.isWarning }
        VStack(alignment: .leading, spacing: 2) {
            if let lead {
                Label {
                    Text(verbatim: lead.text)
                } icon: {
                    Image(systemName: "figure.run")
                }
                .font(.subheadline.weight(.semibold))
            }
            ForEach(warnings) { segment in
                Label {
                    Text(verbatim: segment.text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.warning)
            }
            if !rest.isEmpty {
                Text(verbatim: rest.map(\.text).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.text)
    }
}

/// The amber "Over plan" mark on an unplanned run: a symbol and the words.
struct OverPlanBadge: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Capsule().strokeBorder(Theme.warning))
    }
}

// MARK: - Weekly gate test

struct GateTestCard: View {
    let model: GateCardModel
    let onSave: (GateTestPayload) -> Void

    /// Unfolded by hand on a day it is only a link.
    @State private var isOpen = false
    @State private var isEditing = false
    @State private var walk: Double = 0
    @State private var hop: Double = 0
    @State private var site: PainSite = .achillesLeft
    @State private var note = ""

    var body: some View {
        Group {
            if model.isProminent || isOpen {
                content
            } else {
                link
            }
        }
        .onChange(of: model.date) { _, _ in
            isOpen = false
            isEditing = false
        }
    }

    /// One small link in the card's pain area.
    private var link: some View {
        Button {
            isOpen = true
        } label: {
            Label {
                Text(verbatim: model.title)
            } icon: {
                Image(systemName: "figure.walk")
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderless)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: model.title)
                } icon: {
                    Image(systemName: "figure.walk")
                }
                .font(.subheadline.weight(.semibold))
                Spacer(minLength: Theme.Spacing.xs)
                if let tested = model.testedText {
                    Text(verbatim: tested)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let empty = model.emptyText {
                Text(verbatim: empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(model.lines) { line in
                    Label {
                        Text(verbatim: line.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: symbol(line.isLocked))
                            .foregroundStyle(tint(line.isLocked))
                    }
                    .font(.subheadline)
                }
            }
            .opacity(model.isStale ? 0.55 : 1)
            if let stale = model.staleText {
                Label {
                    Text(verbatim: stale)
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let physio = model.physioText {
                Label {
                    Text(verbatim: physio)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "stethoscope")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let pending = model.pendingText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: pending)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    let status = [model.deliveryLine, model.pendingHint].compactMap { $0 }
                    if !status.isEmpty {
                        Text(verbatim: status.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if isEditing {
                editor
            } else if model.canRecord {
                Button {
                    walk = model.initialWalk
                    hop = model.initialHop
                    site = model.initialSite
                    note = model.initialNote
                    isEditing = true
                } label: {
                    Text(verbatim: model.recordTitle)
                        .fontWeight(.semibold)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(verbatim: model.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            scoreRow(label: model.walkLabel, value: $walk)
            scoreRow(label: model.hopLabel, value: $hop)
            Picker(model.siteLabel, selection: $site) {
                ForEach(model.sites, id: \.self) { candidate in
                    Text(verbatim: model.siteName(candidate)).tag(candidate)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            TextField(model.notePlaceholder, text: Binding(get: { note }, set: { note = String($0.prefix(PainEntry.noteMaxLength)) }))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    isEditing = false
                } label: {
                    Text(verbatim: model.cancelTitle)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button {
                    Haptics.success()
                    onSave(model.payload(walk: walk, hop: hop, site: site, note: note))
                    isEditing = false
                } label: {
                    Text(verbatim: model.saveTitle)
                        .fontWeight(.semibold)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
    }

    /// One score: its label, the score as text and a 0-10 half-step
    /// slider (one VoiceOver element, adjustable by half steps).
    private func scoreRow(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label)
                    .font(.subheadline)
                Spacer(minLength: Theme.Spacing.xs)
                Text(verbatim: model.scoreText(value.wrappedValue))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityHidden(true)
            }
            Slider(value: value, in: PainEntry.scoreRange, step: PainEntry.scoreStep)
                .tint(Theme.accent)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue(Text(verbatim: model.scoreAccessibilityValue(value.wrappedValue)))
        }
    }

    /// A lock, a check or a dash: the verdict is never colour alone.
    private func symbol(_ isLocked: Bool?) -> String {
        switch isLocked {
        case true?: return "lock.fill"
        case false?: return "checkmark.circle"
        case nil: return "minus.circle"
        }
    }

    private func tint(_ isLocked: Bool?) -> Color {
        switch isLocked {
        case true?: return Theme.warning
        case false?: return Theme.success
        case nil: return Color.secondary
        }
    }
}
