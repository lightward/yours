import SwiftUI

// The web app's palette (app/assets/stylesheets/application.css), as dynamic
// colors. Dark is the default theme there and here.
enum Theme {
    static let background = Color(light: 0xF5F5F0, dark: 0x0A0A0F)
    static let foreground = Color(light: 0x3D3D3D, dark: 0xB7B3AC)
    static let foregroundHeading = Color(light: 0x1A1A1A, dark: 0xCFCCC6)
    static let border = Color(light: 0xE0E0D8, dark: 0x1A1A2E)
    static let borderLight = Color(light: 0xD0D0C8, dark: 0x2A2A3E)
    static let accent = Color(light: 0x0088AA, dark: 0x00E5FF)
    static let accentHover = Color(light: 0x006688, dark: 0x00C2D9)
    static let accentActive = Color(light: 0xCC44CC, dark: 0xFF66FF)
    static let success = Color(light: 0x00AA77, dark: 0x00FFA3)
    static let warning = Color(light: 0xCC9900, dark: 0xFFD700)
    static let error = Color(light: 0xCC0066, dark: 0xFF0080)
    static let userMessageBg = Color(light: 0xE8E8E0, dark: 0x1A1A3E)
    static let assistantMessageBg = Color(light: 0xF0F0E8, dark: 0x0F0F1F)
}

// Until the Lightward Favorit licensing question is settled for app
// distribution, these use the system faces: SF Mono where the web uses
// Favorit Mono, SF where it uses Favorit.
extension Font {
    static func yoursMono(_ size: CGFloat = 16, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func yoursBody(_ size: CGFloat = 17) -> Font {
        .system(size: size)
    }

    static func yoursHeading(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

// Mirrors the web's theme setting (localStorage "yours-theme"): dark default,
// light, or follow the system.
enum ThemePreference: String, CaseIterable {
    case dark, light, auto

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .auto: nil
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
