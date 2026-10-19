// LoveDay.swift
//
// add-partner-love-theme: the day arithmetic of the love features, on the
// `yyyy-MM-dd` strings the rest of the app uses as day keys
// (`NutritionDate.string(from:)`). A day key is a calendar date with no time
// zone: "the 14th" is the 14th wherever the phone is. So the arithmetic runs
// on a fixed UTC Gregorian calendar, and only the conversion of a day plus a
// wall-clock minute into an instant (`date(day:minute:calendar:)`) uses the
// device's calendar -- which is what keeps the love message at the same
// wall-clock minute across a DST change (design D6).
//
// Pure. Depended on by LovePack (date validation), DailyLoveMessage,
// LoveReveal, PictureRotation. Tests: LoveMinuteTests, DailyLoveMessageTests.

import Foundation

public enum LoveDay {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The day key's year, month and day, or `nil` when it is not a real
    /// `yyyy-MM-dd` date (2030-02-30 is not).
    public static func components(_ day: String) -> (year: Int, month: Int, day: Int)? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ part in part.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
            return nil
        }
        guard let date = utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) else { return nil }
        let back = utc.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == dayOfMonth else { return nil }
        return (year, month, dayOfMonth)
    }

    public static func isValid(_ day: String) -> Bool {
        components(day) != nil
    }

    /// Whole days from `from` to `to` (negative when `to` is earlier).
    public static func days(from: String, to: String) -> Int? {
        guard let start = utcDate(from), let end = utcDate(to) else { return nil }
        return utc.dateComponents([.day], from: start, to: end).day
    }

    /// `day` moved by `offset` days.
    public static func adding(_ offset: Int, to day: String) -> String? {
        guard let date = utcDate(day), let moved = utc.date(byAdding: .day, value: offset, to: date) else { return nil }
        return key(of: moved, calendar: utc)
    }

    /// The day key of `date` in `calendar` (the device's).
    public static func key(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The instant of `minute` (minutes after midnight, wall clock) on `day`
    /// in `calendar`.
    public static func date(day: String, minute: Int, calendar: Calendar = .current) -> Date? {
        guard let components = triggerComponents(day: day, minute: minute) else { return nil }
        return calendar.date(from: components)
    }

    /// The trigger components for `minute` on `day`: a calendar trigger with
    /// these fires at that wall-clock minute whatever the UTC offset is.
    public static func triggerComponents(day: String, minute: Int) -> DateComponents? {
        guard let parts = components(day) else { return nil }
        return DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: minute / 60, minute: minute % 60)
    }

    private static func utcDate(_ day: String) -> Date? {
        guard let parts = components(day) else { return nil }
        return utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }
}
