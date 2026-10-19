// PartnerAchievements.swift
//
// add-partner-love-theme D9, spec partner-achievements: "Svitky srdce",
// the achievements that exist only in the partner theme. Pure rules over
// what the phone already knows -- her love state (reveals, favourites,
// scrolls, coupons, a few marks) and the gamification day signals -- and
// counted only from the day the pack was imported, so nothing unlocks in a
// burst on day one.
//
// They pay hearts, never XP: an unlock IS its line in the hearts ledger
// (`achievement:<id>`, LoveState.earnHearts, idempotent), so there is no
// second store to keep in step and the XP budget (XPBudgetTests) is never
// touched. The words (title, description) are in the theme's Czech table;
// this file has ids, rules and amounts only.
//
// "Same food on five days" stands in for the design's "same meal preset":
// the day signals carry foods, not presets. `p.active` counts days with at
// least `activeDayKcal` active kcal (add-health-active-calories; the app
// passes them as `activeGoalMetDays`).
//
// Pure. Depended on by the app's PartnerThemeModel. Tests:
// PartnerAchievementsTests.

import Foundation

public struct PartnerAchievementDefinition: Sendable, Equatable, Identifiable {
    public let id: String
    public let hearts: Int
    /// Hidden until unlocked (shown as "???").
    public let isSecret: Bool
    /// Exists only when the pack has scrolls / coupons.
    public let needsScrolls: Bool
    public let needsCoupons: Bool
    /// An SF Symbol until the badge art exists (task 6.5).
    public let symbol: String

    init(_ id: String, hearts: Int, symbol: String, secret: Bool = false, scrolls: Bool = false, coupons: Bool = false) {
        self.id = id
        self.hearts = hearts
        self.isSecret = secret
        self.needsScrolls = scrolls
        self.needsCoupons = coupons
        self.symbol = symbol
    }
}

/// What the rules read, all counted from the import day.
public struct PartnerAchievementFacts: Sendable, Equatable {
    /// Days (since import) with at least one food entry, sorted.
    public var loggedDays: [String]
    /// Days with breakfast, lunch and dinner each logged.
    public var allMainMealsDays: Int
    /// Days whose water goal was met.
    public var waterGoalDays: Int
    /// Days whose active-calorie goal was met.
    public var activeGoalMetDays: Int
    /// Whether a ramen or noodle food was logged.
    public var loggedRamen: Bool
    /// The most days any one food was logged on.
    public var sameFoodDays: Int
    /// The current food streak, capped at the days since import.
    public var streak: Int

    public init(
        loggedDays: [String] = [],
        allMainMealsDays: Int = 0,
        waterGoalDays: Int = 0,
        activeGoalMetDays: Int = 0,
        loggedRamen: Bool = false,
        sameFoodDays: Int = 0,
        streak: Int = 0
    ) {
        self.loggedDays = loggedDays
        self.allMainMealsDays = allMainMealsDays
        self.waterGoalDays = waterGoalDays
        self.activeGoalMetDays = activeGoalMetDays
        self.loggedRamen = loggedRamen
        self.sameFoodDays = sameFoodDays
        self.streak = streak
    }

    /// The facts of `snapshot`'s days on or after `importDay`, with the
    /// main streak capped at the days since import.
    public static func from(snapshot: SignalsSnapshot, importDay: String, streakLength: Int, activeGoalMetDays: Int = 0) -> PartnerAchievementFacts {
        let days = snapshot.days.values.filter { $0.day >= importDay }.sorted { $0.day < $1.day }
        let logged = days.filter { !$0.entries.isEmpty }
        let mainMeals: Set<SignalMeal> = [.breakfast, .lunch, .dinner]
        var daysByFood: [String: Set<String>] = [:]
        var ramen = false
        for day in logged {
            for entry in day.entries {
                daysByFood[entry.foodId, default: []].insert(day.day)
                let name = (entry.name ?? "").lowercased()
                if name.contains("ramen") || name.contains("nudl") || name.contains("noodle") { ramen = true }
            }
        }
        let sinceImport = (LoveDay.days(from: importDay, to: snapshot.today) ?? 0) + 1
        return PartnerAchievementFacts(
            loggedDays: logged.map(\.day),
            allMainMealsDays: logged.filter { mainMeals.isSubset(of: Set($0.entries.map(\.meal))) }.count,
            waterGoalDays: days.filter { day in
                guard let water = day.waterML, let goal = day.waterGoalML, goal > 0 else { return false }
                return water >= goal
            }.count,
            activeGoalMetDays: activeGoalMetDays,
            loggedRamen: ramen,
            sameFoodDays: daysByFood.values.map(\.count).max() ?? 0,
            streak: max(0, min(streakLength, sinceImport))
        )
    }
}

