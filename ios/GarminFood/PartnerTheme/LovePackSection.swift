// LovePackSection.swift
//
// add-partner-love-theme D1/D2: Settings > Appearance > Love pack -- import
// a pack from Files (the AirDrop path opens the same sheet by itself), and,
// once one is stored, remove it after a confirmation. Removing returns the
// app to GF Teal and keeps what was already revealed for the pack's return
// (LoveStore). Shown on every phone, in en + cs.
//
// Depends on PartnerThemeModel; uses LovePackImportSheet.

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The love pack file (`.arclove`), exported in Info.plist (project.yml).
    static let lovePack = UTType(exportedAs: "com.mlcousek.garminfood.arclove")
}

@MainActor
struct LovePackSection: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isPicking = false
    @State private var picked: LovePackImportRequest?
    @State private var confirmsRemove = false
    @State private var removeFailed = false

    private var partner: PartnerThemeModel { environment.partner }

    var body: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                Label("Import love pack…", systemImage: "heart.text.square")
            }
            if partner.isPackInstalled {
                Button("Remove love pack", role: .destructive) {
                    confirmsRemove = true
                }
            }
            if partner.isMissingPictures {
                Label("Pictures are missing. Import the love pack again.", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(Theme.warning)
            }
            if removeFailed {
                Label("Couldn't remove the love pack. Try again.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Love pack")
        } footer: {
            Text("A love pack unlocks a theme made for one person. Open it from Files or AirDrop.")
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.lovePack, .json]) { result in
            if case .success(let url) = result {
                picked = LovePackImportRequest(url: url)
            }
        }
        .sheet(item: $picked) { request in
            LovePackImportSheet(url: request.url)
        }
        .confirmationDialog("Remove the love pack?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    do {
                        try await partner.removePack()
                        removeFailed = false
                        await environment.syncNotifications()
                    } catch {
                        removeFailed = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its messages and pictures leave this phone. What was already revealed is kept and comes back when the same pack is imported again.")
        }
    }
}
