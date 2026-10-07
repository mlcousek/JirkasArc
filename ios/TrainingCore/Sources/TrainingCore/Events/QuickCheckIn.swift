// QuickCheckIn.swift
//
// The morning check-in recorded WITHOUT Today's row: the lock-screen
// Controls, the Home Screen check-in widget and the "Morning check-in" App
// Shortcut (add-training-shortcuts-and-widgets design D3). All three reach
// the app through one hook (Shared/MorningCheckInIntents.swift ->
// GarminFood/Training/TrainingEventsService.handleCheckIn), which builds
// its event here, so the rules are tested where they can be.
//
// The Controls and the widget send the light only. The shortcut may add
// ONE pain number (and, optionally, where it hurts) -- far less than the
// pain step on Today can say, so:
//
//   - a score must be a finite number within 0...10, else the check-in is
//     refused whole (`QuickCheckInError.painScoreOutOfRange`). Clamping
//     would record a pain nobody reported;
//   - inside the range it is rounded to the nearest half step, the
//     contract's grid and what Today's slider does (`PainDraft.rounded`);
//   - without a site it is the FIRST site the pain step would offer: the
//     Achilles site of the latest earlier day that scored one, else the
//     fallback site (`PainDraft.defaultSites`). "The days" are the file's
//     days with the phone's own answers laid over (`TrainingSnapshot
//     .allDays`), the same days the step reads;
//   - the event carries `pains: [{site, score}]`. By the vault's contract a
//     check-in with `pains` REPLACES the day's answer (CheckInOverlay), so
//     a two-site answer becomes this one site;
//   - without a score `pains` stays `nil`: not asked, the earlier answer
//     is kept;
//   - a site WITHOUT a score is refused whole
//     (`QuickCheckInError.painSiteWithoutScore`), like a score out of
//     range: ignoring it would answer "recorded" to something that wasn't.
//
// Nothing here is about anyone in particular: the default comes from what
// was recorded. Tests: QuickCheckInTests.

import Foundation

/// One pain number from a shortcut, with or without a site.
public struct QuickPainAnswer: Equatable, Sendable {
    /// As given: checked and rounded by `CheckInPlanning.painScore`.
    public var score: Double
    /// `nil`: the first site the pain step would offer.
    public var site: PainSite?

    public init(score: Double, site: PainSite? = nil) {
        self.score = score
        self.site = site
    }

    /// What a shortcut said about pain: `nil` when it said nothing. A site
    /// WITHOUT a score is refused (`painSiteWithoutScore`): dropping it
    /// silently would look like a recorded answer, and a site alone can't
    /// be one (the contract's entry is a site with its score).
    public static func given(score: Double?, site: PainSite?) throws -> QuickPainAnswer? {
        guard let score else {
            if site != nil { throw QuickCheckInError.painSiteWithoutScore }
            return nil
        }
        return QuickPainAnswer(score: score, site: site)
    }
}

public enum QuickCheckInError: Error, Equatable, Sendable {
    /// Not a finite number within 0...10. Nothing is recorded.
    case painScoreOutOfRange
    /// A pain site was given without a pain score. Nothing is recorded.
    case painSiteWithoutScore
}

public extension CheckInPlanning {
    /// `raw` on the contract's half-step grid; throws outside 0...10.
    static func painScore(_ raw: Double) throws -> Double {
        guard raw.isFinite, PainEntry.scoreRange.contains(raw) else {
            throw QuickCheckInError.painScoreOutOfRange
        }
        return PainDraft.rounded(raw)
    }

    /// The `pains` of a quick check-in on `date`: `nil` without an answer
    /// (not asked), else one entry. `days` are every day the app knows,
    /// the phone's answers applied.
    static func pains(for answer: QuickPainAnswer?, on date: LocalDate, days: [Day]) throws -> [PainEntry]? {
        guard let answer else { return nil }
        let score = try painScore(answer.score)
        let site = answer.site
            ?? PainDraft.defaultSites(before: date, days: days).first
            ?? PainDraft.fallbackSites.first
            ?? .other
        return [PainEntry(site: site, score: score)]
    }

    /// The check-in the Controls, the widget and the shortcut record:
    /// today's training day, its traffic-light session, and -- only when a
    /// score was given -- one pain entry. `checkIns` is the phone's own
    /// overlay; it matters for the default site only.
    static func morningCheckIn(
        light: MorningLight,
        pain: QuickPainAnswer?,
        projection: Projection?,
        checkIns: CheckInOverlay = .empty,
        now: Date,
        deviceTimeZone: TimeZone
    ) throws -> MorningCheckInPayload {
        var payload = morningCheckIn(light: light, projection: projection, now: now, deviceTimeZone: deviceTimeZone)
        guard let pain else { return payload }
        let days = projection.map { TrainingSnapshot(projection: $0, checkIns: checkIns).allDays } ?? []
        payload.pains = try pains(for: pain, on: payload.date, days: days)
        return payload
    }
}
