// QuickHealthLog.swift
//
// A weigh-in or a drink logged WITHOUT its screen (add-training-shortcuts-
// and-widgets design D5): the "Log weight" / "Log water" App Shortcuts and
// the water Control. Their intents live in the app and in `Shared/`
// (Shared/QuickHealthLogIntents.swift, GarminFood/Shortcuts/), where
// nothing can be unit-tested, so every rule that can be wrong is here:
//
//   - `QuickLogInput`: which number may be recorded. The bounds are the
//     ones the two sheets enforce (AddWeightSheet: above 0 and below 500
//     kg; AddHydrationSheet: above 0 and below 5000 ml), so a shortcut
//     can't save what the screen would refuse. No amount means one glass.
//   - `QuickHealthLog`: check, then commit through the SAME coordinators
//     the sheets use (`WeightLogCoordinator`, `HydrationLogCoordinator`):
//     the local record first, then the outbox entry, no network. A refused
//     number writes nothing.
//   - `QuickLogDelivery`: what the short, bounded drain after the commit
//     says happened, so Siri's answer and the Control's result don't claim
//     a sync that didn't happen (the rule LogNamedFoodIntent follows for
//     food).
//
// Unlike a food log there is no `ConfirmedLogRelay` step: a weigh-in or a
// drink earns no award in the app either, so nothing has to be held for
// the gamification engine.
//
// Pure apart from the two coordinator calls. Tests: QuickHealthLogTests.

import Foundation
import GarminKit

/// Which number a screenless weigh-in or drink may record.
public enum QuickLogInput {
    /// The glass logged when no amount is given: the Water screen's middle
    /// preset. The intents' `@Parameter(default:)` must be a literal, so it
    /// repeats this number; QuickHealthLogTests pins it.
    public static let defaultGlassML: Double = 250
    /// Exclusive, as in AddWeightSheet.
    public static let weightUpperBoundKg: Double = 500
    /// Exclusive, as in AddHydrationSheet.
    public static let waterUpperBoundML: Double = 5000

    public enum Rejection: Error, Equatable, Sendable {
        /// Not a finite number above 0 and below 500 kg.
        case weightOutOfRange
        /// Not a finite amount above 0 and below 5000 ml.
        case waterOutOfRange
    }

    /// `kilograms` as given, if the weigh-in form would accept it.
    public static func weightKg(_ kilograms: Double) throws -> Double {
        guard kilograms.isFinite, kilograms > 0, kilograms < weightUpperBoundKg else {
            throw Rejection.weightOutOfRange
        }
        return kilograms
    }

    /// The amount to log: `milliliters`, or one glass when none is given.
    public static func waterML(_ milliliters: Double?) throws -> Double {
        guard let milliliters else { return defaultGlassML }
        guard milliliters.isFinite, milliliters > 0, milliliters < waterUpperBoundML else {
            throw Rejection.waterOutOfRange
        }
        return milliliters
    }
}

/// Check, then commit: the testable half of the weight and water intents.
public enum QuickHealthLog {
    /// A weigh-in for `now`. Throws `QuickLogInput.Rejection` before
    /// anything is written, or the coordinator's own error.
    @discardableResult
    public static func logWeight(
        kilograms: Double,
        using coordinator: WeightLogCoordinator,
        now: Date = Date()
    ) async throws -> WeightEntry {
        let weight = try QuickLogInput.weightKg(kilograms)
        return try await coordinator.logWeight(weightKg: weight, loggedAt: now, now: now)
    }

    /// A drink for `now`; one glass when `milliliters` is `nil`.
    @discardableResult
    public static func logWater(
        milliliters: Double?,
        using coordinator: HydrationLogCoordinator,
        now: Date = Date()
    ) async throws -> HydrationEntry {
        let amount = try QuickLogInput.waterML(milliliters)
        return try await coordinator.logHydration(valueInML: amount, loggedAt: now, now: now)
    }
}

/// What happened to a screenless weigh-in or drink after its local commit.
public enum QuickLogDelivery: Equatable, Sendable {
    /// Standalone mode: the phone is the record, nothing is sent.
    case localOnly
    /// Saved and queued; Garmin doesn't have it yet (the drain didn't
    /// finish in time, is backing off, or another drain is running).
    case queued
    /// Garmin accepted it.
    case delivered
    /// Saved and queued, but the Garmin sign-in is gone: it waits until
    /// the user signs in again. Must be said out loud.
    case signedOut

    /// The outcome of a bounded drain. `drainFinished` is `false` when the
    /// wait ran out; then nothing is known and the entry is just queued.
    /// `outboxEntryId` is the committed entry's link to its outbox entry
    /// (`nil` in standalone mode, which never reaches here).
    public static func afterDrain(
        drainFinished: Bool,
        deliveredIds: [UUID],
        authOutcome: DrainAuthOutcome,
        outboxEntryId: UUID?
    ) -> QuickLogDelivery {
        guard drainFinished else { return .queued }
        if let outboxEntryId, deliveredIds.contains(outboxEntryId) { return .delivered }
        // A switch, not `!= .none`: `.none` could resolve to Optional.none.
        switch authOutcome {
        case .longLivedTokenExpired, .notSignedIn:
            return .signedOut
        case .none:
            return .queued
        }
    }
}
