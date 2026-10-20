// PartnerAchievementsView.swift
//
// add-partner-love-theme D9, spec partner-achievements: "Svitky srdce" --
// the heart balance, every partner achievement this pack offers (an
// unlocked one with its date, a locked one with what it asks, a secret one
// sealed until it unlocks), and, when the pack has them, the love coupons:
// redeemed with hearts, then kept as a stamped, dated scroll to show in
// person. Reached from the love card; Czech only, from the theme's table.
//
// Depends on PartnerThemeModel (state, redeem) and FoodLogCore
// PartnerAchievements.

import SwiftUI
import FoodLogCore

@MainActor
struct PartnerAchievementsView: View {
    @Environment(AppEnvironment.self) private var environment
    /// The coupon waiting for "really redeem?" and the ticket on screen.
    @State private var confirming: LovePackCoupon?
    @State private var ticket: LoveTicketRequest?
    private var partner: PartnerThemeModel { environment.partner }

    var body: some View {
        let content = partner.content
        let state = partner.state
        List {
            if let content, let state {
                Section {
                    Label {
                        Text(verbatim: content.text(PartnerThemeContent.TextKey.heartBalance, [
                            "count": content.counted(state.heartBalance, PartnerThemeContent.PluralKey.hearts)
                        ]))
                        .font(.title3.weight(.bold))
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }

                if let pack = partner.pack {
                    Section {
                        ForEach(PartnerAchievements.available(for: pack)) { definition in
                            achievementRow(definition, content: content, state: state)
                        }
                    } header: {
                        Text(verbatim: content.text(PartnerThemeContent.TextKey.achievementsTitle))
                    }

                    if !pack.coupons.isEmpty {
                        Section {
                            ForEach(pack.coupons) { coupon in
                                couponRow(coupon, content: content, state: state)
                            }
                        } header: {
                            Text(verbatim: content.text(PartnerThemeContent.TextKey.couponsTitle))
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: content?.text(PartnerThemeContent.TextKey.achievementsTitle) ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.groupedBackground)
        .sheet(item: $ticket) { request in
            LoveTicketView(request: request)
        }
        .confirmationDialog(
            Text(verbatim: confirming.flatMap { coupon in
                content?.text(PartnerThemeContent.TextKey.couponConfirm, [
                    "title": coupon.title,
                    "count": content?.counted(coupon.price, PartnerThemeContent.PluralKey.hearts) ?? ""
                ])
            } ?? ""),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let coupon = confirming, let content {
                Button {
                    redeem(coupon)
                } label: {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.couponRedeem))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Spends the hearts, then shows the coupon's ticket.
    private func redeem(_ coupon: LovePackCoupon) {
        Task {
            guard case .redeemed = await partner.redeem(couponId: coupon.id) else { return }
            Haptics.heartbeat()
            let at = partner.state?.redeemedCoupons.first { $0.couponId == coupon.id }?.at ?? Date()
            ticket = LoveTicketRequest(coupon: coupon, redeemedAt: at)
            await environment.evaluatePartnerAchievements()
        }
    }

    private func achievementRow(_ definition: PartnerAchievementDefinition, content: PartnerThemeContent, state: LoveState) -> some View {
        let unlockedAt = state.hearts.first { $0.id == "achievement:" + definition.id }?.at
        let words = content.achievements[definition.id]
        let sealed = definition.isSecret && unlockedAt == nil
        return HStack(spacing: Theme.Spacing.md) {
            Image(systemName: sealed ? "lock.fill" : definition.symbol)
                .font(.title2)
                .foregroundStyle(unlockedAt == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sealed ? content.text(PartnerThemeContent.TextKey.achievementSecret) : (words?.title ?? definition.id))
                    .font(.headline)
                if !sealed, let description = words?.description {
                    Text(verbatim: description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: "+\(definition.hearts) ❤️")
                .font(.caption.weight(.semibold))
                .foregroundStyle(unlockedAt == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accentSecondary))
        }
        .opacity(unlockedAt == nil ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func couponRow(_ coupon: LovePackCoupon, content: PartnerThemeContent, state: LoveState) -> some View {
        let redeemedAt = state.redeemedCoupons.first { $0.couponId == coupon.id }?.at
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label {
                    Text(verbatim: coupon.title)
                        .font(.headline)
                } icon: {
                    Image(systemName: redeemedAt == nil ? "ticket" : "ticket.fill")
                        .foregroundStyle(Theme.accentSecondary)
                }
                Spacer()
                Text(verbatim: content.counted(coupon.price, PartnerThemeContent.PluralKey.hearts))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let redeemedAt {
                Text(verbatim: content.text(PartnerThemeContent.TextKey.couponRedeemed, ["date": Self.dateText(redeemedAt)]))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(Theme.Spacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    )
                    .rotationEffect(.degrees(-3))
                Button {
                    ticket = LoveTicketRequest(coupon: coupon, redeemedAt: redeemedAt)
                } label: {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.ticketShow))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            } else if state.heartBalance >= coupon.price {
                Button {
                    confirming = coupon
                } label: {
                    Text(verbatim: content.text(PartnerThemeContent.TextKey.couponRedeem))
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else {
                Text(verbatim: content.text(PartnerThemeContent.TextKey.couponMissing, [
                    "count": content.counted(coupon.price - state.heartBalance, PartnerThemeContent.PluralKey.hearts)
                ]))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "cs_CZ")))
    }
}
