// FoodLogDeletionQueueTests.swift
//
// improve-food-day-flow (E2, spec food-log-delete-sync): the queue of
// deletes of entries that are in Garmin -- durable, retried like every other
// queue, tied to one Garmin account, and a 404 is success. Real `Outbox` and
// store on unique temp files; Garmin is a scripted fake that never touches
// the network. Synthetic ids only.

import XCTest
@testable import GarminKit

final class FoodLogDeletionQueueTests: XCTestCase {
    // MARK: - Helpers

    /// Mutable account key for an outbox's provider.
    private final class KeyBox: @unchecked Sendable {
        var value: String?
        init(_ value: String?) { self.value = value }
    }

    private struct Queue {
        let outbox: Outbox
        let entriesURL: URL
        let deletionsURL: URL
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day = "2026-10-04"

    private func makeQueue(maxAttempts: Int = 5, accountKey: @escaping AccountScope.Provider = { nil }) throws -> Queue {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("food-deletions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let entriesURL = dir.appendingPathComponent("entries.json")
        let deletionsURL = dir.appendingPathComponent("deletions.json")
        return Queue(
            outbox: open(entriesURL: entriesURL, deletionsURL: deletionsURL, maxAttempts: maxAttempts, accountKey: accountKey),
            entriesURL: entriesURL,
            deletionsURL: deletionsURL
        )
    }

    /// A fresh `Outbox` over the same two files: a relaunch.
    private func open(entriesURL: URL, deletionsURL: URL, maxAttempts: Int = 5, accountKey: @escaping AccountScope.Provider = { nil }) -> Outbox {
        Outbox(
            store: OutboxStore(fileURL: entriesURL),
            deletions: FoodLogDeletionStore(fileURL: deletionsURL),
            maxAttempts: maxAttempts,
            accountKey: accountKey
        )
    }

    // MARK: - Queuing

    func testQueuingIsDurableAndMakesNoRequest() async throws {
        let queue = try makeQueue()
        let deleter = ScriptedDeleter()

        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)

        XCTAssertEqual(queued.state, .pending)
        XCTAssertEqual(queued.attemptCount, 0)
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 0, "queuing never touches Garmin")

        // A relaunch reads the very same record back from the file.
        let reopened = open(entriesURL: queue.entriesURL, deletionsURL: queue.deletionsURL)
        let afterRelaunch = await reopened.allDeletions()
        XCTAssertEqual(afterRelaunch, [queued])
    }

    func testARecordWithOnlyTheOriginalFieldsStillDecodes() async throws {
        let queue = try makeQueue()
        let json = """
        [ { "id": "3C4D5E6F-7A8B-4C9D-8E0F-1A2B3C4D5E11", "date": "2026-10-04", "logId": "log-old",
            "state": "pending", "attemptCount": 2, "createdAt": 812794500, "nextAttemptAt": 812794500 } ]
        """
        try Data(json.utf8).write(to: queue.deletionsURL)

        let deletions = await queue.outbox.allDeletions()

        XCTAssertEqual(deletions.map(\.logId), ["log-old"])
        XCTAssertEqual(deletions.first?.attemptCount, 2)
        XCTAssertNil(deletions.first?.accountKey)
        XCTAssertNil(deletions.first?.deliveredAt)
        XCTAssertNil(deletions.first?.lastError)
    }

    func testTheSameEntryIsQueuedOnce() async throws {
        let queue = try makeQueue()
        let first = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let second = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now.addingTimeInterval(5))
        try await queue.outbox.queueDeletion(logId: "log-1", date: "2026-10-03", now: now)

