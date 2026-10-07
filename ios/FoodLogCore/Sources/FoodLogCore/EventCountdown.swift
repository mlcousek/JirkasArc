// EventCountdown.swift
//
// The day arithmetic of the countdown widget (add-training-shortcuts-and-
// widgets design D7; GarminFoodWidget/CountdownWidget.swift): how many
// whole calendar days are left to an event, and when the number changes.
//
// It is here, and not in TrainingCore next to the plan's own countdowns,
// because the widget extension links FoodLogCore and never TrainingCore
// (project.yml), and a widget's view can't be unit-tested: this is the
// part of that widget that can be wrong (an off-by-one around midnight, a
// DST night counted as a day more or less).
//
// The event is whatever the user typed into the widget's own
// configuration; nothing here knows a race, a plan or a name. A day is a
// calendar day in `calendar` (the device's): the time of day of either
// date does not matter.
//
// Pure. Tests: EventCountdownTests.

import Foundation

public enum EventCountdown: Equatable, Sendable {
    /// The event is `days` calendar days ahead (1 = tomorrow).
    case upcoming(days: Int)
    /// The event is today.
    case today
    /// The event was `days` calendar days ago (1 = yesterday).
    case past(days: Int)

    /// Where `now` stands relative to the day of `eventDate`.
    public static func state(on now: Date, eventDate: Date, calendar: Calendar = .current) -> EventCountdown {
        let from = calendar.startOfDay(for: now)
        let to = calendar.startOfDay(for: eventDate)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        if days > 0 { return .upcoming(days: days) }
        if days < 0 { return .past(days: -days) }
        return .today
    }

    /// The next `count` midnights after `now`, oldest first: the moments
    /// the count changes, which is when the widget needs a new entry.
    public static func refreshDates(after now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<max(0, count) {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            // Start of day again: a DST change can move "the same time
            // tomorrow" off midnight.
            let start = calendar.startOfDay(for: next)
            guard start > day else { break }
            dates.append(start)
            day = start
        }
        return dates
    }

    /// The longest event name the widget shows.
    public static let nameMaxLength = 40

    /// The typed name, trimmed and cut to `nameMaxLength` characters;
    /// `nil` when there is nothing to show.
    public static func cleanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cut = String(trimmed.prefix(nameMaxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }
}
