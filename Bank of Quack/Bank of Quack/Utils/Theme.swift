import SwiftUI

enum Theme {
    enum Colors {
        // Primary palette - Deep teal/emerald tones
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
        
        // Secondary palette - Warm gold/amber (accent)
        static let accent = Color(hex: "FFCA28")
        static let accentLight = Color(hex: "FFE082")
        static let accentDark = Color(hex: "FFB300")
        
        // Background colors
        static let backgroundPrimary = Color(hex: "004D40")
        static let backgroundSecondary = Color(hex: "00695C")
        static let backgroundTertiary = Color(hex: "26A69A")
        static let backgroundCard = Color.white.opacity(0.1)
        static let backgroundCardSolid = Color(hex: "00796B")
        static let backgroundInput = Color.white.opacity(0.15)
        
        // Text colors
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.8)
        static let textTertiary = Color.white.opacity(0.6)
        static let textMuted = Color.white.opacity(0.4)
        static let textInverse = Color(hex: "212121")
        
        // Semantic colors
        static let success = Color(hex: "4CAF50")
        static let successLight = Color(hex: "81C784")
        static let warning = Color(hex: "FF9800")
        static let error = Color(hex: "F44336")
        static let errorLight = Color(hex: "E57373")
        static let info = Color(hex: "2196F3")
        
        // Transaction type colors
        static let expense = Color(hex: "EF5350")
        static let income = Color(hex: "66BB6A")
        static let settlement = Color(hex: "42A5F5")
        static let reimbursement = Color(hex: "AB47BC")
        
        // Border
        static let borderLight = Color.white.opacity(0.2)
        static let borderDefault = Color.white.opacity(0.3)
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

// MARK: - View Modifiers

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

struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Colors.textInverse)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.accent)
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
    
    func inputFieldStyle() -> some View {
        modifier(InputFieldStyle())
    }
}

