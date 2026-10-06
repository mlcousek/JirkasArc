// RaceResultModels.swift
//
// add-training-gates-and-load (design D13): how a race ended, on the Race
// screen, as pure models. THE VAULT DECIDES what the result is -- one
// source for the whole record (the race report once it states a status,
// else the app's accepted `race.result`), whether the typed goal was
// reached and whether it is a personal record. The phone shows that record
// and records its own `race.result`; it infers nothing.
//
//   - `RaceResultModel`: the record in neutral words ("Finished", "Did not
//     finish", "Did not start", the reason for the last two). TWO TIMES:
//     when the vault publishes an `officialTime` (the organiser's results
//     time, when that is another one than the clock) it is THE result and
//     the elapsed `time` is the second line ("21:31:23 elapsed"); without
//     one the elapsed time is the result and there is no second line.
//     Neither is ever copied into the other. Distance, laps, "Goal
//     reached" and "Personal record" only when the vault says `true`
//     (`nil` is "not known", never "no", and is not shown), where the
//     record came from, and the note.
//   - This phone's own result is shown instead while the vault has not
//     read it ("Saved on phone" / "Sent", "The plan answers after the next
//     sync."), and with the vault's reason when the vault refused it (a
//     finish sent before race day).
//   - `RaceResultEditorModel`: the result sheet -- status, a reason for a
//     race not finished or not started (with "Stopped by the stop rule"),
//     the elapsed time, an optional results time, distance, laps for a lap
//     race, a note -- and the `race.result` payload Save builds. Before
//     race day only "Did not start" is offered (the vault refuses a finish
//     sent early), and only in the two weeks before the race.
//   - Withdraw retracts every `race.result` of this phone for the race
//     that is still in the fold (the vault takes the last one that is not
//     retracted).
//
// Depended on by: RaceDetailModel (`result`), the app's RaceResultViews.
// Tests: GatesAndLoadTests.

import Foundation

public struct RaceResultModel: Equatable, Sendable {
    public let raceID: String
    /// "Result".
    public let title: String
    /// A result is shown (the vault's, or this phone's unread one).
    public let hasRecord: Bool
    public let status: RaceOutcome?
    /// "Finished" / "Did not finish" / "Did not start".
    public let statusText: String?
    /// With a race not finished or not started: "Stopped by the stop rule".
    public let reasonText: String?
    /// THE result time: the organiser's when there is one, else the
    /// elapsed time.
    public let timeText: String?
    /// "21:31:23 elapsed": only under an organiser's time.
    public let elapsedText: String?
    /// "42.2 km", "9 laps".
    public let factLines: [String]
    /// "Goal reached", only when the vault says so.
    public let goalReachedText: String?
    /// "Personal record", only when the race report says so.
    public let personalRecordText: String?
    /// "From the race report" / "Logged in the app".
    public let sourceText: String?
    public let note: String?
    /// "Saved on phone" / "Sent" for this phone's unread result.
    public let deliveryLine: String?
    /// "The plan answers after the next sync."
    public let pendingHint: String?
    /// The vault refused this phone's result: its reason, in the app's
    /// language.
    public let refusalText: String?
    /// "How did it go?" / "Change the result" / "Did not start".
    public let actionTitle: String
    /// The sheet; `nil` when nothing may be recorded for this race now.
    public let editor: RaceResultEditorModel?
    public let withdrawTitle: String
    /// This phone's `race.result` events for the race that Withdraw
    /// retracts; empty = nothing of this phone's to withdraw.
    public let withdrawEventIDs: [String]
    public let accessibilityLabel: String
}

