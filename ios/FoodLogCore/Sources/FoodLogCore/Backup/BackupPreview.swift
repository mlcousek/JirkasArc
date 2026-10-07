// BackupPreview.swift
//
// add-data-safety D5: what the import sheet shows before the user confirms
// replacing everything -- "12 custom foods, 340 food-log entries, ..." --
// so a wrong or empty file is noticed BEFORE the restore, not after.
//
// Why generic counting instead of decoding each store: the backup carries
// raw store bytes, and decoding them here would duplicate every store's
// decoder (and its shims) in one place that then has to track them all.
// Every store the preview counts persists a top-level JSON array of items
// (custom foods, meal presets, favourites, weigh-ins, drinks, day notes, and
// each FoodLog month shard), so "length of the top-level array" is the item
// count, summed per `BackupArea` via `StoreCatalog`. A file that isn't a
// top-level array still counts as a file.
//
// Also `BackupReminderPolicy`: when the quiet "export a backup" reminder
// shows on Today (design D6).
//
// Depends on: StoreCatalog, BackupManifest (BackupContainer).
// Depended on by: the app's import preview sheet.

import Foundation

public struct BackupPreview: Equatable, Sendable {
    /// Item counts for the areas the preview lists (only areas with at
    /// least one file are present).
    public let itemCounts: [BackupArea: Int]
    /// Files in the progress/history/other areas (XP, achievements,
    /// challenges, usage history...), shown as one number.
    public let otherFileCount: Int
    public let totalFileCount: Int
    public let preferenceCount: Int

    /// The areas shown with an item count, in display order.
    public static let itemAreas: [BackupArea] = [
        .foodLog, .customFoods, .mealPresets, .favorites, .weight, .hydration, .dayNotes
    ]

    public init(itemCounts: [BackupArea: Int], otherFileCount: Int, totalFileCount: Int, preferenceCount: Int) {
        self.itemCounts = itemCounts
        self.otherFileCount = otherFileCount
        self.totalFileCount = totalFileCount
        self.preferenceCount = preferenceCount
    }

    public static func make(files: [(path: String, contents: Data)], preferenceCount: Int, catalog: [StoreCatalogEntry] = StoreCatalog.entries) -> BackupPreview {
        var counts: [BackupArea: Int] = [:]
        var other = 0
        for file in files {
            let area = catalog.first { $0.location.matches(relativePath: file.path) }?.area ?? .other
            if itemAreas.contains(area) {
                counts[area, default: 0] += topLevelArrayCount(file.contents) ?? 0
            } else {
                other += 1
            }
        }
        return BackupPreview(itemCounts: counts, otherFileCount: other, totalFileCount: files.count, preferenceCount: preferenceCount)
    }

    public static func make(container: BackupContainer, catalog: [StoreCatalogEntry] = StoreCatalog.entries) -> BackupPreview {
        make(
            files: container.files.map { (path: $0.path, contents: $0.contents) },
            preferenceCount: container.preferences.count,
            catalog: catalog
        )
    }

    /// The number of elements when `data` is a top-level JSON array.
    static func topLevelArrayCount(_ data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let array = object as? [Any] else { return nil }
        return array.count
    }
}

/// Design D6's reminder: show when the last export is more than
/// `interval` old (or there never was one), unless "Not now" was tapped
/// within `interval`. Pure, so the 14-day edges are tested. Since
/// add-vault-backup a backup that reached the vault counts like an export.
public enum BackupReminderPolicy {
    public static let interval: TimeInterval = 14 * 24 * 60 * 60

    /// UserDefaults keys for the reminder's bookkeeping. `dataSafety.*` is
    /// excluded from backups (BackupExclusions), so restoring an old backup
    /// never rewinds when the last export happened.
    public static let lastExportAtKey = "dataSafety.lastExportAt"
    public static let dismissedAtKey = "dataSafety.reminderDismissedAt"
    /// add-vault-backup D10: when a backup last reached the vault (a file
    /// created there, or found already there). Written by the app's
    /// VaultBackupService; excluded from backups by the same prefix.
    public static let lastVaultBackupAtKey = "dataSafety.lastVaultBackupAt"

    /// Whole calendar days from `date` to `now` (0 = today), for "Today" /
    /// "N days ago" on the Data screen. Never negative, so a clock set back
    /// reads as "Today" rather than "-1 days ago".
    public static func daysSince(_ date: Date, now: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// add-vault-backup D10: `lastVaultBackupAt` counts like an export --
    /// either one within `interval` is an off-phone copy. So the reminder
    /// stays away while the weekly vault backup works and comes back when
    /// it has not worked for `interval`. Last and defaulted, so callers
    /// without a vault (the tests of add-data-safety) read as before.
    ///
    /// A date in the FUTURE counts for nothing (review of add-vault-backup):
    /// a backup, an export or a "Not now" recorded while the clock was set
    /// forward must not keep the reminder away until real time catches up
    /// and then for `interval` more. Ignoring it errs towards showing.
    public static func shouldShow(
        lastExportAt: Date?,
        dismissedAt: Date?,
        now: Date,
        interval: TimeInterval = BackupReminderPolicy.interval,
        lastVaultBackupAt: Date? = nil
    ) -> Bool {
        if isWithin(interval, of: lastExportAt, now: now) { return false }
        if isWithin(interval, of: lastVaultBackupAt, now: now) { return false }
        if isWithin(interval, of: dismissedAt, now: now) { return false }
        return true
    }

    /// `date` is in the past (or now) and less than `interval` ago.
    static func isWithin(_ interval: TimeInterval, of date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < interval
    }
}
