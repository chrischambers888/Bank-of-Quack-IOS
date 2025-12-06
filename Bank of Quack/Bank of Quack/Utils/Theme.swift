import SwiftUI
import Combine

// MARK: - Theme Provider (Dynamic Theme Colors)

/// Observable class that provides dynamic theme colors based on the current household's theme.
/// Falls back to Quack Classic when no theme is set or user is logged out.
class ThemeProvider: ObservableObject {
    static let shared = ThemeProvider()
    
    @Published private(set) var currentPalette: ColorPalette
    
    private init() {
        self.currentPalette = QuackPalettes.quackClassic
    }
    
    /// Update the current palette (called when household changes or theme is applied)
    func updatePalette(_ palette: ColorPalette?) {
        currentPalette = palette ?? QuackPalettes.quackClassic
        objectWillChange.send()
    }
    
    /// Reset to default theme (used when logging out)
    func resetToDefault() {
        currentPalette = QuackPalettes.quackClassic
        objectWillChange.send()
    }
    
    // MARK: - Dynamic Colors
    
    var gradientStart: Color { currentPalette.gradientStartColor }
    var gradientEnd: Color { currentPalette.gradientEndColor }
    var accent: Color { currentPalette.accent }
    var textPrimary: Color { currentPalette.textPrimary }
    var textSecondary: Color { currentPalette.textSecondary }
    var backgroundPrimary: Color { currentPalette.bgPrimary }
    var backgroundSecondary: Color { currentPalette.bgSecondary }
    var isLightMode: Bool { currentPalette.isLightMode }
    
    // Theme-aware semantic colors
    var success: Color { currentPalette.success }
    var error: Color { currentPalette.error }
    
    // Derived colors
    var textTertiary: Color { textSecondary.opacity(0.75) }
    var textMuted: Color { textSecondary.opacity(0.5) }
    var textInverse: Color { isLightMode ? .white : Color(hex: "212121") }
    var backgroundCard: Color { textPrimary.opacity(0.1) }
    var backgroundCardSolid: Color { backgroundSecondary }
    var backgroundInput: Color { textPrimary.opacity(0.15) }
    var borderLight: Color { textPrimary.opacity(0.2) }
    var borderDefault: Color { textPrimary.opacity(0.3) }
    
    // Gradient helper
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .top,
            endPoint: .center
        )
    }
}

// MARK: - Static Theme (Backwards Compatibility + Spacing/Radius)

enum Theme {
    /// Dynamic colors from current theme - use these for themed views
    static var current: ThemeProvider { ThemeProvider.shared }
    
    enum Colors {
        // MARK: - Dynamic Colors (from current theme)
        
        /// Returns the current theme's gradient start color
        static var gradientStart: Color { ThemeProvider.shared.gradientStart }
        /// Returns the current theme's gradient end color  
        static var gradientEnd: Color { ThemeProvider.shared.gradientEnd }
        
        // MARK: - Static Primary Palette (Quack Classic - used as fallback)
        
        static let primary50 = Color(hex: "E0F2F1")
        static let primary100 = Color(hex: "B2DFDB")
        static let primary200 = Color(hex: "80CBC4")
        static let primary300 = Color(hex: "4DB6AC")
        static let primary400 = Color(hex: "26A69A")
        static let primary500 = Color(hex: "009688")
        static let primary600 = Color(hex: "00897B")
        static let primary700 = Color(hex: "00796B")
        static let primary800 = Color(hex: "00695C")
        static let primary900 = Color(hex: "004D40")
        
        // MARK: - Dynamic Accent (from current theme)
        
        /// Returns the current theme's accent color
        static var accent: Color { ThemeProvider.shared.accent }
        static let accentLight = Color(hex: "FFE082")
        static let accentDark = Color(hex: "FFB300")
        
        // MARK: - Dynamic Background Colors
        
        /// Returns the current theme's primary background
        static var backgroundPrimary: Color { ThemeProvider.shared.backgroundPrimary }
        /// Returns the current theme's secondary background
        static var backgroundSecondary: Color { ThemeProvider.shared.backgroundSecondary }
        static var backgroundTertiary: Color { ThemeProvider.shared.gradientStart }
        static var backgroundCard: Color { ThemeProvider.shared.backgroundCard }
        static var backgroundCardSolid: Color { ThemeProvider.shared.backgroundCardSolid }
        static var backgroundInput: Color { ThemeProvider.shared.backgroundInput }
        
        // MARK: - Dynamic Text Colors
        
        /// Returns the current theme's primary text color
        static var textPrimary: Color { ThemeProvider.shared.textPrimary }
        /// Returns the current theme's secondary text color
        static var textSecondary: Color { ThemeProvider.shared.textSecondary }
        static var textTertiary: Color { ThemeProvider.shared.textTertiary }
        static var textMuted: Color { ThemeProvider.shared.textMuted }
        static var textInverse: Color { ThemeProvider.shared.textInverse }
        
        // MARK: - Semantic Colors (theme-aware for success/error)
        
        static var success: Color { ThemeProvider.shared.success }
        static let successLight = Color(hex: "81C784")
        static let warning = Color(hex: "FF9800")
        static var error: Color { ThemeProvider.shared.error }
        static let errorLight = Color(hex: "E57373")
        static let info = Color(hex: "2196F3")
        
        // MARK: - Transaction Type Colors (static - consistent across themes)
        
        static let expense = Color(hex: "EF5350")
        static let income = Color(hex: "66BB6A")
        static let settlement = Color(hex: "42A5F5")
        static let reimbursement = Color(hex: "AB47BC")
        
        // MARK: - Balance Colors (static - always green/red regardless of theme)
        
        static let balancePositive = Color(hex: "4CAF50")
        static let balanceNegative = Color(hex: "F44336")
        
        // MARK: - Dynamic Border Colors
        
        static var borderLight: Color { ThemeProvider.shared.borderLight }
        static var borderDefault: Color { ThemeProvider.shared.borderDefault }
        
        // MARK: - Light Mode Detection
        
        static var isLightMode: Bool { ThemeProvider.shared.isLightMode }
    }
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    enum CornerRadius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let full: CGFloat = 9999
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers (Dynamic)

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
    }
}

struct SolidCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCardSolid)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
    }
}

struct MaterialCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isLoading: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.Colors.textInverse : Theme.Colors.textInverse.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderDefault, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundInput)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderLight, lineWidth: 1)
            )
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    func solidCardStyle() -> some View {
        modifier(SolidCardStyle())
    }
    
    func materialCardStyle() -> some View {
        modifier(MaterialCardStyle())
    }
    
    func inputFieldStyle() -> some View {
        modifier(InputFieldStyle())
    }
    
    /// Apply the current theme's background gradient
    func themedBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [Theme.Colors.gradientStart, Theme.Colors.gradientEnd],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }
    
    /// Apply a subtle gradient background (for non-home tabs)
    func subtleThemedBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [Theme.Colors.gradientStart, Theme.Colors.backgroundPrimary],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }
    
    /// Apply toolbar color scheme based on current theme
    func themedToolbar() -> some View {
        self
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
    }
}
