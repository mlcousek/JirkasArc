// LovePackDiff.swift
//
// add-partner-love-theme D1: what importing a pack would change, shown
// before anything is applied ("+40 vzkazů, +6 obrázků"). A pack with the
// same `packId` is an update that keeps her state; another `packId` is a
// different pack, which the app confirms first ("Nahradit současný
// balíček?") because it starts a new state (spec love-pack, "Re-importing a
// pack keeps everything already seen").
//
// Pure. Depended on by LoveStore and the app's import sheet. Tests:
// LovePackTests.

import Foundation

public struct LovePackDiff: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case firstImport
        case update
        case otherPack
    }

    public struct ListChange: Sendable, Equatable {
        public let added: Int
        public let removed: Int

        public init(added: Int, removed: Int) {
            self.added = added
            self.removed = removed
        }

        public var isEmpty: Bool { added == 0 && removed == 0 }

        static func between(_ old: [String], _ new: [String]) -> ListChange {
            let oldSet = Set(old)
            let newSet = Set(new)
            return ListChange(added: newSet.subtracting(oldSet).count, removed: oldSet.subtracting(newSet).count)
        }
    }

    public let kind: Kind
    public let daily: ListChange
    public let openWhen: ListChange
    public let coupons: ListChange
    public let pictures: ListChange
    public let countdownChanged: Bool

    /// The counts of the incoming pack, for a first import's summary.
    public let totalDaily: Int
    public let totalPictures: Int

    public static func between(current: LovePack?, incoming: LovePack) -> LovePackDiff {
        let kind: Kind
        let base: LovePack?
        switch current {
        case nil:
            kind = .firstImport
            base = nil
        case let current? where current.packId == incoming.packId:
            kind = .update
            base = current
        default:
            kind = .otherPack
            base = nil
        }
        return LovePackDiff(
            kind: kind,
            daily: .between(base?.daily.map(\.id) ?? [], incoming.daily.map(\.id)),
            openWhen: .between(base?.openWhen.map(\.id) ?? [], incoming.openWhen.map(\.id)),
            coupons: .between(base?.coupons.map(\.id) ?? [], incoming.coupons.map(\.id)),
            pictures: .between(base?.images.map(\.id) ?? [], incoming.images.map(\.id)),
            countdownChanged: base?.countdown != incoming.countdown,
            totalDaily: incoming.daily.count,
            totalPictures: incoming.images.count
        )
    }
}
