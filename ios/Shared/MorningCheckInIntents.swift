// MorningCheckInIntents.swift
//
// The morning check-in from outside Today's row: the lock-screen Controls
// (add-training-checkins design D7; the architecture note's section 6.3:
// "three static Controls ... Each opens the app and commits
// checkin.morning"), and, since add-training-shortcuts-and-widgets (design
// D1-D3), the Home Screen check-in widget's three buttons and the "Morning
// check-in" App Shortcut (GarminFood/Shortcuts/GarminFoodShortcuts.swift).
// ONE intent for all of them, so there is one place that records and one
// set of failure messages.
//
// Same shape as the quick-pick Controls (QuickPickLoggingIntents.swift;
// read its header for the full reasoning): there is no App Group on this
// free account, so the widget extension can't reach the app's files, and
// the intent sets `openAppWhenRun = true` so `perform()` runs in the APP's
// process. `authenticationPolicy = .alwaysAllowed` for the same one-tap
// reason, with the same unconfirmed caveat (whether iOS still asks for Face
// ID when the app must come forward; tasks 6.2 there, 7.2 here, check it on
// the device). One type can't have `openAppWhenRun` both ways, so a
// check-in said to Siri opens the app too.
//
// DUAL TARGET MEMBERSHIP: this file is in Shared/, compiled into the app
// AND the widget extension (the extension needs the intent type to declare
// the Controls and the widget's buttons). The widget never links VaultKit
// or TrainingCore, so this file can't call them. Instead the app installs
// `MorningCheckInControlAction.handler` in `GarminFoodApp.init()` -- before
// any scene, so a cold launch by a Control finds it -- pointing at
// `TrainingEventsService.handleCheckIn`, which records the event with the
// app's own files. The request and the receipt are plain values (the
// contract's words as strings) for that reason. In the widget process the
// handler is never set and `perform()` never runs there anyway.
//
// Parameters:
//   - `light`: required. The Controls and the widget pass it; a shortcut
//     run without one is ASKED ("Green, amber or red?") -- `init()` must
//     not preset a light, or "Morning check-in in Jirka's Arc" would
//     silently record green.
//   - `painScore`, `painSite`: optional, never asked for. A score is sent
//     only when given (TrainingCore's QuickCheckIn.swift has the rules: 0
//     to 10 or refused, half steps, the default site); without one the
//     check-in carries no pain answer and the day's earlier one is kept.
//
// The confirmation names what was RECORDED (the receipt), not what was
// asked. A failure throws a localized error, so the Control shows it
// instead of a success it hasn't earned (the connection is off, never
// tested, the app couldn't record, or the score is out of range). Strings
// live in BOTH catalogs (the checker's rule for Shared/).

import AppIntents
import Foundation

/// The light as the Controls and Shortcuts name it; raw values are the
/// event contract's words (TrainingCore's `MorningLight`).
enum CheckInLightOption: String, AppEnum {
    // Case names avoid colour words (the design-token lint forbids `.red`
    // and friends); the raw values are the contract's words.
    case greenLight = "green"
    case amberLight = "amber"
    case redLight = "red"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Traffic Light"
    static var caseDisplayRepresentations: [CheckInLightOption: DisplayRepresentation] = [
        .greenLight: DisplayRepresentation(title: "Green"),
        .amberLight: DisplayRepresentation(title: "Amber"),
        .redLight: DisplayRepresentation(title: "Red")
    ]

    /// The light's name in the app's language, for the confirmation.
    var localizedName: String {
        switch self {
        case .greenLight: return String(localized: "Green")
        case .amberLight: return String(localized: "Amber")
        case .redLight: return String(localized: "Red")
        }
    }
}

/// Where it hurts, as Shortcuts names it; raw values are the event
/// contract's site words (TrainingCore's `PainSite`).
enum CheckInPainSiteOption: String, AppEnum {
    case achillesLeft = "achilles-left"
    case achillesRight = "achilles-right"
    case kneeLeft = "knee-left"
    case kneeRight = "knee-right"
    case other

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Pain Site"
    static var caseDisplayRepresentations: [CheckInPainSiteOption: DisplayRepresentation] = [
        .achillesLeft: DisplayRepresentation(title: "Achilles (left)"),
        .achillesRight: DisplayRepresentation(title: "Achilles (right)"),
        .kneeLeft: DisplayRepresentation(title: "Knee (left)"),
        .kneeRight: DisplayRepresentation(title: "Knee (right)"),
        .other: DisplayRepresentation(title: "Other site")
    ]

