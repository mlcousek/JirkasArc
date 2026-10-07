// AppEnvironment+QuickHealthLog.swift
//
// add-training-shortcuts-and-widgets (design D5): what the running app does
// after a weigh-in or a drink was logged WITHOUT its screen -- by the "Log
// weight" / "Log water" App Shortcuts (Shortcuts/LogWeightAndWaterIntents
// .swift) or the water Control (Shared/QuickHealthLogIntents.swift).
//
// By the time `QuickHealthLogAction.onLogged` is called the entry is
// already committed (the local record, then the outbox entry) and the
// action's short, bounded delivery is over. So this only shows it: the same
// `weightLogged()` / `hydrationLogged()` the two sheets call after their own
// Save -- reload the card, recount the sync queue, start a drain.
//
// Nothing is held when the hook isn't set yet (an intent that cold-launched
// the app runs before this environment exists): the first foreground reads
// the stores. That is why there is no relay here, unlike a food log, which
// has an award to hand over exactly once (ConfirmedLogRelay).
//
// In its own file so `AppEnvironment.init` carries one line for it.
//
// Depends on: AppEnvironment, QuickHealthLogAction (Shared/).
// Depended on by: AppEnvironment.init.

import Foundation

extension AppEnvironment {
    /// Points the screenless weight and water logs at this environment;
    /// called once in `init`.
    func wireQuickHealthLog() {
        QuickHealthLogAction.onLogged = { [weak self] kind in
            switch kind {
            case .weight: await self?.weightLogged()
            case .water: await self?.hydrationLogged()
            }
        }
    }
}
