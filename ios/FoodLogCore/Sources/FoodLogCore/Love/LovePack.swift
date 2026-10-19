// LovePack.swift
//
// add-partner-love-theme D1: the love pack -- the one file that carries
// everything personal of the partner theme (her nickname, his signature,
// the daily messages, the optional extras) and the pictures the owner
// chooses for it. It exists as a FILE the owner AirDrops to her phone,
// never as code, because this repository is public: nothing personal, and
// no picture she sees, may be committed or built into a CI artifact.
//
// Two shapes:
//   - the wire file (`.arclove`): `LovePack`'s fields, with each picture's
//     bytes embedded as base64 under `images[].data`. Written by
//     `tools/love-pack/build.mjs`, which applies the same rules as
//     `LovePackReader` (keep both in step);
//   - the stored pack (`LovePack`, `love-pack.json` in `LoveStore`): the same
//     fields WITHOUT picture bytes. The pictures are separate files, so the
//     pack's texts travel in a backup and its pictures do not (BackupExclusions
//     only copies `.json` files).
//
// `LovePackReader.read` validates the whole file before anything is stored
// and names the FIRST problem it finds (spec love-pack, "An invalid pack is
// refused with a reason and changes nothing"). The lore tags are carried but
// not judged here: the spoiler allow-list is enforced by CI and the builder
// (design D11), not by the phone.
//
// Pure, no UI. Depended on by LoveStore, LovePackDiff, DailyLoveMessage,
// PictureRotation, and the app's import sheet. Tests: LovePackTests.

import Foundation

// MARK: - The stored pack

public struct LovePackDaily: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// An "Otevři, až…" scroll: its title is visible, its text only once opened.
public struct LovePackOpenWhen: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let text: String

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

/// A love coupon, bought with hearts (design D9).
public struct LovePackCoupon: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let price: Int

    public init(id: String, title: String, price: Int) {
        self.id = id
        self.title = title
        self.price = price
    }
}

/// The one optional countdown on the love card (`yyyy-MM-dd`).
public struct LovePackCountdown: Codable, Sendable, Equatable {
    public let date: String
    public let title: String

    public init(date: String, title: String) {
        self.date = date
        self.title = title
    }
}

public enum LovePictureFormat: String, Codable, Sendable, Equatable {
    case png
    case jpeg

    /// The extension the picture's file is stored under.
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

/// A pack picture's metadata. Its bytes are a separate file (`LoveStore`).
public struct LovePackImage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let format: LovePictureFormat
    /// Raw slot names (`LovePictureSlot`), as written in the pack.
    public let slots: [String]
    /// Lore terms the owner tagged the picture with (design D11).
    public let lore: [String]

    public init(id: String, format: LovePictureFormat, slots: [String], lore: [String]) {
        self.id = id
        self.format = format
        self.slots = slots
        self.lore = lore
    }
}

public struct LovePack: Codable, Sendable, Equatable {
    public static let format = "love-pack"
    public static let version = 1

    public let packId: String
    public let nickname: String
    public let signature: String
    /// The theme's name as she sees it (Settings, the icon grid). Optional:
    /// without it the theme table's own name is used. In the pack, not the
    /// code, because the repository is public.
    public let themeName: String?
    /// Day 0 of the daily sequence (`yyyy-MM-dd`).
    public let startDate: String
    /// Decides each day's minute and the order of the messages (design D6).
    public let seed: String
    public let daily: [LovePackDaily]
    public let openWhen: [LovePackOpenWhen]
    public let coupons: [LovePackCoupon]
    public let countdown: LovePackCountdown?
    public let images: [LovePackImage]