    /// The site's name in the app's language, for the confirmation. The
    /// same words as the pain step on Today (TrainingCore's own strings,
    /// which `Shared/` can't reach).
    var localizedName: String {
        switch self {
        case .achillesLeft: return String(localized: "Achilles (left)")
        case .achillesRight: return String(localized: "Achilles (right)")
        case .kneeLeft: return String(localized: "Knee (left)")
        case .kneeRight: return String(localized: "Knee (right)")
        case .other: return String(localized: "Other site")
        }
    }
}

/// What the intent asks the app to record. Plain values: `Shared/` can't
/// name TrainingCore's types (see this file's header).
struct MorningCheckInRequest: Equatable, Sendable {
    /// "green", "amber" or "red".
    var light: String
    /// `nil`: the light only (the Controls, the widget, a spoken light).
    var painScore: Double?
    /// The contract's site word; `nil`: the app picks the site scored last.
    var painSite: String?

    init(light: String, painScore: Double? = nil, painSite: String? = nil) {
        self.light = light
        self.painScore = painScore
        self.painSite = painSite
    }
}

/// What the app recorded: the pain entry in the event, if any (the score
/// on the half-step grid, the site it chose).
struct MorningCheckInReceipt: Equatable, Sendable {
    var painScore: Double?
    var painSite: String?

    init(painScore: Double? = nil, painSite: String? = nil) {
        self.painScore = painScore
        self.painSite = painSite
    }
}

enum MorningCheckInControlAction {
    /// Installed by the app (see this file's header). Throws `ActionError`
    /// or the app's own error.
    static var handler: (@MainActor (MorningCheckInRequest) async throws -> MorningCheckInReceipt)?

    enum ActionError: Error, CustomLocalizedStringResourceConvertible {
        case vaultOff
        case notTested
        case notAvailable
        case painScoreOutOfRange

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .vaultOff:
                return "Nothing recorded: turn on the vault connection in Jirka's Arc first."
            case .notTested:
                return "Nothing recorded: test the vault connection in Jirka's Arc first."
            case .notAvailable:
                return "Nothing recorded: open Jirka's Arc once, then try again."
            case .painScoreOutOfRange:
                return "Nothing recorded: the pain score must be between 0 and 10."
            }
        }
    }

    /// "Check-in recorded: Amber." or, with a pain entry, "Check-in
    /// recorded: Amber. Pain 4.5/10, Achilles (left)." A label and its
    /// values, in the catalog's own words.
    static func confirmation(light: CheckInLightOption, receipt: MorningCheckInReceipt) -> IntentDialog {
        let lightName = light.localizedName
        guard let score = receipt.painScore else {
            return "Check-in recorded: \(lightName)."
        }
        let scoreText = score.formatted(.number.precision(.fractionLength(0...1)))
        // A site this build doesn't name reads as "Other site": the
        // contract's rule for an unknown site word.
        let site = receipt.painSite.flatMap(CheckInPainSiteOption.init(rawValue:)) ?? .other
        return "Check-in recorded: \(lightName). Pain \(scoreText)/10, \(site.localizedName)."
    }
}

struct MorningCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Morning Check-in"
    static var description = IntentDescription("Records this morning's check-in in Jirka's Arc.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Traffic Light", requestValueDialog: "Green, amber or red?")
    var light: CheckInLightOption

    // No `inclusiveRange:` on purpose: a score outside 0...10 must reach
    // `perform()`, so the answer is this app's own sentence
    // (`painScoreOutOfRange`) and the rule stays in one tested place
    // (TrainingCore's QuickCheckIn.swift).
    @Parameter(
        title: "Pain Score",
        description: "From 0 to 10, in half steps. Leave it empty to record the light only. A score replaces this morning's earlier pain answer."
    )
    var painScore: Double?

    @Parameter(
        title: "Pain Site",
        description: "Where it hurts, used with a pain score. Leave it empty for the site you scored last."
    )
    var painSite: CheckInPainSiteOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Record a \(\.$light) morning check-in") {
            \.$painScore
            \.$painSite
        }
    }

    /// No preset light: a run without one must ask (see the header).
    init() {}

    init(light: CheckInLightOption) {
        self.light = light
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let handler = MorningCheckInControlAction.handler else {
            throw MorningCheckInControlAction.ActionError.notAvailable
        }
        let receipt = try await handler(MorningCheckInRequest(
            light: light.rawValue,
            painScore: painScore,
            painSite: painSite?.rawValue
        ))
        return .result(dialog: MorningCheckInControlAction.confirmation(light: light, receipt: receipt))
    }
}
