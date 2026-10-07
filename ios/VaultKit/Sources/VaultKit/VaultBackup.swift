// VaultBackup.swift
//
// The pure rules of the weekly vault backup (add-vault-backup design D2,
// D4, D5): which ISO week a moment is in, what the backup's file is called,
// whether a backup is due, and how an attempt changes the bookkeeping.
// VaultKit knows nothing about WHAT is backed up -- it is handed bytes --
// only where they go and how often.
//
//   path     backups/<deviceId>/<YYYY>/<YYYY>-W<ww>.json.gz
//            (ISO week-numbering year and week, in UTC -- the event
//            segments name their files in UTC too, and a week must not get
//            two names because the phone changed time zone), which
//            `VaultPathPolicy.allowsWrite` accepts for the own device id;
//   by hand  .../<YYYY>-W<ww>-<yyyymmdd>T<hhmmss>Z.json.gz -- "Back up now"
//            in a week that already has its file;
//   message  "hub: ios-0000beef backup 2030-W42.json.gz (412345 bytes)",
//            beside the events' "hub: ios-0000beef seq ...".
//
//   due      no success recorded for the current week, fewer than
//            `maxAttemptsPerWeek` counted failures in it, and the last
//            attempt at least `retryInterval` ago. Offline, a rejected
//            token and a rate limit are not counted (DurableQueue's house
//            rule: not the upload's fault); the interval alone keeps them
//            from looping. A week that ends without a success is skipped:
//            the counter belongs to its week.
//
// The week is computed with integer arithmetic on days since 1970-01-01
// (the algorithm TrainingCore's `ISOWeek` uses), not with `Calendar`, so it
// cannot depend on a locale or a first-weekday setting.
//
// Depended on by: VaultBackupUploader, the app's VaultBackupService and
// VaultSettingsView. Tests: VaultBackupTests.

import Foundation

/// An ISO 8601 week (Monday to Sunday), judged in UTC.
public struct VaultBackupWeek: Hashable, Sendable, CustomStringConvertible {
    /// The ISO week-numbering year (the year of the week's Thursday).
    public let year: Int
    /// 1 ... 53.
    public let week: Int

    /// The week containing `date`.
    public init(containing date: Date) {
        let dayNumber = VaultBackupWeek.dayNumber(of: date)
        // 1970-01-01 was a Thursday: remainder 0 is Thursday, 1 = Monday.
        let weekday = ((dayNumber % 7 + 7) % 7 + 3) % 7 + 1
        let thursday = dayNumber + 4 - weekday
        let thursdayYear = VaultBackupWeek.civil(fromDayNumber: thursday).year
        let januaryFirst = VaultBackupWeek.dayNumber(year: thursdayYear, month: 1, day: 1)
        self.year = thursdayYear
        self.week = (thursday - januaryFirst) / 7 + 1
    }

    /// `YYYY-Www`, e.g. `2030-W42`.
    public var key: String {
        String(format: "%04d-W%02d", year, week)
    }

    public var description: String { key }

    // MARK: Day arithmetic (UTC)

    /// Whole days since 1970-01-01 UTC (negative before).
    static func dayNumber(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDayNumber number: Int) -> (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}

/// Where a backup goes and what its commit says.
public enum VaultBackupPath {
    /// The automatic weekly file; `nil` only if the id were not a valid
    /// path segment (it always is: `ios-` + 8 hex).
    public static func weekly(deviceID: VaultDeviceID, week: VaultBackupWeek) -> HubPath? {
        HubPath("\(folder(deviceID: deviceID, week: week))/\(week.key)\(VaultPathPolicy.backupFileExtension)")
    }

    /// "Back up now" in a week that already has its file: the week, then
    /// the moment in UTC.
    public static func manual(deviceID: VaultDeviceID, week: VaultBackupWeek, at date: Date) -> HubPath? {
        HubPath("\(folder(deviceID: deviceID, week: week))/\(week.key)-\(stamp(date))\(VaultPathPolicy.backupFileExtension)")
    }

    /// `backups/<deviceId>/`, as Settings shows it.
    public static func deviceFolder(_ deviceID: VaultDeviceID) -> String {
        "\(VaultPathPolicy.backupsFolder)/\(deviceID.rawValue)/"
    }

    public static func commitMessage(deviceID: VaultDeviceID, path: HubPath, byteCount: Int) -> String {
        "hub: \(deviceID.rawValue) backup \(path.lastSegment) (\(byteCount) bytes)"
    }

    static func folder(deviceID: VaultDeviceID, week: VaultBackupWeek) -> String {
        let year = String(format: "%04d", week.year)
        return "\(VaultPathPolicy.backupsFolder)/\(deviceID.rawValue)/\(year)"
    }

    /// `yyyymmddThhmmssZ` in UTC, the stamp the event segments use.
    static func stamp(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSince1970.rounded(.down))
        let dayNumber = VaultBackupWeek.dayNumber(of: date)
        let secondOfDay = seconds - dayNumber * 86_400
        let civil = VaultBackupWeek.civil(fromDayNumber: dayNumber)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            civil.year, civil.month, civil.day,
            secondOfDay / 3_600, (secondOfDay % 3_600) / 60, secondOfDay % 60
        )
    }
}

/// Why a backup did not reach the vault.
public enum VaultBackupFailure: Codable, Equatable, Sendable {
    /// The compressed archive is over the cap; nothing was sent.
    case tooLarge(byteCount: Int, limit: Int)
    /// No data file to back up (a brand-new or wiped container).
    case nothingToBackUp
    /// The archive could not be built; the reason is in Diagnostics.
    case archiveFailed
    /// The request failed.
    case vault(VaultOutcome)

