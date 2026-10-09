// BackgroundOutboxDelivery.swift
//
// fix-review-findings-2026-09 finding 3: the background refresh's delivery
// and the "is anything still waiting?" rule, for ALL three outboxes (food,
// weight, water), in one tested place.
//
// What was wrong: `BackgroundRefresh.run` already drained all three (fixed
// 2026-09-23), but whether a refresh got scheduled when the app went to the
// background came from `AppEnvironment.undeliveredCount`, a cached count
// refreshed right after a FOOD confirm and otherwise only at the END of a
// drain. After a weigh-in or a drink it was not refreshed until that drain
// finished (or not at all, if a drain was already running) -- so leaving
// the app during an offline drain cancelled the refresh, and a weight-only
// or water-only queue waited for the next foreground. Now the background
// transition asks the outboxes themselves (`OutboxBacklog`), and the
// background worker (`BackgroundOutboxDelivery.run`) is the same code the
// app runs, tested with weight-only and water-only queues.
//
// Finding 8: the background pass only reconciled what THAT pass delivered.
// A food entry Garmin accepted (`.sent`) whose re-read then failed
// (`reconciliationSkipped`) was never reconciled by a later background
// pass, and `.sent` didn't keep a refresh scheduled -- it waited for the
// next foreground (`AppEnvironment.drainAndReconcile` already reconciles
// every `.sent` entry). Now the background pass does the same, and an
// unreconciled `.sent` food entry keeps a refresh scheduled. Weight and
// water `.sent` entries are kept as history by design and are not
// reconciled this way, so they never count.
//
// improve-food-day-flow (E2): queued DELETES of synced food entries are a
// fourth kind of work. A waiting one keeps a refresh scheduled; one that
// gave up waits for the user and one Garmin confirmed is done. The pass
// sends them after the creates were sent and re-read (design D2): a delete
// sent before an accepted create was confirmed could make that create look
// missing, and a missing create is sent again.
//
// Depended on by: GarminFood/App/BackgroundRefresh.swift,
// GarminFood/App/AppEnvironment.swift (didEnterBackground).
// Tests: BackgroundOutboxDeliveryTests.

import Foundation
import GarminKit

/// Whether any outbox still has work a later drain can do.
public enum OutboxBacklog {
    /// `.pending` entries (due now or backing off), a food replace that
    /// still owes its delete and is not parked, and a food entry Garmin
    /// accepted that is not reconciled yet (`.sent`; finding 8). `.failed`
    /// and parked entries wait for the user in the sync queue, so they
    /// don't keep a refresh scheduled.
    /// improve-food-day-flow: `foodDeletions` -- a queued delete that is
    /// still waiting counts; one that gave up or was confirmed doesn't.
    public static func needsDelivery(
        food: [OutboxEntry],
        weight: [WeightOutboxEntry],
        hydration: [HydrationOutboxEntry],
        foodDeletions: [FoodLogDeletion] = []
    ) -> Bool {
        food.contains { $0.state == .pending || $0.state == .sent || ($0.state == .createdAwaitingDelete && !$0.isParkedReplace) }
            || weight.contains { $0.state == .pending }
            || hydration.contains { $0.state == .pending }
            || foodDeletions.contains { $0.isWaiting }
    }

    /// Reads the three outboxes now (never a cached count); the food
    /// outbox's queued deletes with them.
    public static func needsDelivery(outbox: Outbox, weightOutbox: WeightOutbox, hydrationOutbox: HydrationOutbox) async -> Bool {
        needsDelivery(
            food: await outbox.allEntries(),
            weight: await weightOutbox.allEntries(),
            hydration: await hydrationOutbox.allEntries(),
            foodDeletions: await outbox.allDeletions()
        )
    }
}

/// One background delivery pass over every outbox.
public enum BackgroundOutboxDelivery {
    public struct Outcome: Sendable, Equatable {
        /// The first auth failure any drain stopped on (`.none` if none).
        public let authOutcome: DrainAuthOutcome
        /// Something is still waiting: ask iOS for another refresh.
        public let needsAnotherRefresh: Bool
    }

    public static func run<Client>(
        outbox: Outbox,
        reconciliation: Reconciliation,
        weightOutbox: WeightOutbox,
        hydrationOutbox: HydrationOutbox,
        client: Client,
        usageHistory: UsageHistoryStore? = nil
    ) async -> Outcome where Client: FoodLogDelivering & FoodLogReconciling & WeighInDelivering & HydrationDelivering {
        let food = await outbox.drain(using: client)
        // Every `.sent` entry, not just this pass's deliveries (finding 8):
        // one whose earlier re-read failed is picked up again here, exactly
        // like the foreground drain does. This pass's deliveries are
        // already `.sent`, so they are included.
        let sent = await outbox.allEntries().filter { $0.state == .sent }
        if !sent.isEmpty {
            let outcomes = await reconciliation.reconcile(delivered: sent, using: client)
            // harden-gamification-data-integrity 1.1: a confirmed delivery's
            // usage event learns Garmin's logId, the id its row is deleted by.
            try? await usageHistory?.linkGarminLogIds(UsageLogLinks.from(outcomes))
        }
        // improve-food-day-flow (E2): after the creates and their re-read.
        let deletions = await outbox.drainDeletions(using: client)
        let weight = await weightOutbox.drain(using: client)
        let hydration = await hydrationOutbox.drain(using: client)

        let authOutcome = [food.authOutcome, deletions.authOutcome, weight.authOutcome, hydration.authOutcome]
            .first { $0 != DrainAuthOutcome.none } ?? DrainAuthOutcome.none
        let waiting = await OutboxBacklog.needsDelivery(outbox: outbox, weightOutbox: weightOutbox, hydrationOutbox: hydrationOutbox)
        return Outcome(authOutcome: authOutcome, needsAnotherRefresh: waiting)
    }
}
