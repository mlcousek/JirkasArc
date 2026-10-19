// PictureRotation.swift
//
// add-partner-love-theme D4: which pack picture a slot shows on a day. A
// picture appears only in the slots it names; where several name the same
// slot they rotate daily, and two consecutive days never show the same one
// when another is available (spec partner-theme, "Picture of the day
// rotates"). With no picture for a slot the answer is `nil` and the theme
// draws its built-in art there.
//
// The candidates are put in a stable order (`LoveMinute.stableHash(seed,
// "picture", slot, id)`) and the day index picks one by modulo: consecutive
// days are consecutive positions, so they differ whenever there are two or
// more.
//
// Pure. Depended on by the app's art resolver and the love notification's
// attachment. Tests: PictureRotationTests.

import Foundation

public enum PictureRotation {
    /// Day 0 of the rotation. Any fixed date works; this one is before
    /// every pack.
    static let epoch = "2000-01-01"

    /// The id of the pack picture `slot` shows on `day`, or `nil`.
    public static func pictureId(slot: String, day: String, pack: LovePack, available: Set<String>? = nil) -> String? {
        var candidates = pack.images.filter { $0.slots.contains(slot) }.map(\.id)
        if let available { candidates = candidates.filter { available.contains($0) } }
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }
        let ordered = candidates.sorted {
            LoveMinute.stableHash(pack.seed, "picture", slot, $0) < LoveMinute.stableHash(pack.seed, "picture", slot, $1)
        }
        let index = LoveDay.days(from: epoch, to: day) ?? 0
        let position = ((index % ordered.count) + ordered.count) % ordered.count
        return ordered[position]
    }
}
