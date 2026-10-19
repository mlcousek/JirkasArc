// LoveTestSupport.swift
//
// add-partner-love-theme: builders shared by the love tests -- a synthetic
// pack as wire JSON (the `.arclove` shape), tiny PNG/JPEG headers, a fixed
// Prague calendar. Nothing personal: nickname "Ninja", dates in 2030.

import Foundation
@testable import FoodLogCore

enum LoveTestSupport {
    static var prague: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// A PNG signature and IHDR chunk with the given size (no pixel data:
    /// the reader only looks at the header).
    static func png(width: Int, height: Int) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += [0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]
        bytes += bigEndian32(width) + bigEndian32(height)
        bytes += [0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        return Data(bytes)
    }

    /// A JPEG with an APP0 segment and a baseline start-of-frame.
    static func jpeg(width: Int, height: Int) -> Data {
        var bytes: [UInt8] = [0xFF, 0xD8]
        bytes += [0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]
        bytes += [0xFF, 0xC0, 0x00, 0x11, 0x08]
        bytes += [UInt8(height >> 8 & 0xFF), UInt8(height & 0xFF), UInt8(width >> 8 & 0xFF), UInt8(width & 0xFF)]
        bytes += [0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]
        bytes += [0xFF, 0xD9]
        return Data(bytes)
    }

    private static func bigEndian32(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    /// The wire pack as a dictionary, so a test can break one field.
    static func wirePack(
        packId: String = "sample-pack-0001",
        dailyCount: Int = 30,
        images: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "format": "love-pack",
            "version": 1,
            "packId": packId,
            "nickname": "Ninja",
            "signature": "Tvůj J.",
            "startDate": "2030-01-01",
            "seed": "sample-seed-0001",
            "daily": (1...max(dailyCount, 1)).prefix(dailyCount).map { ["id": String(format: "d%03ld", $0), "text": "Ukázkový vzkaz \($0)"] },
            "openWhen": [["id": "o-sad", "title": "Otevři, až jsi smutná", "text": "Ukázkový text."]],
            "coupons": [["id": "c001", "title": "Večeře podle tvého výběru", "price": 40]],
            "countdown": ["date": "2031-06-20", "title": "Svatba"],
            "images": images
        ]
    }

    static func wireImage(id: String, data: Data, slots: [String] = ["loveCard"]) -> [String: Any] {
        ["id": id, "slots": slots, "lore": ["ramen"], "data": data.base64EncodedString()]
    }

    static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func pack(dailyCount: Int = 30, packId: String = "sample-pack-0001", startDate: String = "2030-01-01") -> LovePack {
        LovePack(
            packId: packId,
            nickname: "Ninja",
            signature: "Tvůj J.",
            startDate: startDate,
            seed: "sample-seed-0001",
            daily: (1...max(dailyCount, 1)).prefix(dailyCount).map { LovePackDaily(id: String(format: "d%03ld", $0), text: "Ukázkový vzkaz \($0)") }
        )
    }

    static func date(_ day: String, _ hour: Int, _ minute: Int, calendar: Calendar = prague) -> Date {
        LoveDay.date(day: day, minute: hour * 60 + minute, calendar: calendar)!
    }
}
