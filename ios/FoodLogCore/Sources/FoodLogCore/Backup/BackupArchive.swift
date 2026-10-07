// BackupArchive.swift
//
// add-vault-backup D1: the compressed form of an exported backup -- what the
// weekly vault backup uploads, and what "Import backup" also reads.
//
// Why it exists: the export (`BackupContainer.encoded()`) is one file, so it
// can be uploaded as it is, but it is pretty-printed JSON holding base64 --
// about 1.35 times the stores it carries, and every byte uploaded stays in
// the vault's git history, which is cloned to a phone. Gzip brings it to
// roughly a fifth. Not a second backup format: the payload is the export's
// exact bytes, so decoding, the version check, the preview and the staged
// restore are the ones add-data-safety already has.
//
// Why gzip and not a bare compressed stream: Foundation compresses
// (`NSData.compressed(using: .zlib)`, no new dependency) but writes a RAW
// DEFLATE stream (RFC 1951) with no header, which opens with nothing on a
// desk. Wrapped in the ten-byte gzip header and the CRC-32 + length trailer
// (RFC 1952) it is an ordinary `.gz`: `gunzip`, 7-Zip or Node's
// `zlib.gunzipSync` give the readable export back.
//
// Nothing here is new machinery. Reading is `GzipInflate` and the checksum
// is `GzipCRC32`, both from OfflineFoodIndex.swift, where they have decoded
// the weekly-built Czech index (a real gzip file written by a Node tool)
// since add-offline-czech-food-index; that reader already skips the
// optional header fields (extra, name, comment, header checksum), which a
// file unpacked and packed again on the desk carries. Writing is the
// framing that package's tests have always used to build their gzip files.
// This file adds what a backup needs on top: a size guard before unpacking,
// "not a backup" for anything unreadable, and the upload's bytes.
//
// Depends on: OfflineFoodIndex.swift (GzipInflate, GzipCRC32), BackupVault
// (makeExportContainer), BackupManifest (BackupError).
// Depended on by: BackupContainer.decode, the app's VaultBackupService.
// Tests: BackupArchiveTests, VaultUploadArchiveTests.

import Foundation

public enum BackupArchive {
    /// Refuse to unpack a file that declares more than this (256 MB): a
    /// real backup is a few megabytes.
    public static let maxUnpackedBytes = 256 * 1024 * 1024

    /// A raw DEFLATE stream holding nothing: one final, empty block.
    private static let emptyDeflateStream: [UInt8] = [0x03, 0x00]

    /// Header (10) + trailer (8): no gzip file is shorter.
    private static let minimumGzipBytes = 18

    /// Whether `data` starts with the gzip magic bytes.
    public static func isGzip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let first = data.startIndex
        return data[first] == 0x1F && data[first + 1] == 0x8B
    }

    /// `data` as a gzip file: header, raw DEFLATE, CRC-32, length.
    public static func gzip(_ data: Data) throws -> Data {
        var deflated = Data(emptyDeflateStream)
        if !data.isEmpty {
            do {
                deflated = try (data as NSData).compressed(using: .zlib) as Data
            } catch {
                throw BackupError.fileOperationFailed("compression failed: \(error.localizedDescription)")
            }
        }
        // Magic, deflate, no flags, no time (the manifest carries the date),
        // no extra flags, operating system "unknown".
        var packed = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        packed.append(deflated)
        packed.append(contentsOf: littleEndian(GzipCRC32.checksum(data)))
        packed.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return packed
    }

    /// The payload of a gzip file. Anything that is not a complete gzip
    /// file with a matching checksum and length is `BackupError.notABackup`.
    public static func gunzip(_ data: Data) throws -> Data {
        guard isGzip(data), data.count >= minimumGzipBytes else {
            throw BackupError.notABackup
        }
        // The trailer says what unpacking will give, before any work.
        let trailer = [UInt8](data.suffix(8))
        let declaredChecksum = littleEndianValue(trailer, at: 0)
        let declaredCount = Int(littleEndianValue(trailer, at: 4))
        guard declaredCount <= maxUnpackedBytes else {
            throw BackupError.notABackup
        }
        if declaredCount == 0 && declaredChecksum == 0 {
            return Data()
        }
        do {
            return try GzipInflate.inflate(data)
        } catch {
            throw BackupError.notABackup
        }
    }

    /// `data` itself, or its payload when it is a gzip file -- so every
    /// reader of a backup file takes both forms.
    public static func unpacked(_ data: Data) throws -> Data {
        guard isGzip(data) else { return data }
        return try gunzip(data)
    }

    // MARK: - Helpers

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private static func littleEndianValue(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}

/// What the weekly vault backup uploads: the export, compressed.
public struct BackupUploadArchive: Equatable, Sendable {
    /// The gzip file's bytes.
    public let bytes: Data
    /// Data files inside.
    public let fileCount: Int
    /// The uncompressed export's size, for the diagnostics line.
    public let containerByteCount: Int
    /// Files left out because their content looked like a credential
    /// (`BackupSecretPolicy`). The app logs them.
    public let skippedPaths: [String]

    public init(bytes: Data, fileCount: Int, containerByteCount: Int, skippedPaths: [String]) {
        self.bytes = bytes
        self.fileCount = fileCount
        self.containerByteCount = containerByteCount
        self.skippedPaths = skippedPaths
    }
}

extension BackupVault {
    /// add-vault-backup D1: the bytes of a vault backup -- exactly what
    /// "Export backup" writes (`makeExportContainer` + `encoded()`), through
    /// gzip. `nil`, building nothing, for an EMPTY data set: a wiped or
    /// brand-new container must not take the week's file name with nothing
    /// in it (the rule `writeSnapshot` keeps for daily snapshots).
    public func makeUploadArchive(preferences: [String: PreferenceValue], appVersion: String?, now: Date) throws -> BackupUploadArchive? {
        let made = try makeExportContainer(preferences: preferences, appVersion: appVersion, now: now)
        if made.container.files.isEmpty { return nil }
        let encoded = try made.container.encoded()
        let packed = try BackupArchive.gzip(encoded)
        return BackupUploadArchive(
            bytes: packed,
            fileCount: made.container.files.count,
            containerByteCount: encoded.count,
            skippedPaths: made.skippedPaths
        )
    }
}
