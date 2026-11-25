// DailyMotivationTests.swift
//
// add-daily-motivation: the day -> line/photo rules and the bundled book.
// Pure logic against the real bundled JSON and a unique temp folder per test.

import XCTest
@testable import FoodLogCore

final class DailyMotivationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testSlotFollowsTheDayOfTheYear() {
        XCTAssertEqual(DailyMotivation.slot(for: date(2027, 1, 1), calendar: calendar), 0)
        XCTAssertEqual(DailyMotivation.slot(for: date(2027, 12, 31), calendar: calendar), 364)
        XCTAssertEqual(DailyMotivation.slot(for: date(2028, 12, 31), calendar: calendar), 364, "leap day 366 reuses the last line")
    }

    func testTwoDaysInARowNeverShareALine() {
        let book = MotivationQuoteBook.bundled()
        let monday = DailyMotivation.slot(for: date(2027, 3, 1), calendar: calendar)
        let tuesday = DailyMotivation.slot(for: date(2027, 3, 2), calendar: calendar)
        XCTAssertNotEqual(book.line(slot: monday, languageCode: "en"), book.line(slot: tuesday, languageCode: "en"))
    }

    func testPhotoIndexWrapsAndHandlesNoPhotos() {
        XCTAssertNil(DailyMotivation.photoIndex(slot: 10, count: 0))
        XCTAssertEqual(DailyMotivation.photoIndex(slot: 10, count: 3), 1)
        XCTAssertEqual(DailyMotivation.photoIndex(slot: 0, count: 1), 0)
    }

    func testTheBookHas365DistinctNonBlankLinesInBothLanguages() {
        let book = MotivationQuoteBook.bundled()
        XCTAssertEqual(book.entries.count, DailyMotivation.lineCount)
        XCTAssertEqual(Set(book.entries.map(\.en)).count, book.entries.count, "no English line repeats")
        XCTAssertEqual(Set(book.entries.map(\.cs)).count, book.entries.count, "no Czech line repeats")
        for entry in book.entries {
            XCTAssertFalse(entry.en.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(entry.cs.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testLanguagePicksCzechOrEnglish() {
        let book = MotivationQuoteBook(entries: [.init(en: "Go", cs: "Jdi")])
        XCTAssertEqual(book.line(slot: 0, languageCode: "cs"), "Jdi")
        XCTAssertEqual(book.line(slot: 0, languageCode: "de"), "Go")
        XCTAssertNil(MotivationQuoteBook(entries: []).line(slot: 0, languageCode: "en"))
    }

    func testPhotoFolderListsOnlyImagesSortedAndSurvivesAMissingFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("motivation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(MotivationPhotoFolder.photoURLs(in: directory), [])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["b.JPG", "a.png", "notes.txt", ".hidden.jpg"] {
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        XCTAssertEqual(MotivationPhotoFolder.photoURLs(in: directory).map(\.lastPathComponent), ["a.png", "b.JPG"])
    }
}
