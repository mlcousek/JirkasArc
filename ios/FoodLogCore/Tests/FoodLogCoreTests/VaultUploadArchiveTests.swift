// VaultUploadArchiveTests.swift
//
// add-vault-backup tasks 2.5 (design D1, D6, D7): what the weekly vault
// backup uploads, read back from the uploaded BYTES -- unpacked and decoded
// the way the import does it.
//
//   - It is the export, compressed: no second format.
//   - Nothing secret and no device state is in it. The data directory is
//     seeded with a token-named file, a store carrying an OAuth key, a
//     GitHub token in a store and in a preference, every VaultKit file and
//     an outbox; none of them, and none of the planted values, may appear.
//   - `neverUploaded` names the stores that hold a credential's neighbour or
//     this phone's delivery state. Flipping one of them to "in backups" in
//     `StoreCatalog`, or loosening `BackupExclusions`, fails here by name.
//   - An empty data set uploads nothing.
//
// Everything is synthetic: the planted tokens are assembled at run time,
// the device is `ios-0000abcd`, the repository `example-owner/example-vault`.

import XCTest
@testable import FoodLogCore

final class VaultUploadArchiveTests: XCTestCase {
    private var root: URL!
    private var vault: BackupVault!

    /// 2030-10-14 08:15:30 UTC.
    private let now = Date(timeIntervalSince1970: 1_918_196_130)

    private static let plantedSecret = "PLANTED-SECRET-5d2e"
    private static let plantedPreferenceSecret = "PLANTED-PREF-SECRET-c41"
    private static let deviceID = "ios-0000abcd"

