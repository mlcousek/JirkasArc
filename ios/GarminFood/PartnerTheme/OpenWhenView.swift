// OpenWhenView.swift
//
// add-partner-love-theme, spec love-messages "Optional sealed scrolls and a
// countdown, shown only when the pack has them": the pack's "Otevři, až…"
// scrolls. A sealed one shows only its title; tapping opens it once, for
// good -- it stays readable afterwards. Reached from the love card, and
// only when the pack has scrolls. The unrolling is a short vertical reveal,
// a plain fade under Reduce Motion.
//
// Text from the pack and the theme's Czech table. Depends on
// PartnerThemeModel (openScroll).

import SwiftUI
import FoodLogCore

@MainActor
struct OpenWhenView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var partner: PartnerThemeModel { environment.partner }

    var body: some View {
        let content = partner.content
        List {
            ForEach(partner.pack?.openWhen ?? []) { scroll in
                let isOpen = partner.state?.openedScrolls[scroll.id] != nil
                Section {
                    Button {
                        guard !isOpen else { return }
                        Haptics.heartbeat()
                        Task { await partner.openScroll(scroll.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label {
                                Text(verbatim: scroll.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: isOpen ? "scroll.fill" : "scroll")
                                    .foregroundStyle(Theme.accentSecondary)
                            }
                            if isOpen {
                                Text(verbatim: scroll.text)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            } else if let content {
                                Text(verbatim: content.text(PartnerThemeContent.TextKey.scrollSealed))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45), value: isOpen)
                }
            }
        }
        .navigationTitle(Text(verbatim: content?.text(PartnerThemeContent.TextKey.scrollsTitle) ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.groupedBackground)
    }
}
