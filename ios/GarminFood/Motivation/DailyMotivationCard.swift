// DailyMotivationCard.swift
//
// add-daily-motivation: the photo and the line of the day at the top of
// Today. The photo is shown WHOLE, never cropped (the partner theme's card
// used to cut a tall photo to a 180-pt strip). Which line and which photo is DailyMotivation's call
// (FoodLogCore, unit-tested); this view only draws it.
//
// The photo sits in WholePhotoFrame: one fixed height, the whole photo fitted
// inside it, whatever its shape.
//
// The photos are the owner's files in Documents/Motivation (the Files app
// shows the folder), added here with the system photo picker, which needs no
// permission. Nothing is bundled (the repository is public) or uploaded.
//
// Pinned above Today's layout cards like the love card (not a layout card
// id); hidden by the Settings switch "Daily photo and quote"
// (`dailyMotivationEnabled`, default on).
//
// Depends on FoodLogCore.DailyMotivation. Depended on by: TodayView.

import SwiftUI
import PhotosUI
import ImageIO
import UIKit
import FoodLogCore

struct DailyMotivationCard: View {
    static let enabledKey = "dailyMotivationEnabled"

    @AppStorage(DailyMotivationCard.enabledKey) private var enabled = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var today = Date()
    @State private var reload = 0
    @State private var picture: UIImage?
    @State private var picked: [PhotosPickerItem] = []

    private let book = MotivationQuoteBook.bundled()

    var body: some View {
        if enabled {
            let slot = DailyMotivation.slot(for: today)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let picture {
                    WholePhotoFrame(image: picture)
                        .accessibilityHidden(true)
                }
                if let line = book.line(slot: slot, languageCode: Bundle.main.preferredLocalizations.first) {
                    Text(verbatim: line)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PhotosPicker(selection: $picked, maxSelectionCount: 20, matching: .images) {
                    Label("Add photos", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Theme.accent)
            }
            .card()
            .task(id: "\(Int(Calendar.current.startOfDay(for: today).timeIntervalSince1970))-\(reload)") {
                picture = await Self.loadPicture(slot: slot)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Date() }
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await Self.importPhotos(items)
                    picked = []
                    reload += 1
                }
            }
        }
    }

    /// `Documents/Motivation`, created on demand.
    private static func folder() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Motivation", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func loadPicture(slot: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let urls = MotivationPhotoFolder.photoURLs(in: folder())
            guard let first = DailyMotivation.photoIndex(slot: slot, count: urls.count) else { return nil }
            // A file that does not decode is skipped for the next one.
            for offset in 0..<urls.count {
                if let image = thumbnail(urls[(first + offset) % urls.count], maxPixels: 1600) { return image }
            }
            return nil
        }.value
    }

    /// Copies each pick into the folder (a UUID name; ImageIO reads by
    /// content, so the extension is only for the folder listing).
    private static func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let url = folder().appendingPathComponent("\(UUID().uuidString).jpg")
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Decoded at no more than `maxPixels` on the long side: a 4000-px photo
    /// shown on a phone needs nowhere near its full size.
    private static func thumbnail(_ url: URL, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
