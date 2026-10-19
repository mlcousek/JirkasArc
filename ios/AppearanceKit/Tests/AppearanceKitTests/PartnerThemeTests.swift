// PartnerThemeTests — add-partner-love-theme D2/D3, specs partner-theme and
// app-theming: the partner theme meets the same contrast, distinctness and
// gradient-header policy as every non-Classic built-in theme, in light and
// dark; it is visible only when unlocked; it is never shared; and the 13
// built-in themes are untouched.

import XCTest
@testable import AppearanceKit

final class PartnerThemeTests: XCTestCase {
    private let partner = ThemeCatalog.partner

    func testItPassesTheContrastPolicyInBothSchemes() {
        XCTAssertEqual(partner.supportedSchemes, [.light, .dark])
        for scheme in partner.supportedSchemes {
            guard let table = partner.table(for: scheme) else { return XCTFail("no \(scheme) table") }
            XCTAssertTrue(table.isComplete, "\(scheme)")
            XCTAssertEqual(PolicyChecker.contrastFailures(table, scheme: scheme, level: .normal), [], "\(scheme)")
            XCTAssertEqual(PolicyChecker.distinctnessFailures(table, scheme: scheme), [], "\(scheme)")
        }
    }

    func testTheOrangeReadsOnCardsAndDiffersFromThePink() {
        for scheme in partner.supportedSchemes {
            let table = partner.table(for: scheme)!
            let surface = table.referenceValue(.surface, in: scheme)
            let pink = table.referenceValue(.accent, in: scheme)
            let orange = table.referenceValue(.accentSecondary, in: scheme)
            XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(orange, surface), ContrastPolicy.minimumGraphicOnSurface(.normal), "\(scheme)")
            XCTAssertGreaterThanOrEqual(ColorMath.deltaEOK(pink, orange), 0.10, "\(scheme)")
            // "Over the goal" is not the accent.
            XCTAssertGreaterThanOrEqual(ColorMath.deltaEOK(pink, table.referenceValue(.over, in: scheme)), 0.10, "\(scheme)")
        }
    }

    func testThePrimaryLabelReadsOnTheGradientStops() {
        for scheme in partner.supportedSchemes {
            let palette = PaletteResolver.resolve(theme: partner, requestedScheme: scheme)
            let background = palette.referenceValue(.background)
            let label: RGBA = scheme == .light ? .black : .white
            for stop in [ThemeRole.headerGradientStart, .headerGradientEnd] {
                for opacity in [0.22, 0.12] {
                    let blended = ColorMath.composite(palette.referenceValue(stop).withAlpha(opacity), over: background)
                    XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(label, blended), 4.5, "\(scheme) \(stop) @\(opacity)")
                }
            }
        }
    }

    func testIncreasedContrastStillResolves() {
        for scheme in partner.supportedSchemes {
            let palette = PaletteResolver.resolve(theme: partner, requestedScheme: scheme, increasedContrast: true)
            let accent = palette.referenceValue(.accent)
            XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(palette.referenceValue(.onAccent), accent), ContrastPolicy.minimumOnAccent(.increased), "\(scheme)")
        }
    }

    // MARK: Unlocking

    func testItIsNotABuiltInTheme() {
        XCTAssertEqual(ThemeCatalog.all.count, 13)
        XCTAssertFalse(ThemeCatalog.all.contains { $0.id == partner.id })
        XCTAssertNil(ThemeCatalog.theme(id: "partner"))
        XCTAssertEqual(ThemeCatalog.available(unlocked: []).count, 13)
        XCTAssertEqual(ThemeCatalog.available(unlocked: ["partner"]).last?.id, "partner")
    }

    func testAStoredPartnerThemeWithoutItsPackShowsTheDefault() {
        let settings = AppearanceSettings(themeID: "partner")

        let locked = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .light))
        XCTAssertEqual(locked.themeID, ThemeCatalog.defaultThemeID)

        let unlocked = PaletteResolver.resolve(
            settings: settings,
            environment: AppearanceEnvironment(systemScheme: .dark, unlockedThemeIDs: ["partner"])
        )
        XCTAssertEqual(unlocked.themeID, "partner")
        XCTAssertEqual(unlocked.referenceValue(.accent), RGBA(hex: 0xFF7FA6))
    }

    // MARK: Sharing

    func testItIsNeverShared() {
        XCTAssertFalse(ThemeShareCode.isShareable(AppearanceSettings(themeID: "partner")))
        XCTAssertTrue(ThemeShareCode.isShareable(AppearanceSettings(themeID: "forest")))

        // A code naming it (made by hand: the app never makes one) is refused.
        let code = ThemeShareCode.encode(AppearanceSettings(themeID: "partner"))
        XCTAssertEqual(ThemeShareCode.decode(code), .failure(.unshareableTheme))

        // Other codes are unchanged.
        let forest = ThemeShareCode.encode(AppearanceSettings(themeID: "forest"))
        guard case .success(let imported) = ThemeShareCode.decode(forest) else { return XCTFail("forest code refused") }
        XCTAssertEqual(imported.settings.themeID, "forest")
    }
}
