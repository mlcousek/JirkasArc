// DailyLoveMessage.swift
//
// add-partner-love-theme D6: WHICH message a day gets. Exactly one per day,
// none repeated while unrevealed ones remain, and once a day has its
// message it keeps it -- across re-plans, re-imports and restores (spec
// love-messages, "Each day has exactly one love message, different every
// day"). No special-date messages: owner decision 2026-10-19.
//
// The order is a seeded permutation that survives the pool changing: every
// message id has a rank, `LoveMinute.stableHash(seed, "order", id)`, and a
// day takes the unassigned id with the lowest rank. Messages added by a
// re-import therefore land at stable, scattered places in the sequence --
// not all at the front, not all at the end.
//
// When every message has been assigned, the pool refills from the
// favourites first, then from all messages, least recently shown first,
// and the day is marked as a repeat so the love card can say so.
//
// The first day is the later of the pack's `startDate` and the day the
// pack was imported: importing never dumps a backlog of "past" messages.
//
// Pure. Depended on by LoveReveal and the app's notification planning.
// Tests: DailyLoveMessageTests.

import Foundation

public enum DailyLoveMessage {
    /// The first day that has a message.
    public static func firstDay(pack: LovePack, state: LoveState) -> String {
        max(pack.startDate, state.importDay)
    }

    /// Records a message for every day in `days` that has none yet,
    /// earliest day first (so the order of planning never changes which day
    /// gets which message). Days before `firstDay` are skipped.
    public static func assign(days: [String], pack: LovePack, state: inout LoveState) {
        let first = firstDay(pack: pack, state: state)
        let open = days.sorted().filter { $0 >= first && LoveDay.isValid($0) && state.assignments[$0] == nil }
        guard !open.isEmpty, !pack.daily.isEmpty else { return }

        // Ranks are hashed once per call: a catch-up after a long absence
        // assigns many days against up to 2 000 messages.
        let ranks = Dictionary(pack.daily.map { ($0.id, rank($0.id, pack)) }, uniquingKeysWith: { first, _ in first })
        var assigned = Set(state.assignments.values)
        for day in open {
            let id = nextId(for: day, pack: pack, state: state, ranks: ranks, assigned: assigned)
            state.assignments[day] = id
            assigned.insert(id)
        }
    }

    /// The message planned for `day`, or `nil` before it is assigned.
    public static func message(for day: String, pack: LovePack, state: LoveState) -> LovePackDaily? {
        guard let id = state.assignments[day] else { return nil }
        return pack.daily(id: id)
    }

    /// Whether `day`'s message was already assigned to an earlier day.
    public static func isRepeat(day: String, state: LoveState) -> Bool {
        guard let id = state.assignments[day] else { return false }
        return state.assignments.contains { $0.key < day && $0.value == id }
    }

    private static func nextId(
        for day: String,
        pack: LovePack,
        state: LoveState,
        ranks: [String: UInt64],
        assigned: Set<String>
    ) -> String {
        let byRank: (String, String) -> Bool = { (ranks[$0] ?? 0) < (ranks[$1] ?? 0) }
        let allIds = pack.daily.map { $0.id }
        if let fresh = allIds.filter({ !assigned.contains($0) }).min(by: byRank) {
            return fresh
        }

        // Everything has been shown: favourites first, then everything, the
        // one shown longest ago first.
        let favorites = allIds.filter { state.isFavorite($0) }
        let candidates = favorites.isEmpty ? allIds : favorites
        var lastShown: [String: String] = [:]
        for (assignedDay, id) in state.assignments where assignedDay < day {
            if let previous = lastShown[id], previous >= assignedDay { continue }
            lastShown[id] = assignedDay
        }
        let pick = candidates.min { lhs, rhs in
            let left = lastShown[lhs] ?? ""
            let right = lastShown[rhs] ?? ""
            if left != right { return left < right }
            return byRank(lhs, rhs)
        }
        // `candidates` is never empty: `assign` returns early for a pack
        // with no messages, and the reader refuses such a pack anyway.
        return pick ?? allIds[0]
    }

    private static func rank(_ id: String, _ pack: LovePack) -> UInt64 {
        LoveMinute.stableHash(pack.seed, "order", id)
    }
}
