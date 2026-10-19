// LovePackImportSheet.swift
//
// add-partner-love-theme D1, spec love-pack: what opening an `.arclove`
// file leads to -- from AirDrop or Files (ContentView, via
// AppRouter.pendingLovePackImport) or Settings > Appearance > Import love
// pack. It reads and validates the file and shows what would change before
// anything is stored; another pack than the current one asks first
// ("Replace the current love pack?"). A file that isn't a valid pack only
// says so and changes nothing.
//
// Shown on any phone, so its words are en + cs (Localizable.xcstrings). The
// problem's technical detail (a field or an id) is for the owner who built
// the pack and stays verbatim.
//
// Depends on PartnerThemeModel (preview, apply).

import SwiftUI
import FoodLogCore

@MainActor
struct LovePackImportSheet: View {
    let url: URL
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var result: Result<LovePackImportPreview, LovePackImportFailure>?
    @State private var isApplying = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Group {
                switch result {
                case nil:
                    ProgressView()
                case .success(let preview):
                    summary(preview)
                case .failure(let failure):
                    ContentUnavailableView {
                        Label("Couldn't read the love pack", systemImage: "heart.slash")
                    } description: {
                        Text(Self.message(for: failure))
                    }
                }
            }
            .navigationTitle("Love pack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            result = await environment.partner.preview(fileAt: url)
        }
    }

    private func summary(_ preview: LovePackImportPreview) -> some View {
        let diff = preview.diff
        return Form {
            Section {
                Label {
                    Text(verbatim: preview.loaded.pack.nickname)
                } icon: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.accent)
                }
                LabeledContent("Messages", value: "\(diff.totalDaily)")
                LabeledContent("Pictures", value: "\(diff.totalPictures)")
            }
            if diff.kind == .update {
                Section {
                    LabeledContent("Added messages", value: "\(diff.daily.added)")
                    if diff.daily.removed > 0 {
                        LabeledContent("Removed messages", value: "\(diff.daily.removed)")
                    }
                    LabeledContent("Added pictures", value: "\(diff.pictures.added)")
                    if diff.pictures.removed > 0 {
                        LabeledContent("Removed pictures", value: "\(diff.pictures.removed)")
                    }
                } footer: {
                    Text("Every message already revealed stays as it is.")
                }
            }
            if diff.kind == .otherPack {
                Section {
                    Label("Replace the current love pack?", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                } footer: {
                    Text("This is a different pack. Its history starts today; the current pack's history stays on this phone.")
                }
            }
            if saveFailed {
                Section {
                    Label("Couldn't save the love pack. Try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.danger)
                }
            }
            Section {
                Button {
                    apply(preview)
                } label: {
                    if diff.kind == .otherPack {
                        Text("Replace")
                    } else {
                        Text("Import")
                    }
                }
                .disabled(isApplying)
            }
        }
    }

    private func apply(_ preview: LovePackImportPreview) {
        isApplying = true
        saveFailed = false
        Task {
            do {
                try await environment.partner.apply(preview)
                Haptics.success()
                await environment.syncNotifications()
                dismiss()
            } catch {
                saveFailed = true
                isApplying = false
            }
        }
    }

    static func message(for failure: LovePackImportFailure) -> String {
        switch failure {
        case .unreadable:
            return String(localized: "The file couldn't be opened. Nothing was changed.")
        case .invalid(let problem):
            switch problem {
            case .notJSON, .wrongFormat, .malformed:
                return String(localized: "This isn't a love pack. Nothing was changed.")
            case .unsupportedVersion:
                return String(localized: "This love pack comes from a newer version of Jirka's Arc. Update the app first. Nothing was changed.")
            case .tooLarge:
                return String(localized: "The love pack is too large. Nothing was changed.")
            default:
                return String(localized: "The love pack has a problem (\(problem.detail)). Nothing was changed.")
            }
        }
    }
}

extension LovePackProblem {
    /// The technical detail for the owner who built the pack: which field,
    /// list or id. Verbatim -- ids are not words.
    var detail: String {
        switch self {
        case .tooLarge(let bytes): return "\(bytes) B"
        case .notJSON: return "JSON"
        case .malformed(let field): return field
        case .wrongFormat: return "format"
        case .unsupportedVersion(let version): return "version \(version)"
        case .missingField(let field): return field
        case .emptyDaily: return "daily"
        case .invalidDate(let field): return field
        case .invalidId(let list, let id): return "\(list): \(id)"
        case .duplicateId(let list, let id): return "\(list): \(id) ×2"
        case .textTooLong(let list, let id): return id.isEmpty ? list : "\(list): \(id)"
        case .tooManyItems(let list): return list
        case .invalidPrice(let id): return "coupons: \(id)"
        case .tooManyPictures(let count): return "images: \(count)"
        case .pictureNotDecodable(let id), .pictureWrongType(let id), .pictureTooLarge(let id), .pictureTooBig(let id):
            return "images: \(id)"
        case .unknownSlot(let id, let slot): return "images: \(id) \(slot)"
        }
    }
}