    /// Whether this failure counts towards the week's attempts. What is
    /// not the upload's fault does not (see this file's header).
    public var spendsAttempt: Bool {
        switch self {
        case .tooLarge, .archiveFailed:
            return true
        case .nothingToBackUp:
            return false
        case .vault(let outcome):
            switch outcome {
            case .offline, .authFailed, .rateLimited, .notConfigured:
                return false
            case .success, .fileNotFound, .alreadyExists, .conflict, .serverError, .refusedByPolicy, .redirectRefused, .unexpected, .transportError:
                return true
            }
        }
    }

    /// A short, English, redacted label for DiagnosticsLog lines.
    public var logLabel: String {
        switch self {
        case .tooLarge(let byteCount, let limit):
            return "too large (\(byteCount) bytes, limit \(limit))"
        case .nothingToBackUp:
            return "nothing to back up"
        case .archiveFailed:
            return "the archive could not be built"
        case .vault(let outcome):
            return outcome.logLabel
        }
    }
}

/// `backup-upload.json`'s content: what THIS phone uploaded and when it
/// last tried. Device-local, never in a backup (design D8).
public struct VaultBackupState: Codable, Equatable, Sendable {
    /// When a backup last reached the vault (created, or found there).
    public var lastSuccessAt: Date?
    /// The ISO week (`YYYY-Www`) that success belongs to.
    public var lastSuccessWeek: String?
    public var lastSuccessPath: HubPath?
    /// `nil` when the week's file was found already there (its size is
    /// not known to this phone).
    public var lastSuccessByteCount: Int?
    /// The last attempt of any kind, successful or not.
    public var lastAttemptAt: Date?
    /// The week `attemptCount` counts in.
    public var attemptWeek: String?
    /// Counted failures in `attemptWeek`.
    public var attemptCount: Int?
    /// The last attempt's failure; `nil` once an attempt succeeds.
    public var lastFailure: VaultBackupFailure?
    public var lastFailureAt: Date?

    public init(
        lastSuccessAt: Date? = nil,
        lastSuccessWeek: String? = nil,
        lastSuccessPath: HubPath? = nil,
        lastSuccessByteCount: Int? = nil,
        lastAttemptAt: Date? = nil,
        attemptWeek: String? = nil,
        attemptCount: Int? = nil,
        lastFailure: VaultBackupFailure? = nil,
        lastFailureAt: Date? = nil
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastSuccessWeek = lastSuccessWeek
        self.lastSuccessPath = lastSuccessPath
        self.lastSuccessByteCount = lastSuccessByteCount
        self.lastAttemptAt = lastAttemptAt
        self.attemptWeek = attemptWeek
        self.attemptCount = attemptCount
        self.lastFailure = lastFailure
        self.lastFailureAt = lastFailureAt
    }

    /// Counted failures in `week` (0 in any other week than `attemptWeek`).
    public func attempts(in week: VaultBackupWeek) -> Int {
        guard attemptWeek == week.key else { return 0 }
        return attemptCount ?? 0
    }

    /// A backup reached the vault: `week` is done.
    public mutating func recordSuccess(week: VaultBackupWeek, path: HubPath, byteCount: Int?, at now: Date) {
        lastSuccessAt = now
        lastSuccessWeek = week.key
        lastSuccessPath = path
        lastSuccessByteCount = byteCount
        lastAttemptAt = now
        attemptWeek = week.key
        attemptCount = 0
        lastFailure = nil
        lastFailureAt = nil
    }

    /// An attempt in `week` did not reach the vault.
    public mutating func recordFailure(_ failure: VaultBackupFailure, week: VaultBackupWeek, at now: Date) {
        var counted = attempts(in: week)
        if failure.spendsAttempt {
            counted += 1
        }
        attemptWeek = week.key
        attemptCount = counted
        lastAttemptAt = now
        lastFailure = failure
        lastFailureAt = now
    }
}

/// When the automatic backup may run, and how large it may be.
public enum VaultBackupSchedule {
    /// A failed attempt is not repeated sooner than this.
    public static let retryInterval: TimeInterval = 60 * 60
    /// Counted failures after which the week is left alone.
    public static let maxAttemptsPerWeek = 5
    /// The largest archive uploaded, in compressed bytes (3 MiB). The vault
    /// is a git repository cloned to a phone: every byte stays in history.
    public static let maxBytes = 3 * 1024 * 1024

    /// Whether `state` already holds a success for the week of `now`.
    public static func isWeekDone(_ state: VaultBackupState, now: Date) -> Bool {
        state.lastSuccessWeek == VaultBackupWeek(containing: now).key
    }

    /// Whether the automatic backup should be attempted now. The caller
    /// checks the connection's gate first; this is only the calendar and
    /// the retry bookkeeping.
    public static func isDue(_ state: VaultBackupState, now: Date) -> Bool {
        let week = VaultBackupWeek(containing: now)
        if state.lastSuccessWeek == week.key { return false }
        if state.attempts(in: week) >= maxAttemptsPerWeek { return false }
        if let lastAttempt = state.lastAttemptAt {
            let since = now.timeIntervalSince(lastAttempt)
            // A clock set back (negative) must not block the backup.
            if since >= 0 && since < retryInterval { return false }
        }
        return true
    }
}
