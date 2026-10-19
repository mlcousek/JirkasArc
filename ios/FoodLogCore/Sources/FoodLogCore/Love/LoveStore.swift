// LoveStore.swift
//
// add-partner-love-theme D1: where the love pack and the partner's state
// live on her phone, in `FoodLogCore/Love/`:
//
//   - `love-pack.json`  the pack's texts and picture metadata (no bytes);
//   - `love-state.json` LoveState -- what she has seen, kept and earned;
//   - `Images/<id>.<png|jpg>` the pack's pictures.
//
// Backups copy only `.json` files (BackupExclusions), so the texts and the
// state travel in her export and the daily snapshot while the pictures --
// up to 80 of them -- do not; re-importing the same pack brings them back
// (spec love-pack, "The pack's texts and state are backed up, its pictures
// are not").
//
// Importing is two steps, like a backup restore: `preview(importing:)`
// validates the file and says what would change, `apply(_:)` stores it. A
// failed preview changes nothing. Pictures are written before the pack
// that names them, and the state last, so an interrupted import leaves at
// worst unused picture files.
//
// Removing the pack deletes the pack and its pictures and KEEPS the state,
// so re-importing the same `packId` restores everything.
//
// Actor-isolated, loaded through `FoodLogCoreStorage.loadPersistedJSON`
// (the quarantining loader), the same two-line load/save contract as every
// store here. One instance, held by AppServices. Tests: LoveStoreTests,
// StoreFixtureTests.

import Foundation

public struct LovePackImportPreview: Sendable, Equatable {
    public let loaded: LoadedLovePack
    public let diff: LovePackDiff
}

public actor LoveStore {
    public static let packFileName = "love-pack.json"
    public static let stateFileName = "love-state.json"
    public static let imagesDirectoryName = "Images"

    private let directory: URL
    private var currentPack: LovePack?
    private var currentState: LoveState?
    private var packLoaded = false
    private var stateLoaded = false

    public init(directory: URL = LoveStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("Love", isDirectory: true)
    }

    private var packURL: URL { directory.appendingPathComponent(Self.packFileName) }
    private var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }
    private var imagesURL: URL { directory.appendingPathComponent(Self.imagesDirectoryName, isDirectory: true) }

    // MARK: Loading

    private func loadIfNeeded() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if !packLoaded {
            let result = FoodLogCoreStorage.loadPersistedJSON(LovePack.self, from: packURL, decoder: decoder, category: "LoveStore")
            packLoaded = !result.isUnreadable
            currentPack = result.value
        }
        if !stateLoaded {
            let result = FoodLogCoreStorage.loadPersistedJSON(LoveState.self, from: stateURL, decoder: decoder, category: "LoveStore")
            stateLoaded = !result.isUnreadable
            currentState = result.value
        }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func persistPack(_ pack: LovePack?) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: packLoaded, fileURL: packURL, category: "LoveStore")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let pack {
            try encoder().encode(pack).write(to: packURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: packURL.path) {
            try FileManager.default.removeItem(at: packURL)
        }
        currentPack = pack
    }

    private func persistState(_ state: LoveState) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: stateLoaded, fileURL: stateURL, category: "LoveStore")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(state).write(to: stateURL, options: .atomic)
        currentState = state
    }

    // MARK: Reading

    public func pack() -> LovePack? {
        loadIfNeeded()
        return currentPack
    }

    /// The state that belongs to the stored pack (`nil` without a pack, or
    /// when the state on disk is another pack's).
    public func state() -> LoveState? {
        loadIfNeeded()
        guard let pack = currentPack, let state = currentState, state.packId == pack.packId else { return nil }
        return state
    }

    /// The file of a stored pack picture, or `nil` when it is not on this
    /// phone (after a restore, until the pack is imported again).
    public func pictureURL(id: String) -> URL? {
        loadIfNeeded()
        guard let image = currentPack?.images.first(where: { $0.id == id }) else { return nil }
        let url = imagesURL.appendingPathComponent(image.id + "." + image.format.fileExtension)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The ids of the pack's pictures whose files are on this phone.
    public func availablePictureIds() -> Set<String> {
        loadIfNeeded()
        let ids = (currentPack?.images ?? []).map(\.id).filter { pictureURL(id: $0) != nil }
        return Set(ids)
    }

    /// Whether some of the pack's pictures are missing (after a restore).
    public func isMissingPictures() -> Bool {
        loadIfNeeded()
        return availablePictureIds().count < (currentPack?.images.count ?? 0)
    }

    // MARK: Importing

    public func preview(importing data: Data) -> Result<LovePackImportPreview, LovePackProblem> {
        loadIfNeeded()
        return LovePackReader.read(data).map { loaded in
            LovePackImportPreview(loaded: loaded, diff: .between(current: currentPack, incoming: loaded.pack))
        }
    }

    /// Stores a previewed pack. Same `packId`: the state is kept and
    /// reconciled. Another pack, or none before: a fresh state from today --
    /// unless the state on disk already belongs to this `packId` (the pack
    /// was removed, or restored without its pictures, and comes back).
    public func apply(_ preview: LovePackImportPreview, now: Date = Date(), calendar: Calendar = .current) throws {
        loadIfNeeded()
        let incoming = preview.loaded.pack
        try writePictures(preview.loaded)

        try persistPack(incoming)

        var state: LoveState
        if let existing = currentState, existing.packId == incoming.packId {
            state = existing
        } else {
            state = LoveState(packId: incoming.packId, importDay: LoveDay.key(of: now, calendar: calendar))
        }
        state.reconcile(with: incoming)
        try persistState(state)
    }

    private func writePictures(_ loaded: LoadedLovePack) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        var keep = Set<String>()
        for image in loaded.pack.images {
            guard let bytes = loaded.pictures[image.id] else { continue }
            let name = image.id + "." + image.format.fileExtension
            try bytes.write(to: imagesURL.appendingPathComponent(name), options: .atomic)
            keep.insert(name)
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: imagesURL.path)) ?? [] where !keep.contains(name) {
            try? fileManager.removeItem(at: imagesURL.appendingPathComponent(name))
        }
    }

    /// Deletes the pack and its pictures; keeps the state (see header).
    public func removePack() throws {
        loadIfNeeded()
        try persistPack(nil)
        if FileManager.default.fileExists(atPath: imagesURL.path) {
            try FileManager.default.removeItem(at: imagesURL)
        }
    }

    // MARK: Changing the state

    /// Applies `change` to the stored pack's state and saves it. Returns
    /// `nil` (and changes nothing) without a pack.
    @discardableResult
    public func update<T: Sendable>(_ change: (LovePack, inout LoveState) -> T) throws -> T? {
        loadIfNeeded()
        guard let pack = currentPack, var current = self.state() else { return nil }
        let before = current
        let result = change(pack, &current)
        if current != before { try persistState(current) }
        return result
    }
}
