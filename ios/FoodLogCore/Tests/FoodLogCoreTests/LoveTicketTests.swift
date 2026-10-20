// LoveTicketTests.swift
//
// add-partner-love-theme: a redeemed coupon's ticket is the same as
// tools/love-pack/ticket.mjs computes (shared vector), and a made-up or
// edited ticket does not verify.

import XCTest
@testable import FoodLogCore

final class LoveTicketTests: XCTestCase {
    private var pack: LovePack {
        LovePack(
            packId: "sample-pack-0001", nickname: "Ninja", signature: "", startDate: "2030-01-01", seed: "sample-seed-0001",
            daily: [LovePackDaily(id: "d001", text: "x")],
            coupons: [LovePackCoupon(id: "c001", title: "Večeře", price: 40)]
        )
    }

    /// 2030-03-14 10:15 UTC.
    private let redeemedAt = Date(timeIntervalSince1970: 1_899_713_700)

    func testTheSharedVector() {
        XCTAssertEqual(LoveTicket.minuteKey(redeemedAt), "203003141015")
        XCTAssertEqual(LoveTicket.code(seed: "sample-seed-0001", packId: "sample-pack-0001", couponId: "c001", minute: "203003141015"), "K6KP-JHN8")
        XCTAssertEqual(LoveTicket.code(seed: "sample-seed-0001", packId: "sample-pack-0001", couponId: "c001", minute: "203003141016"), "QXNB-ZCMH")
        XCTAssertEqual(LoveTicket.make(pack: pack, couponId: "c001", redeemedAt: redeemedAt).payload, "LASKA1:c001:203003141015:K6KP-JHN8")
    }

    func testAGenuineTicketVerifiesAndAnEditedOneDoesNot() {
        let payload = LoveTicket.make(pack: pack, couponId: "c001", redeemedAt: redeemedAt).payload
        XCTAssertNotNil(LoveTicket.verify(payload, pack: pack))
        XCTAssertNotNil(LoveTicket.verify(" laska1:c001:203003141015:k6kp-jhn8 ", pack: pack))
        XCTAssertNil(LoveTicket.verify("LASKA1:c001:203003141016:K6KP-JHN8", pack: pack), "another date")
        XCTAssertNil(LoveTicket.verify("LASKA1:c001:203003141015:K6KP-JHN9", pack: pack), "another code")
        XCTAssertNil(LoveTicket.verify("LASKA1:c999:203003141015:K6KP-JHN8", pack: pack), "a coupon the pack does not have")
        XCTAssertNil(LoveTicket.verify("hello", pack: pack))

        let other = LovePack(packId: "sample-pack-0001", nickname: "Ninja", signature: "", startDate: "2030-01-01", seed: "another-seed",
                             daily: [LovePackDaily(id: "d001", text: "x")], coupons: pack.coupons)
        XCTAssertNil(LoveTicket.verify(payload, pack: other), "another pack's seed")
    }
}
