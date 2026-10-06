// FoodLoggingTests.swift
//
// add-standalone-mode 1.4 (design D4): the write seam must change nothing
// in Garmin mode. `ModeRoutingFoodLogging` forwards to the Garmin
// `LogEntryCoordinator` with every argument intact. Real `Outbox` per test
// (LogEntryCoordinatorTests' pattern).
//
// improve-food-day-flow (E2): the synced-row delete no longer calls Garmin
// from the coordinator. It queues the delete in the outbox and returns --
// no network -- and the delete drain later makes exactly the one Garmin
// call the direct delete used to make (recorded by a fake, since the real
// one is the network).

import XCTest
@testable import FoodLogCore
import GarminKit

final class FoodLoggingTests: XCTestCase {
    private actor RecordingGarmin: FoodLogDelivering {
        private(set) var deletes: [(logIds: [String], date: String)] = []
        private(set) var creates = 0

        @discardableResult
        func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
            creates += 1
            return HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }

        @discardableResult
        func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
            deletes.append((logIds, date))
            return HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        }
    }

    private let food = Food(id: "food-1", name: "Test food", source: .garmin, servings: [Serving(id: "serving-1", unit: "g", numberOfUnits: 100)])

    private func makeOutbox() -> Outbox {
        Outbox(processName: "foodlogging-test-\(UUID().uuidString)")
    }

    private func makeCoordinator(outbox: Outbox) -> LogEntryCoordinator {
        let tmp = FileManager.default.temporaryDirectory
        return LogEntryCoordinator(
            outbox: outbox,
            usageHistory: UsageHistoryStore(fileURL: tmp.appendingPathComponent("foodlogging-usage-\(UUID().uuidString).json")),
            servingDefaults: ServingDefaultStore(fileURL: tmp.appendingPathComponent("foodlogging-servings-\(UUID().uuidString).json"))
        )
    }

    func testRouterForwardsAConfirmToTheGarminOutboxUnchanged() async throws {
        let outbox = makeOutbox()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))

        let entry = try await router.confirm(
            food: food, serving: food.servings[0], numberOfUnits: 2, mealType: .lunch, date: "2026-09-24",
            regionCode: "CZ", languageCode: "cs"
        )

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(stored.first?.numberOfUnits, 2)
        XCTAssertEqual(stored.first?.regionCode, "CZ")
        XCTAssertEqual(stored.first?.languageCode, "cs")
    }

    func testRouterForwardsAPendingDeleteToTheGarminOutbox() async throws {
        let outbox = makeOutbox()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))
        let entry = try await router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .breakfast, date: "2026-09-24")

        let outcome = try await router.deletePending(outboxId: entry.id)

        XCTAssertEqual(outcome, .removed)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testDeleteCommittedQueuesTheDeleteAndMakesNoRequest() async throws {
        let outbox = makeOutbox()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))

        try await router.deleteCommitted(logId: "abc123", date: "2026-09-24")

        let queued = await outbox.allDeletions()
        XCTAssertEqual(queued.map(\.logId), ["abc123"])
        XCTAssertEqual(queued.map(\.date), ["2026-09-24"])
        XCTAssertEqual(queued.map(\.state), [.pending], "saved on the phone, nothing sent yet")
        let entries = await outbox.allEntries()
        XCTAssertTrue(entries.isEmpty, "a delete is never a food entry in the outbox")
    }

    func testTheQueuedDeleteIsDeliveredAsExactlyThatLogIdInGarmin() async throws {
        let outbox = makeOutbox()
        let garmin = RecordingGarmin()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))
        try await router.deleteCommitted(logId: "abc123", date: "2026-09-24")

        let result = await outbox.drainDeletions(using: garmin)

        XCTAssertEqual(result.delivered.count, 1)
        let deletes = await garmin.deletes
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.logIds, ["abc123"])
        XCTAssertEqual(deletes.first?.date, "2026-09-24")
        let creates = await garmin.creates
        XCTAssertEqual(creates, 0)
    }

    func testDeletingTheSameSyncedRowTwiceQueuesOneDelete() async throws {
        let outbox = makeOutbox()
        let coordinator = makeCoordinator(outbox: outbox)

        try await coordinator.deleteCommitted(logId: "abc123", date: "2026-09-24")
        try await coordinator.deleteCommitted(logId: "abc123", date: "2026-09-24")

        let queued = await outbox.allDeletions()
        XCTAssertEqual(queued.count, 1)
    }

    func testDeleteCommittedWithoutAnIdThrowsInsteadOfPretending() async throws {
        let outbox = makeOutbox()
        let coordinator = makeCoordinator(outbox: outbox)

        do {
            try await coordinator.deleteCommitted(logId: "", date: "2026-09-24")
            XCTFail("expected a throw")
        } catch let error as FoodLogDeletionError {
            XCTAssertEqual(error, .missingIdentifier)
        }
        let queued = await outbox.allDeletions()
        XCTAssertTrue(queued.isEmpty)
    }
}
