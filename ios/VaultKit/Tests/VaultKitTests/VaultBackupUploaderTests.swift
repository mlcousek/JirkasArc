// VaultBackupUploaderTests.swift
//
// add-vault-backup task 3.5 (design D3, D5, D6, D9): one backup upload and
// its bookkeeping, over the in-memory transport and over the GitHub client
// behind the URLProtocol stub -- created; already there (done once the file
// is seen, never compared, never overwritten); a 422 with no file there (a
// failure, not a done week); the lost answer that heals on the next
// attempt; too large (nothing sent); five server errors end the week;
// "Back up now" in a fresh week, in a done week and when the week's file is
// there unknown to the phone; a rate limit pauses the connection; a
// rejected token is NOT written into the connection's status; another
// device's folder is refused.
//
// The "archive" here is any bytes: VaultKit does not know what a backup
// holds. Everything is synthetic (`example-owner/example-vault`,
// `ios-0000abcd`, dates in 2030).

import XCTest
@testable import VaultKit

final class VaultBackupUploaderTests: XCTestCase {
    private let device = TestSupport.deviceID
    private let archive = Data("synthetic backup archive bytes".utf8)
    private let hour: TimeInterval = 60 * 60

    private struct Rig {
        let uploader: VaultBackupUploader
        let states: VaultBackupStateStore
        let status: VaultStatusStore
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }

    /// Monday of 2030-W42.
    private var monday: Date { date("2030-10-14T06:00:00Z") }

    private var weeklyPath: HubPath { HubPath("backups/ios-0000abcd/2030/2030-W42.json.gz")! }

    private func makeRig(transport: VaultTransport, maxBytes: Int = VaultBackupSchedule.maxBytes) throws -> Rig {
        let directory = try makeTemporaryDirectory()
        let states = VaultBackupStateStore(directory: directory)
        let status = VaultStatusStore(directory: directory)
        let uploader = VaultBackupUploader(transport: transport, stateStore: states, statusStore: status, maxBytes: maxBytes)
        return Rig(uploader: uploader, states: states, status: status)
    }

    // MARK: - Created

