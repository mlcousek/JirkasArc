// UsageEventIdentityTests.swift
//
// harden-gamification-data-integrity 1.1, 1.2, 3.3: each usage event knows
// which logged entry it records (`entryId`, then Garmin's `logId` once a
// delivery is confirmed), so deleting or cancelling THAT entry removes
// exactly its event -- and never an identical food logged separately, nor
// an event written before identities existed. Same conventions as
// LogEntryCoordinatorTests.swift: a REAL `Outbox` (unique process name per
// test) and real stores on unique temp files, never mocks.

import XCTest
@testable import FoodLogCore
import GarminKit

final class UsageEventIdentityTests: XCTestCase {
    private let day = "2026-09-30"
    private let food = Food(id: "food-1", name: "Rohlík", source: .garmin, servings: [Serving(id: "serving-1", unit: "piece", numberOfUnits: 1, calories: 150)])

    private struct Harness {
        let coordinator: LogEntryCoordinator
        let outbox: Outbox
        let usageHistory: UsageHistoryStore
        let usageURL: URL
    }

    private func makeHarness() -> Harness {
        let usageURL = tempURL("usage")
        let outbox = Outbox(processName: "foodlogcore-identity-test-\(UUID().uuidString)")
        let usageHistory = UsageHistoryStore(fileURL: usageURL)
        let coordinator = LogEntryCoordinator(
            outbox: outbox,
            usageHistory: usageHistory,
            servingDefaults: ServingDefaultStore(fileURL: tempURL("servingdefaults"))
        )
        return Harness(coordinator: coordinator, outbox: outbox, usageHistory: usageHistory, usageURL: usageURL)
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-identity-\(name)-\(UUID().uuidString).json")
    }

    // MARK: - Recording

    func testAConfirmedEntryRecordsItsOwnId() async throws {
        let h = makeHarness()

        let entry = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)

        let events = await h.usageHistory.all()
        XCTAssertEqual(events.map(\.entryId), [entry.id.uuidString])
        XCTAssertNil(events.first?.garminLogId, "not delivered yet")
    }

    func testEveryIngredientOfAPresetRecordsItsOwnEntry() async throws {
        let h = makeHarness()
        let banana = Food(id: "food-2", name: "Banana", source: .garmin, servings: [Serving(id: "serving-2", unit: "medium", numberOfUnits: 1, calories: 105)])
        let preset = MealPreset(name: "Snack", ingredients: [
            MealPresetIngredient(food: food, serving: food.servings[0], quantity: 1),
            MealPresetIngredient(food: banana, serving: banana.servings[0], quantity: 1),
        ])

        let entries = try await h.coordinator.confirmMealPreset(preset, mealType: .snack, date: day)

        let events = await h.usageHistory.all()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.compactMap(\.entryId)), Set(entries.map(\.id.uuidString)))
    }

    // MARK: - Removing

    func testCancellingAQueuedEntryRemovesOnlyItsOwnEvent() async throws {
        let h = makeHarness()
        let first = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)
        // The same food, serving and amount again: an identical, separate log.
        let second = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)

        _ = try await h.coordinator.deletePending(outboxId: first.id)

        let events = await h.usageHistory.all()
        XCTAssertEqual(events.map(\.entryId), [second.id.uuidString], "the identical second log keeps counting")
    }

    func testDeletingADeliveredEntryRemovesItsEventByGarminLogId() async throws {
        let h = makeHarness()
        let entry = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)
        let other = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)
        // Reconciliation confirmed both deliveries.
        let links = UsageLogLinks.from(verdicts: [
            (entryId: entry.id, verdict: .confirmed(logId: "log-1")),
            (entryId: other.id, verdict: .confirmed(logId: "log-2")),
        ])
        let linked = try await h.usageHistory.linkGarminLogIds(links)
        XCTAssertEqual(linked, 2)

        try await h.coordinator.deleteCommitted(logId: "log-1", date: day)

        let events = await h.usageHistory.all()
        XCTAssertEqual(events.map(\.garminLogId), ["log-2"])
    }

    func testAnEventWrittenBeforeIdentitiesExistedIsNeverRemoved() async throws {
        let h = makeHarness()
        try await h.usageHistory.record(foodId: food.id, servingId: "serving-1", numberOfUnits: 1, nutritionDay: day)

        let removedByEntry = try await h.usageHistory.remove(.entry(UUID().uuidString))
        let removedByLog = try await h.usageHistory.remove(.garminLog("log-1"))
        let removedByEmpty = try await h.usageHistory.remove(.entry(""))

        XCTAssertEqual(removedByEntry + removedByLog + removedByEmpty, 0)
        let count = await h.usageHistory.all().count
        XCTAssertEqual(count, 1)
    }

    func testEditingAQueuedEntryMovesItsEventSoDeletingTheEditStillRemovesIt() async throws {
        let h = makeHarness()
        let original = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)
        let row = MealDashboard.pendingEntry(original, food: food, mealType: .lunch)

        let edited = try await h.coordinator.edit(row, date: day, newQuantity: 2, newMeal: .lunch)
        let afterEdit = await h.usageHistory.all()
        XCTAssertEqual(afterEdit.map(\.entryId), [edited.id.uuidString], "an edit is not another thing eaten: still one event")

        _ = try await h.coordinator.deletePending(outboxId: edited.id)
        let afterDelete = await h.usageHistory.all()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    // MARK: - Garmin links

    func testOnlyAConfirmedOrResolvedVerdictLinksALogId() {
        let confirmed = UUID(), resolved = UUID(), missing = UUID(), skipped = UUID(), unknown = UUID()

        let links = UsageLogLinks.from(verdicts: [
            (entryId: confirmed, verdict: .confirmed(logId: "log-a")),
            (entryId: resolved, verdict: .duplicateResolved(keptLogId: "log-b", deletedLogIds: ["log-c"])),
            (entryId: missing, verdict: .missingRequeued),
            (entryId: skipped, verdict: .reconciliationSkipped),
            (entryId: unknown, verdict: .confirmed(logId: nil)),
        ])

        XCTAssertEqual(links, [confirmed.uuidString: "log-a", resolved.uuidString: "log-b"])
    }

    // MARK: - Persistence

    func testIdentitiesSurviveAReloadAndAnOlderFileStillDecodes() async throws {
        let h = makeHarness()
        let entry = try await h.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .lunch, date: day)
        try await h.usageHistory.linkGarminLogIds([entry.id.uuidString: "log-9"])

        let reloaded = UsageHistoryStore(fileURL: h.usageURL)
        let events = await reloaded.all()
        XCTAssertEqual(events.first?.entryId, entry.id.uuidString)
        XCTAssertEqual(events.first?.garminLogId, "log-9")

        let olderFile = #"[{"foodId":"f","servingId":"s","numberOfUnits":1,"timestamp":"2026-09-01T12:00:00Z","nutritionDay":"2026-09-01","mealType":"LUNCH"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([UsageEvent].self, from: Data(olderFile.utf8))
        XCTAssertNil(decoded.first?.entryId)
        XCTAssertNil(decoded.first?.garminLogId)
    }
}
