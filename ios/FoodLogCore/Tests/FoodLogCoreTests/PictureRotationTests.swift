// PictureRotationTests.swift
//
// add-partner-love-theme D4, spec partner-theme "The theme is illustrated
// with original art, and pack pictures fill named slots": a picture shows
// only in its slots, several rotate daily without a repeat on consecutive
// days, and a slot nobody names falls back to built-in art (`nil`). Also
// CzechPlural, the theme table's plural rule.

import XCTest
@testable import FoodLogCore

final class PictureRotationTests: XCTestCase {
    private func makePack(_ images: [LovePackImage]) -> LovePack {
        LovePack(
            packId: "p", nickname: "Ninja", signature: "", startDate: "2030-01-01", seed: "sample-seed-0001",
            daily: [LovePackDaily(id: "d001", text: "x")], images: images
        )
    }

    private func image(_ id: String, _ slots: [String]) -> LovePackImage {
        LovePackImage(id: id, format: .png, slots: slots, lore: [])
    }

    func testThreePicturesNeverRepeatOnConsecutiveDays() {
        let pack = makePack([
            image("i001", [LovePictureSlot.pictureOfDay]),
            image("i002", [LovePictureSlot.pictureOfDay, LovePictureSlot.loveCard]),
            image("i003", [LovePictureSlot.pictureOfDay])
        ])
        var previous: String?
        var seen = Set<String>()
        var day = "2030-03-01"
        for _ in 0..<30 {
            let id = PictureRotation.pictureId(slot: LovePictureSlot.pictureOfDay, day: day, pack: pack)
            XCTAssertNotNil(id)
            XCTAssertNotEqual(id, previous, day)
            previous = id
            if let id { seen.insert(id) }
            day = LoveDay.adding(1, to: day)!
        }
        XCTAssertEqual(seen, ["i001", "i002", "i003"])
    }

    func testAPictureShowsOnlyInItsSlots() {
        let pack = makePack([image("i001", [LovePictureSlot.badge("p.genin")]), image("i002", [LovePictureSlot.loveCard])])
        XCTAssertEqual(PictureRotation.pictureId(slot: LovePictureSlot.badge("p.genin"), day: "2030-03-01", pack: pack), "i001")
        XCTAssertEqual(PictureRotation.pictureId(slot: LovePictureSlot.loveCard, day: "2030-03-01", pack: pack), "i002")
        XCTAssertNil(PictureRotation.pictureId(slot: LovePictureSlot.emptyState, day: "2030-03-01", pack: pack))
        XCTAssertNil(PictureRotation.pictureId(slot: LovePictureSlot.badge("p.kage"), day: "2030-03-01", pack: pack))
    }

    func testMissingPictureFilesAreSkipped() {
        let pack = makePack([image("i001", [LovePictureSlot.loveCard]), image("i002", [LovePictureSlot.loveCard])])
        XCTAssertEqual(PictureRotation.pictureId(slot: LovePictureSlot.loveCard, day: "2030-03-01", pack: pack, available: ["i002"]), "i002")
        XCTAssertNil(PictureRotation.pictureId(slot: LovePictureSlot.loveCard, day: "2030-03-01", pack: pack, available: []))
    }

    func testSlotNames() {
        XCTAssertTrue(LovePictureSlot.isKnown("rankEmblem:kage"))
        XCTAssertFalse(LovePictureSlot.isKnown("rankEmblem:"))
        XCTAssertTrue(LovePictureSlot.isKnown("badge:p.firstnote"))
        XCTAssertFalse(LovePictureSlot.isKnown("badge:"))
        XCTAssertFalse(LovePictureSlot.isKnown("badge:../x"))
    }

    func testCzechPlural() {
        func hearts(_ n: Int) -> String {
            "\(n) " + CzechPlural.choose(n, one: "srdíčko", few: "srdíčka", many: "srdíček")
        }
        XCTAssertEqual(hearts(0), "0 srdíček")
        XCTAssertEqual(hearts(1), "1 srdíčko")
        XCTAssertEqual(hearts(3), "3 srdíčka")
        XCTAssertEqual(hearts(4), "4 srdíčka")
        XCTAssertEqual(hearts(7), "7 srdíček")
        XCTAssertEqual(hearts(21), "21 srdíček", "Czech has no 'one' form for 21")
    }
}
