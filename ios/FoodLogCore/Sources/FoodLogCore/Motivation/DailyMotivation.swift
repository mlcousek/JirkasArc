// DailyMotivation.swift
//
// add-daily-motivation: the rules of Today's "photo and line of the day",
// kept here (no SwiftUI) because nothing in the app target can be unit
// tested. Which of the 365 bundled lines and which of the owner's photos a
// day shows is a function of the local calendar day alone: no random state
// and no store, so the card is the same on every launch of the day and
// different tomorrow.
//
// The photos are the owner's files on the phone (Documents/Motivation), never
// in the repository (public) or a backup; `MotivationPhotoFolder` only lists
// them. The lines are original text, deliberately unattributed.
//
// Depended on by: GarminFood/Motivation/DailyMotivationCard.swift.

import Foundation

public enum DailyMotivation {
    /// How many lines the book holds, one per day of a (non-leap) year.
    public static let lineCount = 365

    /// 0...364: the day of the year, capped so Dec 31 of a leap year reuses
    /// the last line instead of running off the book.
    public static func slot(for date: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return min(max(day, 1), lineCount) - 1
    }

    /// The photo for a slot among `count` photos, or nil with none.
    public static func photoIndex(slot: Int, count: Int) -> Int? {
        guard count > 0, slot >= 0 else { return nil }
        return slot % count
    }
}

/// The bundled lines, one `{ "en", "cs" }` pair each.
public struct MotivationQuoteBook: Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let en: String
        public let cs: String

        public init(en: String, cs: String) {
            self.en = en
            self.cs = cs
        }
    }

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The book in this package's resources; empty (never a crash) when the
    /// file is missing or unreadable.
    public static func bundled() -> MotivationQuoteBook {
        guard let url = Bundle.module.url(forResource: "motivation-quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return MotivationQuoteBook(entries: [])
        }
        return MotivationQuoteBook(entries: entries)
    }

    /// The line for `slot` in the app's language (`cs` is Czech, anything
    /// else English); nil when the book is empty.
    public func line(slot: Int, languageCode: String?) -> String? {
        guard !entries.isEmpty, slot >= 0 else { return nil }
        let entry = entries[slot % entries.count]
        return languageCode == "cs" ? entry.cs : entry.en
    }
}

/// The owner's photos in a folder.
public enum MotivationPhotoFolder {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp"]

    /// Image files directly in `directory`, sorted by name so the day's pick
    /// is stable; empty when the folder is missing.
    public static func photoURLs(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
