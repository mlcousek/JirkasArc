// GateModels.swift
//
// add-training-gates-and-load: what Today shows of the vault's training
// load and gates, as pure models. THE VAULT COMPUTES, the phone records and
// displays -- nothing here judges a score, sums a week or decides a window.
//
//   - `GateCardModel` (design D4): the weekly gate test, in pain mode only.
//     The verdict lines are the vault's `athlete.gate` in words ("Hops
//     4/10 — speed, hills and jumps stay locked"), greyed when the vault
//     calls the test stale, with a neutral line that a physio check is
//     advised when `weeksHopAbove2 > 2` (the contract's own display rule,
//     the one number compared here). A test this phone recorded that the
//     file does not show yet is listed as "Your test of ..." with its
//     delivery -- never with a verdict the phone worked out. The editor's
//     labels, defaults and the `test.gate` payload are here too, so the
//     view only draws. `isProminent` on Saturday and Sunday (the weekly
//     rhythm without a reminder); on other days the same model is one link
//     in the pain flow.
//   - `WeekLoadModel` (D7): "the plan is the ceiling" as one line of
//     segments -- run km of the target, km over plan, unplanned km, the
//     longest run of its cap, hills, hard sessions. A value the vault does
//     not know is "–", never 0. Over-plan and a longest run above its cap
//     are marked as warnings (the view adds a symbol; never praise).
//   - `RecoveryChipModel` (D12): `athlete.recovery` as "Recovery day 10 of
//     14 · until 27 Oct" with one line of what it means. It reads `of`
//     (14, or 7 after a race that was not finished) and never prints the
//     two-week text beside a 7-day window. Information only.
//   - vault notices (D9): the projection's `notices` in the app's language.
//
// The gate card, the chip and the notices are built for the CURRENT
// training day only (`TodayTrainingBuilder.today`; the shown day when the
// caller gives none) -- they describe now, not the day being browsed.
//
// Depended on by: TodayTrainingModel, PlanModels (the week header), the
// app's GateAndLoadViews. Tests: GatesAndLoadTests.

import Foundation

// MARK: - Gate test

public struct GateLineModel: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case walk, hop
    }

    public let kind: Kind
    public let text: String
    /// The vault's verdict: `true` = locked, `false` = allowed, `nil` = it
    /// did not say (never read as allowed).
    public let isLocked: Bool?

    public var id: Kind { kind }
}

public struct GateCardModel: Equatable, Sendable {
    /// The training day a new test is recorded for.
    public let date: LocalDate
    public let title: String
    public let hint: String
    /// Saturday and Sunday: a card of its own; else a link in the pain flow.
    public let isProminent: Bool
    /// Recording is possible (the vault connection can record).
    public let canRecord: Bool
    /// "Tested Wed 23 Oct"; `nil` without a test in the file.
    public let testedText: String?
    public let lines: [GateLineModel]
    /// The vault calls the test stale: the lines are greyed.
    public let isStale: Bool
    public let staleText: String?
    /// Shown when the vault counts more than two weeks above 2/10.
    public let physioText: String?
    /// "No gate test yet" when neither the file nor the phone has one.
    public let emptyText: String?
    /// The phone's own test the file does not show yet.
    public let pendingText: String?
    public let pendingHint: String?
    public let deliveryLine: String?
    /// "Record a test" / "Test again".
    public let recordTitle: String

    // The editor.
    public let walkLabel: String
    public let hopLabel: String
    public let siteLabel: String
    public let notePlaceholder: String
    public let saveTitle: String
    public let cancelTitle: String
    public let initialWalk: Double
    public let initialHop: Double
    public let initialSite: PainSite
    public let initialNote: String
    public let sites: [PainSite]
    public let siteNames: [PainSite: String]
    /// "0/10" ... "10/10" by half step (index = score x 2).
    public let scoreTexts: [String]
    /// VoiceOver values, "4.5 of 10", by half step.
    public let scoreAccessibilityValues: [String]

