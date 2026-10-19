// CzechPlural.swift
//
// add-partner-love-theme D5: the partner theme's text is Czech only and
// lives in its own content table, not in a `.stringsdict`/`.xcstrings`, so
// it gets no plural rules for free. This is the CLDR rule for Czech
// integers, which the table's counts use (1 srdíčko, 2–4 srdíčka, 0 and 5+
// srdíček). Fractions ("other") never occur in it.
//
// Pure. Depended on by the app's PartnerText table. Tests: CzechPluralTests.

import Foundation

public enum CzechPlural {
    public enum Form: Sendable, Equatable {
        case one
        case few
        case many
    }

    public static func form(_ count: Int) -> Form {
        switch abs(count) {
        case 1: return .one
        case 2...4: return .few
        default: return .many
        }
    }

    public static func choose(_ count: Int, one: String, few: String, many: String) -> String {
        switch form(count) {
        case .one: return one
        case .few: return few
        case .many: return many
        }
    }
}
