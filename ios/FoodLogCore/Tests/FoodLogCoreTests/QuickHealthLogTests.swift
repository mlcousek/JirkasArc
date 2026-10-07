// QuickHealthLogTests.swift
//
// add-training-shortcuts-and-widgets (design D5): what the "Log weight" /
// "Log water" App Shortcuts and the water Control may record, and that a
// refused number writes NOTHING -- neither the local record nor an outbox
// entry. Real `WeightStore` / `HydrationStore` / outbox instances on unique
// temp files and process names (no mocks), as in the coordinators' own
// tests. Synthetic numbers only.

import XCTest
@testable import FoodLogCore
import GarminKit

final class QuickHealthLogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func weight(deliversToGarmin: Bool = true) -> (WeightLogCoordinator, WeightStore, WeightOutbox) {
        let store = WeightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("quick-weight-\(UUID().uuidString).json"))
        let outbox = WeightOutbox(processName: "quick-weight-\(UUID().uuidString)")
        return (WeightLogCoordinator(store: store, outbox: outbox, deliversToGarmin: { deliversToGarmin }), store, outbox)
    }

    private func water(deliversToGarmin: Bool = true) -> (HydrationLogCoordinator, HydrationStore, HydrationOutbox) {
        let store = HydrationStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("quick-water-\(UUID().uuidString).json"))
        let outbox = HydrationOutbox(processName: "quick-water-\(UUID().uuidString)")
        return (HydrationLogCoordinator(store: store, outbox: outbox, deliversToGarmin: { deliversToGarmin }), store, outbox)
    }

    // MARK: Input rules

    func testWeightBoundsAreTheWeighInFormsBounds() throws {
        XCTAssertEqual(try QuickLogInput.weightKg(75.5), 75.5)
        XCTAssertEqual(try QuickLogInput.weightKg(0.1), 0.1)
        XCTAssertEqual(try QuickLogInput.weightKg(499.9), 499.9)
        for refused in [0, -1, 500, 750, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try QuickLogInput.weightKg(refused), "\(refused) kg must be refused") { error in
                XCTAssertEqual(error as? QuickLogInput.Rejection, .weightOutOfRange)
            }
        }
    }

    func testWaterBoundsAreTheWaterFormsBoundsAndNoAmountIsOneGlass() throws {
        XCTAssertEqual(QuickLogInput.defaultGlassML, 250, "the intents' @Parameter(default: 250) repeats this literal")
        XCTAssertEqual(try QuickLogInput.waterML(nil), 250)
        XCTAssertEqual(try QuickLogInput.waterML(500), 500)
        XCTAssertEqual(try QuickLogInput.waterML(1), 1)
        XCTAssertEqual(try QuickLogInput.waterML(4999), 4999)
        for refused in [0, -250, 5000, 12_000, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try QuickLogInput.waterML(refused), "\(refused) ml must be refused") { error in
                XCTAssertEqual(error as? QuickLogInput.Rejection, .waterOutOfRange)
            }
        }
    }

    // MARK: Weight

    func testAQuickWeighInIsSavedForNowAndQueued() async throws {
        let (coordinator, store, outbox) = weight()

        let entry = try await QuickHealthLog.logWeight(kilograms: 75.5, using: coordinator, now: now)

        XCTAssertEqual(entry.weightKg, 75.5)
        XCTAssertEqual(entry.loggedAt, now, "a screenless weigh-in is for now, never backdated")
        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(queued.map(\.id), [entry.outboxEntryId].compactMap { $0 })
        XCTAssertEqual(queued.first?.weightKg, 75.5)
        XCTAssertEqual(queued.first?.state, .pending, "the commit never delivers by itself")
    }

    func testARefusedWeightWritesNothing() async throws {
        let (coordinator, store, outbox) = weight()

        for refused in [0, 500, Double.nan] {
            do {
                _ = try await QuickHealthLog.logWeight(kilograms: refused, using: coordinator, now: now)
                XCTFail("\(refused) kg must be refused")
            } catch {
                XCTAssertEqual(error as? QuickLogInput.Rejection, .weightOutOfRange)
            }
        }

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty, "a refused number never reaches the local store")
        XCTAssertTrue(queued.isEmpty, "a refused number is never queued for Garmin")
    }

    func testAStandaloneQuickWeighInStaysOnThePhone() async throws {
        let (coordinator, store, outbox) = weight(deliversToGarmin: false)

        let entry = try await QuickHealthLog.logWeight(kilograms: 60, using: coordinator, now: now)

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertNil(entry.outboxEntryId)
        XCTAssertTrue(queued.isEmpty)
    }

    // MARK: Water

    func testAQuickDrinkWithoutAnAmountIsOneGlass() async throws {
        let (coordinator, store, outbox) = water()

        let entry = try await QuickHealthLog.logWater(milliliters: nil, using: coordinator, now: now)

        XCTAssertEqual(entry.valueInML, 250)
        XCTAssertEqual(entry.loggedAt, now)
        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(queued.map(\.id), [entry.outboxEntryId].compactMap { $0 })
        XCTAssertEqual(queued.first?.valueInML, 250)
    }

    func testAQuickDrinkWithAnAmountLogsThatAmountAndTwoTapsAreTwoDrinks() async throws {
        let (coordinator, store, outbox) = water()

        try await QuickHealthLog.logWater(milliliters: 500, using: coordinator, now: now)
        try await QuickHealthLog.logWater(milliliters: nil, using: coordinator, now: now.addingTimeInterval(1))

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.valueInML).sorted(), [250, 500])
        XCTAssertEqual(queued.count, 2, "each tap is its own drink")
    }

    func testARefusedAmountWritesNothing() async throws {
        let (coordinator, store, outbox) = water()

        for refused in [0, 5000, -1] as [Double] {
            do {
                _ = try await QuickHealthLog.logWater(milliliters: refused, using: coordinator, now: now)
                XCTFail("\(refused) ml must be refused")
            } catch {
                XCTAssertEqual(error as? QuickLogInput.Rejection, .waterOutOfRange)
            }
        }

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertTrue(queued.isEmpty)
    }

    func testAStandaloneQuickDrinkStaysOnThePhone() async throws {
        let (coordinator, store, outbox) = water(deliversToGarmin: false)

        let entry = try await QuickHealthLog.logWater(milliliters: nil, using: coordinator, now: now)

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertNil(entry.outboxEntryId)
        XCTAssertTrue(queued.isEmpty)
    }

    // MARK: What the bounded drain says

    func testDeliveryOutcomeAfterTheBoundedDrain() {
        let mine = UUID()
        let other = UUID()

        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [other, mine], authOutcome: .none, outboxEntryId: mine),
            .delivered
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [other], authOutcome: .none, outboxEntryId: mine),
            .queued,
            "another entry's delivery is not this one's"
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [], authOutcome: .none, outboxEntryId: mine),
            .queued,
            "offline, backing off, or another drain already running"
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [], authOutcome: .longLivedTokenExpired, outboxEntryId: mine),
            .signedOut
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [], authOutcome: .notSignedIn, outboxEntryId: mine),
            .signedOut
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: false, deliveredIds: [mine], authOutcome: .notSignedIn, outboxEntryId: mine),
            .queued,
            "the wait ran out: nothing is known yet, so nothing is claimed"
        )
        XCTAssertEqual(
            QuickLogDelivery.afterDrain(drainFinished: true, deliveredIds: [mine], authOutcome: .none, outboxEntryId: nil),
            .queued,
            "an entry without an outbox link can't be called delivered"
        )
    }
}
