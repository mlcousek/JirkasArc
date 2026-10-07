// CountdownWidget.swift
//
// A countdown to one event (add-training-shortcuts-and-widgets design D7):
// "Example 50K" over "120 days", small. The event's name and date are typed into
// THIS WIDGET's configuration (Edit Widget), nowhere else.
//
// Why that, and not the plan's next race: this extension can't read the
// app's plan on a free account (no App Group, no shared file --
// add-glanceable-surfaces D2). But a widget's own configuration is stored
// by WidgetKit with the widget instance and handed to this process's own
// timeline provider as a `WidgetConfigurationIntent`, exactly like the
// per-widget theme (WidgetTheme.swift). So this is the one widget here
// that shows a number, and it is still honest: the number comes from what
// the user typed and from today's date, never from the app, Garmin or the
// vault. No event name or date is written into the code; an unconfigured
// widget says how to set one and shows no count.
//
// The day arithmetic is FoodLogCore's `EventCountdown` (pure, tested: a
// day is a calendar day, a DST night is one day). The timeline has an
// entry for now and for each of the next seven midnights, so the count
// changes at midnight without the app being opened; `.atEnd` asks WidgetKit
// for the next week about once a week.
//
// Counts are plural keys in the widget's catalog (Czech one / few / many /
// other). A tap opens the app on the plan (`GarminFoodDeepLink.Action
// .plan`; Today in the food-first experience).
//
// Unconfirmed until a device check (tasks 7.6): the date parameter's
// date-only picker (`kind: .date`), and that its value is a moment of the
// chosen calendar day in the phone's own time zone.

import WidgetKit
import SwiftUI
import AppIntents
import FoodLogCore

/// Edit Widget's configuration: the event, its day, the theme.
struct CountdownWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Countdown"
    static var description = IntentDescription("Choose the event to count down to.")

    @Parameter(title: "Event")
    var eventName: String?

    @Parameter(title: "Date", kind: .date)
    var eventDate: Date?

    // Type-qualified: a bare `.teal` reads as a literal colour to the
    // design-token lint.
    @Parameter(title: "Theme", default: WidgetThemeOption.teal)
    var theme: WidgetThemeOption

    init() {}
}

struct CountdownWidgetEntry: TimelineEntry {
    let date: Date
    /// Already trimmed and cut (`EventCountdown.cleanName`); `nil`: none.
    var eventName: String?
    /// `nil`: the widget isn't set up yet.
    var eventDate: Date?
    var theme: WidgetThemeOption = .standard
}

struct CountdownWidgetProvider: AppIntentTimelineProvider {
    /// Midnights ahead in one timeline: a week, then WidgetKit asks again.
    private static let daysAhead = 7

    func placeholder(in context: Context) -> CountdownWidgetEntry {
        CountdownWidgetEntry(date: .now)
    }

    func snapshot(for configuration: CountdownWidgetIntent, in context: Context) async -> CountdownWidgetEntry {
        // No sample event, not even in the widget gallery: before anything
        // is set the tile says how to set it and shows no number (design
        // D7: no default event).
        entry(at: Date(), configuration)
    }

    func timeline(for configuration: CountdownWidgetIntent, in context: Context) async -> Timeline<CountdownWidgetEntry> {
        let now = Date()
        // Not set up: nothing changes with time. Editing the widget
        // reloads it by itself.
        guard configuration.eventDate != nil else {
            return Timeline(entries: [entry(at: now, configuration)], policy: .never)
        }
        let dates = [now] + EventCountdown.refreshDates(after: now, count: Self.daysAhead)
        return Timeline(entries: dates.map { entry(at: $0, configuration) }, policy: .atEnd)
    }

    private func entry(at date: Date, _ configuration: CountdownWidgetIntent) -> CountdownWidgetEntry {
        CountdownWidgetEntry(
            date: date,
            eventName: EventCountdown.cleanName(configuration.eventName),
            eventDate: configuration.eventDate,
            theme: configuration.theme
        )
    }
}

struct CountdownWidgetView: View {
    let entry: CountdownWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The widget's own theme, not `Theme.*` (WidgetTheme.swift).
        let colors = WidgetThemeColors(option: entry.theme, colorScheme: colorScheme)
        content
            .foregroundStyle(colors.label)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                colors.accentBackground
            }
            .widgetURL(GarminFoodDeepLink.url(for: .plan))
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if let eventDate = entry.eventDate {
            VStack(alignment: .leading, spacing: 2) {
                eventTitle
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .opacity(0.9)
                Spacer(minLength: 0)
                countText(EventCountdown.state(on: entry.date, eventDate: eventDate))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                Text(eventDate, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2)
                    .opacity(0.85)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 26, weight: .semibold))
                    .widgetAccentable()
                Text("Countdown")
                    .font(.subheadline.weight(.bold))
                Text("Edit the widget to choose an event")
                    .font(.caption2)
                    .opacity(0.9)
            }
        }
    }

    /// The typed name as it is; "Countdown" when only a date was set.
    private var eventTitle: Text {
        if let name = entry.eventName {
            return Text(verbatim: name)
        }
        return Text("Countdown")
    }

    /// "120 days" / "Today" / "3 days ago" -- catalog plurals, never a
    /// singular/plural chosen in code.
    private func countText(_ state: EventCountdown) -> Text {
        switch state {
        case .upcoming(let days):
            return Text("\(days) days")
        case .today:
            return Text("Today")
        case .past(let days):
            return Text("\(days) days ago")
        }
    }
}

struct CountdownWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.countdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: CountdownWidgetIntent.self, provider: CountdownWidgetProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        // Says where the event comes from: this widget reads nothing from
        // the app (no shared storage on this account).
        .description("The days to an event you name. Set the event and its date by editing the widget.")
        .supportedFamilies([.systemSmall])
    }
}

/// An invented event for the canvas: 100 days after an invented "today"
/// (2030-01-01, midnight UTC). Nothing here is anyone's calendar.
enum CountdownWidgetPreview {
    static let today = Date(timeIntervalSince1970: 1_893_456_000)
    static let eventDay = today.addingTimeInterval(100 * 86_400)
}

#Preview(as: .systemSmall) {
    CountdownWidget()
} timeline: {
    CountdownWidgetEntry(date: CountdownWidgetPreview.today, eventName: "Example 50K", eventDate: CountdownWidgetPreview.eventDay)
    CountdownWidgetEntry(date: CountdownWidgetPreview.today)
}