    public func siteName(_ site: PainSite) -> String {
        siteNames[site] ?? site.rawValue
    }

    public func scoreText(_ score: Double) -> String {
        Self.lookup(scoreTexts, score)
    }

    public func scoreAccessibilityValue(_ score: Double) -> String {
        Self.lookup(scoreAccessibilityValues, score)
    }

    private static func lookup(_ texts: [String], _ score: Double) -> String {
        let index = Int(PainDraft.rounded(score) * 2)
        return texts.indices.contains(index) ? texts[index] : ""
    }

    /// The `test.gate` Save records: both scores on the half-step grid, the
    /// note trimmed and cut to the contract's length (blank = none).
    public func payload(walk: Double, hop: Double, site: PainSite, note: String) -> GateTestPayload {
        GateTestPayload(
            date: date,
            walkPain: PainDraft.rounded(walk),
            hopPain: PainDraft.rounded(hop),
            site: site,
            note: PainDraft.cleanNote(note)
        )
    }
}

// MARK: - The plan is the ceiling

public struct WeekLoadSegment: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case run, overPlan, unplanned, longest, hills, hardSessions
    }

    public let kind: Kind
    public let text: String
    /// Over the plan, or above the longest-run cap: amber with a symbol.
    public let isWarning: Bool

    public var id: Kind { kind }
}

public struct WeekLoadModel: Equatable, Sendable {
    public let segments: [WeekLoadSegment]

    /// "Week 34 of 60 km · 8 km unplanned · longest 21 of 24 km cap · ...".
    public var text: String {
        segments.map(\.text).joined(separator: " · ")
    }

    public var hasWarning: Bool {
        segments.contains { $0.isWarning }
    }
}

// MARK: - Recovery window

public struct RecoveryChipModel: Equatable, Sendable {
    public let day: Int
    public let length: Int
    /// "Recovery day 10 of 14".
    public let title: String
    /// "until 27 Oct".
    public let untilText: String?
    /// "After Harvest Marathon".
    public let raceText: String?
    /// One generic line of what the window means; `nil` for a rule this
    /// build does not know (then the day count alone is shown).
    public let meaningText: String?
    /// `day / length`, 0...1.
    public let fraction: Double
    public let accessibilityLabel: String

