// ActiveCaloriesModel.swift
//
// add-health-active-calories D4/D5: the app's view of a standalone
// install's active calories -- today's record (the Health bridge's report
// and the manual activities), when the bridge last reported, and the
// add / edit / delete of manual activities. After every change Today's
// day is rebuilt (`onChange`), so the "Active today" line and the calorie
// Target move at once, like after a log.
//
// One instance, in AppEnvironment. Depends on FoodLogCore
// ActiveCaloriesStore (AppServices).

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class ActiveCaloriesModel {
    /// How long the bridge may stay silent before Today says so.
    static let silentAfter: TimeInterval = 2 * 24 * 60 * 60

    private(set) var today = ActiveCaloriesDay(day: NutritionDate.todayString())
    private(set) var lastHealthReport: Date?
    private(set) var saveFailed = false

    @ObservationIgnored private let store: ActiveCaloriesStore
    @ObservationIgnored var onChange: () async -> Void = {}

    init(store: ActiveCaloriesStore) {
        self.store = store
    }

    func reload(now: Date = Date()) async {
        today = await store.day(NutritionDate.string(from: now))
        lastHealthReport = await store.lastHealthReportAt()
    }

    /// The bridge reported before and has been silent for two days.
    func isBridgeSilent(now: Date = Date()) -> Bool {
        guard let lastHealthReport else { return false }
        return now.timeIntervalSince(lastHealthReport) >= Self.silentAfter
    }

    func add(type: ManualActivityType, minutes: Int?, kcal: Double, now: Date = Date()) async -> Bool {
        await change(now: now) {
            try await self.store.addManual(type: type, minutes: minutes, kcal: kcal, day: NutritionDate.string(from: now), now: now)
        }
    }

    func update(_ activity: ManualActivity, now: Date = Date()) async -> Bool {
        await change(now: now) {
            try await self.store.updateManual(activity, day: self.today.day, now: now)
        }
    }

    func delete(id: String, now: Date = Date()) async {
        _ = await change(now: now) {
            try await self.store.deleteManual(id: id, day: self.today.day, now: now)
        }
    }

    /// Days on or after `from` with at least `kcal` active (the partner
    /// theme's "Ohnivá vůle").
    func daysWithTotal(atLeast kcal: Double, from: String) async -> Int {
        await store.daysWithTotal(atLeast: kcal, from: from)
    }

    private func change(now: Date, _ write: @escaping () async throws -> Void) async -> Bool {
        do {
            try await write()
            saveFailed = false
        } catch {
            DiagnosticsLog.log(.error, category: "ActiveCalories", "couldn't save a manual activity: \(error)")
            saveFailed = true
            return false
        }
        await reload(now: now)
        await onChange()
        return true
    }
}

extension ManualActivityType {
    var title: String {
        switch self {
        case .running: return String(localized: "Running", comment: "Manual activity type (add-health-active-calories).")
        case .walking: return String(localized: "Walking", comment: "Manual activity type (add-health-active-calories).")
        case .cycling: return String(localized: "Cycling", comment: "Manual activity type (add-health-active-calories).")
        case .swimming: return String(localized: "Swimming", comment: "Manual activity type (add-health-active-calories).")
        case .gym: return String(localized: "Gym", comment: "Manual activity type: strength training (add-health-active-calories).")
        case .yoga: return String(localized: "Yoga", comment: "Manual activity type (add-health-active-calories).")
        case .other: return String(localized: "Other", comment: "Manual activity type (add-health-active-calories).")
        }
    }

    var symbol: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .gym: return "dumbbell.fill"
        case .yoga: return "figure.yoga"
        case .other: return "flame.fill"
        }
    }
}