    public init(
        packId: String,
        nickname: String,
        signature: String,
        themeName: String? = nil,
        startDate: String,
        seed: String,
        daily: [LovePackDaily],
        openWhen: [LovePackOpenWhen] = [],
        coupons: [LovePackCoupon] = [],
        countdown: LovePackCountdown? = nil,
        images: [LovePackImage] = []
    ) {
        self.packId = packId
        self.nickname = nickname
        self.signature = signature
        self.themeName = themeName
        self.startDate = startDate
        self.seed = seed
        self.daily = daily
        self.openWhen = openWhen
        self.coupons = coupons
        self.countdown = countdown
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, packId, nickname, signature, themeName, startDate, seed, daily, openWhen, coupons, countdown, images
    }

    /// The stored file is written by this code; the optional lists are
    /// still read leniently so a pack stored without extras decodes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packId = try container.decode(String.self, forKey: .packId)
        nickname = try container.decode(String.self, forKey: .nickname)
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        themeName = try container.decodeIfPresent(String.self, forKey: .themeName)
        startDate = try container.decode(String.self, forKey: .startDate)
        seed = try container.decode(String.self, forKey: .seed)
        daily = try container.decode([LovePackDaily].self, forKey: .daily)
        openWhen = try container.decodeIfPresent([LovePackOpenWhen].self, forKey: .openWhen) ?? []
        coupons = try container.decodeIfPresent([LovePackCoupon].self, forKey: .coupons) ?? []
        countdown = try container.decodeIfPresent(LovePackCountdown.self, forKey: .countdown)
        images = try container.decodeIfPresent([LovePackImage].self, forKey: .images) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(Self.version, forKey: .version)
        try container.encode(packId, forKey: .packId)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(signature, forKey: .signature)
        try container.encodeIfPresent(themeName, forKey: .themeName)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(seed, forKey: .seed)
        try container.encode(daily, forKey: .daily)
        try container.encode(openWhen, forKey: .openWhen)
        try container.encode(coupons, forKey: .coupons)
        try container.encodeIfPresent(countdown, forKey: .countdown)
        try container.encode(images, forKey: .images)
    }

    public func daily(id: String) -> LovePackDaily? {
        daily.first { $0.id == id }
    }
}

// MARK: - Picture slots

/// Where a pack picture may appear (design D4). Kept as raw strings in the
/// pack so a slot added later is refused by an older build, not silently
/// dropped.
public enum LovePictureSlot {
    public static let loveCard = "loveCard"
    public static let messageBoxHeader = "messageBoxHeader"
    public static let pictureOfDay = "pictureOfDay"
    public static let emptyState = "emptyState"
    public static let rankEmblemPrefix = "rankEmblem:"
    public static let badgePrefix = "badge:"

    /// The seven ninja ranks a `rankEmblem:<rank>` slot may name.
    public static let ranks = ["akademie", "genin", "chunin", "jonin", "anbu", "sannin", "kage"]

    public static func rankEmblem(_ rank: String) -> String { rankEmblemPrefix + rank }
    public static func badge(_ achievementId: String) -> String { badgePrefix + achievementId }

    public static func isKnown(_ slot: String) -> Bool {
        switch slot {
        case loveCard, messageBoxHeader, pictureOfDay, emptyState:
            return true
        default:
            if slot.hasPrefix(rankEmblemPrefix) {
                return ranks.contains(String(slot.dropFirst(rankEmblemPrefix.count)))
            }
            if slot.hasPrefix(badgePrefix) {
                return LovePackLimits.isValidId(String(slot.dropFirst(badgePrefix.count)))
            }
            return false
        }
    }
}

// MARK: - Limits

public enum LovePackLimits {
    /// Checked before the file is parsed at all.
    public static let maxFileBytes = 40 * 1024 * 1024
    public static let maxTextLength = 600
    /// Nickname, signature, titles.
    public static let maxShortTextLength = 120
    public static let maxItemsPerList = 2_000
    public static let maxPictures = 80
    public static let maxPictureBytes = 2 * 1024 * 1024
    public static let maxPictureSide = 4_096
    public static let maxIdLength = 64
    public static let maxCouponPrice = 10_000