public struct RaceResultEditorModel: Equatable, Sendable {
    public let raceID: String
    public let title: String
    public let statusLabel: String
    /// What may be recorded now: all three on or after race day, only
    /// "Did not start" before it.
    public let statuses: [RaceOutcome]
    public let statusNames: [RaceOutcome: String]
    /// Why only one status is offered; `nil` on or after race day.
    public let beforeRaceText: String?
    public let reasonLabel: String
    public let reasons: [RaceResultReason]
    public let reasonNames: [RaceResultReason: String]
    public let noReasonTitle: String
    public let timeLabel: String
    public let officialTimeLabel: String
    public let timeHint: String
    public let distanceLabel: String
    public let lapsLabel: String
    /// Laps are asked for a lap race (a timed race, or one that already
    /// has laps recorded).
    public let asksLaps: Bool
    public let notePlaceholder: String
    public let saveTitle: String
    public let cancelTitle: String
    public let initialStatus: RaceOutcome
    public let initialReason: RaceResultReason?
    public let initialTime: String
    public let initialOfficialTime: String
    public let initialDistanceKm: Double?
    public let initialLaps: Int?
    public let initialNote: String

    public func statusName(_ status: RaceOutcome) -> String {
        statusNames[status] ?? status.rawValue
    }

    public func reasonName(_ reason: RaceResultReason) -> String {
        reasonNames[reason] ?? reason.rawValue
    }

    /// A reason is asked for a race that was not finished or not started.
    public func asksReason(_ status: RaceOutcome) -> Bool {
        status != .finished
    }

    /// Times, distance and laps are asked for a race that was started.
    public func asksTimes(_ status: RaceOutcome) -> Bool {
        status != .dns
    }

    /// A typed time as the contract writes it: trimmed, hours without a
    /// leading zero ("03:24:10" -> "3:24:10"); `nil` for a blank field.
    /// Anything else is left as typed and refused by `payload`.
    public static func cleanTime(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let hours = Int(parts[0]), hours >= 0, parts[0].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return trimmed
        }
        return "\(hours):\(parts[1]):\(parts[2])"
    }

    /// The `race.result` Save records; `nil` when a value is not one the
    /// contract takes (a time that is not `h:mm:ss`, a distance that is not
    /// above 0, a status that is not offered). A race not started sends no
    /// time, distance or laps; a finished one no reason. The results time
    /// is sent only when filled AND different from the elapsed one -- never
    /// a copy of it. The distance is put on a 0.01 km grid; a blank note
    /// is none.
    public func payload(
        status: RaceOutcome,
        reason: RaceResultReason?,
        time: String,
        officialTime: String,
        distanceKm: Double?,
        laps: Int?,
        note: String
    ) -> RaceResultPayload? {
        guard statuses.contains(status) else { return nil }
        let started = asksTimes(status)
        let elapsed = started ? Self.cleanTime(time) : nil
        var official = started ? Self.cleanTime(officialTime) : nil
        if official == elapsed { official = nil }
        var distance: Double?
        if started, let distanceKm {
            distance = (distanceKm * 100).rounded() / 100
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = RaceResultPayload(
            raceId: raceID,
            status: status,
            reason: asksReason(status) ? reason : nil,
            time: elapsed,
            officialTime: official,
            distanceKm: distance,
            laps: started && asksLaps ? laps : nil,
            note: trimmed.isEmpty ? nil : String(trimmed.prefix(SessionNotePayload.maxLength))
        )
        do {
            try HubEventPayload.raceResult(payload).validate()
        } catch {
            return nil
        }
        return payload
    }
}

// MARK: - Builder

extension PlanBuilder {
    /// How many days before race day "Did not start" is offered.
    static let nonStartWindowDays = 14

