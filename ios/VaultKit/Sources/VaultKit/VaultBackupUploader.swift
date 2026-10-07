// VaultBackupUploader.swift
//
// Sends one backup of the app's data to the vault and keeps the books
// (add-vault-backup design D3, D5, D8, D9). Two types:
//
//   - `VaultBackupStateStore`: the actor owning `VaultKit/backup-upload.json`
//     (`VaultBackupState`), loaded through `PersistedJSON` like every
//     VaultKit store. Device-local, never in a backup.
//   - `VaultBackupUploader`: one upload.
//       1. Over `maxBytes`: nothing is sent, the failure is recorded.
//       2. One create-only write to the week's path.
//          created         -> the week is done.
//          already exists  -> the week is done too, ONCE THE FILE IS SEEN:
//                             an earlier attempt landed and its answer was
//                             lost, or the file was there before this phone
//                             knew. Its content is never compared and never
//                             overwritten -- next week's file holds
//                             everything again. But GitHub answers 422 to a
//                             create for more than "it exists" (validation,
//                             abuse detection), and a backup that calls a
//                             week done with no file in the vault fails
//                             silently, every week. So one read of that
//                             path decides: there -> done; not found -> a
//                             failure ("unexpected 422"), shown in Settings.
//          anything else   -> a failure, counted or not
//                             (`VaultBackupFailure.spendsAttempt`).
//       3. By hand (`.manual`), in a week that is already done -- known
//          beforehand or learned from "already exists" -- the bytes go to a
//          second, time-stamped name, so the tap always leaves a current
//          copy.
//
// Why not `DurableQueue` + `CreateOnlyFileUploader`, which deliver the
// event segments: the queue exists so that sealed bytes are never lost and
// a collision is never mistaken for a delivery. A backup has no bytes worth
// keeping -- it is rebuilt fresh for every attempt -- and "a different file
// is there" is not an error for it. The queue would hold a megabyte of
// base64 on disk and list a failed backup as events "Not uploaded". What
// this keeps from that uploader is its distrust of a bare 422.
//
// The connection's status is fed the way the event upload feeds it (the
// app's TrainingEventsService.drainNow): a success moves "Last sync", a
// rate limit pauses every vault request. A rejected token is NOT written
// into the status from here -- the app asks for the forced plan fetch
// instead, whose answer names the loud problem, so a token that can read
// but not write never blocks the plan.
//
// One upload at a time is the caller's business (the app's
// VaultBackupService holds the guard); overlapping calls would only race
// for the same create-only path, which GitHub settles.
//
// Depended on by: the app's VaultServices / VaultBackupService.
// Tests: VaultBackupUploaderTests, StoreFixtureTests.

import Foundation
import GarminKit

public actor VaultBackupStateStore {
    public static let fileName = "backup-upload.json"

    private let fileURL: URL
    private var state = VaultBackupState()
    private var loaded = false

    public init(directory: URL = VaultStorage.defaultDirectory()) {
        self.fileURL = directory.appendingPathComponent("backup-upload.json")
    }

    /// See PersistedJSON.swift: `.unreadable` leaves `loaded` unset so the
    /// next access retries the read.
    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load(VaultBackupState.self, from: fileURL, decoder: VaultStorage.makeDecoder(), category: VaultLog.category)
        state = result.value ?? VaultBackupState()
        loaded = !result.isUnreadable
    }

    public func current() -> VaultBackupState {
        loadIfNeeded()
        return state
    }

    /// Replaces the state and persists it; the in-memory copy changes only
    /// once the write succeeded.
    private func save(_ updated: VaultBackupState) throws {
        guard updated != state else { return }
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: VaultLog.category)
        try VaultStorage.write(try VaultStorage.makeEncoder().encode(updated), to: fileURL)
        state = updated
    }

    /// `VaultBackupState.recordSuccess` + persist. A failed write is
    /// logged, never thrown: the upload it describes already happened, and
    /// the next attempt finds the file in the vault.
    @discardableResult
    public func recordSuccess(week: VaultBackupWeek, path: HubPath, byteCount: Int?, at now: Date) -> VaultBackupState {
        loadIfNeeded()
        var updated = state
        updated.recordSuccess(week: week, path: path, byteCount: byteCount, at: now)
        do {
            try save(updated)
        } catch {
            VaultLog.log(.warning, "backup: state could not be saved (\(type(of: error)))")
        }
        return state
    }

    /// `VaultBackupState.recordFailure` + persist, logged like above.
    @discardableResult
    public func recordFailure(_ failure: VaultBackupFailure, week: VaultBackupWeek, at now: Date) -> VaultBackupState {
        loadIfNeeded()
        var updated = state
        updated.recordFailure(failure, week: week, at: now)
        do {
            try save(updated)
        } catch {
            VaultLog.log(.warning, "backup: state could not be saved (\(type(of: error)))")
        }
        return state
    }
}

