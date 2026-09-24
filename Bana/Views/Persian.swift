import SwiftUI

extension View {
    /// Persian UI: right-to-left layout and Persian number formatting.
    func persianUI() -> some View {
        environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "fa_IR"))
    }

    /// Paths, commands, URLs and tool output stay left-to-right inside the RTL UI.
    func ltr() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}

/// Pins a technical token (".env", "public_html/", "--no-dev") left-to-right inside a Persian sentence,
/// so its leading/trailing punctuation doesn't jump to the other side.
func lrm(_ token: String) -> String { "\u{200E}\(token)\u{200E}" }

extension String {
    /// Text picks paragraph direction from the first strong character, not from layoutDirection;
    /// a Persian sentence that starts with "public_html/" or "build.sh" would otherwise lay out left-to-right.
    var rtl: String { "\u{200F}" + self }
}
