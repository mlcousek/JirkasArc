// VaultBackupService.swift
//
// The weekly backup of the app's data to the vault (add-vault-backup design
// D4, D9, D10) -- the app's one caller of VaultKit's `VaultBackupUploader`,
// one instance per process like `TrainingEventsService`. It joins two
// packages that must not know each other: FoodLogCore builds the archive
// (the export, compressed -- `BackupVault.makeUploadArchive`), VaultKit
// decides where and how often it goes.
//
// Who calls it:
//   - `AppEnvironment.deliverTrainingEvents` on launch and on every return
//     to the foreground, after that task's event drain, unstructured, never
//     awaited by a screen. The order makes two commits at once unlikely,
//     not impossible (another drain may be running); a 409 is not counted
//     as an attempt and is tried again an hour later;
//   - `BackgroundRefresh.run`, when iOS grants background time;
//   - Settings > Vault's "Back up now".
//
// Rules:
//   - Nothing is sent unless the event upload could send too: the
//     connection is on and configured on a Garmin-connected install
//     (`TrainingEventsService.isConnectionOn`), "Test connection" has
//     succeeded once (the device id names the folder), and VaultKit's
//     request gate is open (a token, no loud block, no rate-limit pause).
//   - `runIfDue` then asks VaultKit whether the week still needs a backup
//     (once per ISO week, an hour between attempts, five counted failures a
//     week -- offline, a rejected token, a rate limit, a 409 and a request
//     iOS cancelled are not counted). `backUpNow` skips that question,
//     never the gate.
//   - The archive is built on `DataSafetyQueue`, off the main thread and
//     never while a snapshot or a restore is being written.
//   - A rejected token is handed to the event upload's hook
//     (`TrainingEventsService.onAuthStop`): the forced plan fetch names the
//     loud problem. Every other failure is quiet -- recorded for Settings,
//     logged in Diagnostics, retried by the schedule.
//   - A backup that reached the vault writes `dataSafety.lastVaultBackupAt`,
//     which keeps Today's "export a backup" reminder away while the weekly
//     backup works (FoodLogCore `BackupReminderPolicy`).
//
// App target only. Depends on VaultServices, DataSafetyLaunch.swift
// (DataSafetyQueue, DataSafetyPreferences), TrainingEventsService.
// Depended on by: AppEnvironment, BackgroundRefresh, VaultSettingsView,
// VaultErrorPresentation.

import Foundation
import GarminKit
import FoodLogCore
import VaultKit

@MainActor
final class VaultBackupService {
    static let shared = VaultBackupService()

    /// Why "Back up now" sent nothing.
    enum Unavailable: Equatable {
        /// Off, not configured, or a standalone install.
        case connectionOff
        /// No device id yet: "Test connection" never succeeded.
        case notTested
        case noToken
        /// A loud problem blocks vault requests until the owner acts.
        case blocked
        case rateLimited
        /// Another backup is being built or uploaded right now.
        case busy
    }

    /// What one backup run did, for Settings.
    enum Report: Equatable {
        case uploaded(byteCount: Int)
        case alreadyInVault
        case unavailable(Unavailable)
        case failed(VaultBackupFailure)
    }

    private let services: VaultServices
    private var isRunning = false

    private init() {
        self.services = VaultServices.shared
    }

    /// The upload's bookkeeping, for Settings > Vault.
    func state() async -> VaultBackupState {
        await services.backupUploader.state()
    }

    // MARK: Running

    /// The weekly backup, if the connection allows a request and the week
    /// still needs one. Quiet: the outcome is in `state()` and Diagnostics.
    func runIfDue() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let unavailable = await availability()
        guard unavailable == nil else { return }
        let due = await services.backupUploader.isDue(now: Date())
        guard due else { return }
        _ = await perform(trigger: .automatic)
    }

    /// "Back up now": at once, whatever the schedule says.
    func backUpNow() async -> Report {
        guard !isRunning else { return .unavailable(.busy) }
        isRunning = true
        defer { isRunning = false }

        if let unavailable = await availability() {
            return .unavailable(unavailable)
        }
        return await perform(trigger: .manual)
    }

    // MARK: The gate

    /// `nil` when a vault request may go out now -- the same conditions as
    /// `TrainingEventsService.drainNow`, plus the device id.
    private func availability() async -> Unavailable? {
        guard TrainingEventsService.shared.isConnectionOn() else { return .connectionOff }
        let deviceID = await services.identityStore.currentID()
        guard deviceID != nil else { return .notTested }

        let settings = VaultConnectionSettings.load(from: .standard)
        let tokenStore = services.tokenStore
        let hasToken: Bool = {
            do { return try tokenStore.load() != nil } catch { return false }
        }()
        let inputs = VaultSyncInputs(enabled: settings.enabled, configured: settings.isConfigured, hasToken: hasToken)
        let gate = await services.coordinator.connectionState(inputs).requestGate(now: Date())
        switch gate {
        case .allowed:
            return nil
        case .disabled, .notConfigured:
            return .connectionOff
        case .noToken:
            return .noToken
        case .blockedByAuth:
            return .blocked
        case .rateLimited:
            return .rateLimited
        }
    }

    // MARK: One backup

    private func perform(trigger: VaultBackupTrigger) async -> Report {
        guard let deviceID = await services.identityStore.currentID() else {
            return .unavailable(.notTested)
        }
        let now = Date()
        let preferences = DataSafetyPreferences.capture()
        let appVersion = DataSafetyPreferences.appVersion

        var built: BackupUploadArchive?
        do {
            built = try await DataSafetyQueue.shared.perform { vault in
                try vault.makeUploadArchive(preferences: preferences, appVersion: appVersion, now: now)
            }
        } catch {
            DiagnosticsLog.log(.error, category: DataSafetyLaunch.diagnosticsCategory, "Vault backup: the archive could not be built: \(DataSafetyLaunch.describe(error))")
            await services.backupUploader.recordNotUploaded(.archiveFailed, now: now)
            return .failed(.archiveFailed)
        }
        guard let archive = built else {
            await services.backupUploader.recordNotUploaded(.nothingToBackUp, now: now)
            return .failed(.nothingToBackUp)
        }
        if !archive.skippedPaths.isEmpty {
            DiagnosticsLog.log(.warning, category: DataSafetyLaunch.diagnosticsCategory, "Left out of the vault backup because they look like credentials: \(archive.skippedPaths.joined(separator: ", "))")
        }

        let result = await services.backupUploader.upload(archive.bytes, deviceID: deviceID, trigger: trigger, now: now)
        switch result {
        case .uploaded(_, let byteCount):
            noteReachedVault(at: now)
            DiagnosticsLog.log(.info, category: DataSafetyLaunch.diagnosticsCategory, "Vault backup uploaded: \(archive.fileCount) files, \(archive.containerByteCount) bytes, \(byteCount) compressed.")
            return .uploaded(byteCount: byteCount)
        case .alreadyInVault:
            noteReachedVault(at: now)
            return .alreadyInVault
        case .failed(let failure):
            if case .vault(.authFailed(_)) = failure {
                // design D9: the forced plan fetch names the loud problem.
                TrainingEventsService.shared.onAuthStop?()
            }
            return .failed(failure)
        }
    }

    /// add-vault-backup D10: an off-phone copy exists as of `date`.
    private func noteReachedVault(at date: Date) {
        UserDefaults.standard.set(date, forKey: BackupReminderPolicy.lastVaultBackupAtKey)
    }
}
