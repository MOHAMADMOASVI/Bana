import AppKit
import SwiftUI

/// UI language, switchable at runtime from Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case fa, en

    static let key = "appLanguage"
    static var current: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .fa }

    var id: String { rawValue }
    var isRTL: Bool { self == .fa }
    var locale: Locale { Locale(identifier: self == .fa ? "fa_IR" : "en_US") }
    var nativeName: String { self == .fa ? "فارسی" : "English" }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appAppearance"
    static var current: AppAppearance { AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: tr("خودکار", "System")
        case .light: tr("روشن", "Light")
        case .dark: tr("تیره", "Dark")
        }
    }

    @MainActor func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The string for the current UI language.
func tr(_ fa: String, _ en: String) -> String { AppLanguage.current == .fa ? fa : en }

/// Integer in the UI language's digits (ports and paths stay Latin — they are typed, not read).
func num(_ n: Int) -> String {
    let f = NumberFormatter()
    f.locale = AppLanguage.current.locale
    f.usesGroupingSeparator = false
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

/// Pins a technical token (".env", "public_html/", "--no-dev") left-to-right inside a Persian sentence,
/// so its leading/trailing punctuation doesn't jump to the other side.
func lrm(_ token: String) -> String { "\u{200E}\(token)\u{200E}" }

extension String {
    /// Text picks paragraph direction from the first strong character, not from layoutDirection;
    /// a Persian sentence that starts with "public_html/" or "build.sh" would otherwise lay out left-to-right.
    var rtl: String { AppLanguage.current.isRTL ? "\u{200F}" + self : self }
}

private struct LocalizedUI: ViewModifier {
    @AppStorage(AppLanguage.key) private var language = AppLanguage.fa.rawValue

    func body(content: Content) -> some View {
        let lang = AppLanguage(rawValue: language) ?? .fa
        content
            .environment(\.layoutDirection, lang.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, lang.locale)
            .id(lang) // rebuild so every tr() is re-read
    }
}

extension View {
    /// Layout direction, locale and strings follow the language chosen in Settings.
    func localizedUI() -> some View { modifier(LocalizedUI()) }

    /// Paths, commands, URLs and tool output stay left-to-right inside an RTL UI.
    func ltr() -> some View { environment(\.layoutDirection, .leftToRight) }

    /// The app's card surface.
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}