    /// The result card of `race`; `nil` when there is nothing to show and
    /// nothing to record.
    func raceResultModel(_ race: Race, snapshot: TrainingSnapshot) -> RaceResultModel? {
        let text = format.text
        let language = format.language
        let phone = snapshot.checkIns.raceResult(race: race.id)
        var vault = race.result

        // This phone withdrew its result and the vault has not read that
        // yet: the event-sourced record on file is on its way out.
        var pendingHint: String?
        if phone == nil, snapshot.checkIns.hasPendingRaceWithdrawal(race: race.id), vault?.source?.known == .event {
            vault = nil
            pendingHint = text(.answersAfterSync)
        }

        var refusalText: String?
        var deliveryLine: String?
        var shown = RaceRecord(vault)
        var isVaults = vault != nil
        if let phone {
            if phone.isRefused {
                let reason = phone.refusalReason?.resolved(language) ?? ""
                refusalText = reason.isEmpty ? text(.raceResultRefused) : reason
            } else if phone.delivery != .received {
                shown = RaceRecord(phone.payload)
                isVaults = false
                deliveryLine = format.deliveryLine(phone.delivery)
                pendingHint = text(.answersAfterSync)
            }
        }

        var statusText: String?
        switch shown.status {
        case .finished?: statusText = text(.phaseFinished)
        case .dnf?: statusText = text(.raceStatusDNF)
        case .dns?: statusText = text(.raceStatusDNS)
        case nil: statusText = nil
        }
        var reasonText: String?
        if shown.status == .dnf || shown.status == .dns {
            reasonText = shown.reason.map(raceReasonName)
        }
        // The organiser's time is the result when there is one.
        let timeText = shown.officialTime ?? shown.time
        var elapsedText: String?
        if shown.officialTime != nil, let elapsed = shown.time {
            elapsedText = text.format(.raceElapsed, elapsed)
        }
        var facts: [String] = []
        if let km = shown.distanceKm { facts.append(NumberText.distance(km, language)) }
        if let laps = shown.laps { facts.append(text.format(.raceLaps, laps)) }

        var sourceText: String?
        if isVaults {
            switch vault?.source?.known {
            case .report?: sourceText = text(.raceResultFromReport)
            case .event?: sourceText = text(.raceResultFromApp)
            case nil: sourceText = nil
            }
        }
        let goalText = isVaults && vault?.goalReached == true ? text(.raceGoalReached) : nil
        let recordText = isVaults && vault?.pr == true ? text(.racePR) : nil
        let hasRecord = statusText != nil || timeText != nil || !facts.isEmpty

        // Recording: never once the race report states the result (the
        // report replaces the app's result whole).
        let reported = vault?.source?.known == .report
        let canRecord = snapshot.capabilities.canRateSession && !reported
        // Before the race's date -- an approximate date too: the vault does
        // not guard those, but a finish months ahead is never offered.
        let isBeforeRace = today < race.date
        var editor: RaceResultEditorModel?
        if canRecord, !isBeforeRace || today.days(until: race.date) <= Self.nonStartWindowDays {
            editor = raceResultEditor(race, phone: phone?.payload, vault: vault, isBeforeRace: isBeforeRace)
        }
        let withdrawIDs = snapshot.capabilities.canRateSession ? snapshot.checkIns.raceResultEventIDs(race: race.id) : []

        guard hasRecord || editor != nil || refusalText != nil || pendingHint != nil || !withdrawIDs.isEmpty else { return nil }

        var actionTitle = text(hasRecord ? TrainingKey.raceResultEdit : TrainingKey.raceResultAction)
        if isBeforeRace, !hasRecord {
            actionTitle = text(.raceStatusDNS)
        }
        let spoken = [statusText, reasonText, timeText, elapsedText].compactMap { $0 }
            + facts
            + [goalText, recordText, sourceText, shown.note, deliveryLine, pendingHint, refusalText].compactMap { $0 }
        return RaceResultModel(
            raceID: race.id,
            title: text(.raceResultTitle),
            hasRecord: hasRecord,
            status: shown.status,
            statusText: statusText,
            reasonText: reasonText,
            timeText: timeText,
            elapsedText: elapsedText,
            factLines: facts,
            goalReachedText: goalText,
            personalRecordText: recordText,
            sourceText: sourceText,
            note: shown.note,
            deliveryLine: deliveryLine,
            pendingHint: pendingHint,
            refusalText: refusalText,
            actionTitle: actionTitle,
            editor: editor,
            withdrawTitle: text(.raceResultWithdraw),
            withdrawEventIDs: withdrawIDs,
            accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    private func raceReasonName(_ reason: RaceResultReason) -> String {
        let text = format.text
        switch reason {
        case .stopRule: return text(.raceReasonStopRule)
        case .injury: return text(.raceReasonInjury)
        case .illness: return text(.raceReasonIllness)
        case .other: return text(.raceReasonOther)
        }
    }

    private func raceResultEditor(_ race: Race, phone: RaceResultPayload?, vault: RaceResult?, isBeforeRace: Bool) -> RaceResultEditorModel {
        let text = format.text
        let statuses: [RaceOutcome] = isBeforeRace ? [.dns] : [.finished, .dnf, .dns]
        let reasons: [RaceResultReason] = [.stopRule, .injury, .illness, .other]
        var statusNames: [RaceOutcome: String] = [:]
        statusNames[.finished] = text(.phaseFinished)
        statusNames[.dnf] = text(.raceStatusDNF)
        statusNames[.dns] = text(.raceStatusDNS)
        var reasonNames: [RaceResultReason: String] = [:]
        for reason in reasons {
            reasonNames[reason] = raceReasonName(reason)
        }

        // Where the sheet starts: this phone's last result, else the
        // vault's record of an earlier one, else the race's own distance.
        let known = phone.map { RaceRecord($0) } ?? RaceRecord(vault)
        var initialStatus = statuses[0]
        if let status = known.status, statuses.contains(status) {
            initialStatus = status
        }
        let label = (race.distanceLabel ?? "").lowercased().filter { !$0.isWhitespace }
        let isTimed = label.hasSuffix("h") && !label.dropLast().isEmpty && label.dropLast().allSatisfy { $0.isNumber }
        let category = (race.category ?? "").lowercased()
        return RaceResultEditorModel(
            raceID: race.id,
            title: text(.raceResultTitle),
            statusLabel: text(.raceResultStatusLabel),
            statuses: statuses,
            statusNames: statusNames,
            beforeRaceText: isBeforeRace ? text(.raceResultBeforeRace) : nil,
            reasonLabel: text(.raceResultReasonLabel),
            reasons: reasons,
            reasonNames: reasonNames,
            noReasonTitle: text(.raceReasonNone),
            timeLabel: text(.raceResultTimeLabel),
            officialTimeLabel: text(.raceResultOfficialLabel),
            timeHint: text(.raceTimeHint),
            distanceLabel: text(.distanceKmLabel),
            lapsLabel: text(.raceResultLapsLabel),
            asksLaps: isTimed || category.contains("24h") || known.laps != nil,
            notePlaceholder: text(.noteOptional),
            saveTitle: text(.raceResultSave),
            cancelTitle: text(.actionCancel),
            initialStatus: initialStatus,
            initialReason: known.reason,
            initialTime: known.time ?? "",
            initialOfficialTime: known.officialTime ?? "",
            initialDistanceKm: known.distanceKm ?? race.distanceKm,
            initialLaps: known.laps,
            initialNote: known.note ?? ""
        )
    }
}

/// The fields a result shows, from the vault's record or from this phone's
/// own event (never mixed).
private struct RaceRecord {
    var status: RaceOutcome?
    var reason: RaceResultReason?
    var time: String?
    var officialTime: String?
    var distanceKm: Double?
    var laps: Int?
    var note: String?

    init(_ result: RaceResult?) {
        status = result?.status?.known
        // An unknown reason reads as "other", like the vault reads it.
        if let reason = result?.reason {
            self.reason = reason.known ?? .other
        }
        time = result?.time
        officialTime = result?.officialTime
        distanceKm = result?.distanceKm
        laps = result?.laps
        note = result?.note
    }

    init(_ payload: RaceResultPayload) {
        status = payload.status
        reason = payload.reason
        time = payload.time
        officialTime = payload.officialTime
        distanceKm = payload.distanceKm
        laps = payload.laps
        note = payload.note
    }
}
