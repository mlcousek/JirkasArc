// WorkoutTrackerTests.swift
//
// add-workout-tracker: the exercise catalog (the bundled JSON, name matching
// in both languages) and the set log (replace, clear, "last time"), against
// the real store pointed at a unique temp file per test.

import XCTest
@testable import FoodLogCore

final class WorkoutTrackerTests: XCTestCase {
    private func tempStore() -> WorkoutLogStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-log-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return WorkoutLogStore(fileURL: url)
    }

    // MARK: Catalog

    func testBundledCatalogIsWellFormed() {
        let catalog = ExerciseCatalog.bundled()
        XCTAssertGreaterThanOrEqual(catalog.exercises.count, 20)
        XCTAssertEqual(Set(catalog.exercises.map(\.id)).count, catalog.exercises.count, "ids are unique")
        for exercise in catalog.exercises {
            XCTAssertFalse(exercise.cues.isEmpty, exercise.id)
            XCTAssertFalse(exercise.images.isEmpty, "\(exercise.id) has no image")
        }
    }

    func testMatchesNamesInEnglishAndCzechIgnoringCaseAndDiacritics() {
        let catalog = ExerciseCatalog.bundled()
        XCTAssertEqual(catalog.match(name: "Bench press")?.id, "bench-press")
        XCTAssertEqual(catalog.match(name: "TLAK NA LAVICI")?.id, "bench-press")
        XCTAssertEqual(catalog.match(name: "Mrtvy tah")?.id, "deadlift", "diacritics folded")
        XCTAssertEqual(catalog.match(name: "Split squat")?.id, "split-squat")
        XCTAssertEqual(catalog.match(name: "Seated calf raise")?.id, "seated-calf-raise")
    }

    func testTheLongestAliasWinsAndAWordInsideALongerNameStillMatches() {
        let catalog = ExerciseCatalog.bundled()
        XCTAssertEqual(catalog.match(name: "Romanian deadlift")?.id, "romanian-deadlift", "not plain deadlift")
        XCTAssertEqual(catalog.match(name: "Paused barbell bench press (3 s)")?.id, "bench-press")
    }

    func testAnUnknownExerciseIsNotMatchedButStillGetsAStableKey() {
        let catalog = ExerciseCatalog.bundled()
        XCTAssertNil(catalog.match(name: "Zercher carry"))
        XCTAssertEqual(catalog.key(forName: "Zercher  Carry!"), "zercher carry")
        XCTAssertNil(catalog.match(name: "   "))
    }

    func testSearchURLCarriesTheName() {
        let url = ExerciseCatalog.searchURL(forName: "Split squat")
        XCTAssertEqual(url?.host, "www.youtube.com")
        XCTAssertTrue(url?.absoluteString.contains("Split") == true)
    }

    func testFieldTextReadsDecimalCommasAndBlanks() {
        XCTAssertEqual(SetEntryText.weight("62,5"), 62.5)
        XCTAssertEqual(SetEntryText.weight(" 60 "), 60)
        XCTAssertNil(SetEntryText.weight(""))
        XCTAssertNil(SetEntryText.weight("abc"))
        XCTAssertNil(SetEntryText.weight("-5"))
        XCTAssertEqual(SetEntryText.reps("8"), 8)
        XCTAssertNil(SetEntryText.reps("8.5"))
        XCTAssertEqual(SetEntryText.text(weight: 60), "60")
        XCTAssertEqual(SetEntryText.text(weight: 62.5), "62.5")
        XCTAssertEqual(SetEntryText.text(weight: nil), "")
    }

    // MARK: Log

    func testRecordReplaceAndClearASet() async throws {
        let store = tempStore()
        var sets = try await store.record(session: "s1", exerciseKey: "bench-press", setNumber: 1, weightKg: 60, reps: 8)
        XCTAssertEqual(sets.map(\.weightKg), [60])

        sets = try await store.record(session: "s1", exerciseKey: "bench-press", setNumber: 1, weightKg: 62.5, reps: 8)
        XCTAssertEqual(sets.count, 1, "the same set is replaced, not added")
        XCTAssertEqual(sets.first?.weightKg, 62.5)

        sets = try await store.record(session: "s1", exerciseKey: "bench-press", setNumber: 1, weightKg: nil, reps: nil)
        XCTAssertEqual(sets, [], "clearing both fields removes the set")
    }

    func testSetsSurviveReopeningTheStore() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-log-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try await WorkoutLogStore(fileURL: url).record(session: "s1", exerciseKey: "deadlift", setNumber: 2, weightKg: 100, reps: 5)
        let reopened = await WorkoutLogStore(fileURL: url).sets(session: "s1")
        XCTAssertEqual(reopened.map(\.reps), [5])
        XCTAssertEqual(reopened.first?.setNumber, 2)
    }

    func testPreviousIsTheLatestOtherSession() async throws {
        let store = tempStore()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.record(session: "old", exerciseKey: "squat", setNumber: 1, weightKg: 80, reps: 5, now: day)
        try await store.record(session: "recent", exerciseKey: "squat", setNumber: 1, weightKg: 90, reps: 5, now: day.addingTimeInterval(86_400))
        try await store.record(session: "recent", exerciseKey: "squat", setNumber: 2, weightKg: 92.5, reps: 4, now: day.addingTimeInterval(86_500))
        try await store.record(session: "today", exerciseKey: "squat", setNumber: 1, weightKg: 95, reps: 5, now: day.addingTimeInterval(172_800))

        let previous = await store.previous(exerciseKey: "squat", excluding: "today")
        XCTAssertEqual(previous.map(\.weightKg), [90, 92.5])
        let none = await store.previous(exerciseKey: "bench", excluding: "today")
        XCTAssertEqual(none, [])
    }
}
