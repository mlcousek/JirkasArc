// BackupArchiveTests.swift
//
// add-vault-backup tasks 2.1-2.2 (design D1): the gzip form of an exported
// backup. Reading goes through the offline index's `GzipInflate`; writing
// is hand-framed around Foundation's DEFLATE, and no compiler ran on the
// machine it was written on, so these tests pin it from both sides: the
// CRC-32 check value everybody uses, the exact header and trailer bytes, a
// round trip -- and two files written by a STANDARD gzip (zlib, via Node,
// text "hello ... vault backup"), one plain and one with every optional
// header field, which must read back.
//
// Also: damaged, truncated and oversized input is "not a backup", and
// `BackupContainer.decode` reads a compressed export.

import XCTest
@testable import FoodLogCore

final class BackupArchiveTests: XCTestCase {
    /// What both real gzip files below hold.
    private let hello = Data("hello hello hello hello, vault backup\n".utf8)

    /// `gzip` of `hello` by zlib, operating-system byte set to "unknown".
    private let plainGzipBase64 = "H4sIAAAAAAAA/8tIzcnJV8hAJ3UUyhJLc0oUkhKTs0sLuADRVe8HJgAAAA=="

    /// The same payload with FHCRC, FEXTRA ("ABC"), FNAME ("2030-W01.json")
    /// and FCOMMENT ("made by hand") in the header.
    private let gzipWithEveryFieldBase64 = "H4sIHgAAAAAAAwMAQUJDMjAzMC1XMDEuanNvbgBtYWRlIGJ5IGhhbmQAsFTLSM3JyVfIQCd1FMoSS3NKFJISk7NLC7gA0VXvByYAAAA="

    private func littleEndian(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    }

    // MARK: - CRC-32

