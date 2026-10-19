// LoveReveal.swift
//
// add-partner-love-theme D6: when a day's message may be SEEN. A message is
// revealed at its minute, or when its notification is opened, whichever
// comes first -- and never before: the text of a day whose minute has not
// come must not be visible anywhere (spec love-messages, "A message is
// revealed only once its time has come"). Revealing does not depend on the
// notification having fired, so a phone with notifications off still fills
// the message box day by day.
//
// `catchUp` reveals every due day since the last revealed one (or the first
// day), so a phone left closed for a week shows that week's messages when
// it is opened again.
//
// The other reminders a day has decide its minute (LoveMinute's clash
// rule), so callers pass the same `otherReminderMinutes` the notification
// planning used; Today and the notification then agree on the minute.
//
// Pure. Depended on by the app's love card and message box. Tests:
// LoveRevealTests.

import Foundation

public enum LoveReveal {
    /// What the love card shows for `day`.
    public enum DayState: Sendable, Equatable {
        /// Before the first day, or a day with no message.
        case none
        /// The message arrives at `at`; its text is not available yet.
        case arrives(at: Date)
        case revealed(RevealedLoveMessage)
    }

    /// The instant `day`'s message is due.
    public static func dueDate(
        day: String,
        pack: LovePack,
        otherReminderMinutes: [Int],
        calendar: Calendar = .current
    ) -> Date? {
        let minute = LoveMinute.minute(seed: pack.seed, day: day, otherReminderMinutes: otherReminderMinutes)
        return LoveDay.date(day: day, minute: minute, calendar: calendar)
    }

    /// Reveals `day`'s message if it is due at `now` (or `openedFromNotification`),
    /// assigning it first when needed. Returns what the love card shows.
    @discardableResult
    public static func reveal(
        day: String,
        pack: LovePack,
        state: inout LoveState,
        now: Date,
        otherReminderMinutes: [Int] = [],
        openedFromNotification: Bool = false,
        calendar: Calendar = .current
    ) -> DayState {
        if let revealed = state.revealed[day] { return .revealed(revealed) }
        let today = LoveDay.key(of: now, calendar: calendar)
        guard day <= today, day >= DailyLoveMessage.firstDay(pack: pack, state: state),
              let due = dueDate(day: day, pack: pack, otherReminderMinutes: otherReminderMinutes, calendar: calendar) else {
            return .none
        }
        guard now >= due || openedFromNotification else { return .arrives(at: due) }

        DailyLoveMessage.assign(days: [day], pack: pack, state: &state)
        guard let message = DailyLoveMessage.message(for: day, pack: pack, state: state) else { return .none }
        let revealed = RevealedLoveMessage(
            day: day,
            messageId: message.id,
            text: message.text,
            revealedAt: now,
            isRepeat: DailyLoveMessage.isRepeat(day: day, state: state)
        )
        state.revealed[day] = revealed
        return .revealed(revealed)
    }

    /// What the love card shows for `day`, without revealing anything.
    public static func state(
        day: String,
        pack: LovePack,
        state: LoveState,
        now: Date,
        otherReminderMinutes: [Int] = [],
        calendar: Calendar = .current
    ) -> DayState {
        if let revealed = state.revealed[day] { return .revealed(revealed) }
        guard day >= DailyLoveMessage.firstDay(pack: pack, state: state),
              let due = dueDate(day: day, pack: pack, otherReminderMinutes: otherReminderMinutes, calendar: calendar) else {
            return .none
        }
        return .arrives(at: due)
    }

    /// Reveals every due day from the day after the newest revealed one
    /// (or the first day) through today, at most `maxDays` of them, oldest
    /// first. Past days are due whatever their minute was; today only once
    /// its minute has come. `otherReminderMinutes` is today's.
    public static func catchUp(
        pack: LovePack,
        state: inout LoveState,
        now: Date,
        otherReminderMinutes: [Int] = [],
        maxDays: Int = 400,
        calendar: Calendar = .current
    ) {
        let today = LoveDay.key(of: now, calendar: calendar)
        let first = DailyLoveMessage.firstDay(pack: pack, state: state)
        var day: String
        if let newest = state.revealed.keys.max(), let next = LoveDay.adding(1, to: newest) {
            day = max(next, first)
        } else {
            day = first
        }
        // Never more than `maxDays`: skip ahead to the most recent ones.
        if let span = LoveDay.days(from: day, to: today), span >= maxDays,
           let start = LoveDay.adding(-(maxDays - 1), to: today) {
            day = start
        }
        var past: [String] = []
        while day < today {
            past.append(day)
            guard let next = LoveDay.adding(1, to: day) else { break }
            day = next
        }
        DailyLoveMessage.assign(days: past, pack: pack, state: &state)
        for pastDay in past {
            guard state.revealed[pastDay] == nil,
                  let message = DailyLoveMessage.message(for: pastDay, pack: pack, state: state) else { continue }
            state.revealed[pastDay] = RevealedLoveMessage(
                day: pastDay,
                messageId: message.id,
                text: message.text,
                revealedAt: now,
                isRepeat: DailyLoveMessage.isRepeat(day: pastDay, state: state)
            )
        }
        reveal(day: today, pack: pack, state: &state, now: now, otherReminderMinutes: otherReminderMinutes, calendar: calendar)
    }
}
