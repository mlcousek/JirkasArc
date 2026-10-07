// VaultPathPolicy.swift
//
// The pure allow-lists every vault request is checked against BEFORE it is
// sent (add-vault-connection design D4, spec "The app may write only into
// its own events folder and read only its allowed files"):
//
//   write: `events/<ownDeviceId>/.../<name>.jsonl` -- this install's own
//          folder, at least one level below it, `.jsonl` only;
//   read:  `projection/<name>.json` -- the projection files, one level;
//          `events/<ownDeviceId>/...` -- the install's own folder (the
//          create-only idempotency check, design D7, reads back what it
//          wrote).
//
// add-vault-backup D2/D3 adds one more shape, for writing and reading:
//
//   write: `backups/<ownDeviceId>/<yyyy>/<name>.json.gz` -- the install's
//          weekly backup of the app's data: exactly four segments, a
//          four-digit year folder, a gzip file;
//   read:  the same shape, nothing else under `backups/` -- to confirm
//          that a file GitHub reported as "already exists" is really
//          there before the week is called done.
//
// Everything else is refused, including another device's folder, and every
// events or backups path while this install has no device id yet. Paths are
// `HubPath`s, already normal (no `..`, no encoding tricks), so the check is
// plain segment comparison -- there is nothing left to normalise.
//
// It limits the app's own bugs, not a stolen token: GitHub has no per-path
// token permissions (design D4, docs/vault-connection.md). Enforced inside
// `GitHubContentsClient`, the only type that builds request URLs, and
// applied by every `VaultTransport` (the in-memory test transport too).
//
// Tests: VaultPathPolicyTests.

import Foundation

public struct VaultPathPolicy: Equatable, Sendable {
    /// This install's id, or `nil` before the first successful connection
    /// test (design D5), in which case no events path is allowed at all.
    public let ownDeviceID: VaultDeviceID?

    public init(ownDeviceID: VaultDeviceID?) {
        self.ownDeviceID = ownDeviceID
    }

    public static let projectionFolder = "projection"
    public static let eventsFolder = "events"
    public static let eventFileExtension = ".jsonl"
    public static let projectionFileExtension = ".json"
    /// add-vault-backup D2: the weekly backups of the app's data.
    public static let backupsFolder = "backups"
    public static let backupFileExtension = ".json.gz"

    public func allowsRead(_ path: HubPath) -> Bool {
        let segments = path.segments
        if segments.count == 2, segments[0] == Self.projectionFolder {
            return Self.hasNamedExtension(segments[1], Self.projectionFileExtension)
        }
        if isOwnBackupFile(segments) { return true }
        return isInOwnEventsFolder(segments)
    }

    public func allowsWrite(_ path: HubPath) -> Bool {
        let segments = path.segments
        if isOwnBackupFile(segments) { return true }
        guard isInOwnEventsFolder(segments), let last = segments.last else { return false }
        return Self.hasNamedExtension(last, Self.eventFileExtension)
    }

    /// `backups/<ownDeviceId>/<yyyy>/<name>.json.gz`, exactly.
    private func isOwnBackupFile(_ segments: [String]) -> Bool {
        guard let own = ownDeviceID, segments.count == 4 else { return false }
        return segments[0] == Self.backupsFolder
            && segments[1] == own.rawValue
            && Self.isFourDigits(segments[2])
            && Self.hasNamedExtension(segments[3], Self.backupFileExtension)
    }

    private static func isFourDigits(_ segment: String) -> Bool {
        let scalars = segment.unicodeScalars
        guard scalars.count == 4 else { return false }
        return scalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39: return true
            default: return false
            }
        }
    }

    /// `events/<ownDeviceId>/<at least one more segment>`.
    private func isInOwnEventsFolder(_ segments: [String]) -> Bool {
        guard let own = ownDeviceID else { return false }
        return segments.count >= 3
            && segments[0] == Self.eventsFolder
            && segments[1] == own.rawValue
    }

    /// `name` ends in `ext` and has something before it (`.jsonl` alone is
    /// not a file name).
    private static func hasNamedExtension(_ name: String, _ ext: String) -> Bool {
        name.hasSuffix(ext) && name.count > ext.count
    }
}