    func testCRC32CheckValues() {
        XCTAssertEqual(GzipCRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(GzipCRC32.checksum(Data()), 0)
        XCTAssertEqual(GzipCRC32.checksum(hello), 0x07EF_55D1)
    }

    // MARK: - Writing

    func testGzipWritesHeaderTrailerAndShrinksRepetitiveJSON() throws {
        let line = #"{"name":"Oatmeal","calories":186,"protein":6.5}"# + "\n"
        let payload = Data(String(repeating: line, count: 500).utf8)

        let packed = try BackupArchive.gzip(payload)

        XCTAssertTrue(BackupArchive.isGzip(packed))
        XCTAssertFalse(BackupArchive.isGzip(payload))
        XCTAssertEqual([UInt8](packed.prefix(10)), [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        let trailer = [UInt8](packed.suffix(8))
        XCTAssertEqual(littleEndian(Array(trailer[0..<4])), GzipCRC32.checksum(payload))
        XCTAssertEqual(littleEndian(Array(trailer[4..<8])), UInt32(payload.count))
        XCTAssertLessThan(packed.count, payload.count / 10, "repetitive JSON compresses well")
    }

    func testRoundTripGivesBackTheExactBytes() throws {
        var payload = Data(#"{"note":"Rohlík s máslem","kcal":130.5}"#.utf8)
        // Bytes that are not text, too.
        payload.append(contentsOf: (0..<2_000).map { UInt8(($0 * 37 + 11) % 251) })

        let packed = try BackupArchive.gzip(payload)

        XCTAssertEqual(try BackupArchive.gunzip(packed), payload)
        XCTAssertEqual(try BackupArchive.unpacked(packed), payload)
        XCTAssertEqual(try BackupArchive.unpacked(payload), payload, "a plain file passes through untouched")
    }

    func testEmptyPayloadRoundTrips() throws {
        let packed = try BackupArchive.gzip(Data())
        XCTAssertEqual(packed.count, 20)
        XCTAssertEqual(try BackupArchive.gunzip(packed), Data())
    }

    // MARK: - Reading what a standard gzip wrote

    func testRealGzipFilesDecode() throws {
        let plain = try XCTUnwrap(Data(base64Encoded: plainGzipBase64))
        let withEveryField = try XCTUnwrap(Data(base64Encoded: gzipWithEveryFieldBase64))

        XCTAssertEqual(try BackupArchive.gunzip(plain), hello)
        XCTAssertEqual(try BackupArchive.gunzip(withEveryField), hello, "extra, name, comment and header checksum are skipped")
    }

    func testReadingFromASliceOfData() throws {
        // `Data` slices keep their parent's indices; nothing may assume 0.
        let packed = try BackupArchive.gzip(hello)
        var padded = Data([0x00, 0x01, 0x02])
        padded.append(packed)
        let slice = padded.dropFirst(3)

        XCTAssertTrue(BackupArchive.isGzip(slice))
        XCTAssertEqual(try BackupArchive.gunzip(slice), hello)
    }

    // MARK: - Refusals

    func testDamagedInputIsNotABackup() throws {
        let packed = try BackupArchive.gzip(Data(String(repeating: "vault backup ", count: 200).utf8))

        var wrongChecksum = packed
        wrongChecksum[wrongChecksum.count - 8] ^= 0xFF
        var wrongLength = packed
        wrongLength[wrongLength.count - 4] ^= 0x01
        var wrongMethod = packed
        wrongMethod[2] = 0x07
        var unterminatedName = packed
        unterminatedName[3] = 0x08
        for index in 10..<unterminatedName.count where unterminatedName[index] == 0 {
            unterminatedName[index] = 0x41
        }
        let truncated = packed.prefix(packed.count - 5)
        let headerOnly = packed.prefix(12)

        let cases: [(String, Data)] = [
            ("wrong checksum", wrongChecksum),
            ("wrong length", wrongLength),
            ("wrong method", wrongMethod),
            ("unterminated name", unterminatedName),
            ("truncated", Data(truncated)),
            ("header only", Data(headerOnly))
        ]
        for (label, data) in cases {
            XCTAssertThrowsError(try BackupArchive.gunzip(data), label) { error in
                XCTAssertEqual(error as? BackupError, .notABackup, label)
            }
        }
    }

    func testADeclaredSizeAboveTheLimitIsRefusedBeforeUnpacking() throws {
        var packed = try BackupArchive.gzip(hello)
        // ISIZE = 0x7FFFFFFF: about 2 GB.
        let count = packed.count
        packed[count - 4] = 0xFF
        packed[count - 3] = 0xFF
        packed[count - 2] = 0xFF
        packed[count - 1] = 0x7F
        XCTAssertThrowsError(try BackupArchive.gunzip(packed)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
    }

    // MARK: - The bound on the compressed input

    /// Review of add-vault-backup: the declared size comes from the file
    /// itself, and the reader inflates the whole body before it compares.
    /// So the INPUT is bounded, before anything is unpacked. Proven with a
    /// good file: it reads back at a bound of its own size and is refused
    /// one byte below -- nothing but the bound differs.
    func testACompressedFileOverTheInputBoundIsRefused() throws {
        let packed = try BackupArchive.gzip(Data(String(repeating: "vault backup ", count: 50).utf8))

        XCTAssertEqual(try BackupArchive.gunzip(packed, maxPackedBytes: packed.count).count, 650)
        XCTAssertThrowsError(try BackupArchive.gunzip(packed, maxPackedBytes: packed.count - 1)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        XCTAssertEqual(BackupArchive.maxPackedBytes, 12 * 1024 * 1024, "four times the vault backup's 3 MiB cap")
    }

    func testAnOversizedCompressedFileIsNotABackupAndAPlainFileOfAnySizePasses() throws {
        // One byte over the bound, with the gzip magic. Its trailer is all
        // zeros, which would read as "an empty payload" -- so only the
        // input bound, checked first, can refuse it.
        var oversized = Data(count: BackupArchive.maxPackedBytes + 1)
        oversized[0] = 0x1F
        oversized[1] = 0x8B
        oversized[2] = 0x08
        XCTAssertThrowsError(try BackupArchive.gunzip(oversized)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupArchive.unpacked(oversized)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        XCTAssertThrowsError(try BackupContainer.decode(oversized)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        // Exactly at the bound the same file is read (as the empty payload
        // its trailer declares): the bound is inclusive.
        let atTheBound = Data(oversized.prefix(BackupArchive.maxPackedBytes))
        XCTAssertEqual(try BackupArchive.gunzip(atTheBound), Data())

        // A plain export is not compressed and is never judged by the bound.
        let plain = Data(repeating: 0x20, count: BackupArchive.maxPackedBytes + 1)
        XCTAssertFalse(BackupArchive.isGzip(plain))
        XCTAssertEqual(try BackupArchive.unpacked(plain).count, plain.count)
    }

    // MARK: - Through the import's decoder

    func testACompressedExportDecodesLikeThePlainOne() throws {
        let bytes = Data(#"[{"name":"Oatmeal","kcal":186}]"#.utf8)
        let container = BackupContainer(
            manifest: BackupManifest(
                kind: .export,
                createdAt: Date(timeIntervalSince1970: 1_918_196_130),
                appVersion: "1.0 (1)",
                files: [.make(path: "FoodLogCore/custom-foods.json", byteCount: bytes.count)]
            ),
            files: [BackupContainer.File(path: "FoodLogCore/custom-foods.json", contents: bytes)],
            preferences: ["preferences.haptics": .bool(true)]
        )
        let plain = try container.encoded()
        let packed = try BackupArchive.gzip(plain)

        XCTAssertEqual(try BackupContainer.decode(packed), container)
        XCTAssertEqual(try BackupContainer.decode(plain), container)
    }

    func testADamagedCompressedFileIsNotABackup() throws {
        let container = BackupContainer(
            manifest: BackupManifest(kind: .export, createdAt: Date(timeIntervalSince1970: 1_918_196_130), appVersion: nil, files: []),
            files: [],
            preferences: [:]
        )
        let packed = try BackupArchive.gzip(try container.encoded())
        let cut = Data(packed.prefix(packed.count - 6))
        XCTAssertThrowsError(try BackupContainer.decode(cut)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
        // Compressed, but not a backup inside.
        let other = try BackupArchive.gzip(Data(#"{"hello":1}"#.utf8))
        XCTAssertThrowsError(try BackupContainer.decode(other)) { error in
            XCTAssertEqual(error as? BackupError, .notABackup)
        }
    }
}
