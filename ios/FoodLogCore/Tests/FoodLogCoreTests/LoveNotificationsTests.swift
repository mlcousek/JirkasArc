// LoveNotificationsTests.swift
//
// add-partner-love-theme D7/D8, specs love-messages and
// reminder-notifications: themed words with unchanged times, stable for
// the day; a love notification for each of the next 7 days at the same
// minute Today reveals at; nothing for a revealed day or a passed minute;
// and the 60-request budget that keeps the love messages.

import XCTest
import GarminKit
@testable import FoodLogCore

final class LoveNotificationsTests: XCTestCase {
    private typealias Support = LoveTestSupport
    private let calendar = LoveTestSupport.prague

    private var preferences: NotificationPreferences {
        var preferences = NotificationPreferences.disabledDefault
        preferences.breakfastReminder = ReminderSetting(isEnabled: true, hour: 8, minute: 30)
        preferences.lunchReminder = ReminderSetting(isEnabled: true, hour: 12, minute: 0)
        preferences.dinnerReminder = ReminderSetting(isEnabled: true, hour: 19, minute: 0)
        preferences.dailyChallengeReminder = ReminderSetting(isEnabled: true, hour: 9, minute: 0)
        return preferences
    }

    private var texts: ThemedNotificationTexts {
        ThemedNotificationTexts(
            seed: "sample-seed-0001",
            nickname: "Ninja",
            signature: "Tvůj J.",
            variants: [
                "mealReminder.breakfast": [
                    NotificationTextVariant(title: "Ninja potřebuje snídani 🍙", body: "Co sis dala, {nickname}?"),
                    NotificationTextVariant(title: "Ranní mise: snídaně", body: "Zapiš ji, {nickname} ❤️"),
                    NotificationTextVariant(title: "Snídaně čeká 🍳", body: "Dobré ráno, {nickname}!")
                ],
                ThemedNotificationTexts.Kind.fastingEnds: [NotificationTextVariant(title: "Půst brzy končí 🥷", body: nil)]
            ]
        )
    }

    // MARK: Themed texts

    func testThemedTextsChangeTheWordsNotTheTimes() {
        let window = NotificationPlanning.planWindow(preferences: preferences, mealsLoggedToday: [], isStreakAtRiskToday: false)
        let themed = NotificationPlanning.themed(window, today: "2030-03-14", texts: texts)

        XCTAssertEqual(themed.count, window.count)
        for (original, new) in zip(window, themed) {
            XCTAssertEqual(new.dayOffset, original.dayOffset)
            XCTAssertEqual(new.notification.id, original.notification.id)
            XCTAssertEqual(new.notification.hour, original.notification.hour)
            XCTAssertEqual(new.notification.minute, original.notification.minute)
        }
        let breakfast = themed.first { $0.dayOffset == 0 && $0.notification.id == "mealReminder.breakfast" }!
        XCTAssertTrue(breakfast.notification.body.contains("Ninja"))
        XCTAssertFalse(breakfast.notification.body.contains("{nickname}"))
        // A kind the table doesn't word keeps its standard text.
        let lunch = themed.first { $0.dayOffset == 0 && $0.notification.id == "mealReminder.lunch" }!
        let standardLunch = window.first { $0.dayOffset == 0 && $0.notification.id == "mealReminder.lunch" }!
        XCTAssertEqual(lunch.notification.text, standardLunch.notification.text)
    }

