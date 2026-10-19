// LoveMinute.swift
//
// add-partner-love-theme D6: WHEN the day's love message arrives -- a
// "random" minute from 08:00 to 12:59, every day of the week (owner
// decision 2026-10-19), that is nevertheless the same every time it is
// computed. The notification scheduler re-plans on every foreground and
// keeps 7 days pending; a minute drawn from a random generator would move
// the pending notification on every re-plan. So the minute is derived only
// from the pack's seed and the date: SHA-256, first 8 bytes, modulo the
// 300-minute window. The same answer after a restore and on every launch.
//
// It moves only to keep away from the app's other reminders that day: a
// minute within 10 minutes of another planned reminder goes to the next
// free minute before 13:00 (spec love-messages, "Clash with breakfast").
//
// Pure. Depended on by the app's notification planning and LoveReveal.
// Tests: LoveMinuteTests.

import CryptoKit
import Foundation

public enum LoveMinute {
    /// 08:00, in minutes after midnight.
    public static let windowStart = 8 * 60
    /// 13:00 -- exclusive.
    public static let windowEnd = 13 * 60
    /// Another reminder this close (either side, inclusive) is a clash.
    public static let clashGap = 10

    /// The day's minute before any clash is resolved.
    public static func baseMinute(seed: String, day: String) -> Int {
        windowStart + Int(stableHash(seed, day) % UInt64(windowEnd - windowStart))
    }

    /// The day's minute, kept away from `otherReminderMinutes` (minutes
    /// after midnight of the same day's other planned reminders).
    public static func minute(seed: String, day: String, otherReminderMinutes: [Int]) -> Int {
        resolve(base: baseMinute(seed: seed, day: day), otherReminderMinutes: otherReminderMinutes)
    }

    /// The first free minute at or after `base` and before 13:00; when
    /// there is none, the nearest free one before `base` (never before
    /// 08:00); when the whole window is taken, `base` itself -- a
    /// notification next to another beats no love message.
    public static func resolve(base: Int, otherReminderMinutes: [Int]) -> Int {
        func isFree(_ minute: Int) -> Bool {
            otherReminderMinutes.allSatisfy { abs($0 - minute) > clashGap }
        }
        if isFree(base) { return base }
        var candidate = base + 1
        while candidate < windowEnd {
            if isFree(candidate) { return candidate }
            candidate += 1
        }
        candidate = base - 1
        while candidate >= windowStart {
            if isFree(candidate) { return candidate }
            candidate -= 1
        }
        return base
    }

    /// SHA-256 of the parts joined by `|`, first 8 bytes big-endian. Also
    /// the order of messages and pictures (DailyLoveMessage,
    /// PictureRotation), so every "random" choice of the theme is stable.
    public static func stableHash(_ parts: String...) -> UInt64 {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
