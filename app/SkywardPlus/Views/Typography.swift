import CoreText
import SwiftUI

/// Unbounded, the bundled display face (SIL Open Font License, see
/// Resources/Fonts/Unbounded-OFL.txt), for big numbers and titles.
enum DisplayFont {
    static let family = "Unbounded"

    /// Registers the bundled font with this process once, the first time it is used.
    static let isAvailable: Bool = {
        guard let url = Bundle.main.url(forResource: "Unbounded", withExtension: "ttf") else { return false }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        // Already registered (a second registration fails harmlessly) still counts.
        return ok || error != nil
    }()
}

extension Font {
    /// Big numbers and titles in Unbounded. It is a wide face, so sizes run a
    /// little smaller than the rounded system font they replace.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        guard DisplayFont.isAvailable else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(DisplayFont.family, size: size, relativeTo: style).weight(weight)
    }
}
