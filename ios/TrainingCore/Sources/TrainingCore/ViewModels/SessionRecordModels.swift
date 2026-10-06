// SessionRecordModels.swift
//
// add-training-gates-and-load: what the session detail records beyond the
// RPE and the note, as pure models -- labels, defaults, what is already
// recorded (the phone's own answer first, else the vault's fold) and the
// event payload each Save builds. The app's views only draw them and hold
// the owner's edits as state.
//
//   - `SessionPainModel` (design D5): pain during and after the session,
//     per site, in pain mode only. It travels WITH the RPE (`session.rpe`
//     needs an `rpe`), so Save needs a chosen RPE and sends it again with
//     `pains`. Both scores of a row are sent as numbers (a row at 0 means
//     "no pain", the morning step's precedent); what the vault publishes
//     as unknown is drawn as "–".
//   - `ManualDoneModel` (D8): "Mark done (no watch)" -- offered when the
//     app may record, the session's day is today or earlier and it is
//     neither done nor skipped; works for a gym session. Defaults are the
//     plan's (`targets.min`, `targets.km`, the option the morning light
//     points at); kilometres are asked for a run, ride or walk. Undo is
//     offered while this phone still holds the `session.done` the session
//     is done by (a completion from another install can not be retracted
//     here -- the vault only lets a device retract its own events).
//   - `SessionFuelModel` (D11): the fuel log -- offered after a long
//     session (planned or done at 2 h or more), a session with a fuel
//     plan, or a race session. It shows the vault's `feedback.fuel`
//     (grams per hour against the plan, the neutral below / on / above
//     chip); the phone computes none of it. `0 g` is an answer.
//
// The vault's `session-pain` / `pain-not-settled` notes need nothing here:
// they are the session's rule notes and are listed with its other notes.
//
// Depended on by: SessionDetailModel, the app's SessionRecordViews. Tests:
// GatesAndLoadTests.

import Foundation

// MARK: - Pain during / after

public struct SessionPainDraftRow: Equatable, Sendable, Identifiable {
    public var site: PainSite
    /// 0...10, a multiple of 0.5.
    public var during: Double
    /// 0...10, a multiple of 0.5.
    public var after: Double

    public var id: PainSite { site }

    public init(site: PainSite, during: Double = 0, after: Double = 0) {
        self.site = site
        self.during = PainDraft.rounded(during)
        self.after = PainDraft.rounded(after)
    }
}

public struct SessionPainDraft: Equatable, Sendable {
    public private(set) var rows: [SessionPainDraftRow]

    public init(rows: [SessionPainDraftRow] = []) {
        var seen = Set<PainSite>()
        self.rows = rows.filter { seen.insert($0.site).inserted }
    }

    /// A recorded answer: one row per site (the first entry of a site
    /// wins), a score that was not asked starts at 0.
    public init(entries: [SessionPainEntry]) {
        self.init(rows: entries.map { SessionPainDraftRow(site: $0.site, during: $0.during ?? 0, after: $0.after ?? 0) })
    }

    /// `sites` at 0 / 0.
    public static func zeros(_ sites: [PainSite]) -> SessionPainDraft {
        SessionPainDraft(rows: sites.map { SessionPainDraftRow(site: $0) })
    }

    /// Sites not in the draft yet, in the offered order.
    public var addableSites: [PainSite] {
        PainDraft.siteOrder.filter { site in !rows.contains { $0.site == site } }
    }

    public var isEmpty: Bool { rows.isEmpty }

    public mutating func add(_ site: PainSite) {
        guard !rows.contains(where: { $0.site == site }) else { return }
        rows.append(SessionPainDraftRow(site: site))
    }

    public mutating func remove(_ site: PainSite) {
        rows.removeAll { $0.site == site }
    }

    public mutating func setDuring(_ score: Double, for site: PainSite) {
        guard let index = rows.firstIndex(where: { $0.site == site }) else { return }
        rows[index].during = PainDraft.rounded(score)
    }

    public mutating func setAfter(_ score: Double, for site: PainSite) {
        guard let index = rows.firstIndex(where: { $0.site == site }) else { return }
        rows[index].after = PainDraft.rounded(score)
    }

    /// The contract's `pains`: every row with both scores; `[]` when every
    /// row was removed ("asked, nothing hurt").
    public var entries: [SessionPainEntry] {
        rows.map { SessionPainEntry(site: $0.site, during: PainDraft.rounded($0.during), after: PainDraft.rounded($0.after)) }
    }
}

