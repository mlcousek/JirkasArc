// LoveTicketView.swift
//
// add-partner-love-theme: the ticket a redeemed love coupon becomes -- the
// coupon, when it was redeemed, a QR code and the line under it
// (FoodLogCore LoveTicket: signed with the pack's seed, so it cannot be
// made up or edited; the owner checks it with
// tools/love-pack/verify-ticket.mjs). The QR code is drawn on the phone with
// Core Image (no dependency). Czech only, like the theme.
//
// Shown right after a redemption and again from "Zobrazit lístek".

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit
import FoodLogCore

/// A ticket waiting for the sheet.
struct LoveTicketRequest: Identifiable {
    let id = UUID()
    let coupon: LovePackCoupon
    let redeemedAt: Date
}

@MainActor
struct LoveTicketView: View {
    let request: LoveTicketRequest
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let partner = environment.partner
        NavigationStack {
            ScrollView {
                if let pack = partner.pack, let content = partner.content {
                    let ticket = LoveTicket.make(pack: pack, couponId: request.coupon.id, redeemedAt: request.redeemedAt)
                    VStack(spacing: Theme.Spacing.md) {
                        Text(verbatim: content.text(PartnerThemeContent.TextKey.ticketTitle))
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.accentSecondary)
                        Text(verbatim: request.coupon.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(verbatim: request.redeemedAt.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "cs_CZ"))))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let qr = Self.qrImage(ticket.payload) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(Theme.Spacing.sm)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                .accessibilityLabel(Text(verbatim: "QR kód lístku"))
                        }
                        Text(verbatim: ticket.payload)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                        Text(verbatim: ticket.code)
                            .font(.system(.title, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                            )
                            .rotationEffect(.degrees(-3))
                        Text(verbatim: content.text(PartnerThemeContent.TextKey.ticketHint))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .card()
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Theme.headerGradientStart, Theme.headerGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2
                            )
                            .accessibilityHidden(true)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .background(Theme.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A crisp QR code for `text` (Core Image, scaled without smoothing).
    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
