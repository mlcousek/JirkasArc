// LovePackTests.swift
//
// add-partner-love-theme, spec love-pack: a pack file is read whole,
// refused with the FIRST problem named, and its pictures checked by their
// headers. Also the import diff (LovePackDiff) and the committed synthetic
// sample `.arclove`, which `tools/love-pack/build.mjs` writes -- the builder
// and the app must agree on it.

import XCTest
@testable import FoodLogCore

final class LovePackTests: XCTestCase {
    private typealias Support = LoveTestSupport

    private func read(_ object: [String: Any]) -> Result<LoadedLovePack, LovePackProblem> {
        LovePackReader.read(Support.data(object))
    }

    private func problem(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> LovePackProblem? {
        if case .failure(let problem) = read(object) { return problem }
        XCTFail("the pack was accepted", file: file, line: line)
        return nil
    }

    // MARK: Valid packs

    func testAValidPackIsReadWithItsPictures() throws {
        let png = Support.png(width: 1200, height: 800)
        let jpeg = Support.jpeg(width: 640, height: 640)
        let object = Support.wirePack(images: [
            Support.wireImage(id: "i001", data: png, slots: ["loveCard", "pictureOfDay"]),
            Support.wireImage(id: "i002", data: jpeg, slots: ["badge:p.genin", "rankEmblem:jonin"])
        ])

        let loaded = try read(object).get()

        XCTAssertEqual(loaded.pack.packId, "sample-pack-0001")
        XCTAssertEqual(loaded.pack.nickname, "Ninja")
        XCTAssertEqual(loaded.pack.daily.count, 30)
        XCTAssertEqual(loaded.pack.openWhen.map(\.id), ["o-sad"])
        XCTAssertEqual(loaded.pack.coupons.first?.price, 40)
        XCTAssertEqual(loaded.pack.countdown?.title, "Svatba")
        XCTAssertEqual(loaded.pack.images.map(\.format), [.png, .jpeg])
        XCTAssertEqual(loaded.pack.images.last?.slots, ["badge:p.genin", "rankEmblem:jonin"])
        XCTAssertEqual(loaded.pictures["i001"], png)
        XCTAssertEqual(loaded.pictures["i002"], jpeg)
    }

    func testTheExtrasAreOptional() throws {
        var object = Support.wirePack()
        object.removeValue(forKey: "openWhen")
        object.removeValue(forKey: "coupons")
        object.removeValue(forKey: "countdown")
        object.removeValue(forKey: "images")
        object.removeValue(forKey: "signature")

        let pack = try read(object).get().pack

        XCTAssertEqual(pack.openWhen, [])
        XCTAssertEqual(pack.coupons, [])
        XCTAssertNil(pack.countdown)
        XCTAssertEqual(pack.images, [])
        XCTAssertEqual(pack.signature, "")
        XCTAssertNil(pack.themeName)
    }

    func testNicknamesAndSignaturesRotateDailyAndStayFixedForTheDay() throws {
        var object = Support.wirePack()
        object["nicknames"] = ["Ninjo", "Lásko", "Srdíčko", "Poklade"]
        object["signatures"] = ["Tvůj J.", "Tvůj ninja"]
        let pack = try read(object).get().pack

        XCTAssertEqual(pack.nicknames.count, 4)
        XCTAssertEqual(pack.nickname(for: "2030-03-14"), pack.nickname(for: "2030-03-14"))
        var seen = Set<String>()
        var day = "2030-03-01"
        for _ in 0..<60 {
            seen.insert(pack.nickname(for: day))
            day = LoveDay.adding(1, to: day)!
        }
        XCTAssertEqual(seen, ["Ninjo", "Lásko", "Srdíčko", "Poklade"])
        XCTAssertTrue(["Tvůj J.", "Tvůj ninja"].contains(pack.signature(for: "2030-03-14")))

        // The reminders call her the same name as the love card that day.
        let texts = ThemedNotificationTexts(
            seed: pack.seed, nickname: pack.nickname, signature: pack.signature,
            nicknames: pack.nicknames, signatures: pack.signatures, variants: [:]
        )
        XCTAssertEqual(texts.fill("{nickname}", day: "2030-03-14"), pack.nickname(for: "2030-03-14"))

        // Without lists: the single names.
        let plain = try read(Support.wirePack()).get().pack
        XCTAssertEqual(plain.nickname(for: "2030-03-14"), "Ninja")

        object["nicknames"] = ["Ninjo", " "]
        XCTAssertEqual(problem(object), .missingField("nicknames[]"))
    }

    func testTheThemeNameComesFromThePack() throws {
        var object = Support.wirePack()
        object["themeName"] = "Ukázkový motiv"
        XCTAssertEqual(try read(object).get().pack.themeName, "Ukázkový motiv")

        object["themeName"] = String(repeating: "x", count: LovePackLimits.maxShortTextLength + 1)
        XCTAssertEqual(problem(object), .textTooLong(list: "themeName", id: ""))
    }

    // MARK: Refusals

    func testAFileOver40MiBIsRefusedBeforeParsing() {
        let data = Data(count: LovePackLimits.maxFileBytes + 1)
        guard case .failure(let problem) = LovePackReader.read(data) else { return XCTFail("accepted") }
        XCTAssertEqual(problem, .tooLarge(bytes: LovePackLimits.maxFileBytes + 1))
    }

    func testNotJSONAndAnotherFormat() {
        guard case .failure(let notJSON) = LovePackReader.read(Data("hello".utf8)) else { return XCTFail("accepted") }
        XCTAssertEqual(notJSON, .notJSON)

        var object = Support.wirePack()
        object["format"] = "backup"
        XCTAssertEqual(problem(object), .wrongFormat)

        object = Support.wirePack()
        object["version"] = 2
        XCTAssertEqual(problem(object), .unsupportedVersion(2))
    }

    func testAMissingRequiredFieldIsNamed() {
        for field in ["packId", "nickname", "startDate", "seed", "daily"] {
            var object = Support.wirePack()
            object.removeValue(forKey: field)
            XCTAssertEqual(problem(object), .missingField(field), field)
        }
        XCTAssertEqual(problem(Support.wirePack(dailyCount: 0)), .emptyDaily)
    }

    func testAWrongTypeIsMalformedNotAMissingField() {
        var object = Support.wirePack()
        object["coupons"] = [["id": "c001", "title": "Kupón", "price": "forty"]]
        XCTAssertEqual(problem(object), .malformed(field: "coupons.[0].price"))
    }

    func testDuplicateIdIsNamed() {
        var object = Support.wirePack(dailyCount: 10)
        var daily = object["daily"] as! [[String: Any]]
        daily[8]["id"] = "d007"
        object["daily"] = daily
        XCTAssertEqual(problem(object), .duplicateId(list: "daily", id: "d007"))
    }

    func testInvalidIdsDatesTextsAndPrices() {
        var object = Support.wirePack()
        object["packId"] = "../other"
        XCTAssertEqual(problem(object), .invalidId(list: "packId", id: "../other"))

        object = Support.wirePack()
        object["startDate"] = "2030-02-30"
        XCTAssertEqual(problem(object), .invalidDate(field: "startDate"))

        object = Support.wirePack(dailyCount: 3)
        var daily = object["daily"] as! [[String: Any]]
        daily[1]["text"] = String(repeating: "❤", count: LovePackLimits.maxTextLength + 1)
        object["daily"] = daily
        XCTAssertEqual(problem(object), .textTooLong(list: "daily", id: "d002"))

        object = Support.wirePack()
        object["coupons"] = [["id": "c001", "title": "Kupón", "price": 0]]
        XCTAssertEqual(problem(object), .invalidPrice(id: "c001"))

        object = Support.wirePack()
        object["countdown"] = ["date": "příští rok", "title": "Svatba"]
        XCTAssertEqual(problem(object), .invalidDate(field: "countdown.date"))
    }

    func testTooManyItems() {
        XCTAssertEqual(problem(Support.wirePack(dailyCount: LovePackLimits.maxItemsPerList + 1)), .tooManyItems(list: "daily"))
    }

    func testPictureRefusals() {
        let small = Support.png(width: 10, height: 10)

        let tooMany = (0...LovePackLimits.maxPictures).map { Support.wireImage(id: "i\($0)", data: small) }
        XCTAssertEqual(problem(Support.wirePack(images: tooMany)), .tooManyPictures(count: LovePackLimits.maxPictures + 1))

        var badBase64 = Support.wireImage(id: "i001", data: small)
        badBase64["data"] = "***"
        XCTAssertEqual(problem(Support.wirePack(images: [badBase64])), .pictureNotDecodable(id: "i001"))

        let gif = Data("GIF89a-not-allowed".utf8)
        XCTAssertEqual(problem(Support.wirePack(images: [Support.wireImage(id: "i001", data: gif)])), .pictureWrongType(id: "i001"))

        var large = Support.png(width: 100, height: 100)
        large.append(Data(count: LovePackLimits.maxPictureBytes))
        XCTAssertEqual(problem(Support.wirePack(images: [Support.wireImage(id: "i001", data: large)])), .pictureTooLarge(id: "i001"))

        let wide = Support.png(width: 5000, height: 100)
        XCTAssertEqual(problem(Support.wirePack(images: [Support.wireImage(id: "i001", data: wide)])), .pictureTooBig(id: "i001"))

        let tall = Support.jpeg(width: 100, height: 4097)
        XCTAssertEqual(problem(Support.wirePack(images: [Support.wireImage(id: "i001", data: tall)])), .pictureTooBig(id: "i001"))

        let unknown = Support.wireImage(id: "i001", data: small, slots: ["loveCard", "wallpaper"])
        XCTAssertEqual(problem(Support.wirePack(images: [unknown])), .unknownSlot(id: "i001", slot: "wallpaper"))

        let badRank = Support.wireImage(id: "i001", data: small, slots: ["rankEmblem:hokage"])
        XCTAssertEqual(problem(Support.wirePack(images: [badRank])), .unknownSlot(id: "i001", slot: "rankEmblem:hokage"))
    }

    // MARK: Picture headers

    func testPictureHeaders() {
        XCTAssertEqual(LovePictureHeader.read(Support.png(width: 1200, height: 800)), LovePictureHeader(format: .png, width: 1200, height: 800))
        XCTAssertEqual(LovePictureHeader.read(Support.jpeg(width: 640, height: 480)), LovePictureHeader(format: .jpeg, width: 640, height: 480))
        XCTAssertNil(LovePictureHeader.read(Data([0xFF, 0xD8, 0xFF, 0xD9])))
        XCTAssertNil(LovePictureHeader.read(Data()))
    }

    // MARK: Diff

    func testDiffOfAFirstImportAnUpdateAndAnotherPack() throws {
        let current = try read(Support.wirePack(dailyCount: 12)).get().pack
        let update = try read(Support.wirePack(dailyCount: 52)).get().pack
        let other = try read(Support.wirePack(packId: "another-pack", dailyCount: 5)).get().pack

        let first = LovePackDiff.between(current: nil, incoming: current)
        XCTAssertEqual(first.kind, .firstImport)
        XCTAssertEqual(first.daily, .init(added: 12, removed: 0))

        let more = LovePackDiff.between(current: current, incoming: update)
        XCTAssertEqual(more.kind, .update)
        XCTAssertEqual(more.daily, .init(added: 40, removed: 0))
        XCTAssertTrue(more.coupons.isEmpty)
        XCTAssertFalse(more.countdownChanged)

        let replace = LovePackDiff.between(current: current, incoming: other)
        XCTAssertEqual(replace.kind, .otherPack)
        XCTAssertEqual(replace.totalDaily, 5)
    }

    // MARK: The builder's sample

    /// `tools/love-pack/sample.arclove`, written by the builder from
    /// `tools/love-pack/sample/` (CI checks it is up to date).
    func testTheBuildersSamplePackIsAcceptedByTheApp() throws {
        let sample = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FoodLogCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FoodLogCore
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("tools/love-pack/sample.arclove")
        let loaded = try LovePackReader.read(Data(contentsOf: sample)).get()

        XCTAssertEqual(loaded.pack.nickname, "Ninja")
        XCTAssertFalse(loaded.pack.daily.isEmpty)
        XCTAssertFalse(loaded.pack.images.isEmpty)
        XCTAssertEqual(loaded.pictures.count, loaded.pack.images.count)
    }
}
