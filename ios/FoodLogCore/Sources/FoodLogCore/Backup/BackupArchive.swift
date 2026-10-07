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
// Why gzip framing by hand: Foundation compresses
// (`NSData.compressed(using: .zlib)`, no new dependency) but writes a RAW
// DEFLATE stream (RFC 1951) with no header. A bare stream opens with nothing
// on a desk. Wrapped in the ten-byte gzip header and the CRC-32 + length
// trailer (RFC 1952) it is an ordinary `.gz`: `gunzip`, 7-Zip or Node's
// `zlib.gunzipSync` give the readable export back. Reading skips the
// optional header fields (extra, name, comment, header checksum), because a
// file unpacked and packed again on the desk carries its name there.
//
// "Documented, not observed" on the machine this was written on (no Swift
// toolchain): that `.zlib` is raw DEFLATE. `BackupArchiveTests
// .testRealGzipFilesDecode` decodes two files a standard gzip wrote and
// fails if it is not.
//
// Depends on: BackupVault (makeExportContainer), BackupManifest (BackupError).
// Depended on by: BackupContainer.decode, the app's VaultBackupService.
// Tests: BackupArchiveTests, VaultUploadArchiveTests.

import Foundation

/// CRC-32 as gzip uses it (IEEE 802.3, reflected polynomial `0xEDB88320`).
/// The check value of the ASCII digits "123456789" is `0xCBF43926`.
enum CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                if (value & 1) == 1 {
                    value = 0xEDB8_8320 ^ (value >> 1)
                } else {
                    value = value >> 1
                }
            }
            table[index] = value
        }
        return table
    }()

    static func checksum(_ data: Data) -> UInt32 {
        let table = Self.table
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

public enum BackupArchive {
    /// Refuse to unpack a file that declares more than this (256 MB): a
    /// real backup is a few megabytes.
    public static let maxUnpackedBytes = 256 * 1024 * 1024

    /// A raw DEFLATE stream holding nothing: one final, empty block.
    private static let emptyDeflateStream: [UInt8] = [0x03, 0x00]

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
        var packed = Data(capacity: deflated.count + 18)
        // Magic, deflate, no flags, no time (the manifest carries the date),
        // no extra flags, operating system "unknown".
        packed.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        packed.append(deflated)
        packed.append(contentsOf: littleEndian(CRC32.checksum(data)))
        packed.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return packed
    }

    /// The payload of a gzip file. Anything that is not a complete gzip
    /// file with a matching checksum and length is `BackupError.notABackup`.
    public static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        // Header (10) + trailer (8) at the very least.
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else {
            throw BackupError.notABackup
        }
        let flags = bytes[3]
        guard (flags & 0xE0) == 0 else { throw BackupError.notABackup }
        var offset = 10
        if (flags & 0x04) != 0 {
            // FEXTRA: a two-byte length, then that many bytes.
            guard offset + 2 <= bytes.count else { throw BackupError.notABackup }
            let length = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + length
        }
        if (flags & 0x08) != 0 {
            offset = try endOfZeroTerminatedField(bytes, from: offset) // FNAME
        }
        if (flags & 0x10) != 0 {
            offset = try endOfZeroTerminatedField(bytes, from: offset) // FCOMMENT
        }
        if (flags & 0x02) != 0 {
            offset += 2 // FHCRC
        }
        let trailer = bytes.count - 8
        guard offset <= trailer else { throw BackupError.notABackup }
        let expectedChecksum = littleEndianValue(bytes, at: trailer)
        let expectedCount = Int(littleEndianValue(bytes, at: trailer + 4))
        guard expectedCount <= maxUnpackedBytes else { throw BackupError.notABackup }
        if expectedCount == 0 && expectedChecksum == 0 {
            return Data()
        }
        guard offset < trailer else { throw BackupError.notABackup }
        let body = Data(bytes[offset..<trailer])
        var inflated = Data()
        do {
            inflated = try (body as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw BackupError.notABackup
        }
        guard inflated.count == expectedCount, CRC32.checksum(inflated) == expectedChecksum else {
            throw BackupError.notABackup
        }
        return inflated
    }

    /// `data` itself, or its payload when it is a gzip file -- so every
    /// reader of a backup file takes both forms.
    public static func unpacked(_ data: Data) throws -> Data {
        guard isGzip(data) else { return data }
        return try gunzip(data)
    }

    // MARK: - Helpers

    /// The index after the zero byte that ends a header string.
    private static func endOfZeroTerminatedField(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count {
            if bytes[index] == 0 { return index + 1 }
            index += 1
        }
        throw BackupError.notABackup
    }

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
