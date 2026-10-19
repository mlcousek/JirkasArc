// PartnerThemeModel.swift
//
// add-partner-love-theme D2: the app's one owner of the partner theme. It
// holds the stored love pack and the partner's state (FoodLogCore
// LoveStore), says whether the theme is ON -- a valid pack is stored AND
// the partner theme is the selected one, the single switch every themed
// behaviour reads (`isActive`) -- and tells ThemeStore which unlockable
// themes this phone may show.
//
// The "a pack is installed" bit is also kept in UserDefaults, so the theme
// is already unlocked when ThemeStore starts at launch, before the pack
// file has been read: no flash of GF Teal on her phone. `reload()` corrects
// it from the store either way (a pack removed, a restore without one).
//
// Import is two steps, like a backup restore: `preview(fileAt:)` reads and
// validates the file and says what would change; `apply(_:)` stores it.
// Nothing changes on a failed preview. The first import also selects the
// theme, so opening the AirDropped file is all it takes.
//
// Depends on: LoveStore (AppServices), ThemeStore, PartnerText. Depended on
// by: AppEnvironment (notifications, foreground), the import sheet,
// Settings > Appearance, and the theme's screens.

import Foundation
import Observation
import AppearanceKit
import FoodLogCore
import Gamification
import GarminKit

/// A love pack file waiting for the import sheet (AirDrop, Files).
struct LovePackImportRequest: Identifiable {
    let id = UUID()
    let url: URL
}

/// Why a picked file could not be previewed.
enum LovePackImportFailure: Error, Equatable {
    case unreadable
    case invalid(LovePackProblem)
}

@MainActor
@Observable
final class PartnerThemeModel {
    nonisolated static let packInstalledKey = "partner.packInstalled"
    /// The pack's `themeName`, kept so Settings shows it from launch.
    nonisolated static let themeNameKey = "partner.themeName"
    nonisolated static let partnerThemeID = "partner"

    private(set) var pack: LovePack?
    private(set) var state: LoveState?
    private(set) var isMissingPictures = false
    /// The day a tapped love notification is for, until the message box
    /// shows it.
    var pendingMessageDay: String?

    @ObservationIgnored private let store: LoveStore
    @ObservationIgnored private let themeStore: ThemeStore
    @ObservationIgnored private let defaults: UserDefaults

    init(store: LoveStore, themeStore: ThemeStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.themeStore = themeStore
        self.defaults = defaults
    }

    /// The unlockable themes the stored "pack installed" bit allows, for
    /// ThemeStore's first resolve at launch.
    static func launchUnlockedThemes(defaults: UserDefaults = .standard) -> Set<String> {
        defaults.bool(forKey: packInstalledKey) ? [partnerThemeID] : []
    }

    var isPackInstalled: Bool { pack != nil }

    /// THE switch: a valid pack is stored and the partner theme is selected.
    var isActive: Bool {
        pack != nil && themeStore.theme.id == Self.partnerThemeID
    }

    var content: PartnerThemeContent? { PartnerText.content }

