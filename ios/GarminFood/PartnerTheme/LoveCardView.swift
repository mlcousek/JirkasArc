// LoveCardView.swift
//
// add-partner-love-theme D10: the top of Today while the partner theme is
// on -- her greeting by time of day, and the love card: today's message
// once its minute has come (never before: spec love-messages), or "it
// arrives this morning"; the picture of the day; the pack's countdown; and
// the way into the message box. The card waits for the minute itself while
// Today stays open and then reveals the message.
//
// Pinned above Today's layout cards for now (not a layout card id: a new id
// would show up in everyone's layout editor); task 7.2 records it.
//
// All text comes from the theme's Czech table (PartnerText), shown
// verbatim. Depends on PartnerThemeModel and AppEnvironment.loveClashMinutes.

import SwiftUI
import UIKit
import FoodLogCore

@MainActor
struct LoveCardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var picture: UIImage?
    @State private var opensBox = false

    private var partner: PartnerThemeModel { environment.partner }

    var body: some View {
        if partner.isActive, let pack = partner.pack, let content = partner.content {
            TimelineView(.everyMinute) { context in
                card(pack: pack, content: content, now: context.date)
            }
            .navigationDestination(isPresented: $opensBox) {
                MessageBoxView()
            }
            .onChange(of: partner.pendingMessageDay) { _, day in
                if day != nil { opensBox = true }
            }
        }
    }

    private func card(pack: LovePack, content: PartnerThemeContent, now: Date) -> some View {
        let today = LoveDay.key(of: now)
        let dayState = partner.todayState(clashMinutes: environment.loveClashMinutes, now: now)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(verbatim: greeting(content: content, nickname: pack.nickname, now: now))
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .accessibilityLabel(Text(verbatim: "Obrázek dne"))
                }

                message(dayState, pack: pack, content: content)

                if let countdown = countdownText(pack: pack, content: content, today: today) {
                    Label {
                        Text(verbatim: countdown)
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Theme.accentSecondary)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if partner.isMissingPictures {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.picturesMissing))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    opensBox = true
                } label: {
                    Label {
                        Text(verbatim: content.text(PartnerThemeContent.TextKey.openMessageBox))
                    } icon: {
                        Image(systemName: "envelope.open.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(Theme.accent)
            }
            .card()
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Theme.headerGradientStart, Theme.headerGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .accessibilityHidden(true)
            }
        }
        .task(id: today) {
            await loadPicture(pack: pack, day: today)
            await revealWhenDue(dayState)
        }
    }

    @ViewBuilder
    private func message(_ dayState: LoveReveal.DayState, pack: LovePack, content: PartnerThemeContent) -> some View {
        switch dayState {
        case .revealed(let revealed):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if revealed.isRepeat {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.allMessagesKnown))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text(verbatim: revealed.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FavoriteHeartButton(messageId: revealed.messageId)
                }
                if !pack.signature.isEmpty {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.signedBy, ["signature": pack.signature]))
                        .font(.subheadline.italic())
                        .foregroundStyle(Theme.accent)
                }
            }
            .accessibilityElement(children: .combine)
        case .arrives:
            Label {
                Text(verbatim: content.text(PartnerThemeContent.TextKey.messageArrives))
            } icon: {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(Theme.accent)
            }
            .font(.body)
        case .none:
            EmptyView()
        }
    }

    private func greeting(content: PartnerThemeContent, nickname: String, now: Date) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let key: String
        switch hour {
        case ..<11: key = PartnerThemeContent.TextKey.greetingMorning
        case ..<18: key = PartnerThemeContent.TextKey.greetingAfternoon
        default: key = PartnerThemeContent.TextKey.greetingEvening
        }
        return content.text(key, ["nickname": nickname])
    }

    private func countdownText(pack: LovePack, content: PartnerThemeContent, today: String) -> String? {
        guard let countdown = pack.countdown, let days = LoveDay.days(from: today, to: countdown.date), days >= 0 else { return nil }
        if days == 0 {
            return content.text(PartnerThemeContent.TextKey.countdownToday, ["title": countdown.title])
        }
        return content.text(PartnerThemeContent.TextKey.countdownDays, [
            "title": countdown.title,
            "count": content.counted(days, PartnerThemeContent.PluralKey.days)
        ])
    }

    private func loadPicture(pack: LovePack, day: String) async {
        let available = Set(pack.images.map(\.id))
        guard let id = PictureRotation.pictureId(slot: LovePictureSlot.pictureOfDay, day: day, pack: pack, available: available)
                ?? PictureRotation.pictureId(slot: LovePictureSlot.loveCard, day: day, pack: pack, available: available),
              let url = await partner.pictureURL(id: id) else {
            picture = nil
            return
        }
        picture = UIImage(contentsOfFile: url.path)
    }

    /// Today stays open past the minute: reveal then, without a refresh.
    private func revealWhenDue(_ dayState: LoveReveal.DayState) async {
        guard case .arrives(let at) = dayState else { return }
        let wait = at.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled else { return }
        await partner.revealDue(clashMinutes: environment.loveClashMinutes)
    }
}

/// The heart that keeps a message among the favourites.
@MainActor
struct FavoriteHeartButton: View {
    let messageId: String
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let isFavorite = environment.partner.state?.isFavorite(messageId) ?? false
        Button {
            Haptics.success()
            Task { await environment.partner.setFavorite(messageId, !isFavorite) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: isFavorite ? "Odebrat z oblíbených" : "Přidat do oblíbených"))
    }
}
