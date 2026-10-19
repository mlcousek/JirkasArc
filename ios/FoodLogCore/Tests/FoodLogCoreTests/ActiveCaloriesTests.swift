// ActiveCaloriesTests.swift
//
// add-health-active-calories, spec active-calories: the newest Health
// report replaces the older one, Health wins over manual entries without
// double counting, out-of-range reports change nothing, and the bridge's
// text accepts a Czech decimal comma. A real store on a fresh temp file.

import XCTest
@testable import FoodLogCore

final class ActiveCaloriesTests: XCTestCase {
    private let calendar = LoveTestSupport.prague

    private func makeStore() -> ActiveCaloriesStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("active-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return ActiveCaloriesStore(fileURL: url)
    }

    private func at(_ day: String, _ hour: Int) -> Date {
        LoveTestSupport.date(day, hour, 0, calendar: calendar)
    }

    func testTheNewestReportReplacesTheOlder() async throws {
        let store = makeStore()
        try await store.recordHealth(kcal: 310, day: "2030-03-14", now: at("2030-03-14", 14), calendar: calendar)
        try await store.recordHealth(kcal: 455, day: "2030-03-14", now: at("2030-03-14", 18), calendar: calendar)
        let total = await store.total(day: "2030-03-14")
        let last = await store.lastHealthReportAt()
        XCTAssertEqual(total, 455)
        XCTAssertEqual(last, at("2030-03-14", 18))
    }

    func testHealthWinsAndManualIsNotCountedTwice() async throws {
        let store = makeStore()
        try await store.addManual(type: .running, minutes: 30, kcal: 300, day: "2030-03-14", now: at("2030-03-14", 8), calendar: calendar)
        let manualOnly = await store.total(day: "2030-03-14")
        XCTAssertEqual(manualOnly, 300)

        try await store.recordHealth(kcal: 640, day: "2030-03-14", now: at("2030-03-14", 20), calendar: calendar)
        let day = await store.day("2030-03-14")
        XCTAssertEqual(day.total, 640)
        XCTAssertEqual(day.source, .health)
        XCTAssertEqual(day.manual.count, 1, "the manual run stays listed")
    }

    func testManualOnlyDaysSumTheirActivities() async throws {
        let store = makeStore()
        try await store.addManual(type: .walking, minutes: 45, kcal: 200, day: "2030-03-14", now: at("2030-03-14", 9), calendar: calendar)
        let yoga = try await store.addManual(type: .yoga, minutes: nil, kcal: 150, day: "2030-03-14", now: at("2030-03-14", 19), calendar: calendar)
        var total = await store.total(day: "2030-03-14")
        XCTAssertEqual(total, 350)

        var edited = yoga
        edited.kcal = 100
        try await store.updateManual(edited, day: "2030-03-14", now: at("2030-03-14", 20), calendar: calendar)
        total = await store.total(day: "2030-03-14")
        XCTAssertEqual(total, 300)

        try await store.deleteManual(id: yoga.id, day: "2030-03-14", now: at("2030-03-14", 21), calendar: calendar)
        total = await store.total(day: "2030-03-14")
        XCTAssertEqual(total, 200)
    }

    func testOutOfRangeReportsChangeNothing() async throws {
        let store = makeStore()
        let now = at("2030-03-14", 12)
        let cases: [(Double, String, ActiveCaloriesRules.Refusal)] = [
            (500, "2030-03-15", .future),
            (500, "2030-03-06", .tooOld),
            (12_000, "2030-03-14", .outOfRange),
            (-5, "2030-03-14", .outOfRange)
        ]
        for (kcal, day, refusal) in cases {
            do {
                try await store.recordHealth(kcal: kcal, day: day, now: now, calendar: calendar)
                XCTFail("accepted \(kcal) for \(day)")
            } catch let error as ActiveCaloriesRules.Refusal {
                XCTAssertEqual(error, refusal, "\(kcal) for \(day)")
            }
        }
        let total = await store.total(day: "2030-03-14")
        XCTAssertNil(total)
        // Exactly 7 days back is still accepted.
        try await store.recordHealth(kcal: 300, day: "2030-03-07", now: now, calendar: calendar)
    }

    func testManualLimits() async {
        let store = makeStore()
        do {
            try await store.addManual(type: .gym, minutes: 30, kcal: 0, day: "2030-03-14", now: at("2030-03-14", 9), calendar: calendar)
            XCTFail("accepted 0 kcal")
        } catch {}
        XCTAssertEqual(ActiveCaloriesRules.checkManual(kcal: 3_001, minutes: nil), .outOfRange)
        XCTAssertNil(ActiveCaloriesRules.checkManual(kcal: 3_000, minutes: 90))
    }

    func testDaysWithTotal() async throws {
        let store = makeStore()
        try await store.recordHealth(kcal: 350, day: "2030-03-12", now: at("2030-03-14", 9), calendar: calendar)
        try await store.recordHealth(kcal: 250, day: "2030-03-13", now: at("2030-03-14", 9), calendar: calendar)
        try await store.recordHealth(kcal: 500, day: "2030-03-14", now: at("2030-03-14", 9), calendar: calendar)
        let count = await store.daysWithTotal(atLeast: 300, from: "2030-03-13")
        XCTAssertEqual(count, 1)
    }

    func testTheBridgeAcceptsCzechNumbers() {
        XCTAssertEqual(ActiveCaloriesIntake.parseKcal("412,5"), 412.5)
        XCTAssertEqual(ActiveCaloriesIntake.parseKcal(" 412.5 "), 412.5)
        XCTAssertEqual(ActiveCaloriesIntake.parseKcal("412,5 kcal"), 412.5)
        XCTAssertEqual(ActiveCaloriesIntake.parseKcal("1\u{00A0}204"), 1204)
        XCTAssertEqual(ActiveCaloriesIntake.parseKcal("640"), 640)
        XCTAssertNil(ActiveCaloriesIntake.parseKcal(""))
        XCTAssertNil(ActiveCaloriesIntake.parseKcal("hodně"))
        XCTAssertNil(ActiveCaloriesIntake.parseKcal("1.2.3"))
        XCTAssertNil(ActiveCaloriesIntake.parseKcal("-40"))
    }
}
