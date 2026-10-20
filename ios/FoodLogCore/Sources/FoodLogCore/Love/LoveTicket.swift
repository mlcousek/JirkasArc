// LoveTicket.swift
//
// add-partner-love-theme: the ticket a redeemed love coupon becomes. Shown
// as a QR code and a line of text she can show the owner:
//
//   LASKA1:<couponId>:<yyyyMMddHHmm UTC>:<code>
//
// <code> is HMAC-SHA256 over "v1|packId|couponId|minute", keyed by
// SHA-256("arclove-ticket|" + the pack's seed), its first 40 bits written in
// Crockford base32 as XXXX-XXXX. The seed is in the pack and never shown in
// the app, so a ticket cannot be made up, or a date or coupon edited,
// without redeeming in the app; the owner checks one with
// tools/love-pack/verify-ticket.mjs (ticket.mjs is the same algorithm;
// the shared vector is in LoveTicketTests and tools/love-pack/test.mjs).
//
// Deterministic: the same redemption always shows the same ticket, so it can
// be opened again later. Pure. Tests: LoveTicketTests.

import CryptoKit
import Foundation

public struct LoveTicket: Sendable, Equatable {
    public static let prefix = "LASKA1"
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public let couponId: String
    /// `yyyyMMddHHmm`, UTC.
    public let minute: String
    public let code: String

    /// What the QR code holds and the line under it shows.
    public var payload: String { "\(Self.prefix):\(couponId):\(minute):\(code)" }

    public static func make(pack: LovePack, couponId: String, redeemedAt: Date) -> LoveTicket {
        let minute = minuteKey(redeemedAt)
        return LoveTicket(couponId: couponId, minute: minute, code: code(seed: pack.seed, packId: pack.packId, couponId: couponId, minute: minute))
    }

    /// Whether `payload` is a genuine ticket of one of `pack`'s coupons.
    public static func verify(_ payload: String, pack: LovePack) -> LoveTicket? {
        let parts = payload.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0].uppercased() == prefix,
              pack.coupons.contains(where: { $0.id == parts[1] }),
              parts[2].count == 12, parts[2].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let expected = code(seed: pack.seed, packId: pack.packId, couponId: parts[1], minute: parts[2])
        guard expected == parts[3].uppercased() else { return nil }
        return LoveTicket(couponId: parts[1], minute: parts[2], code: expected)
    }

    static func code(seed: String, packId: String, couponId: String, minute: String) -> String {
        let key = SymmetricKey(data: SHA256.hash(data: Data("arclove-ticket|\(seed)".utf8)))
        let mac = HMAC<SHA256>.authenticationCode(for: Data("v1|\(packId)|\(couponId)|\(minute)".utf8), using: key)
        let bits = Array(mac).prefix(5).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let chars = (0..<8).reversed().map { alphabet[Int((bits >> UInt64($0 * 5)) & 31)] }
        return String(chars[0..<4]) + "-" + String(chars[4..<8])
    }

    static func minuteKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let p = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04ld%02ld%02ld%02ld%02ld", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0)
    }
}
