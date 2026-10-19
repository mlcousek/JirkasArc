// LoveStoreTests.swift
//
// add-partner-love-theme D1, spec love-pack: importing stores the pack and
// its pictures, a re-import of the same pack keeps her state, another pack
// starts a new one, removing the pack keeps the state, and backups carry
// the texts and the state but not the pictures. A real LoveStore on a
// fresh temp directory per test.

import XCTest
@testable import FoodLogCore

final class LoveStoreTests: XCTestCase {
    private typealias Support = LoveTestSupport

    private func makeStore() -> (LoveStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("love-store-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (LoveStore(directory: directory), directory)
    }

    private func importPack(_ store: LoveStore, _ object: [String: Any], on day: String = "2030-03-14") async throws -> LovePackDiff {
        let preview = try await store.preview(importing: Support.data(object)).get()
        try await store.apply(preview, now: Support.date(day, 12, 0), calendar: Support.prague)
        return preview.diff
    }

    func testImportStoresThePackAndItsPictures() async throws {
        let (store, directory) = makeStore()
        let png = Support.png(width: 100, height: 100)

        let diff = try await importPack(store, Support.wirePack(images: [Support.wireImage(id: "i001", data: png)]))

        XCTAssertEqual(diff.kind, .firstImport)
        let pack = await store.pack()
        let state = await store.state()
        XCTAssertEqual(pack?.daily.count, 30)
        XCTAssertEqual(state?.importDay, "2030-03-14")
        let pictureURL = await store.pictureURL(id: "i001")
        XCTAssertEqual(pictureURL.flatMap { try? Data(contentsOf: $0) }, png)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("love-pack.json").path))
        let missing = await store.isMissingPictures()
        XCTAssertFalse(missing)
    }

    func testAnInvalidFileChangesNothing() async throws {
        let (store, _) = makeStore()
        _ = try await importPack(store, Support.wirePack(dailyCount: 5))

        var broken = Support.wirePack(dailyCount: 10)
        var daily = broken["daily"] as! [[String: Any]]
        daily[8]["id"] = "d007"
        broken["daily"] = daily
        let result = await store.preview(importing: Support.data(broken))

        guard case .failure(let problem) = result else { return XCTFail("accepted") }
        XCTAssertEqual(problem, .duplicateId(list: "daily", id: "d007"))
        let pack = await store.pack()
        XCTAssertEqual(pack?.daily.count, 5)
    }

    func testAReimportKeepsWhatWasSeen() async throws {
        let (store, _) = makeStore()
        _ = try await importPack(store, Support.wirePack(dailyCount: 12))
        try await store.update { pack, state in
            LoveReveal.catchUp(pack: pack, state: &state, now: Support.date("2030-03-14", 13, 0), calendar: Support.prague)
            if let id = state.revealed["2030-03-14"]?.messageId { state.setFavorite(id, true) }
            state.earnHearts(achievementId: "p.firstnote", amount: 5, at: Date())
        }
        let before = await store.state()

        let diff = try await importPack(store, Support.wirePack(dailyCount: 52), on: "2030-03-20")

        XCTAssertEqual(diff.kind, .update)
        XCTAssertEqual(diff.daily, .init(added: 40, removed: 0))
        let after = await store.state()
        XCTAssertEqual(after?.importDay, "2030-03-14", "an update is not a new import")
        XCTAssertEqual(after?.revealed, before?.revealed)
        XCTAssertEqual(after?.favorites, before?.favorites)
        XCTAssertEqual(after?.heartBalance, 5)
    }

    func testAnotherPackStartsANewState() async throws {
        let (store, _) = makeStore()
        _ = try await importPack(store, Support.wirePack(dailyCount: 12))
        try await store.update { _, state in state.earnHearts(achievementId: "p.genin", amount: 5, at: Date()) }

        let diff = try await importPack(store, Support.wirePack(packId: "another-pack", dailyCount: 3), on: "2030-04-01")

        XCTAssertEqual(diff.kind, .otherPack)
        let state = await store.state()
        XCTAssertEqual(state?.packId, "another-pack")
        XCTAssertEqual(state?.importDay, "2030-04-01")
        XCTAssertEqual(state?.heartBalance, 0)
    }

    func testRemovingThePackKeepsTheStateForItsReturn() async throws {
        let (store, _) = makeStore()
        let png = Support.png(width: 10, height: 10)
        let object = Support.wirePack(images: [Support.wireImage(id: "i001", data: png)])
        _ = try await importPack(store, object)
        try await store.update { _, state in state.setFavorite("d003", true) }

        try await store.removePack()
        let removedPack = await store.pack()
        let hiddenState = await store.state()
        let removedPicture = await store.pictureURL(id: "i001")
        XCTAssertNil(removedPack)
        XCTAssertNil(hiddenState, "no state is handed out without its pack")
        XCTAssertNil(removedPicture)

        _ = try await importPack(store, object, on: "2030-05-01")
        let back = await store.state()
        XCTAssertEqual(back?.favorites, ["d003"])
        XCTAssertEqual(back?.importDay, "2030-03-14")
    }

    func testBackupsCarryTheTextsAndTheStateButNotThePictures() {
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "FoodLogCore/Love/love-pack.json"))
        XCTAssertTrue(BackupExclusions.includesFile(relativePath: "FoodLogCore/Love/love-state.json"))
        XCTAssertFalse(BackupExclusions.includesFile(relativePath: "FoodLogCore/Love/Images/i001.png"))
        XCTAssertFalse(BackupExclusions.includesFile(relativePath: "FoodLogCore/Love/Images/i002.jpg"))
        XCTAssertEqual(StoreCatalog.entry(forRelativePath: "FoodLogCore/Love/love-state.json")?.id, "foodlog.love")
    }

    func testNoStateIsWrittenWithoutAPack() async throws {
        let (store, directory) = makeStore()
        let result = try await store.update { _, state in state.setFavorite("d001", true) }
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("love-state.json").path))
    }
}