    /// "Recovery day 10 of 14 · until 27 Oct".
    public var text: String {
        [title, untilText].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Builders

public extension TrainingFormatting {
    /// The mark for a value the vault does not know: "–", never "0".
    var unknownMark: String { text(.unknownValue) }

    /// The week's load line; `nil` when the file carries none of the load
    /// fields (an older file keeps its plain run line).
    func weekLoad(actual: WeekActual?, targetKm: Double?) -> WeekLoadModel? {
        guard let actual, actual.hasLoadFields else { return nil }
        func number(_ value: Double?) -> String {
            value.map { NumberText.decimal($0, language) } ?? unknownMark
        }
        func count(_ value: Int?) -> String {
            value.map { String($0) } ?? unknownMark
        }
        var segments: [WeekLoadSegment] = []
        let run = targetKm == nil
            ? text.format(.loadWeek, number(actual.runKm))
            : text.format(.loadWeekOfTarget, number(actual.runKm), number(targetKm))
        segments.append(WeekLoadSegment(kind: .run, text: run, isWarning: false))
        if let over = actual.overPlanKm, over > 0 {
            segments.append(WeekLoadSegment(kind: .overPlan, text: text.format(.loadOverPlan, number(over)), isWarning: true))
        }
        segments.append(WeekLoadSegment(kind: .unplanned, text: text.format(.loadUnplanned, number(actual.unplannedRunKm)), isWarning: false))
        var spike = false
        if let longest = actual.longestRunKm, let cap = actual.longestRunCapKm {
            spike = longest > cap
        }
        segments.append(WeekLoadSegment(
            kind: .longest,
            text: text.format(.loadLongestOfCap, number(actual.longestRunKm), number(actual.longestRunCapKm)),
            isWarning: spike
        ))
        segments.append(WeekLoadSegment(kind: .hills, text: text.format(.loadHills, count(actual.hillM)), isWarning: false))
        segments.append(WeekLoadSegment(kind: .hardSessions, text: text.format(.loadHardSessions, count(actual.highSessions)), isWarning: false))
        return WeekLoadModel(segments: segments)
    }
}

public extension TodayTrainingBuilder {
    /// Whether `date` is the current training day for this builder.
    internal func isCurrentDay(_ date: LocalDate) -> Bool {
        date == (today ?? date)
    }

    /// The weekly gate test for `date`: only in pain mode, only on the
    /// current training day.
    func gateCard(on date: LocalDate) -> GateCardModel? {
        guard let snapshot = source.snapshot, snapshot.painMode.isActive, isCurrentDay(date) else { return nil }
        let text = format.text
        let vault = snapshot.athlete.gate
        let phone = snapshot.checkIns.latestGateTest

        var lines: [GateLineModel] = []
        var physio: String?
        if let vault {
            let walkScore = vault.walkPain.map(format.painScoreText) ?? format.unknownMark
            let hopScore = vault.hopPain.map(format.painScoreText) ?? format.unknownMark
            var walkKey = TrainingKey.gateWalkPlain
            if vault.runAllowed == true {
                walkKey = .gateWalkAllowed
            } else if vault.runAllowed == false {
                walkKey = .gateWalkLocked
            }
            lines.append(GateLineModel(kind: .walk, text: text.format(walkKey, walkScore), isLocked: vault.runAllowed.map { !$0 }))
            // No running locks speed too, whatever `speedAllowed` says.
            let speedLocked: Bool? = vault.runAllowed == false ? true : vault.speedAllowed.map { !$0 }
            var hopKey = TrainingKey.gateHopPlain
            if speedLocked == true {
                hopKey = .gateHopLocked
            } else if speedLocked == false {
                hopKey = .gateHopAllowed
            }
            lines.append(GateLineModel(kind: .hop, text: text.format(hopKey, hopScore), isLocked: speedLocked))
            if let weeks = vault.weeksHopAbove2, weeks > 2 {
                physio = text.format(.gatePhysio, weeks)
            }
        }

        // The phone's own test, while the file does not show it.
        var pendingText: String?
        var delivery: String?
        if let phone {
            let test = phone.value
            var isNews = true
            if let vault {
                if test.date < vault.date {
                    isNews = false
                } else if test.date == vault.date {
                    let same = vault.walkPain == test.walkPain && vault.hopPain == test.hopPain
                    isNews = !same && phone.delivery != .received
                }
            }
            if isNews {
                pendingText = text.format(.gatePending, format.dates.short(test.date), format.painScoreText(test.walkPain), format.painScoreText(test.hopPain))
                delivery = format.deliveryLine(phone.delivery)
            }
        }

        let week = ISOWeek(containing: date)
        let weekHasTest = (vault.map { ISOWeek(containing: $0.date) == week } ?? false)
            || snapshot.checkIns.gateTests.keys.contains { ISOWeek(containing: $0) == week }
        let todays = snapshot.checkIns.gateTest(on: date)?.value
        let siteDefault = phone?.value.site
            ?? vault?.site
            ?? snapshot.painMode.vault.sites.first(where: \.isAchilles)
            ?? PainDraft.defaultSites(before: date.adding(days: 1), days: snapshot.allDays).first
            ?? .achillesLeft

        var names: [PainSite: String] = [:]
        for site in PainSite.allCases {
            names[site] = format.painSiteName(site)
        }
        let steps = (0...20).map { Double($0) / 2 }
        return GateCardModel(
            date: date,
            title: text(.gateTitle),
            hint: text(.gateHint),
            isProminent: date.isoWeekday >= 6,
            canRecord: snapshot.capabilities.canCheckIn,
            testedText: vault.map { text.format(.gateTested, format.dates.short($0.date)) },
            lines: lines,
            isStale: vault?.stale ?? false,
            staleText: vault?.stale == true ? text(.gateStale) : nil,
            physioText: physio,
            emptyText: vault == nil && pendingText == nil ? text(.gateNone) : nil,
            pendingText: pendingText,
            pendingHint: pendingText == nil ? nil : text(.answersAfterSync),
            deliveryLine: delivery,
            recordTitle: text(weekHasTest ? TrainingKey.gateRecordAgain : TrainingKey.gateRecord),
            walkLabel: text(.gateWalkLabel),
            hopLabel: text(.gateHopLabel),
            siteLabel: text(.gateSiteLabel),
            notePlaceholder: text(.noteOptional),
            saveTitle: text(.gateSave),
            cancelTitle: text(.actionCancel),
            initialWalk: todays?.walkPain ?? 0,
            initialHop: todays?.hopPain ?? 0,
            initialSite: todays?.site ?? siteDefault,
            initialNote: todays?.note ?? "",
            sites: PainDraft.siteOrder,
            siteNames: names,
            scoreTexts: steps.map(format.painScoreText),
            scoreAccessibilityValues: steps.map { text.format(.a11yPainValue, NumberText.decimal($0, format.language)) }
        )
    }

    /// The load line of the week `date` is in; `nil` when the week is not
    /// written or the file carries no load fields.
    func weekLoad(on date: LocalDate) -> WeekLoadModel? {
        guard let snapshot = source.snapshot, let week = snapshot.plan?.week(containing: date) else { return nil }
        let target = week.targets.runKm ?? snapshot.outlineRow(for: week.week)?.row.runKmTarget
        return format.weekLoad(actual: week.actual, targetKm: target)
    }

    /// The recovery window, on the current training day only.
    func recoveryChip(on date: LocalDate) -> RecoveryChipModel? {
        guard let snapshot = source.snapshot, let window = snapshot.athlete.recovery, isCurrentDay(date) else { return nil }
        let text = format.text
        let title = text.format(.recoveryChip, window.day, window.of)
        let untilText = window.until.map { text.format(.recoveryUntil, format.dates.dayMonth($0)) }
        let raceText = snapshot.race(id: window.raceId).map { race in
            text.format(.recoveryAfterRace, race.name.resolvedText(format.language) ?? race.id)
        }
        // By the rule AND the length: the two-week text never stands
        // beside a 7-day window.
        var meaning: String?
        if window.rule == "PM-SEQ-1" {
            meaning = text(window.day <= 7 ? TrainingKey.recoveryNoRunning : TrainingKey.recoveryEasyOnly)
        } else if window.rule == "PM-SEQ-3", window.of == 7 {
            meaning = text(.recoveryShortWeek)
        } else if window.rule == "PM-SEQ-3", window.of == 14 {
            meaning = text(.recoveryNoBuild)
        }
        let spoken = [title, untilText, raceText, meaning].compactMap { $0 }.joined(separator: ". ")
        return RecoveryChipModel(
            day: window.day,
            length: window.of,
            title: title,
            untilText: untilText,
            raceText: raceText,
            meaningText: meaning,
            fraction: min(1, max(0, Double(window.day) / Double(max(window.of, 1)))),
            accessibilityLabel: spoken
        )
    }

    /// The vault's data-gap notices in the app's language, on the current
    /// training day only. An unknown kind is shown all the same.
    func vaultNotices(on date: LocalDate) -> [String] {
        guard let snapshot = source.snapshot, isCurrentDay(date) else { return [] }
        return snapshot.notices.compactMap { notice in
            let resolved = notice.text.resolved(format.language)
            return resolved.isEmpty ? nil : resolved
        }
    }
}
