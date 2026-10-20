// LoveNotifications.swift
//
// add-partner-love-theme D7/D8: the notification side of the partner
// theme, as pure planning the app's NotificationScheduler applies.
//
//   - `ThemedNotificationTexts`: while the theme is on, every reminder the
//     app plans keeps its time and its rules and only changes its WORDS, to
//     a Czech variant from the theme's content table. The variant is chosen
//     by `stableHash(seed, day, kind)`, so it is the same all day: the
//     scheduler's text diff (`NotificationPlanning.diff`) then has nothing
//     to replace on the next re-plan. Repeating requests (fasting) pass an
//     empty day and keep one variant for good.
//   - `LoveNotificationPlanning`: the day's love message as a dated local
//     notification, for today and the next six days, so it fires with the
//     app closed. Its minute is `LoveMinute`'s, kept away from the times the
//     user has CONFIGURED for other reminders -- not from what is pending,
//     which changes as meals are logged and would move the minute.
//   - `NotificationBudget`: iOS keeps at most 64 pending requests. The love
//     messages take priority; the food reminders' window of days shrinks to
//     make room (spec reminder-notifications, "The love notification has
//     priority within the pending limit").
//
// Pure. The table's texts come from the app (PartnerTheme resources); this
// file only picks and fills them. Tests: LoveNotificationsTests.

import Foundation

// MARK: - Themed texts

/// One wording of a reminder in the theme's table. A `nil` body keeps the
/// standard body (supplement reminders keep the supplement's name there).
public struct NotificationTextVariant: Codable, Sendable, Equatable {
    public let title: String
    public let body: String?

    public init(title: String, body: String?) {
        self.title = title
        self.body = body
    }
}

public struct ThemedNotificationTexts: Sendable, Equatable {
    /// Kind keys the table uses beyond `PlannedNotification.id`.
    public enum Kind {
        public static let fastingEnds = "fasting.ends"
        public static let fastingStarts = "fasting.starts"
        public static let supplementSlot = "supplement.slot"
    }

    public let seed: String
    public let nickname: String
    public let signature: String
    /// Kind (a `PlannedNotification.id` such as `mealReminder.breakfast`,
    /// or a `Kind` key) -> its variants.
    public let variants: [String: [NotificationTextVariant]]
    /// The pack's rotating names (empty: always `nickname` / `signature`),
    /// picked per day like `LovePack.nickname(for:)`.
    public let nicknames: [String]
    public let signatures: [String]

    public init(
        seed: String,
        nickname: String,
        signature: String,
        nicknames: [String] = [],
        signatures: [String] = [],
        variants: [String: [NotificationTextVariant]]
    ) {
        self.seed = seed
        self.nickname = nickname
        self.signature = signature
        self.nicknames = nicknames
        self.signatures = signatures
        self.variants = variants
    }

    /// The themed text of `kind` on `day` (`""` for a repeating request),
    /// or `standard` when the table has no variant for the kind.
    public func text(kind: String, day: String, standard: NotificationPlanning.NotificationText) -> NotificationPlanning.NotificationText {
        guard let options = variants[kind], !options.isEmpty else { return standard }
        let variant = options[Int(LoveMinute.stableHash(seed, day, kind) % UInt64(options.count))]
        return NotificationPlanning.NotificationText(
            title: fill(variant.title, day: day),
            body: variant.body.map { fill($0, day: day) } ?? standard.body
        )
    }

    /// `{nickname}` and `{signature}` replaced with `day`'s names.
    public func fill(_ template: String, day: String = "") -> String {
        let name = LovePack.dailyChoice(nicknames, seed: seed, day: day, salt: "nickname") ?? nickname
        let sign = LovePack.dailyChoice(signatures, seed: seed, day: day, salt: "signature") ?? signature
        return template
            .replacingOccurrences(of: "{nickname}", with: name)
            .replacingOccurrences(of: "{signature}", with: sign)
    }
}

extension NotificationPlanning {
    /// `window` with each reminder's words taken from `texts` (unchanged
    /// when `texts` is nil). `today` is the day of offset 0.
    public static func themed(
        _ window: [DatedPlannedNotification],
        today: String,
        texts: ThemedNotificationTexts?
    ) -> [DatedPlannedNotification] {
        guard let texts else { return window }
        return window.map { dated in
            let day = LoveDay.adding(dated.dayOffset, to: today) ?? today
            let text = texts.text(kind: dated.notification.id, day: day, standard: dated.notification.text)
            return DatedPlannedNotification(
                dayOffset: dated.dayOffset,
                notification: PlannedNotification(
                    id: dated.notification.id,
                    title: text.title,
                    body: text.body,
                    hour: dated.notification.hour,
                    minute: dated.notification.minute
                )
            )
        }
    }

