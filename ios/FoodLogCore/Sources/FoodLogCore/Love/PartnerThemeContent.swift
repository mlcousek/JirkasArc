// PartnerThemeContent.swift
//
// add-partner-love-theme D5: the shape of the partner theme's own Czech
// text -- `ios/GarminFood/PartnerTheme/Resources/partner-theme.cs.json`.
// The theme is Czech only, so its words live in this one table rather than
// in the en+cs string catalogs (whose completeness check would demand an
// English for every line). Every entry carries its lore tags, which CI
// checks against the spoiler allow-list (tools/love-pack/lint-theme-content.mjs).
//
// Here, and not in the app, so a test can decode the committed table and
// prove every reminder kind, rank and achievement has its words: the app
// target has no unit tests.
//
// Placeholders: `{nickname}`, `{signature}`, `{count}`, `{title}`, `{date}`.
//
// Pure. Depended on by the app's PartnerText. Tests: PartnerThemeContentTests.

import Foundation

public struct PartnerThemeContent: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public let text: String
        public let lore: [String]
    }

    public struct Notification: Codable, Sendable, Equatable {
        public let title: String
        public let body: String?
        public let lore: [String]
    }

    public struct Rank: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        /// The first level tier (1-based, of LevelTier's 20) with this rank.
        public let fromTier: Int
        public let lore: [String]
    }

    public struct Achievement: Codable, Sendable, Equatable {
        public let title: String
        public let description: String
        public let lore: [String]
    }

    /// Czech plural forms of one counted word.
    public struct Plural: Codable, Sendable, Equatable {
        public let one: String
        public let few: String
        public let many: String

        public func word(for count: Int) -> String {
            CzechPlural.choose(count, one: one, few: few, many: many)
        }
    }

    public let themeName: String
    public let loveNotificationTitle: Line
    /// Reminder kind (as `ThemedNotificationTexts` keys them) -> variants.
    public let notifications: [String: [Notification]]
    public let texts: [String: Line]
    public let plurals: [String: Plural]
    public let ranks: [Rank]
    public let achievements: [String: Achievement]

    /// The keys of `texts` the app reads; the test holds the table to them.
    public enum TextKey {
        public static let greetingMorning = "greeting.morning"
        public static let greetingAfternoon = "greeting.afternoon"
        public static let greetingEvening = "greeting.evening"
        public static let messageArrives = "love.arrives"
        public static let allMessagesKnown = "love.allKnown"
        public static let picturesMissing = "love.picturesMissing"
        public static let messageBoxTitle = "box.title"
        public static let messageBoxEmpty = "box.empty"
        public static let favorites = "box.favorites"
        public static let allMessages = "box.all"
        public static let openMessageBox = "box.open"
        public static let signedBy = "love.signedBy"
        public static let scrollsTitle = "scrolls.title"
        public static let scrollSealed = "scrolls.sealed"
        public static let achievementsTitle = "achievements.title"
        public static let achievementsLink = "achievements.link"
        public static let achievementSecret = "achievements.secret"
        public static let couponsTitle = "coupons.title"
        public static let couponRedeem = "coupons.redeem"
        public static let couponRedeemed = "coupons.redeemed"
        public static let countdownToday = "countdown.today"
        public static let countdownDays = "countdown.days"
        public static let heartBalance = "hearts.balance"
        public static let couponMissing = "coupon.missing"

        public static let all = [
            greetingMorning, greetingAfternoon, greetingEvening, messageArrives, allMessagesKnown,
            picturesMissing, messageBoxTitle, messageBoxEmpty, favorites, allMessages, openMessageBox, signedBy,
            scrollsTitle, scrollSealed, achievementsTitle, achievementsLink, achievementSecret,
            couponsTitle, couponRedeem, couponRedeemed,
            countdownToday, countdownDays,
            heartBalance, couponMissing
        ]
    }

    public enum PluralKey {
        public static let days = "days"
        public static let hearts = "hearts"

        public static let all = [days, hearts]
    }

    /// The reminder kinds every theme table must word.
    public static let requiredNotificationKinds = [
        "mealReminder.breakfast", "mealReminder.lunch", "mealReminder.dinner",
        "streakReminder", "dailyChallengeReminder",
        ThemedNotificationTexts.Kind.fastingEnds, ThemedNotificationTexts.Kind.fastingStarts,
        ThemedNotificationTexts.Kind.supplementSlot
    ]

    public static func decode(_ data: Data) throws -> PartnerThemeContent {
        try JSONDecoder().decode(PartnerThemeContent.self, from: data)
    }

    /// The table's reminder variants, filled with the pack's names.
    public func notificationTexts(seed: String, nickname: String, signature: String) -> ThemedNotificationTexts {
        ThemedNotificationTexts(
            seed: seed,
            nickname: nickname,
            signature: signature,
            variants: notifications.mapValues { variants in
                variants.map { NotificationTextVariant(title: $0.title, body: $0.body) }
            }
        )
    }

    /// `texts[key]` with the placeholders replaced (`""` for a missing key,
    /// which PartnerThemeContentTests rules out for the committed table).
    public func text(_ key: String, _ values: [String: String] = [:]) -> String {
        Self.fill(texts[key]?.text ?? "", values)
    }

    /// "213 dní", "1 srdíčko".
    public func counted(_ count: Int, _ pluralKey: String) -> String {
        "\(count) " + (plurals[pluralKey]?.word(for: count) ?? "")
    }

    /// The rank name of a 1-based level tier.
    public func rank(forTier tier: Int) -> Rank? {
        ranks.filter { $0.fromTier <= tier }.max { $0.fromTier < $1.fromTier }
    }

    public static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { text, pair in text.replacingOccurrences(of: "{\(pair.key)}", with: pair.value) }
    }
}