    /// The theme's name: the pack's `themeName`, else the table's.
    nonisolated static func displayName(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: themeNameKey) ?? PartnerText.content?.themeName ?? partnerThemeID
    }

    // MARK: Loading

    func reload() async {
        pack = await store.pack()
        state = await store.state()
        isMissingPictures = await store.isMissingPictures()
        let installed = pack != nil
        defaults.set(installed, forKey: Self.packInstalledKey)
        if let name = pack?.themeName {
            defaults.set(name, forKey: Self.themeNameKey)
        } else {
            defaults.removeObject(forKey: Self.themeNameKey)
        }
        themeStore.setUnlockedThemes(installed ? [Self.partnerThemeID] : [])
    }

    // MARK: Importing

    func preview(fileAt url: URL) async -> Result<LovePackImportPreview, LovePackImportFailure> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= LovePackLimits.maxFileBytes else {
            return .failure(.invalid(.tooLarge(bytes: size)))
        }
        guard let data = try? Data(contentsOf: url) else {
            DiagnosticsLog.log(.warning, category: "LovePack", "couldn't read the picked love pack file")
            return .failure(.unreadable)
        }
        return await store.preview(importing: data).mapError { .invalid($0) }
    }

    func apply(_ preview: LovePackImportPreview) async throws {
        try await store.apply(preview)
        await reload()
        if preview.diff.kind != .update {
            themeStore.selectTheme(Self.partnerThemeID)
        }
    }

    /// Back to GF Teal; the state is kept for the pack's return.
    func removePack() async throws {
        if themeStore.theme.id == Self.partnerThemeID {
            themeStore.selectTheme(ThemeCatalog.defaultThemeID)
        }
        try await store.removePack()
        await reload()
    }

    // MARK: The daily message

    /// Reveals every due day (a week away included) and saves.
    func revealDue(clashMinutes: [Int], now: Date = Date()) async {
        guard isActive else { return }
        await mutate { pack, state in
            LoveReveal.catchUp(pack: pack, state: &state, now: now, otherReminderMinutes: clashMinutes)
        }
    }

    /// A love notification was opened: its day is revealed (even before its
    /// minute) and the message box is asked to show it.
    func openedNotification(day: String, clashMinutes: [Int], now: Date = Date()) async {
        guard pack != nil else { return }
        await mutate { pack, state in
            _ = LoveReveal.reveal(day: day, pack: pack, state: &state, now: now, otherReminderMinutes: clashMinutes, openedFromNotification: true)
            // "Ranní ninja": opened within a quarter of an hour of arriving.
            if let due = LoveReveal.dueDate(day: day, pack: pack, otherReminderMinutes: clashMinutes),
               now >= due, now.timeIntervalSince(due) <= 15 * 60 {
                state.mark(PartnerAchievements.Mark.quickOpen(day), at: now)
            }
        }
        pendingMessageDay = day
    }

    /// What the love card shows today.
    func todayState(clashMinutes: [Int], now: Date = Date()) -> LoveReveal.DayState {
        guard let pack, let state else { return .none }
        return LoveReveal.state(day: LoveDay.key(of: now), pack: pack, state: state, now: now, otherReminderMinutes: clashMinutes)
    }

    func setFavorite(_ messageId: String, _ isFavorite: Bool) async {
        await mutate { _, state in state.setFavorite(messageId, isFavorite) }
    }

    // MARK: Achievements and hearts (D9)

    /// Pays the hearts of every partner achievement that now holds and
    /// returns the newly unlocked ones (nothing while the theme is off).
    func evaluateAchievements(signals: SignalsSnapshot?, streakLength: Int, activeDays: Int = 0, now: Date = Date()) async -> [PartnerAchievementDefinition] {
        guard isActive, let importDay = state?.importDay else { return [] }
        let facts = signals.map {
            PartnerAchievementFacts.from(snapshot: $0, importDay: importDay, streakLength: streakLength, activeGoalMetDays: activeDays)
        } ?? PartnerAchievementFacts(activeGoalMetDays: activeDays)
        var unlocked: [PartnerAchievementDefinition] = []
        do {
            unlocked = try await store.update { pack, state in
                PartnerAchievements.award(pack: pack, facts: facts, state: &state, now: now)
            } ?? []
        } catch {
            DiagnosticsLog.log(.error, category: "LovePack", "couldn't save partner achievements: \(error)")
        }
        state = await store.state()
        return unlocked
    }

    /// A small fact for a partner achievement (PartnerAchievements.Mark).
    func mark(_ key: String, now: Date = Date()) async {
        guard isActive else { return }
        await mutate { _, state in state.mark(key, at: now) }
    }

    func redeem(couponId: String, now: Date = Date()) async -> LoveCouponRedemption? {
        guard let coupon = pack?.coupons.first(where: { $0.id == couponId }) else { return nil }
        var result: LoveCouponRedemption?
        do {
            result = try await store.update { _, state in state.redeem(coupon, at: now) }
        } catch {
            DiagnosticsLog.log(.error, category: "LovePack", "couldn't save a coupon redemption: \(error)")
        }
        state = await store.state()
        return result
    }

    /// Opens an "Otevři, až…" scroll for good (the first opening is kept).
    func openScroll(_ id: String, now: Date = Date()) async {
        await mutate { _, state in
            if state.openedScrolls[id] == nil { state.openedScrolls[id] = now }
        }
    }

    /// The love notifications to keep pending (empty while the theme is
    /// off); records the planned days' messages.
    func plannedNotifications(clashMinutes: [Int], now: Date = Date()) async -> [PlannedLoveNotification] {
        guard isActive, let pack, let content else { return [] }
        let title = PartnerThemeContent.fill(content.loveNotificationTitle.text, ["nickname": pack.nickname])
        let available = await store.availablePictureIds()
        var planned: [PlannedLoveNotification] = []
        do {
            planned = try await store.update { pack, state in
                LoveNotificationPlanning.plan(
                    pack: pack, state: &state, now: now, clashMinutes: clashMinutes,
                    title: title, availablePictures: available
                )
            } ?? []
        } catch {
            DiagnosticsLog.log(.error, category: "LovePack", "couldn't save the planned love messages: \(error)")
        }
        state = await store.state()
        return planned
    }

    /// spec partner-theme "level titles become ninja ranks": the tier's
    /// rank name while the theme is on, its own title otherwise. Display
    /// only -- no tier's level range changes.
    func levelTitle(_ tier: LevelTier) -> String {
        guard isActive, let content,
              let index = LevelTiers.all.firstIndex(of: tier),
              let rank = content.rank(forTier: index + 1) else { return tier.title }
        return rank.name
    }

    /// A heart burst to play (HeartBurstOverlay); a new id per log.
    private(set) var heartBurst: UUID?

    /// A log was confirmed: with the theme on, the burst and the heartbeat.
    func celebrateLog() {
        guard isActive else { return }
        heartBurst = UUID()
    }

    /// The theme's reminder wording, or `nil` while the theme is off.
    var notificationTexts: ThemedNotificationTexts? {
        guard isActive, let pack, let content else { return nil }
        return content.notificationTexts(seed: pack.seed, nickname: pack.nickname, signature: pack.signature)
    }

    func pictureURL(id: String) async -> URL? {
        await store.pictureURL(id: id)
    }

    private func mutate(_ change: (LovePack, inout LoveState) -> Void) async {
        do {
            try await store.update { pack, state in change(pack, &state) }
        } catch {
            DiagnosticsLog.log(.error, category: "LovePack", "couldn't save the love state: \(error)")
        }
        state = await store.state()
    }
}

/// The partner theme's Czech table, read once from the app bundle.
enum PartnerText {
    static let content: PartnerThemeContent? = {
        guard let url = Bundle.main.url(forResource: "partner-theme.cs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            DiagnosticsLog.log(.error, category: "LovePack", "partner-theme.cs.json is missing from the app bundle")
            return nil
        }
        do {
            return try PartnerThemeContent.decode(data)
        } catch {
            DiagnosticsLog.log(.error, category: "LovePack", "partner-theme.cs.json does not decode: \(error)")
            return nil
        }
    }()
}