public enum PartnerAchievements {
    /// Marks the app sets in LoveState for the secret and timing rules.
    public enum Mark {
        /// `quickOpen:<day>`: that day's notification opened within 15 min.
        public static func quickOpen(_ day: String) -> String { "quickOpen:" + day }
        /// Ten taps on the love card's heart in a row.
        public static let heartTaps = "heartTaps10"
        /// The message box opened after 23:00.
        public static let nightBox = "nightBox"
    }

    /// A day counts for "Ohnivá vůle" (`p.active`) with this many active kcal.
    public static let activeDayKcal: Double = 300

    public static let all: [PartnerAchievementDefinition] = [
        .init("p.firstnote", hearts: 5, symbol: "envelope.open.fill"),
        .init("p.week", hearts: 10, symbol: "calendar.badge.checkmark"),
        .init("p.box30", hearts: 15, symbol: "tray.full.fill"),
        .init("p.box100", hearts: 40, symbol: "books.vertical.fill"),
        .init("p.box365", hearts: 100, symbol: "heart.text.square.fill"),
        .init("p.morning", hearts: 15, symbol: "sunrise.fill"),
        .init("p.genin", hearts: 5, symbol: "star.fill"),
        .init("p.chunin", hearts: 20, symbol: "star.circle.fill"),
        .init("p.jonin", hearts: 40, symbol: "flame.fill"),
        .init("p.kage", hearts: 100, symbol: "crown.fill"),
        .init("p.ramen", hearts: 10, symbol: "fork.knife"),
        .init("p.water", hearts: 15, symbol: "drop.fill"),
        .init("p.clone", hearts: 10, symbol: "square.on.square.fill"),
        .init("p.active", hearts: 15, symbol: "bolt.heart.fill"),
        .init("p.scroll", hearts: 5, symbol: "scroll.fill", scrolls: true),
        .init("p.coupon", hearts: 5, symbol: "ticket.fill", coupons: true),
        .init("p.heart10", hearts: 10, symbol: "heart.circle.fill", secret: true),
        .init("p.night", hearts: 5, symbol: "moon.stars.fill", secret: true),
        .init("p.allfav", hearts: 15, symbol: "heart.square.fill", secret: true)
    ]

    /// The achievements this pack offers (scroll and coupon ones only with
    /// such content).
    public static func available(for pack: LovePack) -> [PartnerAchievementDefinition] {
        all.filter { (!$0.needsScrolls || !pack.openWhen.isEmpty) && (!$0.needsCoupons || !pack.coupons.isEmpty) }
    }

    public static func isUnlocked(_ id: String, in state: LoveState) -> Bool {
        state.hearts.contains { $0.id == "achievement:" + id }
    }

    /// Whether `id`'s rule holds.
    public static func holds(_ id: String, facts: PartnerAchievementFacts, state: LoveState) -> Bool {
        let revealed = state.revealed.values.filter { $0.day >= state.importDay }
        switch id {
        case "p.firstnote": return revealed.count >= 1
        case "p.week": return longestRun(revealed.map(\.day)) >= 7
        case "p.box30": return revealed.count >= 30
        case "p.box100": return revealed.count >= 100
        case "p.box365": return revealed.count >= 365
        case "p.morning": return state.marks.keys.filter { $0.hasPrefix("quickOpen:") }.count >= 5
        case "p.genin": return facts.streak >= 3
        case "p.chunin": return facts.allMainMealsDays >= 7
        case "p.jonin": return facts.streak >= 30
        case "p.kage": return facts.streak >= 100
        case "p.ramen": return facts.loggedRamen
        case "p.water": return facts.waterGoalDays >= 7
        case "p.clone": return facts.sameFoodDays >= 5
        case "p.active": return facts.activeGoalMetDays >= 5
        case "p.scroll": return !state.openedScrolls.isEmpty
        case "p.coupon": return !state.redeemedCoupons.isEmpty
        case "p.heart10": return state.marks[Mark.heartTaps] != nil
        case "p.night": return state.marks[Mark.nightBox] != nil
        case "p.allfav": return state.favorites.count >= 20
        default: return false
        }
    }

    /// Pays the hearts of every available achievement whose rule now holds
    /// and that was not paid yet. Returns those newly unlocked, in catalog
    /// order.
    @discardableResult
    public static func award(pack: LovePack, facts: PartnerAchievementFacts, state: inout LoveState, now: Date) -> [PartnerAchievementDefinition] {
        var unlocked: [PartnerAchievementDefinition] = []
        for definition in available(for: pack) where !isUnlocked(definition.id, in: state) {
            guard holds(definition.id, facts: facts, state: state) else { continue }
            if state.earnHearts(achievementId: definition.id, amount: definition.hearts, at: now) {
                unlocked.append(definition)
            }
        }
        return unlocked
    }

    /// The longest run of consecutive days in `days`.
    static func longestRun(_ days: [String]) -> Int {
        let sorted = Array(Set(days)).sorted()
        var best = 0, run = 0
        var previous: String?
        for day in sorted {
            if let previous, LoveDay.adding(1, to: previous) == day { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }
}
