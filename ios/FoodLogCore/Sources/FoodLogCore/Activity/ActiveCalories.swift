// ActiveCalories.swift
//
// add-health-active-calories D2: a standalone install's active calories,
// one record per day. Garmin-connected installs read active kcal from
// Garmin (DayLogLoader); a standalone one has no Garmin, so this is its
// source -- the Apple Watch's day total from Apple Health, handed over by a
// Shortcuts automation (the free tier has no HealthKit), and activities
// typed in by hand.
//
// One rule for the day's total: a Health report wins (the newest one --
// Health's day total only grows, so a later read is the truth); without one,
// the sum of the manual activities. Manual entries stay listed either way,
// so a workout the watch also saw is never counted twice.
//
// A report for a day more than 7 days ago or in the future, a negative one,
// or one above 10 000 kcal changes nothing. Days older than 400 are dropped.
//
// Actor-isolated, JSON-file-backed (`active-calories.json`), loaded through
// `FoodLogCoreStorage.loadPersistedJSON` like every store here; in backups.
// One instance, held by AppServices. Tests: ActiveCaloriesTests,
// StoreFixtureTests.

import Foundation

public enum ManualActivityType: String, Codable, Sendable, CaseIterable, Identifiable {
    case running
    case walking
    case cycling
    case swimming
    case gym
    case yoga
    case other

    public var id: String { rawValue }
}

public struct ManualActivity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var type: ManualActivityType
    public var minutes: Int?
    public var kcal: Double
    public let createdAt: Date

    public init(id: String = UUID().uuidString, type: ManualActivityType, minutes: Int?, kcal: Double, createdAt: Date) {
        self.id = id
        self.type = type
        self.minutes = minutes
        self.kcal = kcal
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, type, minutes, kcal, createdAt }

    /// An activity type a later build added reads as `.other`, not as an
    /// undecodable file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = ManualActivityType(rawValue: (try? container.decode(String.self, forKey: .type)) ?? "") ?? .other
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        kcal = try container.decode(Double.self, forKey: .kcal)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

public struct HealthActiveReport: Codable, Sendable, Equatable {
    public let kcal: Double
    public let reportedAt: Date

    public init(kcal: Double, reportedAt: Date) {
        self.kcal = kcal
        self.reportedAt = reportedAt
    }
}

public struct ActiveCaloriesDay: Codable, Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case health
        case manual
    }

    public let day: String
    public var health: HealthActiveReport?
    public var manual: [ManualActivity]

    public init(day: String, health: HealthActiveReport? = nil, manual: [ManualActivity] = []) {
        self.day = day
        self.health = health
        self.manual = manual
    }

    /// The day's active kcal: the Health report when there is one,
    /// otherwise the manual sum; `nil` with neither.
    public var total: Double? {
        if let health { return health.kcal }
        guard !manual.isEmpty else { return nil }
        return manual.reduce(0) { $0 + $1.kcal }
    }

    public var source: Source? {
        if health != nil { return .health }
        return manual.isEmpty ? nil : .manual
    }
}

public enum ActiveCaloriesRules {
    public static let maxReportKcal: Double = 10_000
    public static let maxManualKcal: Double = 3_000
    public static let maxManualMinutes = 24 * 60
    /// A report this many days old is the oldest still accepted.
    public static let maxReportAgeDays = 7
    public static let keptDays = 400

    public enum Refusal: Error, Sendable, Equatable {
        case notANumber
        case outOfRange
        case future
        case tooOld
    }

    /// Why a report of `kcal` for `day` cannot be recorded on `today`.
    public static func check(kcal: Double, day: String, today: String) -> Refusal? {
        guard kcal.isFinite, kcal >= 0, kcal <= maxReportKcal else { return .outOfRange }
        guard let age = LoveDay.days(from: day, to: today) else { return .notANumber }
        if age < 0 { return .future }
        if age > maxReportAgeDays { return .tooOld }
        return nil
    }

    public static func checkManual(kcal: Double, minutes: Int?) -> Refusal? {
        guard kcal.isFinite, kcal >= 1, kcal <= maxManualKcal else { return .outOfRange }
        if let minutes, minutes < 0 || minutes > maxManualMinutes { return .outOfRange }
        return nil
    }
}

