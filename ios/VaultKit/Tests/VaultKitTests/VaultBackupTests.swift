// VaultBackupTests.swift
//
// add-vault-backup task 3.5 (design D2, D4, D5): the pure rules of the
// weekly backup -- ISO weeks in UTC (year boundaries, long years, a time
// zone at the week's edge), the file names, the path policy's allowed and
// refused shapes, what counts as an attempt, and "due or not" through a
// week of failures and into the next week.
//
// Dates are synthetic (2030); the device is `ios-0000abcd`.

import XCTest
@testable import VaultKit

final class VaultBackupTests: XCTestCase {
    private let device = TestSupport.deviceID
    private let hour: TimeInterval = 60 * 60

    private func date(_ string: String, file: StaticString = #filePath, line: UInt = #line) -> Date {
        guard let date = ISO8601DateFormatter().date(from: string) else {
            XCTFail("\(string) is not an ISO 8601 date", file: file, line: line)
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func week(_ string: String) -> VaultBackupWeek {
        VaultBackupWeek(containing: date(string))
    }

    // MARK: - ISO weeks

    func testIsoWeeksInUTC() {
        let cases: [(String, String)] = [
            ("2030-10-14T08:15:30Z", "2030-W42"),
            ("2030-01-01T00:00:00Z", "2030-W01"),
            // Monday 2029-12-31 already belongs to 2030's first week.
            ("2029-12-30T23:59:59Z", "2029-W52"),
            ("2029-12-31T00:00:00Z", "2030-W01"),
            // 2032 is a long year: W53 runs into January 2033.
            ("2032-12-31T12:00:00Z", "2032-W53"),
            ("2033-01-02T23:59:59Z", "2032-W53"),
            ("2033-01-03T00:00:00Z", "2033-W01"),
            ("2026-12-31T12:00:00Z", "2026-W53"),
            ("2027-01-03T12:00:00Z", "2026-W53"),
            ("2027-01-04T00:00:00Z", "2027-W01"),
            // Before 1970 the day arithmetic still holds (a Thursday).
            ("1969-12-25T12:00:00Z", "1969-W52")
        ]
        for (moment, expected) in cases {
            XCTAssertEqual(week(moment).key, expected, moment)
        }
        XCTAssertEqual(week("2030-10-14T08:15:30Z").year, 2030)
        XCTAssertEqual(week("2030-10-14T08:15:30Z").week, 42)
        XCTAssertEqual("\(week("2029-12-31T00:00:00Z"))", "2030-W01")
    }

    func testTheWeekTurnsOverAtMidnightUTCWhateverTheLocalTime() {
        // Sunday 23:30 UTC is already Monday in Prague; it is still W41.
        XCTAssertEqual(week("2030-10-13T23:30:00Z").key, "2030-W41")
        XCTAssertEqual(week("2030-10-13T23:59:59Z").key, "2030-W41")
        XCTAssertEqual(week("2030-10-14T00:00:00Z").key, "2030-W42")
        // Every day of one week has one key.
        let monday = date("2030-10-14T00:00:00Z")
        for day in 0..<7 {
            XCTAssertEqual(VaultBackupWeek(containing: monday.addingTimeInterval(Double(day) * 24 * hour + 5 * hour)).key, "2030-W42", "day \(day)")
        }
        XCTAssertEqual(VaultBackupWeek(containing: monday.addingTimeInterval(7 * 24 * hour)).key, "2030-W43")
    }

    func testDayArithmeticRoundTrips() {
        XCTAssertEqual(VaultBackupWeek.dayNumber(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(VaultBackupWeek.dayNumber(year: 2000, month: 3, day: 1), 11_017)
        for number in stride(from: -800, through: 30_000, by: 37) {
            let civil = VaultBackupWeek.civil(fromDayNumber: number)
            XCTAssertEqual(VaultBackupWeek.dayNumber(year: civil.year, month: civil.month, day: civil.day), number)
        }
    }

    // MARK: - Paths

    func testWeeklyAndManualPaths() throws {
        let moment = date("2030-10-14T08:15:30Z")
        let week = VaultBackupWeek(containing: moment)

        let weekly = try XCTUnwrap(VaultBackupPath.weekly(deviceID: device, week: week))
        XCTAssertEqual(weekly.rawValue, "backups/ios-0000abcd/2030/2030-W42.json.gz")

        let later = date("2030-10-16T19:30:05Z")
        let manual = try XCTUnwrap(VaultBackupPath.manual(deviceID: device, week: VaultBackupWeek(containing: later), at: later))
        XCTAssertEqual(manual.rawValue, "backups/ios-0000abcd/2030/2030-W42-20301016T193005Z.json.gz")

        // The folder is the week-numbering year, not the calendar year.
        let newYearsEve = date("2029-12-31T07:00:00Z")
        let boundary = try XCTUnwrap(VaultBackupPath.weekly(deviceID: device, week: VaultBackupWeek(containing: newYearsEve)))
        XCTAssertEqual(boundary.rawValue, "backups/ios-0000abcd/2030/2030-W01.json.gz")
        let boundaryManual = try XCTUnwrap(VaultBackupPath.manual(deviceID: device, week: VaultBackupWeek(containing: newYearsEve), at: newYearsEve))
        XCTAssertEqual(boundaryManual.rawValue, "backups/ios-0000abcd/2030/2030-W01-20291231T070000Z.json.gz")

        XCTAssertEqual(VaultBackupPath.deviceFolder(device), "backups/ios-0000abcd/")
        XCTAssertEqual(
            VaultBackupPath.commitMessage(deviceID: device, path: weekly, byteCount: 412_345),
            "hub: ios-0000abcd backup 2030-W42.json.gz (412345 bytes)"
        )
        // Both names are ones the policy lets this device write.
        let policy = VaultPathPolicy(ownDeviceID: device)
        XCTAssertTrue(policy.allowsWrite(weekly))
        XCTAssertTrue(policy.allowsWrite(manual))
        XCTAssertTrue(policy.allowsWrite(boundaryManual))
    }

    func testStampIsUTCToTheSecond() {
        XCTAssertEqual(VaultBackupPath.stamp(date("2030-01-01T00:00:00Z")), "20300101T000000Z")
        XCTAssertEqual(VaultBackupPath.stamp(date("2030-12-31T23:59:59Z")), "20301231T235959Z")
        XCTAssertEqual(VaultBackupPath.stamp(date("2030-10-16T19:30:05Z").addingTimeInterval(0.9)), "20301016T193005Z")
    }

    // MARK: - Path policy

    func testPolicyAllowsOnlyTheOwnBackupFile() throws {
        let own = try XCTUnwrap(VaultDeviceID("ios-7f3a91c2"))
        let policy = VaultPathPolicy(ownDeviceID: own)
        func path(_ raw: String) throws -> HubPath {
            try XCTUnwrap(HubPath(raw), raw)
        }

        XCTAssertTrue(policy.allowsWrite(try path("backups/ios-7f3a91c2/2030/2030-W42.json.gz")))
        XCTAssertTrue(policy.allowsWrite(try path("backups/ios-7f3a91c2/2030/2030-W42-20301016T193005Z.json.gz")))

        let refused = [
            "backups/ios-00000000/2030/2030-W42.json.gz",        // another device
            "backups/ios-7f3a91c2x/2030/2030-W42.json.gz",       // prefix trick
            "backups/ios-7F3A91C2/2030/2030-W42.json.gz",        // uppercase id
            "backups/ios-7f3a91c2/2030-W42.json.gz",             // no year folder
            "backups/ios-7f3a91c2/2030/extra/2030-W42.json.gz",  // deeper
            "backups/ios-7f3a91c2/203/2030-W42.json.gz",         // not four digits
            "backups/ios-7f3a91c2/20300/2030-W42.json.gz",
            "backups/ios-7f3a91c2/year/2030-W42.json.gz",
            "backups/ios-7f3a91c2/2030/2030-W42.json",           // not compressed
            "backups/ios-7f3a91c2/2030/2030-W42.jsonl",
            "backups/ios-7f3a91c2/2030/2030-W42.json.gz.md",
            "backups/ios-7f3a91c2/2030/.json.gz",                // no name
            "backups/2030/2030-W42.json.gz",
            "backup/ios-7f3a91c2/2030/2030-W42.json.gz",
            "events/ios-7f3a91c2/2030/2030-W42.json.gz",         // events take .jsonl only
            "projection/2030-W42.json.gz",
            "Sport/Training/_hub/backups/ios-7f3a91c2/2030/2030-W42.json.gz" // no full repository paths
        ]
        for raw in refused {
            XCTAssertFalse(policy.allowsWrite(try path(raw)), raw)
        }

        // Reading: the own backup file only (to confirm a file reported as
        // existing is there); every shape refused for writing is refused
        // for reading too.
        XCTAssertTrue(policy.allowsRead(try path("backups/ios-7f3a91c2/2030/2030-W42.json.gz")))
        XCTAssertTrue(policy.allowsRead(try path("backups/ios-7f3a91c2/2030/2030-W42-20301016T193005Z.json.gz")))
        for raw in refused where raw.hasPrefix("backup") {
            XCTAssertFalse(policy.allowsRead(try path(raw)), raw)
        }

        // Without a device id there is no backups folder at all.
        XCTAssertFalse(VaultPathPolicy(ownDeviceID: nil).allowsWrite(try path("backups/ios-7f3a91c2/2030/2030-W42.json.gz")))
        XCTAssertFalse(VaultPathPolicy(ownDeviceID: nil).allowsRead(try path("backups/ios-7f3a91c2/2030/2030-W42.json.gz")))
        // The events rule is unchanged.
        XCTAssertTrue(policy.allowsWrite(try path("events/ios-7f3a91c2/2030/10/20301014T081530Z-1.jsonl")))
    }

    // MARK: - What counts as an attempt

    func testWhichFailuresSpendAnAttempt() {
        let now = date("2030-10-14T08:15:30Z")
        let counted: [VaultBackupFailure] = [
            .tooLarge(byteCount: 4_000_000, limit: 3_145_728),
            .archiveFailed,
            .vault(.serverError(status: 502)),
            .vault(.unexpected(status: 418)),
            // A transport error that is not a cancellation: TLS, a bad
            // response, "not an HTTP response" (code 0).
            .vault(.transportError(code: -1200)),
            .vault(.transportError(code: 0)),
            .vault(.refusedByPolicy),
            .vault(.redirectRefused)
        ]
        let free: [VaultBackupFailure] = [
            .nothingToBackUp,
            .vault(.offline),
            .vault(.authFailed(.tokenRejected)),
            .vault(.authFailed(.forbidden)),
            .vault(.rateLimited(until: now.addingTimeInterval(60))),
            .vault(.notConfigured),
            // Ordinary, not the upload's fault: the event upload committed
            // at the same moment (409), or iOS ended the background task.
            .vault(.conflict),
            .vault(.transportError(code: URLError.Code.cancelled.rawValue)),
            .vault(.transportError(code: -999))
        ]
        for failure in counted {
            XCTAssertTrue(failure.spendsAttempt, failure.logLabel)
        }
        for failure in free {
            XCTAssertFalse(failure.spendsAttempt, failure.logLabel)
        }
        XCTAssertEqual(VaultBackupFailure.tooLarge(byteCount: 4_000_000, limit: 3_145_728).logLabel, "too large (4000000 bytes, limit 3145728)")
    }

    func testFailureCodingIsStable() throws {
        // The shapes `backup-upload.json` holds; a change here needs a new
        // fixture beside the old one.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cases: [(VaultBackupFailure, String)] = [
            (.tooLarge(byteCount: 4_000_000, limit: 3_145_728), #"{"tooLarge":{"byteCount":4000000,"limit":3145728}}"#),
            (.nothingToBackUp, #"{"nothingToBackUp":{}}"#),
            (.archiveFailed, #"{"archiveFailed":{}}"#),
            (.vault(.offline), #"{"vault":{"_0":{"offline":{}}}}"#),
            (.vault(.serverError(status: 502)), #"{"vault":{"_0":{"serverError":{"status":502}}}}"#)
        ]
        for (failure, json) in cases {
            let encoded = try encoder.encode(failure)
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), json)
            let decoded = try JSONDecoder().decode(VaultBackupFailure.self, from: Data(json.utf8))
            XCTAssertEqual(decoded, failure)
        }
    }

    // MARK: - Due or not

    func testDueOnceAWeek() throws {
        let monday = date("2030-10-14T06:00:00Z")
        let week = VaultBackupWeek(containing: monday)
        var state = VaultBackupState()

        XCTAssertTrue(VaultBackupSchedule.isDue(state, now: monday), "never backed up")
        XCTAssertFalse(VaultBackupSchedule.isWeekDone(state, now: monday))

        let path = try XCTUnwrap(VaultBackupPath.weekly(deviceID: device, week: week))
        state.recordSuccess(week: week, path: path, byteCount: 412_345, at: monday)

        XCTAssertTrue(VaultBackupSchedule.isWeekDone(state, now: monday))
        XCTAssertEqual(state.lastSuccessWeek, "2030-W42")
        XCTAssertEqual(state.lastSuccessPath, path)
        XCTAssertEqual(state.lastSuccessByteCount, 412_345)
        XCTAssertNil(state.lastFailure)
        // Not again this week, however often the app comes forward.
        let laterHours: [Double] = [0, 0.5, 2, 48, 161]
        for hours in laterHours {
            XCTAssertFalse(VaultBackupSchedule.isDue(state, now: monday.addingTimeInterval(hours * hour)), "\(hours) h later")
        }
        // The next Monday it is.
        XCTAssertTrue(VaultBackupSchedule.isDue(state, now: date("2030-10-21T00:00:01Z")))
    }

    func testAFailedAttemptWaitsAnHourAndTheWeekStopsAfterFive() {
        let monday = date("2030-10-14T06:00:00Z")
        let week = VaultBackupWeek(containing: monday)
        var state = VaultBackupState()
        var now = monday

        for attempt in 1...VaultBackupSchedule.maxAttemptsPerWeek {
            XCTAssertTrue(VaultBackupSchedule.isDue(state, now: now), "attempt \(attempt)")
            state.recordFailure(.vault(.serverError(status: 503)), week: week, at: now)
            XCTAssertEqual(state.attemptCount, attempt)
            XCTAssertEqual(state.lastFailure, .vault(.serverError(status: 503)))
            XCTAssertFalse(VaultBackupSchedule.isDue(state, now: now.addingTimeInterval(59 * 60)), "within the hour")
            now = now.addingTimeInterval(hour)
        }
        // Five counted failures: the week is left alone...
        XCTAssertFalse(VaultBackupSchedule.isDue(state, now: now))
        XCTAssertFalse(VaultBackupSchedule.isDue(state, now: date("2030-10-20T23:00:00Z")))
        XCTAssertFalse(VaultBackupSchedule.isWeekDone(state, now: now), "a skipped week is not a done week")
        // ...and the next week starts at zero.
        let nextMonday = date("2030-10-21T06:00:00Z")
        XCTAssertTrue(VaultBackupSchedule.isDue(state, now: nextMonday))
        XCTAssertEqual(state.attempts(in: VaultBackupWeek(containing: nextMonday)), 0)
        state.recordFailure(.vault(.serverError(status: 500)), week: VaultBackupWeek(containing: nextMonday), at: nextMonday)
        XCTAssertEqual(state.attemptWeek, "2030-W43")
        XCTAssertEqual(state.attemptCount, 1)
    }

    /// Review of add-vault-backup: a 409 (the phone's own event upload
    /// committed at the same moment) and a cancelled request (iOS ended the
    /// background refresh) are ordinary. They must not use up the week --
    /// and the hour between attempts still keeps them from looping.
    func testConflictsAndCancellationsNeverUseUpTheWeekButKeepTheInterval() {
        let monday = date("2030-10-14T06:00:00Z")
        let week = VaultBackupWeek(containing: monday)
        var state = VaultBackupState()
        var now = monday
        let ordinary: [VaultBackupFailure] = [
            .vault(.conflict),
            .vault(.transportError(code: VaultBackupFailure.cancelledTransportCode))
        ]

        for round in 0..<12 {
            let failure = ordinary[round % ordinary.count]
            XCTAssertTrue(VaultBackupSchedule.isDue(state, now: now), "round \(round)")
            state.recordFailure(failure, week: week, at: now)
            XCTAssertEqual(state.attemptCount, 0, failure.logLabel)
            XCTAssertEqual(state.lastFailure, failure)
            XCTAssertFalse(VaultBackupSchedule.isDue(state, now: now.addingTimeInterval(30 * 60)), "no loop")
            now = now.addingTimeInterval(hour)
        }
        XCTAssertTrue(VaultBackupSchedule.isDue(state, now: now), "the week is still open after twelve of them")
        XCTAssertEqual(VaultBackupFailure.cancelledTransportCode, -999)
    }

    func testOfflineNeverUsesUpTheWeekButKeepsTheInterval() {
        let monday = date("2030-10-14T06:00:00Z")
        let week = VaultBackupWeek(containing: monday)
        var state = VaultBackupState()
        var now = monday

        for _ in 0..<40 {
            XCTAssertTrue(VaultBackupSchedule.isDue(state, now: now))
            state.recordFailure(.vault(.offline), week: week, at: now)
            XCTAssertFalse(VaultBackupSchedule.isDue(state, now: now.addingTimeInterval(10 * 60)), "no loop while offline")
            now = now.addingTimeInterval(hour)
        }
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertEqual(state.lastFailure, .vault(.offline))
        XCTAssertEqual(state.lastFailureAt, now.addingTimeInterval(-hour))
    }

    func testSuccessAfterFailuresClearsTheProblem() throws {
        let monday = date("2030-10-14T06:00:00Z")
        let week = VaultBackupWeek(containing: monday)
        var state = VaultBackupState()
        state.recordFailure(.vault(.serverError(status: 500)), week: week, at: monday)
        state.recordFailure(.tooLarge(byteCount: 4_000_000, limit: 3_145_728), week: week, at: monday.addingTimeInterval(hour))
        XCTAssertEqual(state.attemptCount, 2)

        let path = try XCTUnwrap(VaultBackupPath.weekly(deviceID: device, week: week))
        state.recordSuccess(week: week, path: path, byteCount: nil, at: monday.addingTimeInterval(2 * hour))

        XCTAssertNil(state.lastFailure)
        XCTAssertNil(state.lastFailureAt)
        XCTAssertEqual(state.attemptCount, 0)
        XCTAssertNil(state.lastSuccessByteCount, "found already there: the size is not known")
        XCTAssertEqual(state.lastSuccessAt, monday.addingTimeInterval(2 * hour))
    }

    func testAClockSetBackDoesNotBlockTheBackup() {
        let monday = date("2030-10-14T06:00:00Z")
        var state = VaultBackupState()
        state.recordFailure(.vault(.offline), week: VaultBackupWeek(containing: monday), at: monday.addingTimeInterval(3 * hour))
        // "Now" is before the recorded attempt.
        XCTAssertTrue(VaultBackupSchedule.isDue(state, now: monday))
    }

    func testTheCapIsThreeMebibytes() {
        XCTAssertEqual(VaultBackupSchedule.maxBytes, 3_145_728)
        XCTAssertEqual(VaultBackupSchedule.retryInterval, 3_600)
        XCTAssertEqual(VaultBackupSchedule.maxAttemptsPerWeek, 5)
    }
}
