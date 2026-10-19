// UnlockedThemes — themes that exist only once something on the phone
// unlocks them (add-partner-love-theme D2/D3). They are not among the 13
// built-in themes `app-theming` promises, never in `ThemeCatalog.all`, and
// never encoded into or accepted from a share code: the partner theme comes
// with her love pack and is hers alone.
//
// "Srdce ninji" mixes love pink (the accent) with Naruto orange (the second
// brand colour), joined by the pink -> orange header gradient the app already
// draws. Values were checked against the D5 policy before they were written
// here (accent 4.95:1 on white, onAccent 4.95:1, orange 3.76:1; dark 6.95 /
// 8.84 / 7.82) and `PartnerThemeTests` holds them to it. `over` is moved to
// violet in both schemes so "over the goal" never reads as the pink accent.
//
// Whether a theme is unlocked is the app's knowledge (a valid love pack is
// stored), passed in as `AppearanceEnvironment.unlockedThemeIDs`; this file
// only describes the themes.
//
// Depended on by: PaletteResolver, ThemeShareCode, the app's theme picker.

import Foundation

/// Stable ids of the unlockable themes. Never rename a raw value: it is
/// persisted as `AppearanceSettings.themeID`.
public enum UnlockedTheme: String, CaseIterable, Sendable {
    case partner

    public var spec: ThemeSpec {
        switch self {
        case .partner: return ThemeCatalog.partner
        }
    }
}

extension ThemeCatalog {
    /// "Srdce ninji" -- the partner theme (light and dark).
    public static let partner = ThemeSpec(
        id: UnlockedTheme.partner.rawValue,
        iconName: "AppIcon-Partner",
        light: legibleTable(.light, brand(
            accent: 0xD12A68, deep: 0x9E1A4D, secondary: 0xD95F00,
            gradient: (0xE8457A, 0xF7841E), onAccent: .white,
            surfaces: Surfaces(background: 0xFFF4EF, surface: 0xFFFFFF, raised: 0xFFEAE2, stroke: 0xF2CFC4),
            extra: [.ember: 0xF7841E, .over: 0x8E3FA8]
        )),
        dark: legibleTable(.dark, brand(
            accent: 0xFF7FA6, deep: 0xE8457A, secondary: 0xFF9A3C,
            gradient: (0xE8457A, 0xF7841E), onAccent: .black,
            surfaces: Surfaces(background: 0x1A1016, surface: 0x2A1A24, raised: 0x352230, stroke: 0x4A3040),
            extra: [.ember: 0xFF9A3C, .over: 0xC58AF0]
        ))
    )

    /// Every unlockable theme, in picker order.
    public static let unlockable: [ThemeSpec] = UnlockedTheme.allCases.map(\.spec)

    /// A built-in theme, or an unlockable one when its id is in `unlocked`.
    public static func theme(id: String, unlocked: Set<String>) -> ThemeSpec? {
        if let builtIn = theme(id: id) { return builtIn }
        guard unlocked.contains(id), let theme = UnlockedTheme(rawValue: id) else { return nil }
        return theme.spec
    }

    /// As `theme(id:unlocked:)`, falling back to the default theme -- what a
    /// phone whose pack is gone shows.
    public static func themeOrDefault(id: String, unlocked: Set<String>) -> ThemeSpec {
        theme(id: id, unlocked: unlocked) ?? teal
    }

    /// The picker's list: the built-in themes, then the unlocked ones.
    public static func available(unlocked: Set<String>) -> [ThemeSpec] {
        all + unlockable.filter { unlocked.contains($0.id) }
    }

    /// Whether `id` is an unlockable theme (unlocked here or not).
    public static func isUnlockable(id: String) -> Bool {
        UnlockedTheme(rawValue: id) != nil
    }
}