/// add-health-active-calories D3: the number a Shortcut hands over, as
/// text: "412,5", "412.5", "412,5 kcal", " 412 ". Czech Shortcuts format
/// numbers with a decimal comma, so both separators are accepted; anything
/// else is refused rather than guessed.
public enum ActiveCaloriesIntake {
    public static func parseKcal(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for unit in ["kcal", "cal"] where cleaned.hasSuffix(unit) {
            cleaned = String(cleaned.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
        }
        // Thousands separators Shortcuts may insert: a space or a no-break space.
        cleaned = cleaned.replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty,
              cleaned.filter({ $0 == "." }).count <= 1,
              cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}

public actor ActiveCaloriesStore {
    public static let fileName = "active-calories.json"

    private let fileURL: URL
    private var daysByKey: [String: ActiveCaloriesDay] = [:]
    private var loaded = false

    public init(fileURL: URL = ActiveCaloriesStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("active-calories.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([ActiveCaloriesDay].self, from: fileURL, decoder: decoder, category: "ActiveCaloriesStore")
        loaded = !result.isUnreadable
        daysByKey = Dictionary((result.value ?? []).map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist(today: String) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "ActiveCaloriesStore")
        if let oldest = LoveDay.adding(-(ActiveCaloriesRules.keptDays - 1), to: today) {
            daysByKey = daysByKey.filter { $0.key >= oldest }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(daysByKey.values.sorted { $0.day < $1.day })
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Reading

    public func day(_ day: String) -> ActiveCaloriesDay {
        loadIfNeeded()
        return daysByKey[day] ?? ActiveCaloriesDay(day: day)
    }

    public func total(day: String) -> Double? {
        loadIfNeeded()
        return daysByKey[day]?.total
    }

    /// When the Health bridge last reported, for Settings and the notice.
    public func lastHealthReportAt() -> Date? {
        loadIfNeeded()
        return daysByKey.values.compactMap { $0.health?.reportedAt }.max()
    }

    /// Days on or after `from` whose total is at least `kcal`.
    public func daysWithTotal(atLeast kcal: Double, from: String) -> Int {
        loadIfNeeded()
        return daysByKey.values.filter { $0.day >= from && ($0.total ?? 0) >= kcal }.count
    }

    // MARK: Writing

    /// Records the Health bridge's day total (the newest report replaces
    /// the older one). Throws a `Refusal` and changes nothing when refused.
    public func recordHealth(kcal: Double, day: String, now: Date = Date(), calendar: Calendar = .current) throws {
        loadIfNeeded()
        let today = LoveDay.key(of: now, calendar: calendar)
        if let refusal = ActiveCaloriesRules.check(kcal: kcal, day: day, today: today) { throw refusal }
        var record = daysByKey[day] ?? ActiveCaloriesDay(day: day)
        record.health = HealthActiveReport(kcal: kcal, reportedAt: now)
        daysByKey[day] = record
        try persist(today: today)
    }

    @discardableResult
    public func addManual(type: ManualActivityType, minutes: Int?, kcal: Double, day: String, now: Date = Date(), calendar: Calendar = .current) throws -> ManualActivity {
        loadIfNeeded()
        if let refusal = ActiveCaloriesRules.checkManual(kcal: kcal, minutes: minutes) { throw refusal }
        let activity = ManualActivity(type: type, minutes: minutes, kcal: kcal, createdAt: now)
        var record = daysByKey[day] ?? ActiveCaloriesDay(day: day)
        record.manual.append(activity)
        daysByKey[day] = record
        try persist(today: LoveDay.key(of: now, calendar: calendar))
        return activity
    }

    public func updateManual(_ activity: ManualActivity, day: String, now: Date = Date(), calendar: Calendar = .current) throws {
        loadIfNeeded()
        if let refusal = ActiveCaloriesRules.checkManual(kcal: activity.kcal, minutes: activity.minutes) { throw refusal }
        guard var record = daysByKey[day], let index = record.manual.firstIndex(where: { $0.id == activity.id }) else { return }
        record.manual[index] = activity
        daysByKey[day] = record
        try persist(today: LoveDay.key(of: now, calendar: calendar))
    }

    public func deleteManual(id: String, day: String, now: Date = Date(), calendar: Calendar = .current) throws {
        loadIfNeeded()
        guard var record = daysByKey[day], record.manual.contains(where: { $0.id == id }) else { return }
        record.manual.removeAll { $0.id == id }
        if record.manual.isEmpty, record.health == nil {
            daysByKey.removeValue(forKey: day)
        } else {
            daysByKey[day] = record
        }
        try persist(today: LoveDay.key(of: now, calendar: calendar))
    }
}
