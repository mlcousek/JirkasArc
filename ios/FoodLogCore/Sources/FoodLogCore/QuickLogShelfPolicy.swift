// QuickLogShelfPolicy.swift
//
// improve-food-day-flow (A3, design D5): when the Today screen's two
// quick-log shelves ("Log again" and "Log a meal") are shown. They used to
// show on today's date only, so catching up yesterday meant going through
// search for foods that were one tap away on today. The rule now follows the
// day being shown:
//
//   - a past day, or today: shown whenever the shelf has something in it;
//   - a day after today: only where the day switcher can reach one -- the
//     training experience ("what's tomorrow?"). Food-first stops at today,
//     so it never asks for a future day; if it ever did, the answer is no;
//   - an empty shelf: never.
//
// The confirm screens already take the day being viewed as their date, so a
// food or meal picked from a shelf lands on that day. Nothing here knows
// about experiences: the caller says whether future days are reachable.
//
// Pure. Depended on by: the app's TodayView (card availability). Tests:
// QuickLogShelfPolicyTests.

import Foundation

public enum QuickLogShelfPolicy {
    /// Where the day on screen stands relative to today.
    public enum ShownDay: Sendable, Equatable {
        case past
        case today
        case future
    }

    /// The day `selected` is on, relative to `now`, in `calendar`'s days.
    public static func shownDay(selected: Date, now: Date = Date(), calendar: Calendar = .current) -> ShownDay {
        if calendar.isDate(selected, inSameDayAs: now) { return .today }
        return selected < now ? .past : .future
    }

    /// Whether a quick-log shelf is shown on `day`.
    public static func showsShelf(on day: ShownDay, hasItems: Bool, allowsFutureDays: Bool) -> Bool {
        guard hasItems else { return false }
        switch day {
        case .past, .today:
            return true
        case .future:
            return allowsFutureDays
        }
    }
}