        XCTAssertEqual(second.id, first.id, "the record already queued is returned")
        let all = await queue.outbox.allDeletions()
        XCTAssertEqual(all.count, 2, "another day's entry with the same id is its own delete")
    }

    func testAnEntryWithoutAnIdOrADayIsRefused() async throws {
        let queue = try makeQueue()
        do {
            try await queue.outbox.queueDeletion(logId: "", date: day, now: now)
            XCTFail("expected a throw")
        } catch let error as FoodLogDeletionError {
            XCTAssertEqual(error, .missingIdentifier)
        }
        let all = await queue.outbox.allDeletions()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Delivery

    func testAConfirmedDeleteIsKeptAsSentWithTheRouteItUsed() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter()

        let result = await queue.outbox.drainDeletions(using: deleter, now: now)

        XCTAssertEqual(result.delivered.map(\.logId), ["log-1"])
        XCTAssertTrue(result.failed.isEmpty)
        let calls = await deleter.deletes
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.logIds, ["log-1"])
        XCTAssertEqual(calls.first?.date, day)
        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.sent])
        XCTAssertEqual(stored.first?.deliveredAt, now)
    }

    func testA404MeansTheEntryIsAlreadyGone() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminClientError.httpError(statusCode: 404, body: nil))])

        let result = await queue.outbox.drainDeletions(using: deleter, now: now)

        XCTAssertEqual(result.delivered.count, 1, "already gone is the goal met")
        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.sent])
        XCTAssertEqual(stored.first?.attemptCount, 0)

        // And it is not sent again.
        _ = await queue.outbox.drainDeletions(using: deleter, now: now.addingTimeInterval(60))
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 1)
    }

    func testBeingOfflineIsNotAnAttempt() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        try await queue.outbox.queueDeletion(logId: "log-2", date: day, now: now)
        let offline = URLError(.notConnectedToInternet)
        let deleter = ScriptedDeleter([.fail(offline), .fail(offline), .fail(offline)])

        for cycle in 0..<3 {
            let result = await queue.outbox.drainDeletions(using: deleter, now: now.addingTimeInterval(Double(cycle)))
            XCTAssertTrue(result.delivered.isEmpty)
            XCTAssertTrue(result.failed.isEmpty)
        }

        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.pending, .pending])
        XCTAssertEqual(stored.map(\.attemptCount), [0, 0], "no attempt is counted without a connection")
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 3, "one request per cycle: the cycle stops at the first offline answer")
    }

    func testARateLimitStopsTheCycleAndHonoursRetryAfter() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        try await queue.outbox.queueDeletion(logId: "log-2", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminClientError.rateLimited(retryAfterSeconds: 30))])

        let result = await queue.outbox.drainDeletions(using: deleter, now: now)

        XCTAssertTrue(result.stoppedDueToRateLimit)
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 1, "the second delete is not attempted in this cycle")
        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.pending, .pending])
        XCTAssertEqual(stored.first?.attemptCount, 1)
        XCTAssertEqual(stored.first?.nextAttemptAt, now.addingTimeInterval(30))

        // Not due again before Retry-After has passed.
        _ = await queue.outbox.drainDeletions(using: deleter, now: now.addingTimeInterval(10))
        let stillWaiting = await queue.outbox.allDeletions()
        XCTAssertEqual(stillWaiting.first?.state, .pending)
    }

    func testAnAuthFailureStopsTheCycleWithoutAnAttempt() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminAuthError.longLivedTokenExpired)])

        let result = await queue.outbox.drainDeletions(using: deleter, now: now)

        XCTAssertEqual(result.authOutcome, .longLivedTokenExpired)
        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.pending])
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }

    func testARefusedDeleteGivesUpAtOnce() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminClientError.httpError(statusCode: 403, body: nil))])

        let result = await queue.outbox.drainDeletions(using: deleter, now: now)

        XCTAssertEqual(result.failed.map(\.logId), ["log-1"])
        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.failed])
        XCTAssertEqual(stored.first?.attemptCount, 1)
        XCTAssertTrue(stored.first?.needsManualRetry ?? false)
    }

    func testAServerErrorIsRetriedAndGivesUpAfterMaxAttempts() async throws {
        let queue = try makeQueue(maxAttempts: 5)
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let serverError = GarminClientError.httpError(statusCode: 500, body: nil)
        let script = [ScriptedDeleter.Outcome](repeating: .fail(serverError), count: 10)
        let deleter = ScriptedDeleter(script)

        var clock = now
        for attempt in 1...5 {
            let result = await queue.outbox.drainDeletions(using: deleter, now: clock, randomJitter: { 1 })
            let stored = await queue.outbox.allDeletions()
            XCTAssertEqual(stored.first?.attemptCount, attempt)
            XCTAssertEqual(result.failed.count, attempt == 5 ? 1 : 0)
            XCTAssertEqual(stored.first?.state, attempt == 5 ? .failed : .pending)
            // Past the capped backoff (8 s).
            clock = clock.addingTimeInterval(60)
        }

        _ = await queue.outbox.drainDeletions(using: deleter, now: clock, randomJitter: { 1 })
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 5, "a delete that gave up is not sent a sixth time")
    }

    // MARK: - Retry and "Keep entry"

    func testRetryMakesADeleteThatGaveUpWaitAgain() async throws {
        let queue = try makeQueue()
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminClientError.httpError(statusCode: 403, body: nil))])
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)

        try await queue.outbox.retryDeletion(id: queued.id, now: now.addingTimeInterval(120))

        var stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.pending])
        XCTAssertEqual(stored.first?.attemptCount, 0)
        XCTAssertNil(stored.first?.lastError)

        _ = await queue.outbox.drainDeletions(using: deleter, now: now.addingTimeInterval(120))
        stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.sent], "the scripted failure is used up: the retry goes through")
    }

    func testDeletingTheEntryAgainRevivesADeleteThatGaveUp() async throws {
        let queue = try makeQueue()
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = ScriptedDeleter([.fail(GarminClientError.httpError(statusCode: 403, body: nil))])
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)

        let again = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now.addingTimeInterval(30))

        XCTAssertEqual(again.id, queued.id)
        XCTAssertEqual(again.state, .pending)
        XCTAssertEqual(again.attemptCount, 0)
        let all = await queue.outbox.allDeletions()
        XCTAssertEqual(all.count, 1)
    }

    func testKeepEntryRemovesAWaitingOrFailedDelete() async throws {
        let queue = try makeQueue()
        let waiting = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)

        try await queue.outbox.cancelDeletion(id: waiting.id)

        let all = await queue.outbox.allDeletions()
        XCTAssertTrue(all.isEmpty)
        let deleter = ScriptedDeleter()
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 0, "a dropped delete is never sent")
    }

    func testKeepEntryIsRefusedOnceGarminConfirmedOrForAnUnknownDelete() async throws {
        let queue = try makeQueue()
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        _ = await queue.outbox.drainDeletions(using: ScriptedDeleter(), now: now)

        do {
            try await queue.outbox.cancelDeletion(id: queued.id)
            XCTFail("expected a throw")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .alreadyDelivered)
        }
        do {
            try await queue.outbox.cancelDeletion(id: UUID())
            XCTFail("expected a throw")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .entryNotFound)
        }
        let all = await queue.outbox.allDeletions()
        XCTAssertEqual(all.map(\.state), [.sent], "nothing changed")
    }

    func testKeepEntryIsRefusedWhileTheDeleteIsBeingSent() async throws {
        let queue = try makeQueue()
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        let deleter = CancellingDeleter()
        await deleter.arm(outbox: queue.outbox, id: queued.id)

        _ = await queue.outbox.drainDeletions(using: deleter, now: now)

        let refusal = await deleter.cancelError
        XCTAssertEqual(refusal, .entryInFlight)
        let all = await queue.outbox.allDeletions()
        XCTAssertEqual(all.map(\.state), [.sent], "the delete went through; the entry cannot be un-deleted")
    }

    // MARK: - Account scope

    func testADeleteIsOnlySentToTheAccountItWasMadeUnder() async throws {
        let key = KeyBox("account-a")
        let queue = try makeQueue(accountKey: { key.value })
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        XCTAssertEqual(queued.accountKey, "account-a", "stamped when queued")
        let deleter = ScriptedDeleter()

        key.value = "account-b"
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        key.value = nil // a new sign-in whose profile isn't known yet
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        var calls = await deleter.deleteCount
        XCTAssertEqual(calls, 0, "never sent to another (or an unknown) account")
        let held = await queue.outbox.allDeletions()
        XCTAssertEqual(held.map(\.state), [.pending], "held, not dropped")

        key.value = "account-a"
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        calls = await deleter.deleteCount
        XCTAssertEqual(calls, 1, "sent once its own account is back")
    }

    func testSigningOutTiesAnUnstampedDeleteToTheOutgoingAccount() async throws {
        let key = KeyBox(nil)
        let queue = try makeQueue(accountKey: { key.value })
        let queued = try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        XCTAssertNil(queued.accountKey, "no account was known when it was queued")

        try await queue.outbox.assignUnscopedEntries(to: "account-a")

        let stamped = await queue.outbox.allDeletions()
        XCTAssertEqual(stamped.first?.accountKey, "account-a")
        key.value = "account-b"
        let deleter = ScriptedDeleter()
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        let calls = await deleter.deleteCount
        XCTAssertEqual(calls, 0, "the next account never receives it")
    }

    // MARK: - Confirmed deletes leave once the day was read without them

    func testAConfirmedDeleteStaysUntilTheDayNoLongerListsTheEntry() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        try await queue.outbox.queueDeletion(logId: "log-2", date: day, now: now)
        _ = await queue.outbox.drainDeletions(using: ScriptedDeleter(), now: now)

        // A read that still lists log-1 (it started before Garmin's answer).
        await queue.outbox.pruneConfirmedDeletions(date: day, remainingLogIds: ["log-1", "other"])
        var stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.logId), ["log-1"], "log-2 is gone from the day, so its record is done")

        // Another day's read says nothing about this one.
        await queue.outbox.pruneConfirmedDeletions(date: "2026-10-03", remainingLogIds: [])
        stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.count, 1)

        await queue.outbox.pruneConfirmedDeletions(date: day, remainingLogIds: [])
        stored = await queue.outbox.allDeletions()
        XCTAssertTrue(stored.isEmpty)
    }

    func testPruningNeverDropsADeleteThatIsNotConfirmed() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)

        await queue.outbox.pruneConfirmedDeletions(date: day, remainingLogIds: [])

        let stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.map(\.state), [.pending])
    }

    func testAConfirmedDeleteOfADayNeverReadAgainExpires() async throws {
        let queue = try makeQueue()
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)
        _ = await queue.outbox.drainDeletions(using: ScriptedDeleter(), now: now)

        _ = await queue.outbox.drainDeletions(using: ScriptedDeleter(), now: now.addingTimeInterval(Outbox.confirmedDeletionRetention - 60))
        var stored = await queue.outbox.allDeletions()
        XCTAssertEqual(stored.count, 1, "still inside the retention")

        _ = await queue.outbox.drainDeletions(using: ScriptedDeleter(), now: now.addingTimeInterval(Outbox.confirmedDeletionRetention + 60))
        stored = await queue.outbox.allDeletions()
        XCTAssertTrue(stored.isEmpty)
    }

    func testFoodEntriesAndDeletesLiveInSeparateFiles() async throws {
        let queue = try makeQueue()
        try await queue.outbox.logFood(date: day, mealType: .lunch, foodId: "synthetic-food", servingId: "synthetic-serving", numberOfUnits: 1, createdAt: now)
        try await queue.outbox.queueDeletion(logId: "log-1", date: day, now: now)

        let entries = await queue.outbox.allEntries()
        let deletions = await queue.outbox.allDeletions()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(deletions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.entriesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.deletionsURL.path))

        // A delete drain never sends the queued food.
        let deleter = ScriptedDeleter()
        _ = await queue.outbox.drainDeletions(using: deleter, now: now)
        let creates = await deleter.createCount
        XCTAssertEqual(creates, 0)
    }
}