    /// `reminders` with their words taken from `texts`; one variant for
    /// good, because these requests repeat daily.
    public static func themed(
        _ reminders: [PlannedFastingReminder],
        texts: ThemedNotificationTexts?
    ) -> [PlannedFastingReminder] {
        guard let texts else { return reminders }
        return reminders.map { reminder in
            let kind = reminder.id.hasPrefix("starts.") ? ThemedNotificationTexts.Kind.fastingStarts : ThemedNotificationTexts.Kind.fastingEnds
            let text = texts.text(kind: kind, day: "", standard: reminder.text)
            return PlannedFastingReminder(id: reminder.id, title: text.title, body: text.body, hour: reminder.hour, minute: reminder.minute)
        }
    }
}

extension NotificationPreferences {
    /// The minutes of the day of every reminder the user has switched on,
    /// whether or not today's is still pending: what the love message keeps
    /// away from. Fasting times come from the schedule, so the caller adds
    /// them (`LoveNotificationPlanning.clashMinutes`).
    public var enabledReminderMinutes: [Int] {
        [breakfastReminder, lunchReminder, dinnerReminder, streakReminder, dailyChallengeReminder]
            .filter(\.isEnabled)
            .map { $0.hour * 60 + $0.minute }
    }
}

// MARK: - The love message as a notification

public struct PlannedLoveNotification: Sendable, Equatable {
    public static let identifierPrefix = "love.daily."
    public static let threadIdentifier = "love"

    public let day: String
    /// Minutes after midnight, wall clock.
    public let minute: Int
    public let title: String
    public let body: String
    /// The pack picture to attach, when its file is on the phone.
    public let pictureId: String?

    public init(day: String, minute: Int, title: String, body: String, pictureId: String?) {
        self.day = day
        self.minute = minute
        self.title = title
        self.body = body
        self.pictureId = pictureId
    }

    public var identifier: String { Self.identifierPrefix + day }

    public var text: NotificationPlanning.NotificationText {
        NotificationPlanning.NotificationText(title: title, body: body)
    }

    /// The day a love notification's identifier is for, or `nil` for any
    /// other identifier (the tap handler's deep link).
    public static func day(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let day = String(identifier.dropFirst(identifierPrefix.count))
        return LoveDay.isValid(day) ? day : nil
    }
}

public enum LoveNotificationPlanning {
    /// The configured reminder minutes plus the fasting reminders' fire
    /// times, sorted and without repeats -- the one input both the planning
    /// and Today's reveal must use, so they agree on the minute.
    public static func clashMinutes(preferences: NotificationPreferences, fasting: [NotificationPlanning.PlannedFastingReminder]) -> [Int] {
        Array(Set(preferences.enabledReminderMinutes + fasting.map { $0.hour * 60 + $0.minute })).sorted()
    }

    /// The love notifications to keep pending: one per day from today for
    /// `days` days, leaving out days before the first day, days already
    /// revealed, and today once its minute has passed. Assigns each day's
    /// message in `state` (the caller saves it: LoveStore.update).
    ///
    /// - Parameter title: the theme's title; a `{nickname}` in it becomes
    ///   that day's nickname (`LovePack.nickname(for:)`).
    public static func plan(
        pack: LovePack,
        state: inout LoveState,
        now: Date,
        clashMinutes: [Int],
        title: String,
        availablePictures: Set<String>,
        days: Int = NotificationPlanning.windowDays,
        calendar: Calendar = .current
    ) -> [PlannedLoveNotification] {
        guard days > 0 else { return [] }
        let today = LoveDay.key(of: now, calendar: calendar)
        let first = DailyLoveMessage.firstDay(pack: pack, state: state)
        let window = (0..<days).compactMap { LoveDay.adding($0, to: today) }.filter { $0 >= first }
        DailyLoveMessage.assign(days: window, pack: pack, state: &state)

        var result: [PlannedLoveNotification] = []
        for day in window where state.revealed[day] == nil {
            let minute = LoveMinute.minute(seed: pack.seed, day: day, otherReminderMinutes: clashMinutes)
            if day == today, let due = LoveDay.date(day: day, minute: minute, calendar: calendar), due <= now { continue }
            guard let message = DailyLoveMessage.message(for: day, pack: pack, state: state) else { continue }
            result.append(PlannedLoveNotification(
                day: day,
                minute: minute,
                title: title.replacingOccurrences(of: "{nickname}", with: pack.nickname(for: day)),
                body: message.text,
                pictureId: PictureRotation.pictureId(slot: LovePictureSlot.pictureOfDay, day: day, pack: pack, available: availablePictures)
            ))
        }
        return result
    }
}

// MARK: - The pending-request budget

public enum NotificationBudget {
    /// iOS keeps 64; four stay free for one-off requests.
    public static let cap = 60

    /// How many days of food reminders fit beside everything else: the love
    /// messages and the repeating and supplement requests are counted
    /// first, then as many days of the food window as fit, nearest first.
    /// Today is always planned.
    public static func foodWindowDays(
        foodRequestsPerDay: Int,
        otherPending: Int,
        maxDays: Int = NotificationPlanning.windowDays,
        cap: Int = NotificationBudget.cap
    ) -> Int {
        guard foodRequestsPerDay > 0 else { return maxDays }
        let room = cap - otherPending
        return min(maxDays, max(1, room / foodRequestsPerDay))
    }
}
