// QuickHealthLogIntents.swift
//
// A weigh-in and a drink without their screens (add-training-shortcuts-
// and-widgets design D5, D6): the shared action behind the "Log weight" /
// "Log water" App Shortcuts (GarminFood/Shortcuts/
// LogWeightAndWaterIntents.swift) and the two Controls
// (GarminFoodWidget/Controls/QuickHealthControls.swift), plus the Controls'
// own intents.
//
// Same split as food logging (QuickPickLoggingIntents.swift; read its
// header for why): the action must run in the APP's process -- the
// extension has no Garmin credential and no access to the app's files on
// this free account -- so the Controls' intents set `openAppWhenRun`, and
// the Siri intents live in the app target and run there by themselves.
// This file is compiled into BOTH targets (the extension must be able to
// name the Controls' intent types); in the widget process nothing here
// ever runs.
//
// What `QuickHealthLogAction` does, in order:
//   1. checks and commits through FoodLogCore's `QuickHealthLog` -- the
//      same `WeightLogCoordinator` / `HydrationLogCoordinator` the sheets
//      use (`AppServices`' one instance each): the local record first, then
//      the outbox entry, no network. A refused number throws before
//      anything is written;
//   2. in Garmin mode waits at most `deliveryWait` seconds for that outbox
//      to drain (never cancelled; `BoundedWait`), so the caller can say
//      what happened. Standalone mode has nothing to deliver;
//   3. tells the running app (`onLogged`, set by `AppEnvironment`), which
//      reloads the card and the sync queue count. On a cold launch by an
//      intent the app's environment doesn't exist yet and the hook is nil:
//      the first foreground reads the stores.
//
// No `ConfirmedLogRelay` here: a weigh-in or a drink earns no gamification
// award in the app either (`AppEnvironment.weightLogged()` /
// `hydrationLogged()` only refresh and drain), so nothing has to be held
// for the engine.
//
// The weight Control can't take a number (a Control is one tap), so it
// opens the weigh-in form instead (`OpenWeighInIntent` ->
// `AppNavigationBridge` -> `AppRouter.weighInRequested`).
//
// No new Garmin route: the drains send what the weight and water screens
// already send (docs/garmin-routes.json: addWeighIn, addHydration).

import AppIntents
import Foundation
import GarminKit
import FoodLogCore

enum QuickHealthLogAction {
    enum Kind: Sendable {
        case weight
        case water
    }

    /// Seconds an intent waits for Garmin before answering
    /// (add-garmin-auth-and-sync design D6: bounded, like the food intents).
    static let deliveryWait: Double = 2

    /// Set by the app (`AppEnvironment.init`); stays `nil` in the widget
    /// extension and until the app's environment exists.
    static var onLogged: (@MainActor (Kind) async -> Void)?

    enum ActionError: Error, CustomLocalizedStringResourceConvertible {
        case weightOutOfRange
        case waterOutOfRange
        /// The entry IS saved and queued; it just can't reach Garmin until
        /// the user signs in again. Thrown by a Control so it shows a
        /// failure instead of a success it hasn't earned.
        case savedButSignedOut

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .weightOutOfRange:
                return "Nothing saved: the weight must be above 0 and below 500 kg."
            case .waterOutOfRange:
                return "Nothing saved: the amount must be above 0 and below 5000 ml."
            case .savedButSignedOut:
                return "Saved in Jirka's Arc, but not sent: sign in to Garmin again in the app."
            }
        }
    }

    /// What was saved (kilograms or millilitres) and where it stands.
    struct Outcome: Sendable {
        let value: Double
        let delivery: QuickLogDelivery
    }

    /// A weigh-in for now. Only ever runs in the app's process.
    @MainActor
    static func logWeight(kilograms: Double) async throws -> Outcome {
        let services = AppServices.shared
        let entry: WeightEntry
        do {
            entry = try await QuickHealthLog.logWeight(kilograms: kilograms, using: services.weightLogCoordinator)
        } catch is QuickLogInput.Rejection {
            throw ActionError.weightOutOfRange
        }

        var delivery = QuickLogDelivery.localOnly
        if ShortcutLoggingRules.waitsForGarminDelivery(in: AppServices.currentDataMode()) {
            let outbox = services.weightOutbox
            let client = services.garminClient
            let result = await BoundedWait.value(within: deliveryWait) {
                await outbox.drain(using: client)
            }
            delivery = QuickLogDelivery.afterDrain(
                drainFinished: result != nil,
                deliveredIds: result?.delivered.map(\.id) ?? [],
                authOutcome: result?.authOutcome ?? DrainAuthOutcome.none,
                outboxEntryId: entry.outboxEntryId
            )
        }
        await onLogged?(.weight)
        return Outcome(value: entry.weightKg, delivery: delivery)
    }

    /// A drink for now; one glass when `milliliters` is `nil`. Only ever
    /// runs in the app's process.
    @MainActor
    static func logWater(milliliters: Double?) async throws -> Outcome {
        let services = AppServices.shared
        let entry: HydrationEntry
        do {
            entry = try await QuickHealthLog.logWater(milliliters: milliliters, using: services.hydrationLogCoordinator)
        } catch is QuickLogInput.Rejection {
            throw ActionError.waterOutOfRange
        }

        var delivery = QuickLogDelivery.localOnly
        if ShortcutLoggingRules.waitsForGarminDelivery(in: AppServices.currentDataMode()) {
            let outbox = services.hydrationOutbox
            let client = services.garminClient
            let result = await BoundedWait.value(within: deliveryWait) {
                await outbox.drain(using: client)
            }
            delivery = QuickLogDelivery.afterDrain(
                drainFinished: result != nil,
                deliveredIds: result?.delivered.map(\.id) ?? [],
                authOutcome: result?.authOutcome ?? DrainAuthOutcome.none,
                outboxEntryId: entry.outboxEntryId
            )
        }
        await onLogged?(.water)
        return Outcome(value: entry.valueInML, delivery: delivery)
    }
}

/// The water Control's action: one glass, in the app's process.
@available(iOS 18.0, *)
struct LogWaterGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Glass of Water"
    static var description = IntentDescription("Logs one 250 ml glass of water in Jirka's Arc.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let outcome = try await QuickHealthLogAction.logWater(milliliters: nil)
        // Saved either way; an expired sign-in must still fail loudly.
        if outcome.delivery == .signedOut {
            throw QuickHealthLogAction.ActionError.savedButSignedOut
        }
        return .result()
    }
}

/// The weight Control's action: the weigh-in form, in the app. Nothing is
/// recorded until that form is saved.
@available(iOS 18.0, *)
struct OpenWeighInIntent: AppIntent {
    static var title: LocalizedStringResource = "Open the Weigh-in Form"
    static var description = IntentDescription("Opens Jirka's Arc on the weigh-in form.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // Only meaningful once this runs in the app's own process (see
        // AppNavigationBridge.swift's header).
        AppNavigationBridge.shared.request(.weighIn)
        return .result()
    }
}