// MARK: - Garmin fakes (synthetic, no network)

private func deleteResponse() -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.invalid/")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
}

/// Answers each delete with the next scripted outcome (success once the
/// script is used up) and records every call.
private actor ScriptedDeleter: FoodLogDelivering {
    enum Outcome {
        case succeed
        case fail(Error)
    }

    private var outcomes: [Outcome]
    private(set) var deletes: [(logIds: [String], date: String)] = []
    private(set) var createCount = 0

    init(_ outcomes: [Outcome] = []) {
        self.outcomes = outcomes
    }

    var deleteCount: Int { deletes.count }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        createCount += 1
        return deleteResponse()
    }

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        deletes.append((logIds: logIds, date: date))
        let index = deletes.count - 1
        let outcome = index < outcomes.count ? outcomes[index] : .succeed
        switch outcome {
        case .succeed:
            return deleteResponse()
        case .fail(let error):
            throw error
        }
    }
}

/// Tries "Keep entry" on the very delete it is being asked to send, from
/// inside the request.
private actor CancellingDeleter: FoodLogDelivering {
    private var outbox: Outbox?
    private var targetID: UUID?
    private(set) var cancelError: OutboxEditError?

    func arm(outbox: Outbox, id: UUID) {
        self.outbox = outbox
        self.targetID = id
    }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        deleteResponse()
    }

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        if let outbox, let targetID {
            do {
                try await outbox.cancelDeletion(id: targetID)
            } catch let error as OutboxEditError {
                cancelError = error
            } catch {
                cancelError = nil
            }
        }
        return deleteResponse()
    }
}