    func testTheVariantIsStableForTheDayAndVariesAcrossDays() {
        let standard = NotificationPlanning.NotificationText(title: "Log your breakfast", body: "Don't forget.")
        let first = texts.text(kind: "mealReminder.breakfast", day: "2030-03-14", standard: standard)
        XCTAssertEqual(texts.text(kind: "mealReminder.breakfast", day: "2030-03-14", standard: standard), first)

        var titles = Set<String>()
        var day = "2030-03-01"
        for _ in 0..<30 {
            titles.insert(texts.text(kind: "mealReminder.breakfast", day: day, standard: standard).title)
            day = LoveDay.adding(1, to: day)!
        }
        XCTAssertGreaterThan(titles.count, 1)

        // Re-planning twice on one day: the diff has nothing to replace.
        let planned = NotificationPlanning.themed(
            NotificationPlanning.planWindow(preferences: preferences, mealsLoggedToday: [], isStreakAtRiskToday: false),
            today: "2030-03-14", texts: texts
        )
        let again = NotificationPlanning.themed(
            NotificationPlanning.planWindow(preferences: preferences, mealsLoggedToday: [], isStreakAtRiskToday: false),
            today: "2030-03-14", texts: texts
        )
        func byId(_ window: [NotificationPlanning.DatedPlannedNotification]) -> [String: NotificationPlanning.NotificationText] {
            Dictionary(window.map { ("reminder.\($0.notification.id).\($0.dayOffset)", $0.notification.text) }, uniquingKeysWith: { a, _ in a })
        }
        XCTAssertEqual(NotificationPlanning.diff(planned: byId(again), pending: byId(planned), ownedPrefix: "reminder.").toAdd, [])
    }

    func testANilBodyKeepsTheStandardBodyAndRepeatingRemindersKeepOneVariant() {
        let fasting = [NotificationPlanning.PlannedFastingReminder(id: "ends.1185.1200", title: "Fasting window ending soon", body: "Your fast ends at 20:00.", hour: 19, minute: 45)]
        let themed = NotificationPlanning.themed(fasting, texts: texts)
        XCTAssertEqual(themed.first?.title, "Půst brzy končí 🥷")
        XCTAssertEqual(themed.first?.body, "Your fast ends at 20:00.")
        XCTAssertEqual(themed.first?.hour, 19)
        XCTAssertEqual(NotificationPlanning.themed(fasting, texts: nil), fasting)
    }

    // MARK: Love notifications

    func testSevenDaysArePlannedAtTheMinuteTodayRevealsAt() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let now = Support.date("2030-03-14", 7, 0, calendar: calendar)
        let clash = LoveNotificationPlanning.clashMinutes(preferences: preferences, fasting: [])

        let planned = LoveNotificationPlanning.plan(
            pack: pack, state: &state, now: now, clashMinutes: clash, title: "Pro Ninja ❤️", availablePictures: [], calendar: calendar
        )