public struct SessionPainModel: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    public let title: String
    public let duringLabel: String
    public let afterLabel: String
    public let saveTitle: String
    public let addSiteTitle: String
    public let nothingHurtsText: String
    /// The RPE the pain is sent with; `nil` = choose one first.
    public let rpe: Int?
    /// Shown instead of an enabled Save while there is no RPE.
    public let needsRPEText: String?
    /// The pain was asked (the phone's or the vault's answer).
    public let isRecorded: Bool
    /// "Achilles (left): during 4/10 · after 6/10" per site, or the one
    /// line "Pain: nothing hurt"; `[]` when not asked.
    public let recordedLines: [String]
    public let deliveryLine: String?
    /// Where the editor starts: the recorded answer, else the pain
    /// episode's sites at 0 / 0.
    public let draft: SessionPainDraft
    public let siteNames: [PainSite: String]
    public let removeLabels: [PainSite: String]
    public let scoreTexts: [String]
    public let scoreAccessibilityValues: [String]

    public func siteName(_ site: PainSite) -> String {
        siteNames[site] ?? site.rawValue
    }

    public func scoreText(_ score: Double) -> String {
        let index = Int(PainDraft.rounded(score) * 2)
        return scoreTexts.indices.contains(index) ? scoreTexts[index] : ""
    }

    public func scoreAccessibilityValue(_ score: Double) -> String {
        let index = Int(PainDraft.rounded(score) * 2)
        return scoreAccessibilityValues.indices.contains(index) ? scoreAccessibilityValues[index] : ""
    }

    /// The rating Save records: the same RPE again, with the draft's
    /// `pains`. `nil` without an RPE.
    public func payload(_ draft: SessionPainDraft) -> SessionRPEPayload? {
        guard let rpe else { return nil }
        return SessionRPEPayload(date: date, sessionId: sessionID, rpe: rpe, pains: draft.entries)
    }
}

// MARK: - Done without a watch

public struct ManualDoneModel: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    /// "Mark done (no watch)" may be offered.
    public let canMark: Bool
    public let actionTitle: String
    public let sheetTitle: String
    public let saveTitle: String
    public let cancelTitle: String
    public let undoTitle: String
    /// G, A, R when the session has options; else empty (no picker).
    public let optionCodes: [OptionCode]
    public let optionLabel: String
    /// "G · Planned session".
    public let optionNames: [OptionCode: String]
    public let initialOption: OptionCode?
    public let minutesLabel: String
    public let initialMinutes: Int?
    /// Kilometres are asked for a run, ride or walk.
    public let asksDistance: Bool
    public let distanceLabel: String
    public let initialKm: Double?
    public let notePlaceholder: String
    /// This phone's `session.done` the session is done by: Undo retracts
    /// it. `nil` = nothing of this phone's to undo.
    public let undoEventID: String?
    public let deliveryLine: String?

    /// The `session.done` Save records; `nil` when a value is out of the
    /// contract's bounds (minutes 1...6000, km above 0 and at most 1000).
    /// Kilometres are rounded to 0.1 first; a blank note is none.
    public func payload(option: OptionCode?, minutes: Int?, km: Double?, note: String) -> SessionDonePayload? {
        var distance: Double?
        if asksDistance, let km {
            distance = (km * 10).rounded() / 10
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = SessionDonePayload(
            date: date,
            sessionId: sessionID,
            option: optionCodes.isEmpty ? nil : option,
            min: minutes,
            km: distance,
            note: trimmed.isEmpty ? nil : String(trimmed.prefix(SessionNotePayload.maxLength))
        )
        do {
            try HubEventPayload.sessionDone(payload).validate()
        } catch {
            return nil
        }
        return payload
    }
}

// MARK: - Fuel log

public struct SessionFuelModel: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    public let canRecord: Bool
    public let title: String
    /// "Log fuel" / "Change the fuel log".
    public let actionTitle: String
    public let saveTitle: String
    public let cancelTitle: String
    public let carbsLabel: String
    public let fluidLabel: String
    public let durationLabel: String
    public let notePlaceholder: String
    /// "90 g carbs eaten · 750 ml fluid", "46 g/h of 60 g/h planned".
    public let lines: [String]
    /// The vault's verdict against the plan; `nil` = no chip.
    public let vsPlan: FuelVsPlan?
    public let vsPlanText: String?
    /// "Add the duration to see grams per hour." / "The plan answers
    /// after the next sync."
    public let hintText: String?
    public let note: String?
    public let deliveryLine: String?
    public let initialCarbs: Double?
    public let initialFluidMl: Int?
    public let initialDurationMin: Int?
    public let initialNote: String

    /// The `session.fuel` Save records; `nil` when a value is out of the
    /// contract's bounds (carbs 0...2000 g, minutes 1...6000). `0 g` is an
    /// answer. Carbs are rounded to whole grams.
    public func payload(carbs: Double, fluidMl: Int?, durationMin: Int?, note: String) -> SessionFuelPayload? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = SessionFuelPayload(
            date: date,
            sessionId: sessionID,
            carbsG: carbs.rounded(),
            fluidMl: fluidMl,
            durationMin: durationMin,
            note: trimmed.isEmpty ? nil : String(trimmed.prefix(SessionNotePayload.maxLength))
        )
        do {
            try HubEventPayload.sessionFuel(payload).validate()
        } catch {
            return nil
        }
        return payload
    }
}

