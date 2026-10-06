// BoundedWaitTests.swift
//
// add-training-shortcuts-and-widgets (design D5): an intent waits for its
// delivery only briefly, and the delivery is never cancelled by the wait
// running out. Generous margins on purpose (a fast answer against a
// 30-second bound, a 0.05-second bound against a half-second operation),
// so a slow CI runner can't flip either.

import XCTest
@testable import FoodLogCore

final class BoundedWaitTests: XCTestCase {
    func testAnOperationThatFinishesInTimeGivesItsValue() async {
        let value = await BoundedWait.value(within: 30) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testAnOperationThatTakesTooLongGivesNilAndStillFinishes() async {
        let flag = Flag()
        let value = await BoundedWait.value(within: 0.05) { () -> Int in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await flag.set()
            return 7
        }
        XCTAssertNil(value, "the wait ran out before the operation did")

        // Not cancelled: it completes on its own.
        var finished = false
        for _ in 0..<100 {
            if await flag.isSet {
                finished = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(finished, "running out of time must never cancel the operation")
    }

    func testAnOptionalValueIsKeptApartFromATimeout() async {
        let value: String?? = await BoundedWait.value(within: 30) { () -> String? in nil }
        XCTAssertNotNil(value, "the operation finished; its own nil is a value, not a timeout")
    }
}

private actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
}