        XCTAssertEqual(planned.map(\.day), (0..<7).map { LoveDay.adding($0, to: "2030-03-14")! })
        XCTAssertEqual(planned.first?.identifier, "love.daily.2030-03-14")
        XCTAssertEqual(Set(planned.map(\.body)).count, 7)
        XCTAssertEqual(state.assignments.count, 7, "the planned days' messages are recorded")
        for item in planned {
            XCTAssertGreaterThanOrEqual(item.minute, 8 * 60)
            XCTAssertLessThan(item.minute, 13 * 60)
            XCTAssertTrue(clash.allSatisfy { abs($0 - item.minute) > LoveMinute.clashGap }, "\(item.day) \(item.minute)")
            XCTAssertEqual(
                LoveDay.date(day: item.day, minute: item.minute, calendar: calendar),
                LoveReveal.dueDate(day: item.day, pack: pack, otherReminderMinutes: clash, calendar: calendar)
            )
        }
    }

    func testLoggingAMealDoesNotMoveTheMinute() {
        // The clash input is the configured times, not what is pending.
        XCTAssertEqual(
            LoveNotificationPlanning.clashMinutes(preferences: preferences, fasting: []),
            [8 * 60 + 30, 9 * 60, 12 * 60, 19 * 60]
        )
    }

    func testRePlanningGivesTheSameNotifications() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let now = Support.date("2030-03-14", 7, 0, calendar: calendar)
        let first = LoveNotificationPlanning.plan(pack: pack, state: &state, now: now, clashMinutes: [], title: "t", availablePictures: [], calendar: calendar)
        let later = Support.date("2030-03-14", 7, 45, calendar: calendar)
        let second = LoveNotificationPlanning.plan(pack: pack, state: &state, now: later, clashMinutes: [], title: "t", availablePictures: [], calendar: calendar)
        XCTAssertEqual(first, second)
    }

    func testARevealedDayAndAPassedMinuteAreLeftOut() {
        let pack = Support.pack()
        var state = LoveState(packId: pack.packId, importDay: "2030-03-14")
        let afternoon = Support.date("2030-03-14", 13, 0, calendar: calendar)

        let planned = LoveNotificationPlanning.plan(pack: pack, state: &state, now: afternoon, clashMinutes: [], title: "t", availablePictures: [], calendar: calendar)
        XCTAssertEqual(planned.first?.day, "2030-03-15")
        XCTAssertEqual(planned.count, 6)

        LoveReveal.reveal(day: "2030-03-15", pack: pack, state: &state, now: Support.date("2030-03-15", 7, 0, calendar: calendar), openedFromNotification: true, calendar: calendar)
        let next = LoveNotificationPlanning.plan(pack: pack, state: &state, now: Support.date("2030-03-15", 7, 1, calendar: calendar), clashMinutes: [], title: "t", availablePictures: [], calendar: calendar)
        XCTAssertFalse(next.contains { $0.day == "2030-03-15" })
    }

    func testNothingBeforeTheFirstDayAndAPictureWhenItsFileIsThere() {
        let pack = LovePack(
            packId: "p", nickname: "Ninja", signature: "", startDate: "2030-03-17", seed: "sample-seed-0001",
            daily: (1...10).map { LovePackDaily(id: "d\($0)", text: "Vzkaz \($0)") },
            images: [LovePackImage(id: "i001", format: .png, slots: [LovePictureSlot.pictureOfDay], lore: [])]
        )
        var state = LoveState(packId: "p", importDay: "2030-03-14")
        let now = Support.date("2030-03-14", 7, 0, calendar: calendar)

        let planned = LoveNotificationPlanning.plan(pack: pack, state: &state, now: now, clashMinutes: [], title: "t", availablePictures: ["i001"], calendar: calendar)

        XCTAssertEqual(planned.map(\.day), ["2030-03-17", "2030-03-18", "2030-03-19", "2030-03-20"])
        XCTAssertTrue(planned.allSatisfy { $0.pictureId == "i001" })
        let without = LoveNotificationPlanning.plan(pack: pack, state: &state, now: now, clashMinutes: [], title: "t", availablePictures: [], calendar: calendar)
        XCTAssertTrue(without.allSatisfy { $0.pictureId == nil })
    }

    func testTheIdentifierLeadsBackToItsDay() {
        XCTAssertEqual(PlannedLoveNotification.day(fromIdentifier: "love.daily.2030-03-14"), "2030-03-14")
        XCTAssertNil(PlannedLoveNotification.day(fromIdentifier: "reminder.mealReminder.breakfast.2030-03-14"))
        XCTAssertNil(PlannedLoveNotification.day(fromIdentifier: "love.daily.tomorrow"))
    }

    // MARK: Budget

    func testTheFoodWindowShrinksToKeepTheLoveMessages() {
        // Everything on: 4 food requests a day, 7 love, 2 fasting, 12 supplement slots.
        let days = NotificationBudget.foodWindowDays(foodRequestsPerDay: 4, otherPending: 7 + 2 + 12)
        XCTAssertEqual(days, 7, "39 / 4 = 9 days fit; capped at the 7-day window")
        XCTAssertLessThanOrEqual(4 * days + 7 + 2 + 12, NotificationBudget.cap)

        let crowded = NotificationBudget.foodWindowDays(foodRequestsPerDay: 4, otherPending: 7 + 2 + 30)
        XCTAssertEqual(crowded, 5)
        XCTAssertLessThanOrEqual(4 * crowded + 7 + 2 + 30, NotificationBudget.cap)

        XCTAssertEqual(NotificationBudget.foodWindowDays(foodRequestsPerDay: 4, otherPending: 70), 1, "today is always planned")
        XCTAssertEqual(NotificationBudget.foodWindowDays(foodRequestsPerDay: 0, otherPending: 70), 7)
    }
}
