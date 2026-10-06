// MorningCheckInWidget.swift
//
// The Home Screen check-in widget (add-training-shortcuts-and-widgets
// design D4): three buttons, Green, Amber and Red, small and medium.
//
// Unlike the other Home Screen widgets here (one whole-widget tap target
// that opens the app), this one has buttons -- and it is still built
// entirely around the same fact: there is no App Group on this free
// account, so this process can't read or write anything the app knows.
// Each button is `Button(intent: MorningCheckInIntent(light:))`
// (Shared/MorningCheckInIntents.swift), the very intent the lock-screen
// Controls use. Its `openAppWhenRun` brings the app forward and
// `perform()` runs THERE, with the app's own files, through the hook
// `GarminFoodApp.init()` installs. Nothing is shared and the widget stores
// nothing.
//
// So it shows NO state: not the light that was chosen, not "done". It
// can't know either, and a guess would be worse than nothing
// (add-glanceable-surfaces D2). The buttons look the same before and
// after; the app that opens is the confirmation. That is also why the
// timeline is one entry that never reloads.
//
// Letter and shape as well as colour, as on Today and the Controls (G
// circle, A triangle, R square). The colours are the widget theme's
// `success`, `warning` and `danger` on its `surface` over its
// `background` (WidgetTheme.swift; the theme is this widget's own Edit
// Widget choice). The letters are the plan's option codes and are not
// translated; the medium size adds the colour's word.
//
// Unconfirmed until a device check (tasks 7.1): that a widget button's
// `openAppWhenRun` intent opens the app and runs there, as a Control's
// does. If it doesn't, the fallback is a `Link` per button to a
// `garminfood://` URL the app handles.

import WidgetKit
import SwiftUI
import AppIntents
import AppearanceKit

struct MorningCheckInWidgetEntry: TimelineEntry {
    let date: Date
    /// This widget's own Edit Widget theme (WidgetTheme.swift, D13).
    var theme: WidgetThemeOption = .standard
}

struct MorningCheckInWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MorningCheckInWidgetEntry {
        MorningCheckInWidgetEntry(date: .now)
    }

    func snapshot(for configuration: WidgetThemeIntent, in context: Context) async -> MorningCheckInWidgetEntry {
        MorningCheckInWidgetEntry(date: .now, theme: configuration.theme)
    }

    func timeline(for configuration: WidgetThemeIntent, in context: Context) async -> Timeline<MorningCheckInWidgetEntry> {
        // `.never`: the widget shows no state (see the header), so there is
        // nothing to refresh towards. Editing its theme reloads it.
        Timeline(entries: [MorningCheckInWidgetEntry(date: .now, theme: configuration.theme)], policy: .never)
    }
}

/// One light's button. The label texts are literals per light, so each is
/// a catalog key the localization check can see.
private struct CheckInWidgetButton: View {
    let light: CheckInLightOption
    let colors: WidgetThemeColors
    /// The medium size has room for the colour's word.
    let showsName: Bool

    var body: some View {
        Button(intent: MorningCheckInIntent(light: light)) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: showsName ? 22 : 18, weight: .bold))
                    .foregroundStyle(colors.color(role))
                    .widgetAccentable()
                Text(verbatim: letter)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                if showsName {
                    name
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.color(.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Records the check-in. Briefly opens Jirka's Arc to do it.")
    }

    /// The plan's option code. Not translated, as on Today.
    private var letter: String {
        switch light {
        case .greenLight: return "G"
        case .amberLight: return "A"
        case .redLight: return "R"
        }
    }

    /// The design system's traffic-light shapes (the Controls' symbols).
    private var symbol: String {
        switch light {
        case .greenLight: return "circle.fill"
        case .amberLight: return "triangle.fill"
        case .redLight: return "square.fill"
        }
    }

    private var role: ThemeRole {
        switch light {
        case .greenLight: return .success
        case .amberLight: return .warning
        case .redLight: return .danger
        }
    }

    private var name: Text {
        switch light {
        case .greenLight: return Text("Green")
        case .amberLight: return Text("Amber")
        case .redLight: return Text("Red")
        }
    }

    private var label: Text {
        switch light {
        case .greenLight: return Text("Check-in: Green")
        case .amberLight: return Text("Check-in: Amber")
        case .redLight: return Text("Check-in: Red")
        }
    }
}

struct MorningCheckInWidgetView: View {
    let entry: MorningCheckInWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The widget's own theme, not `Theme.*` (WidgetTheme.swift).
        let colors = WidgetThemeColors(option: entry.theme, colorScheme: colorScheme)
        let showsNames = family == .systemMedium
        VStack(alignment: .leading, spacing: 8) {
            Text("Morning Check-in")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: showsNames ? 10 : 6) {
                CheckInWidgetButton(light: .greenLight, colors: colors, showsName: showsNames)
                CheckInWidgetButton(light: .amberLight, colors: colors, showsName: showsNames)
                CheckInWidgetButton(light: .redLight, colors: colors, showsName: showsNames)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A theme with one scheme (a dark-only theme in light mode) must
        // also decide what `.primary` / `.secondary` mean on its surfaces.
        .environment(\.colorScheme, colors.colorScheme)
        .containerBackground(for: .widget) {
            colors.color(.background)
        }
    }
}

struct MorningCheckInWidget: Widget {
    static let kind = "com.mlcousek.garminfood.widget.checkin"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetThemeIntent.self, provider: MorningCheckInWidgetProvider()) { entry in
            MorningCheckInWidgetView(entry: entry)
        }
        .configurationDisplayName("Morning Check-in")
        // Says what a tap does, and that the app opens: this widget can't
        // record anything by itself (no shared storage on this account).
        .description("Green, amber or red in one tap. Briefly opens Jirka's Arc to record it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    MorningCheckInWidget()
} timeline: {
    MorningCheckInWidgetEntry(date: .now)
}

#Preview(as: .systemMedium) {
    MorningCheckInWidget()
} timeline: {
    MorningCheckInWidgetEntry(date: .now)
}
