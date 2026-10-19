// LoveState.swift
//
// add-partner-love-theme D1/D6/D9: everything the partner has seen, kept,
// opened and earned in the theme, keyed by the pack's item ids -- never by
// position and never by text -- so a re-import that adds, reorders or
// corrects messages loses or repeats nothing (spec love-pack, "Re-importing
// a pack keeps everything already seen").
//
//   - `assignments`: day -> daily message id, recorded the first time a day
//     is planned and never changed after (DailyLoveMessage). The scheduler
//     plans 7 days ahead, so tomorrow's message is decided today.
//   - `revealed`: day -> the message as it was revealed, TEXT INCLUDED. The
//     message box reads only this, so a message the owner later removes
//     from the pack stays in her box.
//   - `favorites`, `openedScrolls`, `hearts` (the ledger: the balance is
//     derived, never stored).
//
// Persisted by LoveStore as `love-state.json` and included in backups: her
// export is her only off-phone copy of the message history. Pure value
// type; every mutation is a method here so the rules have one home.
// Tests: LoveStoreTests, DailyLoveMessageTests, LoveRevealTests.

import Foundation

public struct RevealedLoveMessage: Codable, Sendable, Equatable {
    public let day: String
    public let messageId: String
    public let text: String
    public let revealedAt: Date
    /// The day repeated an already-known message (the pool ran out).
    public let isRepeat: Bool

    public init(day: String, messageId: String, text: String, revealedAt: Date, isRepeat: Bool) {
        self.day = day
        self.messageId = messageId
        self.text = text
        self.revealedAt = revealedAt
        self.isRepeat = isRepeat
    }
}

/// One line of the hearts ledger: positive when earned, negative when spent.
/// `id` makes earning idempotent (`achievement:<id>`) and a coupon single-use
/// (`coupon:<id>`).
public struct LoveHeartEntry: Codable, Sendable, Equatable {
    public let id: String
    public let amount: Int
    public let at: Date

    public init(id: String, amount: Int, at: Date) {
        self.id = id
        self.amount = amount
        self.at = at
    }
}

public enum LoveCouponRedemption: Sendable, Equatable {
    case redeemed(balance: Int)
    case notEnough(missing: Int)
    case alreadyRedeemed
}

public struct LoveState: Codable, Sendable, Equatable {
    public let packId: String
    /// The day the pack was first imported: partner achievements count from
    /// here, and the daily sequence never reaches back before it.
    public let importDay: String
    public var assignments: [String: String]
    public var revealed: [String: RevealedLoveMessage]
    /// Daily message ids, sorted, no repeats.
    public private(set) var favorites: [String]
    /// Scroll id -> when it was opened.
    public var openedScrolls: [String: Date]
    public private(set) var hearts: [LoveHeartEntry]

    public init(packId: String, importDay: String) {
        self.packId = packId
        self.importDay = importDay
        self.assignments = [:]
        self.revealed = [:]
        self.favorites = []
        self.openedScrolls = [:]
        self.hearts = []
    }

    private enum CodingKeys: String, CodingKey {
        case packId, importDay, assignments, revealed, favorites, openedScrolls, hearts
    }

    /// Lenient on everything but the identity, so a state file written by
    /// a later build with one more field, or missing one, still decodes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packId = try container.decode(String.self, forKey: .packId)
        importDay = try container.decode(String.self, forKey: .importDay)
        assignments = try container.decodeIfPresent([String: String].self, forKey: .assignments) ?? [:]
        revealed = try container.decodeIfPresent([String: RevealedLoveMessage].self, forKey: .revealed) ?? [:]
        favorites = Array(Set(try container.decodeIfPresent([String].self, forKey: .favorites) ?? [])).sorted()
        openedScrolls = try container.decodeIfPresent([String: Date].self, forKey: .openedScrolls) ?? [:]
        hearts = try container.decodeIfPresent([LoveHeartEntry].self, forKey: .hearts) ?? []
    }

    // MARK: Favourites

    public func isFavorite(_ messageId: String) -> Bool {
        favorites.contains(messageId)
    }

    public mutating func setFavorite(_ messageId: String, _ isFavorite: Bool) {
        var set = Set(favorites)
        if isFavorite { set.insert(messageId) } else { set.remove(messageId) }
        favorites = set.sorted()
    }

    // MARK: Message box

    /// Every revealed message, newest day first.
    public var messageBox: [RevealedLoveMessage] {
        revealed.values.sorted { $0.day > $1.day }
    }

    public var revealedCount: Int { revealed.count }

    // MARK: Hearts

    public var heartBalance: Int {
        hearts.reduce(0) { $0 + $1.amount }
    }

    /// Records hearts for an unlocked partner achievement, once.
    /// Returns `false` when it was already paid.
    @discardableResult
    public mutating func earnHearts(achievementId: String, amount: Int, at date: Date) -> Bool {
        let id = "achievement:" + achievementId
        guard amount > 0, !hearts.contains(where: { $0.id == id }) else { return false }
        hearts.append(LoveHeartEntry(id: id, amount: amount, at: date))
        return true
    }

    public func isRedeemed(couponId: String) -> Bool {
        hearts.contains { $0.id == "coupon:" + couponId }
    }

    /// Redeemed coupons with the day they were redeemed, newest first.
    public var redeemedCoupons: [(couponId: String, at: Date)] {
        hearts
            .filter { $0.id.hasPrefix("coupon:") }
            .map { (couponId: String($0.id.dropFirst("coupon:".count)), at: $0.at) }
            .sorted { $0.at > $1.at }
    }

    public mutating func redeem(_ coupon: LovePackCoupon, at date: Date) -> LoveCouponRedemption {
        guard !isRedeemed(couponId: coupon.id) else { return .alreadyRedeemed }
        let balance = heartBalance
        guard balance >= coupon.price else { return .notEnough(missing: coupon.price - balance) }
        hearts.append(LoveHeartEntry(id: "coupon:" + coupon.id, amount: -coupon.price, at: date))
        return .redeemed(balance: heartBalance)
    }

    // MARK: Re-import

    /// Keeps the state in step with an updated pack of the same id: a day
    /// planned but not yet revealed whose message is gone is re-drawn the
    /// next time it is planned. Revealed days are never touched.
    public mutating func reconcile(with pack: LovePack) {
        let ids = Set(pack.daily.map(\.id))
        for (day, messageId) in assignments where revealed[day] == nil && !ids.contains(messageId) {
            assignments.removeValue(forKey: day)
        }
    }
}
