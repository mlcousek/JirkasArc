// MessageBoxView.swift
//
// add-partner-love-theme D6, spec love-messages "The message box keeps
// every revealed message": "Krabička vzkazů" -- every message revealed so
// far, newest day first, with its date and a heart to keep it among the
// favourites, and a filter to the favourites. A future day is never listed
// (only revealed messages are in the state). Opening a love notification
// lands here, scrolled to its day (PartnerThemeModel.pendingMessageDay).
//
// Text from the theme's Czech table, dates in Czech whatever the app
// language (the theme is Czech only). Depends on PartnerThemeModel.

import SwiftUI
import FoodLogCore

@MainActor
struct MessageBoxView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var favoritesOnly = false

    private var partner: PartnerThemeModel { environment.partner }

    var body: some View {
        let content = partner.content
        let messages = (partner.state?.messageBox ?? []).filter { !favoritesOnly || partner.state?.isFavorite($0.messageId) == true }

        ScrollViewReader { proxy in
            List {
                if let content {
                    Section {
                        Picker(selection: $favoritesOnly) {
                            Text(verbatim: content.text(PartnerThemeContent.TextKey.allMessages)).tag(false)
                            Text(verbatim: content.text(PartnerThemeContent.TextKey.favorites)).tag(true)
                        } label: {
                            Text(verbatim: content.text(PartnerThemeContent.TextKey.favorites))
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }
                if messages.isEmpty, let content {
                    Section {
                        Label {
                            Text(verbatim: content.text(PartnerThemeContent.TextKey.messageBoxEmpty))
                        } icon: {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                ForEach(messages, id: \.day) { message in
                    Section {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(verbatim: Self.dateText(message.day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                Text(verbatim: message.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            FavoriteHeartButton(messageId: message.messageId)
                        }
                    }
                    .id(message.day)
                }
            }
            .navigationTitle(Text(verbatim: content?.text(PartnerThemeContent.TextKey.messageBoxTitle) ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.groupedBackground)
            .onAppear {
                scrollToPending(proxy)
                // The secret "Noční hlídka": the box opened after 23:00.
                if Calendar.current.component(.hour, from: Date()) >= 23 {
                    Task {
                        await partner.mark(PartnerAchievements.Mark.nightBox)
                        await environment.evaluatePartnerAchievements()
                    }
                }
            }
            .onChange(of: partner.pendingMessageDay) { _, _ in scrollToPending(proxy) }
        }
    }

    private func scrollToPending(_ proxy: ScrollViewProxy) {
        guard let day = partner.pendingMessageDay else { return }
        favoritesOnly = false
        withAnimation { proxy.scrollTo(day, anchor: .top) }
        partner.pendingMessageDay = nil
    }

    /// "14. března 2030", in Czech.
    static func dateText(_ day: String) -> String {
        guard let date = LoveDay.date(day: day, minute: 12 * 60) else { return day }
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "cs_CZ")))
    }
}
