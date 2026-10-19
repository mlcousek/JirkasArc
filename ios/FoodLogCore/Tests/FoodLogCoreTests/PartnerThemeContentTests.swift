// PartnerThemeContentTests.swift
//
// add-partner-love-theme D5: the committed Czech table of the partner theme
// (ios/GarminFood/PartnerTheme/Resources/partner-theme.cs.json, read from
// disk -- the app target has no tests) decodes, words every reminder kind,
// has every text the app reads, ranks covering all 20 level tiers, the
// D9 achievements, and only the placeholders the app fills.

import XCTest
@testable import FoodLogCore

final class PartnerThemeContentTests: XCTestCase {
    private static let tableURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FoodLogCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // FoodLogCore
        .deletingLastPathComponent() // ios
        .appendingPathComponent("GarminFood/PartnerTheme/Resources/partner-theme.cs.json")

    private func content() throws -> PartnerThemeContent {
        try PartnerThemeContent.decode(Data(contentsOf: Self.tableURL))
    }

    func testEveryReminderKindHasVariants() throws {
        let table = try content()
        for kind in PartnerThemeContent.requiredNotificationKinds {
            XCTAssertFalse(table.notifications[kind]?.isEmpty ?? true, kind)
        }
        // Supplement and fasting variants keep the standard body.
        for kind in [ThemedNotificationTexts.Kind.supplementSlot, ThemedNotificationTexts.Kind.fastingEnds] {
            XCTAssertTrue(table.notifications[kind]?.allSatisfy { $0.body == nil } ?? false, kind)
        }
    }

    func testEveryTextAndPluralTheAppReadsIsThere() throws {
        let table = try content()
        for key in PartnerThemeContent.TextKey.all {
            XCTAssertFalse(table.text(key).isEmpty, key)
        }
        for key in PartnerThemeContent.PluralKey.all {
            XCTAssertNotNil(table.plurals[key], key)
        }
        XCTAssertEqual(table.counted(213, PartnerThemeContent.PluralKey.days), "213 dní")
        XCTAssertEqual(table.counted(3, PartnerThemeContent.PluralKey.hearts), "3 srdíčka")
        XCTAssertEqual(table.text(PartnerThemeContent.TextKey.greetingMorning, ["nickname": "Ninja"]), "Dobré ráno, Ninja ❤️")
        XCTAssertEqual(table.themeName, "Srdce ninji")
    }

    func testRanksCoverEveryLevelTierInOrder() throws {
        let table = try content()
        XCTAssertEqual(table.ranks.map(\.id), LovePictureSlot.ranks)
        XCTAssertEqual(table.ranks.first?.fromTier, 1)
        XCTAssertEqual(table.ranks.map(\.fromTier), table.ranks.map(\.fromTier).sorted())
        XCTAssertEqual(table.rank(forTier: 1)?.name, "Akademie")
        XCTAssertEqual(table.rank(forTier: 4)?.name, "Genin")
        XCTAssertEqual(table.rank(forTier: 20)?.name, "Kage")
        for tier in 1...20 { XCTAssertNotNil(table.rank(forTier: tier), "tier \(tier)") }
    }

    func testTheDesignsAchievementsAreWorded() throws {
        let ids = [
            "p.firstnote", "p.week", "p.box30", "p.box100", "p.box365", "p.morning", "p.genin", "p.chunin",
            "p.jonin", "p.kage", "p.ramen", "p.water", "p.clone", "p.active", "p.scroll", "p.coupon",
            "p.heart10", "p.night", "p.allfav"
        ]
        let table = try content()
        XCTAssertEqual(Set(table.achievements.keys), Set(ids))
    }

    func testOnlyKnownPlaceholdersAreUsed() throws {
        let raw = try String(contentsOf: Self.tableURL, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: "\\{([a-z]+)\\}")
        let names = Set(pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap {
            Range($0.range(at: 1), in: raw).map { String(raw[$0]) }
        })
        XCTAssertTrue(names.isSubset(of: ["nickname", "signature", "count", "title", "date"]), "\(names.sorted())")
    }

    func testTheTableBecomesThemedNotificationTexts() throws {
        let texts = try content().notificationTexts(seed: "sample-seed-0001", nickname: "Ninja", signature: "Tvůj J.")
        let standard = NotificationPlanning.NotificationText(title: "Log your breakfast", body: "Don't forget to log breakfast today.")
        let themed = texts.text(kind: "mealReminder.breakfast", day: "2030-03-14", standard: standard)
        XCTAssertNotEqual(themed.title, standard.title)
        XCTAssertFalse(themed.title.contains("{") || themed.body.contains("{"))
    }
}