    /// Ids name picture files and state keys, so they are kept to a safe,
    /// short alphabet.
    public static func isValidId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maxIdLength else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": return true
            default: return false
            }
        }
    }
}

// MARK: - Problems

/// The first thing wrong with a pack file. The app words it (en + cs);
/// the cases carry what the message needs to name.
public enum LovePackProblem: Error, Sendable, Equatable {
    case tooLarge(bytes: Int)
    case notJSON
    case malformed(field: String)
    case wrongFormat
    case unsupportedVersion(Int)
    case missingField(String)
    case emptyDaily
    case invalidDate(field: String)
    case invalidId(list: String, id: String)
    case duplicateId(list: String, id: String)
    case textTooLong(list: String, id: String)
    case tooManyItems(list: String)
    case invalidPrice(id: String)
    case tooManyPictures(count: Int)
    case pictureNotDecodable(id: String)
    case pictureWrongType(id: String)
    case pictureTooLarge(id: String)
    case pictureTooBig(id: String)
    case unknownSlot(id: String, slot: String)
}

/// A pack read from a file: its texts and its pictures' bytes by id.
public struct LoadedLovePack: Sendable, Equatable {
    public let pack: LovePack
    public let pictures: [String: Data]

    public init(pack: LovePack, pictures: [String: Data]) {
        self.pack = pack
        self.pictures = pictures
    }
}

// MARK: - Reading the wire file

