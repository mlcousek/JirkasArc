// ActiveCaloriesView.swift
//
// add-health-active-calories D3/D4/D5: Settings > Activity on a standalone
// install -- today's active calories and where they came from, the manual
// activities (add, edit, delete; greyed with "counted by Apple Health" once
// the bridge reported the day, so nothing is counted twice), and how to set
// up the Apple Health bridge: a Shortcut and a personal automation, since
// the free tier has no HealthKit. Also opened from Today's activity row.
//
// en + cs. Depends on ActiveCaloriesModel (AppEnvironment).

import SwiftUI
import FoodLogCore

@MainActor
struct ActiveCaloriesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var editing: ManualActivityDraft?

    private var model: ActiveCaloriesModel { environment.activeCalories }

    var body: some View {
        let day = model.today
        Form {
            Section {
                if let total = day.total {
                    Label {
                        switch day.source {
                        case .health:
                            Text("\(Int(total.rounded())) kcal from Apple Health")
                        default:
                            Text("\(Int(total.rounded())) kcal entered by hand")
                        }
                    } icon: {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.headline)
                } else {
                    Text("Nothing recorded today")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Today")
            } footer: {
                Text("Today's active calories are added to your calorie target.")
            }

            Section {
                ForEach(day.manual) { activity in
                    Button {
                        editing = ManualActivityDraft(activity)
                    } label: {
                        HStack {
                            Label(activity.type.title, systemImage: activity.type.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let minutes = activity.minutes {
                                Text("\(minutes) min")
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(Int(activity.kcal.rounded())) kcal")
                                .foregroundStyle(.primary)
                        }
                        .opacity(day.health != nil ? 0.5 : 1)
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { day.manual[$0].id }
                    Task { for id in ids { await model.delete(id: id) } }
                }
                Button {
                    editing = ManualActivityDraft()
                } label: {
                    Label("Add activity", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Activities")
            } footer: {
                if day.health != nil, !day.manual.isEmpty {
                    Text("Apple Health already counts these.")
                }
            }

            Section {
                if let last = model.lastHealthReport {
                    LabeledContent("Last report", value: last.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No report from Apple Health yet.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("1. In the Shortcuts app, make a shortcut: Find Health Samples (Active Energy, start date is today), then Calculate Statistics (Sum), then Record Active Calories from Jirka's Arc with that sum.")
                    Text("2. In Automation, add Time of Day automations (for example 10:00, 14:00, 18:00 and 21:30) that run it, and turn on Run Immediately.")
                    Text("3. Optional: an automation for when Jirka's Arc is opened, so Today is always current.")
                }
                .font(.footnote)
            } header: {
                Text("Apple Health")
            } footer: {
                Text("Your Apple Watch's active calories include every workout, so there is no need to enter them by hand as well.")
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.reload() }
        .sheet(item: $editing) { draft in
            ManualActivitySheet(draft: draft)
        }
    }
}

/// An activity being added (no `original`) or edited.
struct ManualActivityDraft: Identifiable {
    let id = UUID()
    var original: ManualActivity?
    var type: ManualActivityType = .walking
    var minutes: Int?
    var kcal: Double?

    init(_ activity: ManualActivity? = nil) {
        original = activity
        if let activity {
            type = activity.type
            minutes = activity.minutes
            kcal = activity.kcal
        }
    }
}

@MainActor
struct ManualActivitySheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State var draft: ManualActivityDraft
    @State private var failed = false

    private var isValid: Bool {
        guard let kcal = draft.kcal else { return false }
        return ActiveCaloriesRules.checkManual(kcal: kcal, minutes: draft.minutes) == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $draft.type) {
                    ForEach(ManualActivityType.allCases) { type in
                        Label(type.title, systemImage: type.symbol).tag(type)
                    }
                }
                TextField("Minutes (optional)", value: $draft.minutes, format: .number)
                    .keyboardType(.numberPad)
                TextField("Calories (kcal)", value: $draft.kcal, format: .number)
                    .keyboardType(.decimalPad)
                if draft.kcal != nil, !isValid {
                    Text("Enter 1 to 3000 kcal.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
                if failed {
                    Text("Couldn't save the activity. Try again.")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(draft.original == nil ? Text("Add activity") : Text("Activity"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let kcal = draft.kcal else { return }
        let model = environment.activeCalories
        Task {
            let saved: Bool
            if var activity = draft.original {
                activity.type = draft.type
                activity.minutes = draft.minutes
                activity.kcal = kcal
                saved = await model.update(activity)
            } else {
                saved = await model.add(type: draft.type, minutes: draft.minutes, kcal: kcal)
            }
            if saved {
                Haptics.success()
                dismiss()
            } else {
                failed = true
            }
        }
    }
}

/// add-health-active-calories D4/D5: the slim row on a standalone Today --
/// the way to add an activity, and the quiet notice when Apple Health has
/// not reported for two days.
@MainActor
struct ActiveCaloriesTodayRow: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if environment.dataMode == .standalone, environment.dayLog.isToday {
            let model = environment.activeCalories
            NavigationLink {
                ActiveCaloriesView()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: model.isBridgeSilent() ? "exclamationmark.circle" : "figure.run")
                        .foregroundStyle(model.isBridgeSilent() ? Theme.warning : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if model.isBridgeSilent() {
                            Text("Apple Health hasn't reported for 2 days.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if model.today.total == nil {
                            Text("Add an activity, or let Apple Health send your active calories.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
            .task { await model.reload() }
        }
    }
}
