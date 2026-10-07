// QuickHealthControls.swift
//
// Two Controls for weight and water (add-training-shortcuts-and-widgets
// design D5, D6). Placeable in Control Center, the Lock Screen's bottom
// slots and the Action Button, like the quick-pick Controls. Both are
// static: this extension can't read the app's weight or water data on a
// free account (no App Group), so neither label shows a total.
//
//   - "Log Water" logs ONE glass (250 ml) through `LogWaterGlassIntent`
//     (Shared/QuickHealthLogIntents.swift), which opens the app and commits
//     the drink there with the app's own files, local first. Tapped twice,
//     it logs two glasses -- that is the feature.
//   - "Log Weight" can't record anything by itself: a Control is one tap
//     and a weight is a number that changes every day. It opens the app on
//     the weigh-in form (`OpenWeighInIntent`), which is honestly two taps
//     and the digits. Siri ("Log weight in Jirka's Arc") is the one-step
//     path.
//
// iOS 18+ (Controls), gated in GarminFoodWidgetBundle. Kinds are stable ids
// (`...control.water`, `...control.weight`); renaming one removes the
// Control a user placed. Same unconfirmed caveat as every Control here:
// whether a locked phone asks to unlock when the app must come forward
// (QuickPickLoggingIntents.swift's header).

import SwiftUI
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct LogWaterControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.water"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogWaterGlassIntent()) {
                Label("Log Water", systemImage: "drop.fill")
                    .controlWidgetActionHint("Logs a 250 ml glass of water")
            }
        }
        .displayName("Log Water")
        .description("Logs one 250 ml glass of water. Briefly opens Jirka's Arc to do it.")
    }
}

@available(iOS 18.0, *)
struct LogWeightControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.weight"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenWeighInIntent()) {
                Label("Log Weight", systemImage: "scalemass.fill")
            }
        }
        .displayName("Log Weight")
        // Same key as the intent's description.
        .description("Opens Jirka's Arc on the weigh-in form.")
    }
}