public enum LovePackReader {
    public static func read(_ data: Data) -> Result<LoadedLovePack, LovePackProblem> {
        guard data.count <= LovePackLimits.maxFileBytes else {
            return .failure(.tooLarge(bytes: data.count))
        }
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
            return .failure(.notJSON)
        }
        let wire: WirePack
        do {
            wire = try JSONDecoder().decode(WirePack.self, from: data)
        } catch let DecodingError.typeMismatch(_, context) {
            return .failure(.malformed(field: fieldName(context.codingPath)))
        } catch let DecodingError.valueNotFound(_, context) {
            return .failure(.malformed(field: fieldName(context.codingPath)))
        } catch let DecodingError.keyNotFound(key, context) {
            return .failure(.malformed(field: fieldName(context.codingPath + [key])))
        } catch let DecodingError.dataCorrupted(context) {
            return .failure(.malformed(field: fieldName(context.codingPath)))
        } catch {
            return .failure(.notJSON)
        }
        return validate(wire)
    }

    private static func validate(_ wire: WirePack) -> Result<LoadedLovePack, LovePackProblem> {
        guard wire.format == LovePack.format else { return .failure(.wrongFormat) }
        guard let version = wire.version else { return .failure(.missingField("version")) }
        guard version == LovePack.version else { return .failure(.unsupportedVersion(version)) }

        guard let packId = nonEmpty(wire.packId) else { return .failure(.missingField("packId")) }
        guard LovePackLimits.isValidId(packId) else { return .failure(.invalidId(list: "packId", id: packId)) }
        guard let nickname = nonEmpty(wire.nickname) else { return .failure(.missingField("nickname")) }
        guard nickname.count <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "nickname", id: "")) }
        let signature = wire.signature ?? ""
        guard signature.count <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "signature", id: "")) }
        let themeName = nonEmpty(wire.themeName)
        guard (themeName?.count ?? 0) <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "themeName", id: "")) }
        guard let startDate = nonEmpty(wire.startDate) else { return .failure(.missingField("startDate")) }
        guard LoveDay.isValid(startDate) else { return .failure(.invalidDate(field: "startDate")) }
        guard let seed = nonEmpty(wire.seed) else { return .failure(.missingField("seed")) }
        guard seed.count <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "seed", id: "")) }

        guard let wireDaily = wire.daily else { return .failure(.missingField("daily")) }
        guard !wireDaily.isEmpty else { return .failure(.emptyDaily) }

        // daily
        var daily: [LovePackDaily] = []
        if let problem = checkList("daily", wireDaily.map(\.id)) { return .failure(problem) }
        for item in wireDaily {
            let id = item.id ?? ""
            guard let text = nonEmpty(item.text) else { return .failure(.missingField("daily[\(id)].text")) }
            guard text.count <= LovePackLimits.maxTextLength else { return .failure(.textTooLong(list: "daily", id: id)) }
            daily.append(LovePackDaily(id: id, text: text))
        }

        // openWhen
        let wireOpenWhen = wire.openWhen ?? []
        var openWhen: [LovePackOpenWhen] = []
        if let problem = checkList("openWhen", wireOpenWhen.map(\.id)) { return .failure(problem) }
        for item in wireOpenWhen {
            let id = item.id ?? ""
            guard let title = nonEmpty(item.title) else { return .failure(.missingField("openWhen[\(id)].title")) }
            guard let text = nonEmpty(item.text) else { return .failure(.missingField("openWhen[\(id)].text")) }
            guard title.count <= LovePackLimits.maxShortTextLength, text.count <= LovePackLimits.maxTextLength else {
                return .failure(.textTooLong(list: "openWhen", id: id))
            }
            openWhen.append(LovePackOpenWhen(id: id, title: title, text: text))
        }

        // coupons
        let wireCoupons = wire.coupons ?? []
        var coupons: [LovePackCoupon] = []
        if let problem = checkList("coupons", wireCoupons.map(\.id)) { return .failure(problem) }
        for item in wireCoupons {
            let id = item.id ?? ""
            guard let title = nonEmpty(item.title) else { return .failure(.missingField("coupons[\(id)].title")) }
            guard title.count <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "coupons", id: id)) }
            guard let price = item.price, price >= 1, price <= LovePackLimits.maxCouponPrice else {
                return .failure(.invalidPrice(id: id))
            }
            coupons.append(LovePackCoupon(id: id, title: title, price: price))
        }

        // countdown
        var countdown: LovePackCountdown?
        if let wireCountdown = wire.countdown {
            guard let date = nonEmpty(wireCountdown.date), LoveDay.isValid(date) else {
                return .failure(.invalidDate(field: "countdown.date"))
            }
            guard let title = nonEmpty(wireCountdown.title) else { return .failure(.missingField("countdown.title")) }
            guard title.count <= LovePackLimits.maxShortTextLength else { return .failure(.textTooLong(list: "countdown", id: "")) }
            countdown = LovePackCountdown(date: date, title: title)
        }

        // images
        let wireImages = wire.images ?? []
        guard wireImages.count <= LovePackLimits.maxPictures else {
            return .failure(.tooManyPictures(count: wireImages.count))
        }
        if let problem = checkList("images", wireImages.map(\.id)) { return .failure(problem) }
        var images: [LovePackImage] = []
        var pictures: [String: Data] = [:]
        for item in wireImages {
            let id = item.id ?? ""
            guard let base64 = item.data,
                  let bytes = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                  !bytes.isEmpty else {
                return .failure(.pictureNotDecodable(id: id))
            }
            guard bytes.count <= LovePackLimits.maxPictureBytes else { return .failure(.pictureTooLarge(id: id)) }
            guard let header = LovePictureHeader.read(bytes) else { return .failure(.pictureWrongType(id: id)) }
            guard header.width > 0, header.height > 0,
                  header.width <= LovePackLimits.maxPictureSide,
                  header.height <= LovePackLimits.maxPictureSide else {
                return .failure(.pictureTooBig(id: id))
            }
            let slots = item.slots ?? []
            if let unknown = slots.first(where: { !LovePictureSlot.isKnown($0) }) {
                return .failure(.unknownSlot(id: id, slot: unknown))
            }
            images.append(LovePackImage(id: id, format: header.format, slots: slots, lore: item.lore ?? []))
            pictures[id] = bytes
        }

        let pack = LovePack(
            packId: packId,
            nickname: nickname,
            signature: signature,
            themeName: themeName,
            startDate: startDate,
            seed: seed,
            daily: daily,
            openWhen: openWhen,
            coupons: coupons,
            countdown: countdown,
            images: images
        )
        return .success(LoadedLovePack(pack: pack, pictures: pictures))
    }

    /// The list-wide rules: size, every id present and valid, no repeats.
    private static func checkList(_ list: String, _ ids: [String?]) -> LovePackProblem? {
        guard ids.count <= LovePackLimits.maxItemsPerList else { return .tooManyItems(list: list) }
        var seen = Set<String>()
        for maybeId in ids {
            guard let id = maybeId, !id.isEmpty else { return .missingField("\(list)[].id") }
            guard LovePackLimits.isValidId(id) else { return .invalidId(list: list, id: id) }
            guard seen.insert(id).inserted else { return .duplicateId(list: list, id: id) }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func fieldName(_ path: [CodingKey]) -> String {
        path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    // The wire shape: everything optional, so a missing field is named
    // instead of failing as "not a pack".
    private struct WirePack: Decodable {
        var format: String?
        var version: Int?
        var packId: String?
        var nickname: String?
        var themeName: String?
        var signature: String?
        var startDate: String?
        var seed: String?
        var daily: [WireDaily]?
        var openWhen: [WireOpenWhen]?
        var coupons: [WireCoupon]?
        var countdown: WireCountdown?
        var images: [WireImage]?
    }

    private struct WireDaily: Decodable {
        var id: String?
        var text: String?
    }

    private struct WireOpenWhen: Decodable {
        var id: String?
        var title: String?
        var text: String?
    }

    private struct WireCoupon: Decodable {
        var id: String?
        var title: String?
        var price: Int?
    }

    private struct WireCountdown: Decodable {
        var date: String?
        var title: String?
    }

    private struct WireImage: Decodable {
        var id: String?
        var slots: [String]?
        var lore: [String]?
        var data: String?
    }
}

// MARK: - Picture headers

/// Reads a PNG's or a JPEG's pixel size from its header, without decoding
/// the picture (no UIKit/ImageIO here). Anything else is "not a picture".
public struct LovePictureHeader: Sendable, Equatable {
    public let format: LovePictureFormat
    public let width: Int
    public let height: Int

    public static func read(_ data: Data) -> LovePictureHeader? {
        let bytes = [UInt8](data.prefix(64 * 1024))
        if let png = readPNG(bytes) { return png }
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return readJPEG([UInt8](data))
        }
        return nil
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func readPNG(_ bytes: [UInt8]) -> LovePictureHeader? {
        // Signature, then the IHDR chunk: length (4), "IHDR" (4), width (4), height (4).
        guard bytes.count >= 24, Array(bytes[0..<8]) == pngSignature,
              bytes[12] == 0x49, bytes[13] == 0x48, bytes[14] == 0x44, bytes[15] == 0x52 else { return nil }
        return LovePictureHeader(format: .png, width: bigEndian32(bytes, 16), height: bigEndian32(bytes, 20))
    }

    private static func readJPEG(_ bytes: [UInt8]) -> LovePictureHeader? {
        // Walk the marker segments to the first start-of-frame (SOF0...SOF15,
        // except DHT C4, JPG C8 and DAC CC), which holds height then width.
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { return nil }
            let marker = bytes[index + 1]
            if marker == 0xFF { index += 1; continue }        // fill byte
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 {
                index += 2                                      // no length
                continue
            }
            if marker == 0xD9 || marker == 0xDA { return nil } // end, or scan data before any frame
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2 else { return nil }
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                guard index + 9 <= bytes.count else { return nil }
                let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                return LovePictureHeader(format: .jpeg, width: width, height: height)
            }
            index += 2 + length
        }
        return nil
    }

    private static func bigEndian32(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
    }
}
