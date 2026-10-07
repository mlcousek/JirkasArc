// VaultServices.swift
//
// The app's one set of vault objects per process (add-vault-connection
// task 4.1, design D1): the Keychain token store, the status, the device
// identity, the GitHub client and transport, the conditional fetch and the
// coordinator. It is the ONLY place that knows the transport is GitHub --
// everything above it (VaultController, later TrainingCore) sees a
// `VaultTransport`.
//
// App target only. `Shared/AppServices.swift` is compiled into the widget
// extension too, and the widget must never link VaultKit or hold the token
// (ios/project.yml lists VaultKit for the app target alone), so these live
// here rather than in AppServices -- the way GamificationEngine stays out
// of the widget.
//
// The client reads its credentials per request: the repository from
// `vault.connection.v1` in UserDefaults, the token from the Keychain. So a
// token or repository saved in Settings applies to the very next request,
// and the token is never held in a property here.
//
// add-training-today-and-plan task 4.1: it also owns TrainingCore's
// `ProjectionStore`, over the same `ConditionalFileSync`, so the last good
// plan is VaultKit's cached copy and nothing else.
//
// add-vault-backup task 4.1: and the weekly backup's uploader with its
// state file, over the same transport and status (VaultBackupService is
// the one caller).
//
// Depended on by: VaultController (AppEnvironment.vault), TrainingModel
// (AppEnvironment.training), VaultBackupService.

import Foundation
import VaultKit
import TrainingCore

@MainActor
final class VaultServices {
    static let shared = VaultServices()

    let tokenStore: VaultTokenStoring
    let statusStore: VaultStatusStore
    let identityStore: DeviceIdentityStore
    let transport: VaultTransport
    let fetchSync: ConditionalFileSync
    let coordinator: VaultSyncCoordinator
    let projectionStore: ProjectionStore
    /// add-vault-backup: the weekly backup of the app's data.
    let backupUploader: VaultBackupUploader

    private init() {
        let directory = VaultStorage.defaultDirectory()
        let tokenStore: VaultTokenStoring = VaultTokenStore()
        let identityStore = DeviceIdentityStore(directory: directory)
        let client = GitHubContentsClient(
            credentials: {
                guard let repository = VaultConnectionSettings.load(from: UserDefaults.standard).repository,
                      let token = try? tokenStore.load()
                else { return nil }
                return VaultCredentials(repository: repository, token: token)
            },
            policy: {
                VaultPathPolicy(ownDeviceID: await identityStore.currentID())
            }
        )
        let transport = GitHubVaultTransport(api: client)
        let fetchSync = ConditionalFileSync(transport: transport, directory: directory)
        let statusStore = VaultStatusStore(directory: directory)

        self.tokenStore = tokenStore
        self.identityStore = identityStore
        self.statusStore = statusStore
        self.transport = transport
        self.fetchSync = fetchSync
        self.projectionStore = ProjectionStore(fetchSync: fetchSync)
        self.coordinator = VaultSyncCoordinator(
            transport: transport,
            fetchSync: fetchSync,
            statusStore: statusStore,
            identityStore: identityStore
        )
        self.backupUploader = VaultBackupUploader(
            transport: transport,
            stateStore: VaultBackupStateStore(directory: directory),
            statusStore: statusStore
        )
    }
}
