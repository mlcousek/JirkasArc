## MODIFIED Requirements

### Requirement: The widget shows no live or cached data of any kind

There is no App Group and no Keychain Sharing on this account
(`errSecMissingEntitlement`/-34018, confirmed live on 2026-09-14, on both
read and write), so no widget process can read anything the app knows or
authenticate to Garmin on its own. The system SHALL NOT attempt to fetch,
cache, or display any Garmin-sourced or app-recorded value (a calorie
total, a streak count, today's check-in light, a weight, a water total) in
any Home Screen widget. A widget MAY show the current date and values the
user typed into that widget's own configuration, which WidgetKit stores
with the widget and hands to the widget's own process.

#### Scenario: Widget renders

- **WHEN** any Home Screen widget this app offers renders its timeline entry
- **THEN** the content shown is identical regardless of the actual state of the user's Garmin account, vault or local logging history
- **AND** no network request and no read of the app's local data occurs as part of rendering it

#### Scenario: After a check-in

- **WHEN** the owner records a check-in from the check-in widget and returns to the Home Screen
- **THEN** the widget looks exactly as it did before, with no light marked

### Requirement: The widget opens the app on tap

The "Log Food" and streak widgets SHALL each present a single whole-widget
tap target that opens the containing app, via `widgetURL`, with no other
interactive elements. Only the check-in widget has buttons (see "A check-in
widget records the morning light in one tap").

#### Scenario: Tapping the widget

- **WHEN** the user taps the "Log Food" or the streak widget
- **THEN** the app opens straight into the food catalog
- **AND** no quick-add or other in-widget action is offered

## ADDED Requirements

### Requirement: A check-in widget records the morning light in one tap

The system SHALL offer a Home Screen widget, small and medium, with three
buttons: Green, Amber and Red, each distinguished by letter and shape as
well as colour and labelled for VoiceOver. A button SHALL open the app and
record that check-in there for the current training day, exactly as the
matching lock-screen Control does, and SHALL fail with the same visible
message when the vault connection is off or has no device id.

#### Scenario: Amber from the Home Screen

- **WHEN** the owner taps the A button of the check-in widget on an install with a tested vault connection
- **THEN** the app opens and an amber check-in is recorded for today's training day

#### Scenario: Connection off

- **WHEN** a button is tapped on an install without the vault connection
- **THEN** nothing is recorded

### Requirement: A countdown widget counts the days to an event set in its own configuration

The system SHALL offer a small Home Screen widget that shows an event's
name and the whole calendar days until its date, both taken from the
widget's own configuration. The day count SHALL use the language's plural
forms, SHALL read "Today" on the event's day and "N days ago" after it,
and SHALL change at midnight without the app being opened. A widget with
no event set SHALL say how to set one and SHALL show no number.

#### Scenario: Before the event

- **WHEN** the widget is configured with the name "Example 50K" and a date 120 days after today
- **THEN** it shows "Example 50K" and "120 days", in Czech "120 dní"

#### Scenario: Few days in Czech

- **WHEN** the event is 3 days away on a Czech phone
- **THEN** the widget shows "3 dny"

#### Scenario: Overnight

- **WHEN** the widget showed "2 days" yesterday evening and the phone was not unlocked since
- **THEN** it shows "1 day" this morning

#### Scenario: Not configured

- **WHEN** the widget was just added and never edited
- **THEN** it asks to edit the widget and shows no count