    /// Stores that must never be in an upload: the vault's device state
    /// (the identity above all -- a restore must never copy it to another
    /// phone), every delivery queue, and the diagnostics log.
    private static let neverUploaded: [(id: String, path: String)] = [
        ("vault.device-identity", "VaultKit/device-identity.json"),
        ("vault.status", "VaultKit/status.json"),
        ("vault.fetch-cache", "VaultKit/fetch-cache.json"),
        ("vault.write-queue", "VaultKit/write-queue.json"),
        ("vault.backup-upload", "VaultKit/backup-upload.json"),
        ("garminkit.outbox", "GarminKit/outbox-app.json"),
        ("garminkit.food-delete-outbox", "GarminKit/food-delete-outbox-app.json"),
        ("garminkit.weight-outbox", "GarminKit/weight-outbox-app.json"),
        ("garminkit.hydration-outbox", "GarminKit/hydration-outbox-app.json"),
        ("garminkit.diagnostics-log", "GarminKit/diagnostics-log.json")
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-upload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = BackupVault(dataDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, _ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// The owner's data, as a backup should carry it.
    private func seedOwnData() throws {
        try write(#"[{"id":"cf1"},{"id":"cf2"}]"#, "FoodLogCore/custom-foods.json")
        try write(#"[{"kg":70}]"#, "FoodLogCore/weight-entries.json")
        try write(#"[{"day":"2030-10-13","entryCount":5}]"#, "FoodLogCore/food-day-closes.json")
        try write(#"{"totalXP":1200}"#, "Gamification/xp-ledger.json")
    }

    private static let ownData: Set<String> = [
        "FoodLogCore/custom-foods.json",
        "FoodLogCore/weight-entries.json",
        "FoodLogCore/food-day-closes.json",
        "Gamification/xp-ledger.json"
    ]

    // MARK: - The upload is the export

    func testTheUploadIsTheExportCompressed() throws {
        try seedOwnData()
        let preferences = PreferencesBackup.capture(domain: ["preferences.haptics": true])

        let archive = try XCTUnwrap(vault.makeUploadArchive(preferences: preferences, appVersion: "1.0 (1)", now: now))
        let exported = try vault.makeExportContainer(preferences: preferences, appVersion: "1.0 (1)", now: now)
        let exportedBytes = try exported.container.encoded()

        XCTAssertTrue(BackupArchive.isGzip(archive.bytes))
        XCTAssertEqual(try BackupArchive.gunzip(archive.bytes), exportedBytes, "byte for byte what Export backup writes")
        XCTAssertEqual(archive.containerByteCount, exportedBytes.count)
        XCTAssertEqual(archive.fileCount, 4)
        XCTAssertEqual(archive.skippedPaths, [])

        // The import's own decoder takes the uploaded file as it is.
        let decoded = try BackupContainer.decode(archive.bytes)
        XCTAssertEqual(decoded, exported.container)
        XCTAssertEqual(decoded.manifest.kind, .export)
        XCTAssertEqual(decoded.manifest.createdAt, now)
        XCTAssertEqual(Set(decoded.files.map(\.path)), Self.ownData)
        XCTAssertEqual(BackupPreview.make(container: decoded).itemCounts[.customFoods], 2)
        XCTAssertNoThrow(try vault.stageRestore(container: decoded))
    }

    func testAnEmptyDataSetUploadsNothing() throws {
        // Preferences alone are not a backup worth a week's file name.
        let preferences = PreferencesBackup.capture(domain: ["preferences.haptics": true])
        XCTAssertNil(try vault.makeUploadArchive(preferences: preferences, appVersion: nil, now: now))

        // Device state alone isn't either.
        try write(#"[{"id":"queued"}]"#, "GarminKit/outbox-app.json")
        try write(#"{"deviceId":"\#(Self.deviceID)"}"#, "VaultKit/device-identity.json")
        XCTAssertNil(try vault.makeUploadArchive(preferences: preferences, appVersion: nil, now: now))
    }

    // MARK: - No secret, no device state

    func testPlantedSecretsAndDeviceStateNeverReachTheUpload() throws {
        try seedOwnData()
        // Assembled at run time: no scanner should mistake these for a leak.
        let fineGrained = "github" + "_pat_" + String(repeating: "Fak3", count: 6)
        let classic = "gh" + "p_" + String(repeating: "Fak3", count: 6)

        // Credentials by name and by content.
        try write(#"{"token":"\#(Self.plantedSecret)"}"#, "GarminKit/oauth-tokens.json")
        try write(#"{"oauth_token_secret":"\#(Self.plantedSecret)","note":"harmless name"}"#, "FoodLogCore/misc-state.json")
        try write(#"[{"day":"2030-10-13","text":"\#(fineGrained)"}]"#, "FoodLogCore/day-notes.json")
        try write(#"{"note":"\#(classic)"}"#, "Gamification/goal-status.json")
        // The vault's own files, the unsent training events among them.
        try write(#"{"createdAt":"2030-10-01T08:00:00Z","deviceId":"\#(Self.deviceID)","nextSequence":7}"#, "VaultKit/device-identity.json")
        try write(#"{"lastSuccessAt":"2030-10-14T08:00:00Z"}"#, "VaultKit/status.json")
        try write(#"{}"#, "VaultKit/fetch-cache.json")
        try write(#"[{"record":{"path":"events/\#(Self.deviceID)/2030/10/x.jsonl"}}]"#, "VaultKit/write-queue.json")
        try write(#"[{"event":{"device":"\#(Self.deviceID)"}}]"#, "VaultKit/training-events.json")
        try write(#"{"lastSuccessWeek":"2030-W41"}"#, "VaultKit/backup-upload.json")
        // Delivery queues.
        try write(#"[{"id":"queued"}]"#, "GarminKit/outbox-app.json")
        try write(#"[{"id":"queued-delete"}]"#, "GarminKit/food-delete-outbox-app.json")

        let preferences = PreferencesBackup.capture(domain: [
            "preferences.haptics": true,
            "garmin.oauthToken": Self.plantedPreferenceSecret,
            "garminAccountTokenFingerprint": Self.plantedPreferenceSecret,
            "preferences.lastSearch": fineGrained,
            "dataSafety.lastVaultBackupAt": Date(timeIntervalSince1970: 1),
            "vault.connection.v1": ["enabled": true, "owner": "example-owner", "name": "example-vault", "branch": "main"] as [String: Any]
        ])

        let archive = try XCTUnwrap(vault.makeUploadArchive(preferences: preferences, appVersion: "1.0 (1)", now: now))
        let unpacked = try BackupArchive.gunzip(archive.bytes)
        let container = try BackupContainer.decode(archive.bytes)

        XCTAssertEqual(Set(container.files.map(\.path)), Self.ownData)
        XCTAssertEqual(
            Set(archive.skippedPaths),
            ["FoodLogCore/misc-state.json", "FoodLogCore/day-notes.json", "Gamification/goal-status.json"],
            "a store with a credential inside is left out whole, and named"
        )
        XCTAssertEqual(Set(container.preferences.keys), ["preferences.haptics", "vault.connection.v1"], "the connection settings travel; nothing token-like and no backup bookkeeping does")

        let needles = [
            Self.plantedSecret, Self.plantedPreferenceSecret, fineGrained, classic,
            "github" + "_pat_", "oauth_token", "oauthToken", Self.deviceID, "queued"
        ]
        for needle in needles {
            XCTAssertNil(unpacked.range(of: Data(needle.utf8)), "the upload contains \(needle)")
            for file in container.files {
                XCTAssertNil(file.contents.range(of: Data(needle.utf8)), "\(file.path) in the upload contains \(needle)")
            }
        }
        XCTAssertFalse(container.files.contains { $0.path.hasPrefix("VaultKit/") })
        XCTAssertFalse(container.files.contains { $0.path.hasPrefix("GarminKit/") })
    }

    func testNamedDeviceOnlyStoresAreNeverUploaded() throws {
        try seedOwnData()
        for store in Self.neverUploaded {
            let entry = try XCTUnwrap(StoreCatalog.entry(id: store.id), "\(store.id) left the catalog")
            XCTAssertFalse(entry.inBackup, "\(store.id) must never be in a backup: it would be uploaded to the vault")
            XCTAssertEqual(entry.area, .deviceOnly, store.id)
            XCTAssertTrue(entry.location.matches(relativePath: store.path), store.id)
            XCTAssertFalse(BackupExclusions.includesFile(relativePath: store.path), "\(store.path) passes the exclusions")
            try write(#"{"planted":"\#(store.id)"}"#, store.path)
        }

        let archive = try XCTUnwrap(vault.makeUploadArchive(preferences: [:], appVersion: nil, now: now))
        let container = try BackupContainer.decode(archive.bytes)

        XCTAssertEqual(Set(container.files.map(\.path)), Self.ownData)
        for store in Self.neverUploaded {
            XCTAssertFalse(container.files.contains { $0.path == store.path }, store.path)
            XCTAssertFalse(container.manifest.files.contains { $0.storeId == store.id }, store.id)
        }
        // And the general rule the list is an instance of.
        for entry in StoreCatalog.entries where entry.area == .deviceOnly {
            XCTAssertFalse(entry.inBackup, entry.id)
        }
    }
}