// MARK: - Builders

extension PlanBuilder {
    /// The pain block of "How did it feel?"; `nil` outside pain mode, when
    /// rating is not allowed, or before the session's day.
    func sessionPainModel(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> SessionPainModel? {
        guard snapshot.capabilities.canRateSession, snapshot.painMode.isActive, day.date <= today else { return nil }
        let text = format.text
        let local = snapshot.checkIns.pains(session: session.id)
        let recorded = local?.value ?? session.feedback?.pains
        let rpe = snapshot.checkIns.rpe(session: session.id)?.value ?? session.feedback?.rpe

        var sites = snapshot.painMode.vault.sites
        if sites.isEmpty {
            sites = PainDraft.defaultSites(before: day.date.adding(days: 1), days: snapshot.allDays)
        }
        var names: [PainSite: String] = [:]
        var removes: [PainSite: String] = [:]
        for site in PainSite.allCases {
            let name = format.painSiteName(site)
            names[site] = name
            removes[site] = text.format(.painRemoveSite, name)
        }
        let steps = (0...20).map { Double($0) / 2 }
        return SessionPainModel(
            sessionID: session.id,
            date: day.date,
            title: text(.sessionPainTitle),
            duringLabel: text(.sessionPainDuring),
            afterLabel: text(.sessionPainAfter),
            saveTitle: text(.sessionPainSave),
            addSiteTitle: text(.painAddSite),
            nothingHurtsText: text(.painNothingHurts),
            rpe: rpe,
            needsRPEText: rpe == nil ? text(.sessionPainNeedsRPE) : nil,
            isRecorded: recorded != nil,
            recordedLines: format.sessionPainLines(recorded),
            deliveryLine: format.deliveryLine(local?.delivery),
            draft: recorded.map { SessionPainDraft(entries: $0) } ?? SessionPainDraft.zeros(sites),
            siteNames: names,
            removeLabels: removes,
            scoreTexts: steps.map(format.painScoreText),
            scoreAccessibilityValues: steps.map { text.format(.a11yPainValue, NumberText.decimal($0, format.language)) }
        )
    }

    /// "Mark done (no watch)" and its undo; `nil` when there is neither.
    func manualDoneModel(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> ManualDoneModel? {
        guard snapshot.capabilities.canRateSession else { return nil }
        let text = format.text
        let status = session.status?.known
        let canMark = day.date <= today && status != .done && status != .skipped && session.done == nil

        // Undo: this phone still holds the event the session is done by.
        let local = snapshot.checkIns.doneByHand(session: session.id)
        var undoID: String?
        if let local, let event = session.done?.manual?.event, event.lowercased() == local.eventID.lowercased() {
            undoID = local.eventID
        }
        guard canMark || undoID != nil else { return nil }

        let codes = session.options.compactMap { $0.code.known }
        var optionNames: [OptionCode: String] = [:]
        for code in codes {
            let meaning = text.optionMeaning(OpenEnum(code)) ?? code.rawValue
            optionNames[code] = "\(code.rawValue) · \(meaning)"
        }
        let lightCode = day.light?.known?.option
        let initialOption = codes.first { $0 == lightCode } ?? codes.first

        var targets = session.targets
        if let initialOption, let option = session.option(initialOption) {
            targets = option.targets
        }
        let sport = (initialOption.flatMap { session.option($0)?.sport } ?? session.sport)?.known
        return ManualDoneModel(
            sessionID: session.id,
            date: day.date,
            canMark: canMark,
            actionTitle: text(.manualDoneAction),
            sheetTitle: text(.manualDoneTitle),
            saveTitle: text(.manualSave),
            cancelTitle: text(.actionCancel),
            undoTitle: text(.actionUndo),
            optionCodes: codes,
            optionLabel: text(.manualOptionLabel),
            optionNames: optionNames,
            initialOption: initialOption,
            minutesLabel: text(.manualMinutesLabel),
            initialMinutes: targets.min ?? session.targets.min,
            asksDistance: sport == .run || sport == .ride || sport == .walk,
            distanceLabel: text(.distanceKmLabel),
            initialKm: targets.km ?? session.targets.km,
            notePlaceholder: text(.noteOptional),
            undoEventID: undoID,
            deliveryLine: undoID == nil ? nil : format.deliveryLine(local?.delivery)
        )
    }

    /// The fuel log; `nil` when the session is not one to log fuel for and
    /// has no log.
    func sessionFuelModel(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> SessionFuelModel? {
        let text = format.text
        let language = format.language
        let local = snapshot.checkIns.fuelLog(session: session.id)
        let vault = session.feedback?.fuel

        let longMinutes = 120
        let isLong = (session.targets.min ?? 0) >= longMinutes
            || (session.done?.activity?.min ?? 0) >= longMinutes
            || (session.done?.manual?.min ?? 0) >= longMinutes
        let wanted = session.isRace || session.fuel != nil || isLong
        let canRecord = snapshot.capabilities.canRateSession && day.date <= today && (wanted || local != nil || vault != nil)
        guard canRecord || vault != nil || local != nil else { return nil }

        func amounts(carbs: Double?, fluid: Int?) -> String? {
            var parts: [String] = []
            if let carbs { parts.append(text.format(.fuelLogCarbs, NumberText.decimal(carbs, language))) }
            if let fluid { parts.append(text.format(.fuelLogFluid, String(fluid))) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        var lines: [String] = []
        var vsPlan: FuelVsPlan?
        var hint: String?
        var note: String?
        var delivery: String?
        // The phone's log while the vault has not read it; else the vault's.
        if let local, local.delivery != .received {
            if let line = amounts(carbs: local.value.carbsG, fluid: local.value.fluidMl) { lines.append(line) }
            hint = text(.answersAfterSync)
            note = local.value.note
            delivery = format.deliveryLine(local.delivery)
        } else if let vault {
            if let line = amounts(carbs: vault.carbsG, fluid: vault.fluidMl) { lines.append(line) }
            if let perHour = vault.gPerH {
                if let plan = vault.planGPerH {
                    lines.append(text.format(.fuelLogPerHourOfPlan, String(perHour), NumberText.decimal(plan, language)))
                } else {
                    lines.append(text.format(.fuelLogPerHour, String(perHour)))
                }
            } else {
                hint = text(.fuelNoDuration)
            }
            vsPlan = vault.vsPlan?.known
            note = vault.note
        }
        var vsPlanText: String?
        switch vsPlan {
        case .below?: vsPlanText = text(.fuelBelow)
        case .on?: vsPlanText = text(.fuelOn)
        case .above?: vsPlanText = text(.fuelAbove)
        case nil: vsPlanText = nil
        }

        let hasLog = local != nil || vault != nil
        return SessionFuelModel(
            sessionID: session.id,
            date: day.date,
            canRecord: canRecord,
            title: text(.fuelLogTitle),
            actionTitle: text(hasLog ? TrainingKey.fuelLogEdit : TrainingKey.fuelLogAction),
            saveTitle: text(.fuelSave),
            cancelTitle: text(.actionCancel),
            carbsLabel: text(.fuelCarbsLabel),
            fluidLabel: text(.fuelFluidLabel),
            durationLabel: text(.fuelDurationLabel),
            notePlaceholder: text(.noteOptional),
            lines: lines,
            vsPlan: vsPlan,
            vsPlanText: vsPlanText,
            hintText: hint,
            note: note,
            deliveryLine: delivery,
            initialCarbs: local?.value.carbsG ?? vault?.carbsG,
            initialFluidMl: local?.value.fluidMl ?? vault?.fluidMl,
            initialDurationMin: local?.value.durationMin,
            initialNote: local?.value.note ?? vault?.note ?? ""
        )
    }
}

public extension TrainingFormatting {
    /// "Achilles (left): during 4/10 · after 6/10" per site; one line
    /// "Pain: nothing hurt" for `[]`; `[]` when not asked. A score the
    /// vault does not know is "–".
    func sessionPainLines(_ pains: [SessionPainEntry]?) -> [String] {
        guard let pains else { return [] }
        if pains.isEmpty { return [text(.sessionPainNone)] }
        return pains.map { entry in
            text.format(
                .sessionPainLine,
                painSiteName(entry.site),
                entry.during.map(painScoreText) ?? unknownMark,
                entry.after.map(painScoreText) ?? unknownMark
            )
        }
    }

    /// "45 min · 10 km · the note" of a manual completion; `nil` when it
    /// says nothing.
    func manualDoneLine(_ manual: ManualDone?) -> String? {
        guard let manual else { return nil }
        var parts: [String] = []
        if let minutes = manual.min { parts.append(NumberText.duration(minutes: minutes)) }
        if let km = manual.km { parts.append(NumberText.distance(km, language)) }
        if let note = manual.note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
