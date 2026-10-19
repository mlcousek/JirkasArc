// HeartBurstOverlay.swift
//
// add-partner-love-theme D4, spec partner-theme "Logging and levelling up
// have themed motion, respecting Reduce Motion": with the partner theme on,
// a confirmed log plays a heart burst -- one big heart, sakura petals
// flying out and a spinning shuriken heart -- in at most 700 ms, with the
// two-tap heartbeat haptic. It sits on the root over every screen, never
// takes a touch, and fades out by itself, so it can never cover or delay
// the success state of the confirm sheet. Under Reduce Motion: one still
// heart that fades.
//
// Triggered by PartnerThemeModel.celebrateLog() (AppEnvironment.logConfirmed).
// Decorative: hidden from VoiceOver (the confirm sheet says what happened).

import SwiftUI

@MainActor
struct HeartBurstOverlay: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress: CGFloat = 0
    @State private var isShowing = false

    private static let petalCount = 7
    private static let duration = 0.7

    var body: some View {
        ZStack {
            if isShowing {
                if reduceMotion {
                    heart(size: 88)
                        .opacity(1 - progress)
                } else {
                    burst
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: environment.partner.heartBurst) { _, burst in
            guard burst != nil else { return }
            play()
        }
    }

    private var burst: some View {
        ZStack {
            ForEach(0..<Self.petalCount, id: \.self) { index in
                let angle = Angle.degrees(Double(index) / Double(Self.petalCount) * 360 - 90)
                SakuraPetal()
                    .fill(index.isMultiple(of: 2) ? Theme.headerGradientStart : Theme.accent.opacity(0.85))
                    .frame(width: 14, height: 20)
                    .rotationEffect(.degrees(angle.degrees + Double(progress) * 120))
                    .offset(
                        x: CGFloat(cos(angle.radians)) * 120 * progress,
                        y: CGFloat(sin(angle.radians)) * 120 * progress
                    )
                    .opacity(Double(1 - progress))
            }
            ShurikenHeart()
                .fill(Theme.accentSecondary, style: FillStyle(eoFill: true))
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(Double(progress) * 540))
                .offset(x: 70 * progress, y: -90 * progress)
                .opacity(Double(1 - progress))
            heart(size: 72 + 40 * progress)
                .opacity(Double(1 - progress * progress))
        }
    }

    private func heart(size: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(
                LinearGradient(colors: [Theme.headerGradientStart, Theme.headerGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .shadow(color: Theme.accent.opacity(0.35), radius: 12)
    }

    private func play() {
        Haptics.heartbeat()
        progress = 0
        isShowing = true
        withAnimation(.easeOut(duration: Self.duration)) {
            progress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.duration))
            isShowing = false
            progress = 0
        }
    }
}

/// A sakura petal: a rounded teardrop with a small notch at its tip.
struct SakuraPetal: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h))
        path.addCurve(to: CGPoint(x: w * 0.35, y: 0), control1: CGPoint(x: -w * 0.2, y: h * 0.6), control2: CGPoint(x: w * 0.05, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.65, y: 0))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w * 0.95, y: h * 0.05), control2: CGPoint(x: w * 1.2, y: h * 0.6))
        path.closeSubpath()
        return path
    }
}

/// A four-point shuriken with a heart-shaped hole: drawn for this app.
struct ShurikenHeart: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.32
        var star = Path()
        for i in 0..<8 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) * .pi / 4 - .pi / 2
            let point = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
        }
        star.closeSubpath()

        // The hole: a small heart in the middle (even-odd fill).
        let s = outer * 0.22
        var heart = Path()
        heart.move(to: CGPoint(x: c.x, y: c.y + s))
        heart.addCurve(to: CGPoint(x: c.x - s, y: c.y - s * 0.3), control1: CGPoint(x: c.x - s * 0.4, y: c.y + s * 0.6), control2: CGPoint(x: c.x - s, y: c.y + s * 0.2))
        heart.addArc(center: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.3), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        heart.addArc(center: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.3), radius: s * 0.5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        heart.addCurve(to: CGPoint(x: c.x, y: c.y + s), control1: CGPoint(x: c.x + s, y: c.y + s * 0.2), control2: CGPoint(x: c.x + s * 0.4, y: c.y + s * 0.6))
        heart.closeSubpath()

        var path = star
        path.addPath(heart)
        return path
    }
}