/// Who asked for the backup.
public enum VaultBackupTrigger: String, Sendable, Equatable {
    /// The weekly schedule (foreground, background refresh).
    case automatic
    /// "Back up now".
    case manual
}

public enum VaultBackupResult: Equatable, Sendable {
    /// A new file was created at `path`.
    case uploaded(path: HubPath, byteCount: Int)
    /// The week's file was already in the vault; nothing was created.
    case alreadyInVault(path: HubPath)
    case failed(VaultBackupFailure)
}

public actor VaultBackupUploader {
    private let transport: VaultTransport
    private let stateStore: VaultBackupStateStore
    private let statusStore: VaultStatusStore
    private let maxBytes: Int
    /// The last attempt and the last done week of THIS PROCESS, kept
    /// whether or not the state file could be written (review of
    /// add-vault-backup). The state store logs a failed save and keeps its
    /// old state, and it refuses to save at all while its file exists but
    /// cannot be read. Judged by the stored state alone, the backup would
    /// then be "due" on every foreground: an archive built and a multi-MB
    /// upload each time, with no hour between them. These two are the
    /// floor under that; they are lost with the process, where the stored
    /// state takes over again.
    private var lastAttemptThisProcess: Date?
    private var doneWeekThisProcess: String?

    public init(
        transport: VaultTransport,
        stateStore: VaultBackupStateStore,
        statusStore: VaultStatusStore,
        maxBytes: Int = VaultBackupSchedule.maxBytes
    ) {
        self.transport = transport
        self.stateStore = stateStore
        self.statusStore = statusStore
        self.maxBytes = maxBytes
    }

    public func state() async -> VaultBackupState {
        await stateStore.current()
    }

    /// `VaultBackupSchedule.isDue` over the stored state -- and never
    /// within the hour after this process's own last attempt, nor in a week
    /// this process already saw done, whatever the state file holds.
    public func isDue(now: Date = Date()) async -> Bool {
        if doneWeekThisProcess == VaultBackupWeek(containing: now).key { return false }
        if VaultBackupSchedule.isTooSoon(after: lastAttemptThisProcess, now: now) { return false }
        let stored = await stateStore.current()
        return VaultBackupSchedule.isDue(stored, now: now)
    }

    /// Records an attempt that never reached the network (no data, or the
    /// archive could not be built), so the retry interval applies to it.
    public func recordNotUploaded(_ failure: VaultBackupFailure, now: Date = Date()) async {
        let week = VaultBackupWeek(containing: now)
        lastAttemptThisProcess = now
        VaultLog.log(failure == .nothingToBackUp ? .info : .warning, "backup \(week.key): \(failure.logLabel)")
        await stateStore.recordFailure(failure, week: week, at: now)
    }

    /// See this file's header. `archive` is the finished file's bytes.
    public func upload(
        _ archive: Data,
        deviceID: VaultDeviceID,
        trigger: VaultBackupTrigger,
        now: Date = Date()
    ) async -> VaultBackupResult {
        let week = VaultBackupWeek(containing: now)
        // Before anything can fail: this is an attempt, saved or not.
        lastAttemptThisProcess = now

        guard archive.count <= maxBytes else {
            let failure = VaultBackupFailure.tooLarge(byteCount: archive.count, limit: maxBytes)
            VaultLog.log(.warning, "backup \(week.key): \(failure.logLabel); nothing sent")
            await stateStore.recordFailure(failure, week: week, at: now)
            return .failed(failure)
        }
        guard let weeklyPath = VaultBackupPath.weekly(deviceID: deviceID, week: week),
              let manualPath = VaultBackupPath.manual(deviceID: deviceID, week: week, at: now)
        else {
            let failure = VaultBackupFailure.vault(.refusedByPolicy)
            await stateStore.recordFailure(failure, week: week, at: now)
            return .failed(failure)
        }

        let before = await stateStore.current()
        let weekAlreadyDone = before.lastSuccessWeek == week.key || doneWeekThisProcess == week.key
        var path = weeklyPath
        if trigger == .manual && weekAlreadyDone {
            path = manualPath
        }

        var write = await transport.createOnly(Self.sealed(archive, path: path, deviceID: deviceID, now: now))
        if write.outcome == .alreadyExists && path == weeklyPath {
            // "Already exists" for the week's file: look before believing it.
            if let problem = await problemConfirming(weeklyPath) {
                return await failed(problem, path: weeklyPath, week: week, now: now, tokenExpiresAt: write.tokenExpiresAt)
            }
            // It is there: the week is done, whoever put it there.
            VaultLog.log(.info, "backup \(weeklyPath.rawValue): already in the vault; the week is done")
            await reachedVault(week: week, path: weeklyPath, byteCount: nil, now: now, tokenExpiresAt: write.tokenExpiresAt)
            guard trigger == .manual else {
                return .alreadyInVault(path: weeklyPath)
            }
            // By hand: go on to a current copy under the time-stamped name.
            path = manualPath
            write = await transport.createOnly(Self.sealed(archive, path: path, deviceID: deviceID, now: now))
        }

        switch write.outcome {
        case .created:
            VaultLog.log(.info, "backup \(path.rawValue): created, \(archive.count) bytes")
            await reachedVault(week: week, path: path, byteCount: archive.count, now: now, tokenExpiresAt: write.tokenExpiresAt)
            return .uploaded(path: path, byteCount: archive.count)
        case .alreadyExists:
            // Only the time-stamped name can get here (the same second
            // twice). The same rule: seen, then believed.
            if let problem = await problemConfirming(path) {
                return await failed(problem, path: path, week: week, now: now, tokenExpiresAt: write.tokenExpiresAt)
            }
            await reachedVault(week: week, path: path, byteCount: nil, now: now, tokenExpiresAt: write.tokenExpiresAt)
            return .alreadyInVault(path: path)
        case .failed(let outcome):
            return await failed(outcome, path: path, week: week, now: now, tokenExpiresAt: write.tokenExpiresAt)
        }
    }

    /// GitHub said a file already exists at `path`. `nil` when one read of
    /// the path finds it; otherwise what stands in the way of calling the
    /// week done -- "unexpected 422" when nothing is there (the 422 meant
    /// something else), or the read's own failure (offline: try later).
    private func problemConfirming(_ path: HubPath) async -> VaultOutcome? {
        let existing = await transport.fetch(path, ifNoneMatch: nil)
        switch existing.outcome {
        case .fetched, .notModified:
            return nil
        case .failed(.fileNotFound):
            VaultLog.log(.error, "backup \(path.rawValue): reported as existing, but nothing is there; not counted as done")
            return .unexpected(status: 422)
        case .failed(let outcome):
            return outcome
        }
    }

    /// A backup is in the vault for `week`: remembered by this process
    /// first (so a state file that cannot be written does not make the week
    /// "due" again), then saved, then the connection's "Last sync" moves.
    private func reachedVault(week: VaultBackupWeek, path: HubPath, byteCount: Int?, now: Date, tokenExpiresAt: Date?) async {
        doneWeekThisProcess = week.key
        await stateStore.recordSuccess(week: week, path: path, byteCount: byteCount, at: now)
        await statusStore.record(.success, at: now, tokenExpiresAt: tokenExpiresAt)
    }

    /// Records a failed request and answers with it. A rate limit is also
    /// written into the connection's status, so every vault request waits.
    private func failed(_ outcome: VaultOutcome, path: HubPath, week: VaultBackupWeek, now: Date, tokenExpiresAt: Date?) async -> VaultBackupResult {
        let failure = VaultBackupFailure.vault(outcome)
        VaultLog.log(outcome == .offline ? .info : .warning, "backup \(path.rawValue): \(failure.logLabel)")
        await stateStore.recordFailure(failure, week: week, at: now)
        if case .rateLimited = outcome {
            await statusStore.record(outcome, at: now, tokenExpiresAt: tokenExpiresAt)
        }
        return .failed(failure)
    }

    private static func sealed(_ archive: Data, path: HubPath, deviceID: VaultDeviceID, now: Date) -> SealedFile {
        SealedFile(
            path: path,
            bytes: archive,
            commitMessage: VaultBackupPath.commitMessage(deviceID: deviceID, path: path, byteCount: archive.count),
            createdAt: now
        )
    }
}