    func testAutomaticUploadCreatesTheWeeksFile() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)

        let dueBefore = await rig.uploader.isDue(now: monday)
        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()
        let status = await rig.status.current()
        let dueAfter = await rig.uploader.isDue(now: monday.addingTimeInterval(3 * 24 * hour))
        let dueNextWeek = await rig.uploader.isDue(now: monday.addingTimeInterval(7 * 24 * hour))

        XCTAssertTrue(dueBefore)
        XCTAssertEqual(result, .uploaded(path: weeklyPath, byteCount: archive.count))
        XCTAssertEqual(transport.file(weeklyPath), archive)
        XCTAssertEqual(transport.createCount, 1)
        XCTAssertEqual(transport.fetchCount, 0, "a created file is not read back")
        XCTAssertEqual(state.lastSuccessAt, monday)
        XCTAssertEqual(state.lastSuccessWeek, "2030-W42")
        XCTAssertEqual(state.lastSuccessPath, weeklyPath)
        XCTAssertEqual(state.lastSuccessByteCount, archive.count)
        XCTAssertNil(state.lastFailure)
        XCTAssertEqual(status.lastSuccessAt, monday, "a backup that landed moves Last sync")
        XCTAssertEqual(status.lastOutcome, .success)
        XCTAssertFalse(dueAfter)
        XCTAssertTrue(dueNextWeek)
    }

    // MARK: - Already there

    func testAFileAlreadyThereIsDoneAndIsNotTouched() async throws {
        let transport = InMemoryVaultTransport()
        let existing = Data("an earlier upload".utf8)
        transport.put(weeklyPath, existing)
        let rig = try makeRig(transport: transport)

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()
        let due = await rig.uploader.isDue(now: monday.addingTimeInterval(2 * hour))

        XCTAssertEqual(result, .alreadyInVault(path: weeklyPath))
        XCTAssertEqual(transport.file(weeklyPath), existing, "never overwritten, whatever it holds")
        XCTAssertEqual(transport.createCount, 1)
        XCTAssertEqual(transport.fetchCount, 1, "one look that it is really there")
        XCTAssertEqual(state.lastSuccessWeek, "2030-W42")
        XCTAssertNil(state.lastSuccessByteCount)
        XCTAssertNil(state.lastFailure)
        XCTAssertFalse(due)
    }

    func testALostAnswerHealsOnTheNextAttempt() async throws {
        let transport = InMemoryVaultTransport()
        transport.loseNextCreateResponse = true
        let rig = try makeRig(transport: transport)

        // The upload lands; its answer does not.
        let first = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let afterFirst = await rig.uploader.state()
        let dueSoon = await rig.uploader.isDue(now: monday.addingTimeInterval(30 * 60))
        let dueLater = await rig.uploader.isDue(now: monday.addingTimeInterval(hour))

        XCTAssertEqual(first, .failed(.vault(.offline)))
        XCTAssertEqual(transport.file(weeklyPath), archive)
        XCTAssertNil(afterFirst.lastSuccessWeek)
        XCTAssertEqual(afterFirst.lastFailure, .vault(.offline))
        XCTAssertEqual(afterFirst.attemptCount, 0, "offline spends no attempt")
        XCTAssertFalse(dueSoon)
        XCTAssertTrue(dueLater)

        // An hour later the data has moved on; the week's file is found.
        let newer = Data("a newer archive".utf8)
        let second = await rig.uploader.upload(newer, deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(hour))
        let afterSecond = await rig.uploader.state()

        XCTAssertEqual(second, .alreadyInVault(path: weeklyPath))
        XCTAssertEqual(transport.file(weeklyPath), archive, "the first upload stays")
        XCTAssertEqual(transport.createCount, 2)
        XCTAssertEqual(afterSecond.lastSuccessWeek, "2030-W42")
        XCTAssertNil(afterSecond.lastFailure)
    }

    // MARK: - The cap

    func testAnArchiveOverTheCapIsNotSent() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport, maxBytes: 10)

        let tooLarge = await rig.uploader.upload(Data(repeating: 0x41, count: 11), deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()

        XCTAssertEqual(tooLarge, .failed(.tooLarge(byteCount: 11, limit: 10)))
        XCTAssertEqual(transport.createCount, 0)
        XCTAssertNil(transport.file(weeklyPath))
        XCTAssertEqual(state.attemptCount, 1)
        XCTAssertEqual(state.lastFailure, .tooLarge(byteCount: 11, limit: 10))
        XCTAssertEqual(state.lastFailureAt, monday)

        // "Back up now" is held to the cap too.
        let byHand = await rig.uploader.upload(Data(repeating: 0x41, count: 11), deviceID: device, trigger: .manual, now: monday)
        XCTAssertEqual(byHand, .failed(.tooLarge(byteCount: 11, limit: 10)))
        XCTAssertEqual(transport.createCount, 0)

        // Exactly at the cap goes through.
        let atTheCap = await rig.uploader.upload(Data(repeating: 0x41, count: 10), deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(hour))
        XCTAssertEqual(atTheCap, .uploaded(path: weeklyPath, byteCount: 10))
    }

    // MARK: - Retries

    func testFiveServerErrorsEndTheWeekAndTheNextWeekStartsFresh() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)
        var now = monday

        for attempt in 1...5 {
            let due = await rig.uploader.isDue(now: now)
            XCTAssertTrue(due, "attempt \(attempt)")
            transport.failNextCreate(with: .serverError(status: 503))
            let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: now)
            XCTAssertEqual(result, .failed(.vault(.serverError(status: 503))))
            now = now.addingTimeInterval(hour)
        }
        let state = await rig.uploader.state()
        let dueSixth = await rig.uploader.isDue(now: now)
        let dueSunday = await rig.uploader.isDue(now: date("2030-10-20T22:00:00Z"))
        let dueNextMonday = await rig.uploader.isDue(now: date("2030-10-21T06:00:00Z"))

        XCTAssertEqual(state.attemptCount, 5)
        XCTAssertEqual(transport.createCount, 5)
        XCTAssertFalse(dueSixth)
        XCTAssertFalse(dueSunday)
        XCTAssertTrue(dueNextMonday)
        XCTAssertNil(transport.file(weeklyPath))

        // The next week's file is its own name.
        let nextWeek = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: date("2030-10-21T06:00:00Z"))
        XCTAssertEqual(nextWeek, .uploaded(path: HubPath("backups/ios-0000abcd/2030/2030-W43.json.gz")!, byteCount: archive.count))
    }

    func testAnAttemptThatNeverReachedTheNetworkKeepsTheInterval() async throws {
        let rig = try makeRig(transport: InMemoryVaultTransport())

        await rig.uploader.recordNotUploaded(.nothingToBackUp, now: monday)
        let afterEmpty = await rig.uploader.state()
        let dueSoon = await rig.uploader.isDue(now: monday.addingTimeInterval(20 * 60))
        let dueLater = await rig.uploader.isDue(now: monday.addingTimeInterval(hour))

        XCTAssertEqual(afterEmpty.lastFailure, .nothingToBackUp)
        XCTAssertEqual(afterEmpty.attemptCount, 0)
        XCTAssertEqual(afterEmpty.lastAttemptAt, monday)
        XCTAssertFalse(dueSoon)
        XCTAssertTrue(dueLater)

        await rig.uploader.recordNotUploaded(.archiveFailed, now: monday.addingTimeInterval(hour))
        let afterBroken = await rig.uploader.state()
        XCTAssertEqual(afterBroken.attemptCount, 1, "an archive that can't be built counts")
    }

    // MARK: - A state file that cannot be written

    /// Review of add-vault-backup: the state store logs a failed save and
    /// keeps its old state, and it refuses to save while its file exists
    /// but cannot be read. Judged by the stored state alone the backup
    /// would then be due on every foreground -- an archive and a multi-MB
    /// upload each time. The uploader's own memory of its last attempt and
    /// of a done week is the floor under that.
    ///
    /// A directory where the file should be makes every read fail with an
    /// error that is not "no such file" (the stand-in PersistedJSONTests
    /// uses for a locked file), so every save is refused.
    func testAStateThatCannotBeSavedStillKeepsTheHourAndTheDoneWeek() async throws {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(VaultBackupStateStore.fileName),
            withIntermediateDirectories: true
        )
        let transport = InMemoryVaultTransport()
        let uploader = VaultBackupUploader(
            transport: transport,
            stateStore: VaultBackupStateStore(directory: directory),
            statusStore: VaultStatusStore(directory: directory)
        )

        // A failure that cannot be saved.
        transport.failNextCreate(with: .serverError(status: 503))
        let dueBefore = await uploader.isDue(now: monday)
        let first = await uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let storedAfterFailure = await uploader.state()
        let dueSoon = await uploader.isDue(now: monday.addingTimeInterval(10 * 60))
        let dueAlmostAnHour = await uploader.isDue(now: monday.addingTimeInterval(59 * 60))
        let dueAfterAnHour = await uploader.isDue(now: monday.addingTimeInterval(hour))

        XCTAssertTrue(dueBefore)
        XCTAssertEqual(first, .failed(.vault(.serverError(status: 503))))
        XCTAssertEqual(storedAfterFailure, VaultBackupState(), "nothing could be saved: the stored state knows no attempt")
        XCTAssertFalse(dueSoon, "not due again on the next foreground")
        XCTAssertFalse(dueAlmostAnHour)
        XCTAssertTrue(dueAfterAnHour, "and not blocked for good either")

        // An attempt that never reached the network is remembered the same way.
        await uploader.recordNotUploaded(.archiveFailed, now: monday.addingTimeInterval(hour))
        let dueAfterBrokenArchive = await uploader.isDue(now: monday.addingTimeInterval(hour + 5 * 60))
        XCTAssertFalse(dueAfterBrokenArchive)

        // A success that cannot be saved: the week is done for this process.
        let second = await uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(2 * hour))
        let storedAfterSuccess = await uploader.state()
        let dueSameWeek = await uploader.isDue(now: monday.addingTimeInterval(30 * hour))
        let dueNextWeek = await uploader.isDue(now: monday.addingTimeInterval(7 * 24 * hour))

        XCTAssertEqual(second, .uploaded(path: weeklyPath, byteCount: archive.count))
        XCTAssertNil(storedAfterSuccess.lastSuccessWeek, "still nothing saved")
        XCTAssertFalse(dueSameWeek, "no second upload in a week this process saw done")
        XCTAssertTrue(dueNextWeek)
        XCTAssertEqual(transport.createCount, 2)

        // "Back up now" in that week goes to the time-stamped name, not to
        // the week's file again.
        let wednesday = date("2030-10-16T19:30:05Z")
        let byHand = await uploader.upload(archive, deviceID: device, trigger: .manual, now: wednesday)
        let manualPath = try XCTUnwrap(HubPath("backups/ios-0000abcd/2030/2030-W42-20301016T193005Z.json.gz"))
        XCTAssertEqual(byHand, .uploaded(path: manualPath, byteCount: archive.count))
        XCTAssertEqual(transport.fetchCount, 0, "no 422, so nothing was read back")
    }

    // MARK: - By hand

    func testBackUpNowInAFreshWeekWritesTheWeeksFile() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .manual, now: monday)
        let due = await rig.uploader.isDue(now: monday.addingTimeInterval(2 * hour))

        XCTAssertEqual(result, .uploaded(path: weeklyPath, byteCount: archive.count))
        XCTAssertFalse(due, "the automatic backup does not run again that week")
    }

    func testBackUpNowInADoneWeekWritesATimeStampedSecondFile() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)
        _ = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)

        let wednesday = date("2030-10-16T19:30:05Z")
        let newer = Data("a newer archive".utf8)
        let result = await rig.uploader.upload(newer, deviceID: device, trigger: .manual, now: wednesday)
        let state = await rig.uploader.state()
        let manualPath = try XCTUnwrap(HubPath("backups/ios-0000abcd/2030/2030-W42-20301016T193005Z.json.gz"))

        XCTAssertEqual(result, .uploaded(path: manualPath, byteCount: newer.count))
        XCTAssertEqual(transport.file(manualPath), newer)
        XCTAssertEqual(transport.file(weeklyPath), archive, "the week's file is unchanged")
        XCTAssertEqual(transport.createCount, 2)
        XCTAssertEqual(state.lastSuccessPath, manualPath)
        XCTAssertEqual(state.lastSuccessAt, wednesday)
        XCTAssertEqual(state.lastSuccessByteCount, newer.count)

        // The automatic backup in the same done week sends nothing at all:
        // it is not due (the caller asks first).
        let due = await rig.uploader.isDue(now: wednesday.addingTimeInterval(2 * hour))
        XCTAssertFalse(due)
    }

    func testBackUpNowGoesOnWhenTheWeeksFileTurnsOutToBeThere() async throws {
        let transport = InMemoryVaultTransport()
        let existing = Data("an earlier upload".utf8)
        transport.put(weeklyPath, existing)
        let rig = try makeRig(transport: transport)

        let tuesday = date("2030-10-15T07:00:00Z")
        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .manual, now: tuesday)
        let state = await rig.uploader.state()
        let manualPath = try XCTUnwrap(HubPath("backups/ios-0000abcd/2030/2030-W42-20301015T070000Z.json.gz"))

        XCTAssertEqual(result, .uploaded(path: manualPath, byteCount: archive.count))
        XCTAssertEqual(transport.file(weeklyPath), existing)
        XCTAssertEqual(transport.file(manualPath), archive)
        XCTAssertEqual(transport.createCount, 2)
        XCTAssertEqual(state.lastSuccessWeek, "2030-W42")
        XCTAssertEqual(state.lastSuccessPath, manualPath)

        // The same second again: that copy is already there.
        let again = await rig.uploader.upload(archive, deviceID: device, trigger: .manual, now: tuesday)
        XCTAssertEqual(again, .alreadyInVault(path: manualPath))
    }

    // MARK: - The connection's status

    func testARateLimitPausesTheConnection() async throws {
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)
        let until = monday.addingTimeInterval(120)
        transport.failNextCreate(with: .rateLimited(until: until))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()
        let status = await rig.status.current()

        XCTAssertEqual(result, .failed(.vault(.rateLimited(until: until))))
        XCTAssertEqual(state.attemptCount, 0, "a rate limit spends no attempt")
        XCTAssertEqual(status.rateLimitedUntil, until, "every vault request waits")
        XCTAssertNil(status.blockedBy)
    }

    func testARejectedTokenIsNotWrittenIntoTheStatus() async throws {
        // A token that can read but not write must not block the plan: the
        // app asks for the forced plan fetch instead (design D9).
        let transport = InMemoryVaultTransport()
        let rig = try makeRig(transport: transport)
        transport.failNextCreate(with: .authFailed(.forbidden))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()
        let status = await rig.status.current()

        XCTAssertEqual(result, .failed(.vault(.authFailed(.forbidden))))
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertEqual(state.lastFailure, .vault(.authFailed(.forbidden)))
        XCTAssertNil(status.blockedBy)
        XCTAssertNil(status.lastOutcome)
    }

    func testAnotherDevicesFolderIsRefusedWithNothingSent() async throws {
        let transport = InMemoryVaultTransport() // its policy knows ios-0000abcd only
        let rig = try makeRig(transport: transport)

        let result = await rig.uploader.upload(archive, deviceID: TestSupport.otherDeviceID, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()

        XCTAssertEqual(result, .failed(.vault(.refusedByPolicy)))
        XCTAssertEqual(transport.createCount, 0)
        XCTAssertEqual(state.attemptCount, 1)
    }

    // MARK: - Over the GitHub client

    func testCreateOverGitHubSendsOnePutToTheHubPath() async throws {
        StubURLProtocol.reset(replies: [.status(201)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)

        XCTAssertEqual(result, .uploaded(path: weeklyPath, byteCount: archive.count))
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT"])
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertEqual(request.url?.path, "/repos/example-owner/example-vault/contents/Sport/Training/_hub/backups/ios-0000abcd/2030/2030-W42.json.gz")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(body["message"], "hub: ios-0000abcd backup 2030-W42.json.gz (\(archive.count) bytes)")
        XCTAssertEqual(body["branch"], "main")
        XCTAssertEqual(body["content"].flatMap { Data(base64Encoded: $0) }, archive)
        XCTAssertNil(body["sha"], "no sha: create-only")
    }

    func testAlreadyExistsOverGitHubIsDoneOnceTheFileIsSeen() async throws {
        // 422, then the file is there (with other content: not compared).
        StubURLProtocol.reset(replies: [.status(422), .status(200, body: Data("an earlier upload".utf8))])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()

        XCTAssertEqual(result, .alreadyInVault(path: weeklyPath))
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT", "GET"])
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.path, "/repos/example-owner/example-vault/contents/Sport/Training/_hub/backups/ios-0000abcd/2030/2030-W42.json.gz")
        XCTAssertEqual(state.lastSuccessWeek, "2030-W42")
        XCTAssertNil(state.lastFailure)
    }

    func testA422WithNoFileThereIsAFailureNotADoneWeek() async throws {
        // GitHub answers 422 to a create for more than "it exists"
        // (validation, abuse detection). A week called done with no file in
        // the vault would be a backup that fails silently.
        StubURLProtocol.reset(replies: [.status(422), .status(404)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let state = await rig.uploader.state()
        let status = await rig.status.current()
        let dueLater = await rig.uploader.isDue(now: monday.addingTimeInterval(hour))

        XCTAssertEqual(result, .failed(.vault(.unexpected(status: 422))))
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT", "GET"])
        XCTAssertNil(state.lastSuccessWeek, "not done")
        XCTAssertNil(state.lastSuccessAt)
        XCTAssertEqual(state.lastFailure, .vault(.unexpected(status: 422)))
        XCTAssertEqual(state.attemptCount, 1)
        XCTAssertNil(status.lastSuccessAt)
        XCTAssertTrue(dueLater, "tried again an hour later")
    }

    func testAnUnconfirmedExistingFileIsTriedAgainLater() async throws {
        // 422, and the look that would confirm it has no network.
        StubURLProtocol.reset(replies: [.status(422), .failure(.notConnectedToInternet)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let result = await rig.uploader.upload(archive, deviceID: device, trigger: .manual, now: monday)
        let state = await rig.uploader.state()

        XCTAssertEqual(result, .failed(.vault(.offline)))
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT", "GET"], "no time-stamped upload on an unconfirmed week")
        XCTAssertNil(state.lastSuccessWeek)
        XCTAssertEqual(state.attemptCount, 0)
    }

    func testFailuresOverGitHubAreClassified() async throws {
        StubURLProtocol.reset(replies: [.status(503), .failure(.notConnectedToInternet), .status(401)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let server = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let offline = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(hour))
        let auth = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(2 * hour))
        let state = await rig.uploader.state()
        let status = await rig.status.current()

        XCTAssertEqual(server, .failed(.vault(.serverError(status: 503))))
        XCTAssertEqual(offline, .failed(.vault(.offline)))
        XCTAssertEqual(auth, .failed(.vault(.authFailed(.tokenRejected))))
        XCTAssertEqual(state.attemptCount, 1, "only the server error counts")
        XCTAssertNil(status.blockedBy)
    }

    /// Review of add-vault-backup: a 409 is the phone's own event upload
    /// committing at the same moment, a cancelled request is iOS ending the
    /// background refresh. Neither uses up the week.
    func testAConflictAndACancelledRequestSpendNoAttempt() async throws {
        StubURLProtocol.reset(replies: [.status(409), .failure(.cancelled)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        let conflict = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        let afterConflict = await rig.uploader.state()
        let cancelled = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday.addingTimeInterval(hour))
        let afterCancelled = await rig.uploader.state()
        let dueSoon = await rig.uploader.isDue(now: monday.addingTimeInterval(hour + 20 * 60))
        let dueLater = await rig.uploader.isDue(now: monday.addingTimeInterval(2 * hour))

        XCTAssertEqual(conflict, .failed(.vault(.conflict)))
        XCTAssertEqual(afterConflict.attemptCount, 0)
        XCTAssertEqual(cancelled, .failed(.vault(.transportError(code: VaultBackupFailure.cancelledTransportCode))))
        XCTAssertEqual(afterCancelled.attemptCount, 0)
        XCTAssertNil(afterCancelled.lastSuccessWeek)
        XCTAssertFalse(dueSoon, "the hour between attempts still holds")
        XCTAssertTrue(dueLater)
    }

    func testBackupLogLinesCarryNoRepositoryOrToken() async throws {
        let log = recordVaultLog()
        StubURLProtocol.reset(replies: [.status(201), .status(500)])
        let rig = try makeRig(transport: GitHubVaultTransport(api: TestSupport.makeClient()))

        _ = await rig.uploader.upload(archive, deviceID: device, trigger: .automatic, now: monday)
        _ = await rig.uploader.upload(archive, deviceID: device, trigger: .manual, now: monday.addingTimeInterval(hour))

        XCTAssertTrue(log.lines.contains { $0.contains("backup backups/ios-0000abcd/2030/2030-W42.json.gz: created") })
        for line in log.lines {
            XCTAssertFalse(line.contains(TestSupport.owner), line)
            XCTAssertFalse(line.contains(TestSupport.repositoryName), line)
            XCTAssertFalse(line.contains(TestSupport.plantedTokenString), line)
            XCTAssertFalse(line.contains("api.github.com"), line)
        }
    }
}
