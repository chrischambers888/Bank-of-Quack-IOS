import SwiftUI
import Combine

// MARK: - Color Palette Model (Expanded)

struct ColorPalette: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let colors: [String] // Sector/category colors
    
    // Theme appearance colors
    let gradientStart: String
    let gradientEnd: String
    let accentColor: String
    let primaryTextColor: String
    let secondaryTextColor: String
    let backgroundPrimary: String
    let backgroundSecondary: String
    let isLightMode: Bool
    
    var previewGradient: [Color] {
        [
            Color(hex: gradientStart.replacingOccurrences(of: "#", with: "")),
            Color(hex: gradientEnd.replacingOccurrences(of: "#", with: ""))
        ]
    }
    
    var categoryPreviewColors: [Color] {
        colors.prefix(4).map { Color(hex: $0.replacingOccurrences(of: "#", with: "")) }
    }
    
    // Computed SwiftUI Colors
    var gradientStartColor: Color { Color(hex: gradientStart.replacingOccurrences(of: "#", with: "")) }
    var gradientEndColor: Color { Color(hex: gradientEnd.replacingOccurrences(of: "#", with: "")) }
    var accent: Color { Color(hex: accentColor.replacingOccurrences(of: "#", with: "")) }
    var textPrimary: Color { Color(hex: primaryTextColor.replacingOccurrences(of: "#", with: "")) }
    var textSecondary: Color { Color(hex: secondaryTextColor.replacingOccurrences(of: "#", with: "")) }
    var bgPrimary: Color { Color(hex: backgroundPrimary.replacingOccurrences(of: "#", with: "")) }
    var bgSecondary: Color { Color(hex: backgroundSecondary.replacingOccurrences(of: "#", with: "")) }
    
    init(
        id: String,
        name: String,
        description: String,
        colors: [String],
        gradientStart: String,
        gradientEnd: String,
        accentColor: String,
        primaryTextColor: String,
        secondaryTextColor: String,
        backgroundPrimary: String,
        backgroundSecondary: String,
        isLightMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.colors = colors
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.accentColor = accentColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.backgroundPrimary = backgroundPrimary
        self.backgroundSecondary = backgroundSecondary
        self.isLightMode = isLightMode
    }
}

// MARK: - Applied Theme Manager (Household-Specific)

class AppliedThemeManager: ObservableObject {
    static let shared = AppliedThemeManager()
    
    @Published var appliedThemeId: String?
    @Published var appliedThemeName: String?
    @Published var currentHouseholdId: UUID?
    @Published var customAccentColor: String?
    
    private let colorOrderKey = "themeColorOrder"
    private let customAccentKey = "customAccentColor"
    
    init() {
        // Will be set when household is selected
    }
    
    // MARK: - Household-Specific Theme Storage
    
    private func themeIdKey(for householdId: UUID) -> String {
        "appliedThemeId_\(householdId.uuidString)"
    }
    
    private func themeNameKey(for householdId: UUID) -> String {
        "appliedThemeName_\(householdId.uuidString)"
    }
    
    /// Load theme for a specific household
    func loadTheme(for householdId: UUID) {
        currentHouseholdId = householdId
        appliedThemeId = UserDefaults.standard.string(forKey: themeIdKey(for: householdId))
        appliedThemeName = UserDefaults.standard.string(forKey: themeNameKey(for: householdId))
        
        // Set default if no theme is set for this household
        if appliedThemeId == nil {
            setAppliedTheme(id: "quack_classic", name: "Quack Classic", for: householdId)
        }
        
        // Load custom accent color for this theme/household
        if let themeId = appliedThemeId {
            customAccentColor = getCustomAccentColor(for: themeId)
        }
        
        objectWillChange.send()
    }
    
    /// Save theme for the current household
    func setAppliedTheme(id: String, name: String, for householdId: UUID? = nil) {
        let hId = householdId ?? currentHouseholdId
        guard let householdId = hId else { return }
        
        appliedThemeId = id
        appliedThemeName = name
        UserDefaults.standard.set(id, forKey: themeIdKey(for: householdId))
        UserDefaults.standard.set(name, forKey: themeNameKey(for: householdId))
        objectWillChange.send()
    }
    
    /// Clear theme when logging out
    func clearForLogout() {
        appliedThemeId = nil
        appliedThemeName = nil
        currentHouseholdId = nil
        objectWillChange.send()
    }
    
    /// Sets "Quack Classic" as the default theme if no theme is currently applied
    func setDefaultThemeIfNeeded() {
        if appliedThemeId == nil, let householdId = currentHouseholdId {
            setAppliedTheme(id: "quack_classic", name: "Quack Classic", for: householdId)
        }
    }
    
    // MARK: - Custom Color Order
    
    private func colorOrderKey(for themeId: String, householdId: UUID) -> String {
        "\(colorOrderKey)_\(themeId)_\(householdId.uuidString)"
    }
    
    /// Get the custom color order for a theme, or nil if using default order
    func getCustomColorOrder(for themeId: String) -> [Int]? {
        guard let householdId = currentHouseholdId else { return nil }
        let key = colorOrderKey(for: themeId, householdId: householdId)
        return UserDefaults.standard.array(forKey: key) as? [Int]
    }
    
    /// Save a custom color order for a theme
    func saveCustomColorOrder(for themeId: String, order: [Int]) {
        guard let householdId = currentHouseholdId else { return }
        let key = colorOrderKey(for: themeId, householdId: householdId)
        UserDefaults.standard.set(order, forKey: key)
    }
    
    /// Reset color order to default for a theme
    func resetColorOrder(for themeId: String) {
        guard let householdId = currentHouseholdId else { return }
        let key = colorOrderKey(for: themeId, householdId: householdId)
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // MARK: - Custom Accent Color
    
    private func accentColorKey(for themeId: String, householdId: UUID) -> String {
        "\(customAccentKey)_\(themeId)_\(householdId.uuidString)"
    }
    
    /// Get the custom accent color for a theme, or nil if using default
    func getCustomAccentColor(for themeId: String) -> String? {
        guard let householdId = currentHouseholdId else { return nil }
        let key = accentColorKey(for: themeId, householdId: householdId)
        return UserDefaults.standard.string(forKey: key)
    }
    
    /// Save a custom accent color for a theme
    func saveCustomAccentColor(for themeId: String, color: String) {
        guard let householdId = currentHouseholdId else { return }
        let key = accentColorKey(for: themeId, householdId: householdId)
        UserDefaults.standard.set(color, forKey: key)
        customAccentColor = color
        objectWillChange.send()
    }
    
    /// Reset accent color to default for a theme
    func resetAccentColor(for themeId: String) {
        guard let householdId = currentHouseholdId else { return }
        let key = accentColorKey(for: themeId, householdId: householdId)
        UserDefaults.standard.removeObject(forKey: key)
        customAccentColor = nil
        objectWillChange.send()
    }
    
    /// Get available accent colors for a theme (colors that work well as accents)
    func getAvailableAccentColors(for palette: ColorPalette) -> [String] {
        // Curated list of colors that work well as accent colors
        // Includes the palette's default accent, and high-contrast/vibrant colors from the palette
        var accentOptions: [String] = []
        
        // Always include the default accent
        accentOptions.append(palette.accentColor)
        
        // Add suitable accent colors based on whether it's light or dark mode
        let suitableAccents: [String]
        if palette.isLightMode {
            // For light themes: darker, more saturated colors work as accents
            suitableAccents = [
                "#00796B", "#0277BD", "#F57F17", "#C62828", "#6A1B9A",
                "#2E7D32", "#D84315", "#AD1457", "#4527A0", "#00695C",
                "#1565C0", "#E65100", "#7B1FA2", "#00838F", "#558B2F"
            ]
        } else {
            // For dark themes: brighter, more vibrant colors work as accents
            suitableAccents = [
                "#FFCA28", "#00E5FF", "#FF4081", "#69F0AE", "#FFAB00",
                "#40C4FF", "#FF6E40", "#B388FF", "#64FFDA", "#EEFF41",
                "#FF80AB", "#18FFFF", "#FFD740", "#A7FFEB", "#F50057",
                "#00E676", "#FF1744", "#7C4DFF", "#76FF03", "#FF9100"
            ]
        }
        
        // Add suitable accents that aren't already in the list
        for color in suitableAccents {
            if !accentOptions.contains(color) {
                accentOptions.append(color)
            }
        }
        
        // Also include any vibrant colors from the palette itself
        for color in palette.colors {
            if !accentOptions.contains(color) {
                accentOptions.append(color)
            }
        }
        
        return accentOptions
    }
    
    /// Get the current theme palette (with custom accent if set)
    func getCurrentPalette() -> ColorPalette? {
        guard let themeId = appliedThemeId else {
            return QuackPalettes.quackClassic // Default fallback
        }
        guard let basePalette = QuackPalettes.all.first(where: { $0.id == themeId }) else {
            return QuackPalettes.quackClassic
        }
        
        // If there's a custom accent color, return a modified palette
        if let customAccent = customAccentColor {
            return ColorPalette(
                id: basePalette.id,
                name: basePalette.name,
                description: basePalette.description,
                colors: basePalette.colors,
                gradientStart: basePalette.gradientStart,
                gradientEnd: basePalette.gradientEnd,
                accentColor: customAccent,
                primaryTextColor: basePalette.primaryTextColor,
                secondaryTextColor: basePalette.secondaryTextColor,
                backgroundPrimary: basePalette.backgroundPrimary,
                backgroundSecondary: basePalette.backgroundSecondary,
                isLightMode: basePalette.isLightMode
            )
        }
        
        return basePalette
    }
    
    /// Get colors in the custom order (or default if no custom order)
    func getOrderedColors(for themeId: String) -> [String] {
        guard let palette = QuackPalettes.all.first(where: { $0.id == themeId }) else { return [] }
        
        guard let customOrder = getCustomColorOrder(for: themeId),
              customOrder.count == palette.colors.count else {
            return palette.colors
        }
        
        // Reorder based on custom indices
        return customOrder.compactMap { index in
            guard index >= 0, index < palette.colors.count else { return nil }
            return palette.colors[index]
        }
    }
    
    /// Get the next color based on item count (used for both sectors and categories)
    func getNextSectorColor(sectorCount: Int) -> String? {
        guard let themeId = appliedThemeId else { return nil }
        let colors = getOrderedColors(for: themeId)
        guard !colors.isEmpty else { return nil }
        return colors[sectorCount % colors.count]
    }
    
    /// Get the next color based on item count (used for both sectors and categories)
    func getNextCategoryColor(categoryCount: Int) -> String? {
        guard let themeId = appliedThemeId else { return nil }
        let colors = getOrderedColors(for: themeId)
        guard !colors.isEmpty else { return nil }
        return colors[categoryCount % colors.count]
    }
}

// MARK: - Quack-Themed Palettes

enum QuackPalettes {
    // MARK: - Dark Themes
    
    /// The signature Bank of Quack theme - teal and gold
    static let quackClassic = ColorPalette(
        id: "quack_classic",
        name: "Quack Classic",
        description: "The signature teal and gold look",
        colors: [
            "#80CBC4", "#FFEB3B", "#B2DFDB", "#FFF176",
            "#E0F2F1", "#FFF59D", "#A5D6A7", "#FFFDE7"
        ],
        gradientStart: "#00796B",
        gradientEnd: "#004D40",
        accentColor: "#FFCA28",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#B0BEC5",
        backgroundPrimary: "#004D40",
        backgroundSecondary: "#00695C",
        isLightMode: false
    )
    
    /// Bold and vibrant quack colors
    static let quackAttack = ColorPalette(
        id: "quack_attack",
        name: "Quack Attack",
        description: "Bold teal, gold, and accent pops",
        colors: [
            "#004D40", "#F57F17", "#00695C", "#F9A825",
            "#00897B", "#FBC02D", "#26A69A", "#FFCA28"
        ],
        gradientStart: "#00897B",
        gradientEnd: "#004D40",
        accentColor: "#FF6D00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#B2DFDB",
        backgroundPrimary: "#00352C",
        backgroundSecondary: "#004D40",
        isLightMode: false
    )
    
    /// Deep midnight blues - like a duck on a moonlit pond
    static let mallardMidnight = ColorPalette(
        id: "mallard_midnight",
        name: "Mallard Midnight",
        description: "Deep blues like a moonlit pond",
        colors: [
            "#1A237E", "#4A148C", "#311B92", "#0D47A1",
            "#880E4F", "#006064", "#263238", "#4527A0"
        ],
        gradientStart: "#1A237E",
        gradientEnd: "#0D1B2A",
        accentColor: "#7C4DFF",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#90CAF9",
        backgroundPrimary: "#0D1B2A",
        backgroundSecondary: "#1A237E",
        isLightMode: false
    )
    
    /// Warm golden hues - precious as a golden egg
    static let goldenEgg = ColorPalette(
        id: "golden_egg",
        name: "Golden Egg",
        description: "Warm sunset golds and oranges",
        colors: [
            "#BF360C", "#D84315", "#E64A19", "#F4511E",
            "#E65100", "#EF6C00", "#F57C00", "#FB8C00"
        ],
        gradientStart: "#E65100",
        gradientEnd: "#BF360C",
        accentColor: "#FFAB00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#FFE0B2",
        backgroundPrimary: "#8B2500",
        backgroundSecondary: "#BF360C",
        isLightMode: false
    )
    
    /// Cool ocean teals - like ripples on a pond
    static let pondRipple = ColorPalette(
        id: "pond_ripple",
        name: "Pond Ripple",
        description: "Cool blues and teals like water",
        colors: [
            "#0D47A1", "#1565C0", "#1976D2", "#1E88E5",
            "#006064", "#00838F", "#0097A7", "#00ACC1"
        ],
        gradientStart: "#0277BD",
        gradientEnd: "#01579B",
        accentColor: "#00E5FF",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#B3E5FC",
        backgroundPrimary: "#01579B",
        backgroundSecondary: "#0277BD",
        isLightMode: false
    )
    
    /// Cool Scandinavian frost tones
    static let featherFrost = ColorPalette(
        id: "feather_frost",
        name: "Feather Frost",
        description: "Cool icy Scandinavian tones",
        colors: [
            "#37474F", "#455A64", "#546E7A", "#607D8B",
            "#0277BD", "#0288D1", "#039BE5", "#03A9F4"
        ],
        gradientStart: "#455A64",
        gradientEnd: "#263238",
        accentColor: "#4DD0E1",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#B0BEC5",
        backgroundPrimary: "#263238",
        backgroundSecondary: "#37474F",
        isLightMode: false
    )
    
    /// Warm sunset oranges - like ducks at dusk
    static let waddleSunset = ColorPalette(
        id: "waddle_sunset",
        name: "Waddle Sunset",
        description: "Warm dusk colors",
        colors: [
            "#BF360C", "#E65100", "#F9A825", "#558B2F",
            "#4E342E", "#D84315", "#FF8F00", "#33691E"
        ],
        gradientStart: "#D84315",
        gradientEnd: "#BF360C",
        accentColor: "#FFAB00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#FFCCBC",
        backgroundPrimary: "#8D2B0B",
        backgroundSecondary: "#BF360C",
        isLightMode: false
    )
    
    /// Electric neon colors - bright as a duck's bill
    static let billBright = ColorPalette(
        id: "bill_bright",
        name: "Bill Bright",
        description: "Electric bold neon colors",
        colors: [
            "#00E676", "#00E5FF", "#651FFF", "#D500F9",
            "#FF1744", "#F50057", "#FF9100", "#FFEA00"
        ],
        gradientStart: "#651FFF",
        gradientEnd: "#311B92",
        accentColor: "#00E676",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#B388FF",
        backgroundPrimary: "#1A0040",
        backgroundSecondary: "#311B92",
        isLightMode: false
    )
    
    /// Tropical paradise vibes - colorful plumage
    static let plumageParadise = ColorPalette(
        id: "plumage_paradise",
        name: "Plumage Paradise",
        description: "Vibrant tropical plumage",
        colors: [
            "#FF6F00", "#00BFA5", "#F50057", "#00B0FF",
            "#FFD600", "#64DD17", "#AA00FF", "#FF3D00"
        ],
        gradientStart: "#00897B",
        gradientEnd: "#00695C",
        accentColor: "#FF6D00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#A7FFEB",
        backgroundPrimary: "#004D40",
        backgroundSecondary: "#00695C",
        isLightMode: false
    )
    
    /// Cyberpunk neons - rubber ducky goes electric
    static let rubberDucky = ColorPalette(
        id: "rubber_ducky",
        name: "Rubber Ducky",
        description: "Futuristic cyber neon vibes",
        colors: [
            "#00FFFF", "#FF00FF", "#FFFF00", "#00FF00",
            "#FF0080", "#8000FF", "#FF8000", "#0080FF"
        ],
        gradientStart: "#880E4F",
        gradientEnd: "#4A0028",
        accentColor: "#FFFF00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#F8BBD0",
        backgroundPrimary: "#1A0A14",
        backgroundSecondary: "#4A0028",
        isLightMode: false
    )
    
    /// Rich gemstone colors - jewels fit for a drake
    static let drakesJewels = ColorPalette(
        id: "drakes_jewels",
        name: "Drake's Jewels",
        description: "Rich gemstone-inspired colors",
        colors: [
            "#B71C1C", "#1A237E", "#004D40", "#E65100",
            "#4A148C", "#006064", "#880E4F", "#33691E"
        ],
        gradientStart: "#4A148C",
        gradientEnd: "#1A0A28",
        accentColor: "#E040FB",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#CE93D8",
        backgroundPrimary: "#1A0A28",
        backgroundSecondary: "#4A148C",
        isLightMode: false
    )
    
    /// Fresh garden colors - Mother Goose's garden
    static let motherGoose = ColorPalette(
        id: "mother_goose",
        name: "Mother Goose",
        description: "Fresh floral garden palette",
        colors: [
            "#C2185B", "#7B1FA2", "#388E3C", "#F57C00",
            "#1976D2", "#D32F2F", "#00796B", "#FBC02D"
        ],
        gradientStart: "#388E3C",
        gradientEnd: "#1B5E20",
        accentColor: "#FFAB00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#A5D6A7",
        backgroundPrimary: "#0D3B16",
        backgroundSecondary: "#1B5E20",
        isLightMode: false
    )
    
    /// Rainbow spectrum - full spectrum of duck colors
    static let ducklingRainbow = ColorPalette(
        id: "duckling_rainbow",
        name: "Duckling Rainbow",
        description: "Full spectrum of vibrant colors",
        colors: [
            "#E53935", "#F57C00", "#FDD835", "#43A047",
            "#1E88E5", "#5E35B1", "#D81B60", "#00ACC1"
        ],
        gradientStart: "#5E35B1",
        gradientEnd: "#311B92",
        accentColor: "#FDD835",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#D1C4E9",
        backgroundPrimary: "#1A0F30",
        backgroundSecondary: "#311B92",
        isLightMode: false
    )
    
    /// Professional corporate colors - wing tips and business
    static let wingTips = ColorPalette(
        id: "wing_tips",
        name: "Wing Tips",
        description: "Clean professional look",
        colors: [
            "#1565C0", "#2E7D32", "#F57F17", "#C62828",
            "#6A1B9A", "#00838F", "#37474F", "#AD1457"
        ],
        gradientStart: "#37474F",
        gradientEnd: "#263238",
        accentColor: "#42A5F5",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#90A4AE",
        backgroundPrimary: "#1C252C",
        backgroundSecondary: "#263238",
        isLightMode: false
    )
    
    /// Autumn harvest - cozy nest egg colors
    static let nestEgg = ColorPalette(
        id: "nest_egg",
        name: "Nest Egg",
        description: "Warm autumn harvest colors",
        colors: [
            "#BF360C", "#E65100", "#F9A825", "#558B2F",
            "#4E342E", "#D84315", "#FF8F00", "#33691E"
        ],
        gradientStart: "#5D4037",
        gradientEnd: "#3E2723",
        accentColor: "#FF8F00",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#BCAAA4",
        backgroundPrimary: "#2C1810",
        backgroundSecondary: "#3E2723",
        isLightMode: false
    )
    
    /// Retro 70s vibes - vintage tail feathers
    static let tailFeathers = ColorPalette(
        id: "tail_feathers",
        name: "Tail Feathers",
        description: "Retro 70s warm contrasts",
        colors: [
            "#D84315", "#FFA000", "#7CB342", "#00897B",
            "#5D4037", "#F4511E", "#C0CA33", "#0097A7"
        ],
        gradientStart: "#8D6E63",
        gradientEnd: "#5D4037",
        accentColor: "#FFA000",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#D7CCC8",
        backgroundPrimary: "#3E2723",
        backgroundSecondary: "#5D4037",
        isLightMode: false
    )
    
    /// Playful candy colors - sweet hatchling vibes
    static let hatchling = ColorPalette(
        id: "hatchling",
        name: "Hatchling",
        description: "Playful sweet candy colors",
        colors: [
            "#D32F2F", "#C2185B", "#7B1FA2", "#512DA8",
            "#1976D2", "#0288D1", "#0097A7", "#00796B"
        ],
        gradientStart: "#AD1457",
        gradientEnd: "#880E4F",
        accentColor: "#FF4081",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#F8BBD0",
        backgroundPrimary: "#4A0028",
        backgroundSecondary: "#880E4F",
        isLightMode: false
    )
    
    /// Elegant monochrome - sleek preening duck
    static let preening = ColorPalette(
        id: "preening",
        name: "Preening",
        description: "Elegant grayscale with accents",
        colors: [
            "#212121", "#424242", "#616161", "#757575",
            "#00BCD4", "#FF5722", "#4CAF50", "#9C27B0"
        ],
        gradientStart: "#424242",
        gradientEnd: "#212121",
        accentColor: "#00BCD4",
        primaryTextColor: "#FFFFFF",
        secondaryTextColor: "#9E9E9E",
        backgroundPrimary: "#121212",
        backgroundSecondary: "#1E1E1E",
        isLightMode: false
    )
    
    // MARK: - All Palettes
    
    static let all: [ColorPalette] = [
        quackClassic, quackAttack, mallardMidnight, goldenEgg, pondRipple,
        featherFrost, waddleSunset, billBright, plumageParadise, rubberDucky,
        drakesJewels, motherGoose, ducklingRainbow, wingTips, nestEgg,
        tailFeathers, hatchling, preening
    ]
    
    static let darkThemes: [ColorPalette] = all
    static let lightThemes: [ColorPalette] = []
}

// Keep backwards compatibility with old name
typealias ColorPalettes = QuackPalettes

// MARK: - Theme Palette View

struct ThemePaletteView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = AppliedThemeManager.shared
    
    @State private var selectedPalette: ColorPalette?
    @State private var isApplying = false
    @State private var showConfirmation = false
    @State private var showSuccess = false
    @State private var showColorReorder = false
    @State private var showAccentPicker = false
    
    private let dataService = DataService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                currentTheme.bgPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Description
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "paintpalette.fill")
                                .font(.largeTitle)
                                .foregroundStyle(currentTheme.accent)
                            
                            Text("Quack Themes")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(currentTheme.textPrimary)
                            
                            Text("Transform your entire app's look and feel")
                                .font(.subheadline)
                                .foregroundStyle(currentTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Theme Customization Buttons (only if a theme is applied)
                        if themeManager.appliedThemeId != nil {
                            VStack(spacing: Theme.Spacing.sm) {
                                // Customize Accent Color Button
                                Button {
                                    showAccentPicker = true
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(currentTheme.accent)
                                            .frame(width: 28, height: 28)
                                            .overlay(
                                                Circle()
                                                    .stroke(currentTheme.textPrimary.opacity(0.3), lineWidth: 2)
                                            )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Customize Accent Color")
                                                .fontWeight(.semibold)
                                            Text(themeManager.customAccentColor != nil ? "Custom accent applied" : "Using theme default")
                                                .font(.caption)
                                                .foregroundStyle(currentTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
                                    }
                                    .foregroundStyle(currentTheme.accent)
                                    .padding(Theme.Spacing.md)
                                    .background(currentTheme.textPrimary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                            .stroke(currentTheme.accent.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                
                                // Customize Color Order Button
                                Button {
                                    showColorReorder = true
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Customize Color Order")
                                                .fontWeight(.semibold)
                                            Text("Reorder category colors in \(themeManager.appliedThemeName ?? "theme")")
                                                .font(.caption)
                                                .foregroundStyle(currentTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
                                    }
                                    .foregroundStyle(currentTheme.accent)
                                    .padding(Theme.Spacing.md)
                                    .background(currentTheme.textPrimary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                            .stroke(currentTheme.accent.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Themes Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("THEMES")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                                ForEach(QuackPalettes.all) { palette in
                                    PaletteCard(
                                        palette: palette,
                                        currentTheme: currentTheme,
                                        isSelected: selectedPalette?.id == palette.id,
                                        isApplied: themeManager.appliedThemeId == palette.id,
                                        isApplying: isApplying && selectedPalette?.id == palette.id,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if selectedPalette?.id == palette.id {
                                                    selectedPalette = nil
                                                } else {
                                                    selectedPalette = palette
                                                }
                                            }
                                        },
                                        onApply: {
                                            selectedPalette = palette
                                            showConfirmation = true
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle("Quack Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(currentTheme.bgPrimary, for: .navigationBar)
            .toolbarColorScheme(currentTheme.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(currentTheme.accent)
                }
            }
            .alert("Apply Theme?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Apply") {
                    applyPalette()
                }
            } message: {
                Text("This will change your app's entire look to \(selectedPalette?.name ?? "the selected theme"), including colors for sectors and categories.")
            }
            .alert("Theme Applied!", isPresented: $showSuccess) {
                Button("OK") {
                    selectedPalette = nil
                }
            } message: {
                Text("Your app has been transformed with the \(themeManager.appliedThemeName ?? "new") theme!")
            }
            .sheet(isPresented: $showColorReorder) {
                ColorReorderView()
            }
            .sheet(isPresented: $showAccentPicker) {
                AccentColorPickerView()
            }
        }
    }
    
    private var currentTheme: ColorPalette {
        themeManager.getCurrentPalette() ?? QuackPalettes.quackClassic
    }
    
    private func applyPalette() {
        guard let palette = selectedPalette else { return }
        
        isApplying = true
        
        Task {
            do {
                // Get the ordered colors (respecting any custom order for this theme)
                let colors = themeManager.getOrderedColors(for: palette.id)
                
                let sectors = authViewModel.sectors
                for (index, sector) in sectors.enumerated() {
                    let colorIndex = index % colors.count
                    let dto = UpdateSectorDTO(color: colors[colorIndex])
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                }
                
                let categories = authViewModel.categories
                for (index, category) in categories.enumerated() {
                    let colorIndex = index % colors.count
                    let dto = UpdateCategoryDTO(color: colors[colorIndex])
                    _ = try await dataService.updateCategory(id: category.id, dto: dto)
                }
                
                await authViewModel.refreshSectors()
                await authViewModel.refreshCategories()
                
                // Save the applied theme for this household
                if let householdId = authViewModel.currentHousehold?.id {
                    themeManager.setAppliedTheme(id: palette.id, name: palette.name, for: householdId)
                }
                
                // Reset any custom accent color when switching themes - user starts fresh with new theme's default
                themeManager.resetAccentColor(for: palette.id)
                
                // Update the ThemeProvider to reflect the new theme immediately
                ThemeProvider.shared.updatePalette(palette)
                
                await MainActor.run {
                    isApplying = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    print("Failed to apply palette: \(error)")
                }
            }
        }
    }
}

// MARK: - Palette Card

struct PaletteCard: View {
    let palette: ColorPalette
    let currentTheme: ColorPalette
    let isSelected: Bool
    var isApplied: Bool = false
    var isApplying: Bool = false
    let onSelect: () -> Void
    var onApply: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Gradient preview showing the theme's actual gradient
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(
                            LinearGradient(
                                colors: palette.previewGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 60)
                        .overlay(
                            HStack(spacing: 4) {
                                ForEach(palette.categoryPreviewColors.indices, id: \.self) { index in
                                    Circle()
                                        .fill(palette.categoryPreviewColors[index])
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle()
                                                .stroke(palette.textPrimary.opacity(0.4), lineWidth: 1)
                                        )
                                }
                                
                                // Accent color indicator
                                Circle()
                                    .fill(palette.accent)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Circle()
                                            .stroke(palette.textPrimary.opacity(0.4), lineWidth: 1)
                                    )
                            }
                            .padding(Theme.Spacing.sm),
                            alignment: .bottomLeading
                        )
                    
                    // Light/Dark mode indicator
                    VStack {
                        HStack {
                            Spacer()
                            if palette.isLightMode {
                                Image(systemName: "sun.max.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                    
                    // Applied badge (top-left)
                    if isApplied && !isSelected {
                        VStack {
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                    Text("Current")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(palette.isLightMode ? .white : palette.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(palette.accent)
                                .clipShape(Capsule())
                                .shadow(radius: 2)
                                
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                    
                    // Apply button (top-right, when selected and not already applied)
                    if isSelected && !isApplied {
                        VStack {
                            HStack {
                                Spacer()
                                Button {
                                    onApply?()
                                } label: {
                                    if isApplying {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.white)
                                            .frame(width: 32, height: 32)
                                            .background(palette.accent)
                                            .clipShape(Circle())
                                            .shadow(radius: 3)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(palette.accent)
                                            .background(
                                                Circle()
                                                    .fill(.white)
                                                    .frame(width: 24, height: 24)
                                            )
                                            .shadow(radius: 3)
                                    }
                                }
                                .disabled(isApplying)
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(palette.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(currentTheme.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if isSelected && !isApplied {
                            Text("Tap ✓")
                                .font(.caption2)
                                .foregroundStyle(currentTheme.accent)
                        }
                    }
                    
                    Text(palette.description)
                        .font(.caption2)
                        .foregroundStyle(currentTheme.textSecondary.opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(currentTheme.textPrimary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(isApplied ? currentTheme.accent : (isSelected ? currentTheme.accent : Color.clear), lineWidth: isApplied || isSelected ? 3 : 0)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Reorder View

struct ColorReorderView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = AppliedThemeManager.shared
    
    @State private var colorOrder: [Int] = []
    @State private var showResetConfirmation = false
    @State private var isApplying = false
    @State private var showSuccess = false
    
    private let dataService = DataService()
    
    private var currentPalette: ColorPalette? {
        themeManager.getCurrentPalette()
    }
    
    private var orderedColors: [String] {
        guard let palette = currentPalette else { return [] }
        return colorOrder.compactMap { index in
            guard index >= 0, index < palette.colors.count else { return nil }
            return palette.colors[index]
        }
    }
    
    private var currentTheme: ColorPalette {
        themeManager.getCurrentPalette() ?? QuackPalettes.quackClassic
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                currentTheme.bgPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Instructions
                    HStack {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(currentTheme.accent)
                        Text("Drag colors to reorder • New items use this order")
                            .font(.caption)
                            .foregroundStyle(currentTheme.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    
                    // Color List
                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ReorderableColorList(
                                colors: orderedColors,
                                currentTheme: currentTheme,
                                onMove: { from, to in
                                    colorOrder.move(fromOffsets: from, toOffset: to)
                                }
                            )
                        }
                        .padding(Theme.Spacing.md)
                    }
                    
                    // Action Buttons
                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            applyColorOrder()
                        } label: {
                            if isApplying {
                                ProgressView()
                                    .tint(currentTheme.isLightMode ? .white : currentTheme.textPrimary)
                            } else {
                                Label("Apply Color Order", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isApplying)
                        
                        Button {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset to Default Order", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                        .foregroundStyle(currentTheme.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Customize Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(currentTheme.bgPrimary, for: .navigationBar)
            .toolbarColorScheme(currentTheme.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(currentTheme.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shuffleColors()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .foregroundStyle(currentTheme.accent)
                }
            }
            .onAppear {
                loadCurrentOrder()
            }
            .alert("Reset Color Order?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset") {
                    resetColorOrder()
                }
            } message: {
                Text("This will restore the default color order for \(currentPalette?.name ?? "this theme").")
            }
            .alert("Colors Updated!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your sectors and categories have been updated with the new color order.")
            }
        }
    }
    
    private func loadCurrentOrder() {
        guard let palette = currentPalette else { return }
        
        // Load existing order or create default
        if let existingOrder = themeManager.getCustomColorOrder(for: palette.id) {
            colorOrder = existingOrder
        } else {
            colorOrder = Array(0..<palette.colors.count)
        }
    }
    
    private func shuffleColors() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            colorOrder.shuffle()
        }
    }
    
    private func resetColorOrder() {
        guard let palette = currentPalette else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            colorOrder = Array(0..<palette.colors.count)
        }
        
        themeManager.resetColorOrder(for: palette.id)
    }
    
    private func applyColorOrder() {
        guard let palette = currentPalette else { return }
        
        isApplying = true
        
        // Save the new order
        themeManager.saveCustomColorOrder(for: palette.id, order: colorOrder)
        
        Task {
            do {
                // Apply new colors to existing sectors
                let sectors = authViewModel.sectors
                for (index, sector) in sectors.enumerated() {
                    let colorIndex = index % orderedColors.count
                    let dto = UpdateSectorDTO(color: orderedColors[colorIndex])
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                }
                
                // Apply new colors to existing categories
                let categories = authViewModel.categories
                for (index, category) in categories.enumerated() {
                    let colorIndex = index % orderedColors.count
                    let dto = UpdateCategoryDTO(color: orderedColors[colorIndex])
                    _ = try await dataService.updateCategory(id: category.id, dto: dto)
                }
                
                await authViewModel.refreshSectors()
                await authViewModel.refreshCategories()
                
                await MainActor.run {
                    isApplying = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    print("Failed to apply color order: \(error)")
                }
            }
        }
    }
}

// MARK: - Reorderable Color List

struct ReorderableColorList: View {
    let colors: [String]
    let currentTheme: ColorPalette
    let onMove: (IndexSet, Int) -> Void
    
    var body: some View {
        ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
            HStack(spacing: Theme.Spacing.md) {
                // Position number
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
                    .frame(width: 24)
                
                // Color swatch
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(currentTheme.textPrimary.opacity(0.2), lineWidth: 1)
                    )
                
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(currentTheme.textPrimary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .draggable("\(index)") {
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                    .frame(width: 60, height: 40)
                    .opacity(0.8)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let draggedItem = items.first,
                      let fromIndex = Int(draggedItem),
                      fromIndex != index,
                      fromIndex >= 0,
                      fromIndex < colors.count else {
                    return false
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onMove(IndexSet(integer: fromIndex), index > fromIndex ? index + 1 : index)
                }
                return true
            }
        }
    }
}

// MARK: - Accent Color Picker View

struct AccentColorPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = AppliedThemeManager.shared
    
    @State private var selectedColor: String?
    @State private var showResetConfirmation = false
    
    private var currentTheme: ColorPalette {
        themeManager.getCurrentPalette() ?? QuackPalettes.quackClassic
    }
    
    private var basePalette: ColorPalette? {
        guard let themeId = themeManager.appliedThemeId else { return nil }
        return QuackPalettes.all.first(where: { $0.id == themeId })
    }
    
    private var availableColors: [String] {
        guard let palette = basePalette else { return [] }
        return themeManager.getAvailableAccentColors(for: palette)
    }
    
    private var defaultAccentColor: String {
        basePalette?.accentColor ?? "#FFCA28"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                currentTheme.bgPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Preview of current accent
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Accent Color Preview")
                            .font(.headline)
                            .foregroundStyle(currentTheme.textPrimary)
                        
                        // Sample button showing accent color - using selected color directly
                        Text("Sample Button")
                            .font(.headline)
                            .foregroundStyle(contrastingTextColor(for: selectedColor ?? defaultAccentColor))
                            .frame(width: 200)
                            .padding(Theme.Spacing.md)
                            .background(Color(hex: (selectedColor ?? defaultAccentColor).replacingOccurrences(of: "#", with: "")))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        
                        // Sample accent elements
                        HStack(spacing: Theme.Spacing.md) {
                            Circle()
                                .fill(Color(hex: (selectedColor ?? defaultAccentColor).replacingOccurrences(of: "#", with: "")))
                                .frame(width: 40, height: 40)
                            
                            Text("Accent Color")
                                .foregroundStyle(Color(hex: (selectedColor ?? defaultAccentColor).replacingOccurrences(of: "#", with: "")))
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .background(currentTheme.textPrimary.opacity(0.05))
                    
                    // Color grid
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("CHOOSE ACCENT COLOR")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(currentTheme.textSecondary.opacity(0.6))
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: Theme.Spacing.md) {
                                ForEach(availableColors, id: \.self) { color in
                                    AccentColorCell(
                                        color: color,
                                        isSelected: (selectedColor ?? themeManager.customAccentColor ?? defaultAccentColor) == color,
                                        isDefault: color == defaultAccentColor,
                                        currentTheme: currentTheme
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedColor = color
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    
                    // Action buttons
                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            applyAccentColor()
                        } label: {
                            Label("Apply Accent Color", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedColor == nil)
                        
                        if themeManager.customAccentColor != nil {
                            Button {
                                showResetConfirmation = true
                            } label: {
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(currentTheme.textSecondary)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Accent Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(currentTheme.bgPrimary, for: .navigationBar)
            .toolbarColorScheme(currentTheme.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(currentTheme.textSecondary)
                }
            }
            .alert("Reset Accent Color?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset") {
                    resetAccentColor()
                }
            } message: {
                Text("This will restore the default accent color for \(themeManager.appliedThemeName ?? "this theme").")
            }
            .onAppear {
                selectedColor = themeManager.customAccentColor ?? defaultAccentColor
            }
        }
    }
    
    private func applyAccentColor() {
        guard let color = selectedColor,
              let themeId = themeManager.appliedThemeId else { return }
        
        // If selecting the default color, reset instead
        if color == defaultAccentColor {
            themeManager.resetAccentColor(for: themeId)
        } else {
            themeManager.saveCustomAccentColor(for: themeId, color: color)
        }
        
        // Update the ThemeProvider
        ThemeProvider.shared.updatePalette(themeManager.getCurrentPalette())
        
        dismiss()
    }
    
    private func resetAccentColor() {
        guard let themeId = themeManager.appliedThemeId else { return }
        themeManager.resetAccentColor(for: themeId)
        selectedColor = defaultAccentColor
        
        // Update the ThemeProvider
        ThemeProvider.shared.updatePalette(themeManager.getCurrentPalette())
        
        dismiss()
    }
    
    /// Returns black or white text color based on background luminance
    private func contrastingTextColor(for hex: String) -> Color {
        let cleanHex = hex.replacingOccurrences(of: "#", with: "")
        guard cleanHex.count == 6,
              let rgb = Int(cleanHex, radix: 16) else { return .white }
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        // Calculate relative luminance
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5 ? Color(hex: "212121") : .white
    }
}

// MARK: - Accent Color Cell

struct AccentColorCell: View {
    let color: String
    let isSelected: Bool
    let isDefault: Bool
    let currentTheme: ColorPalette
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? currentTheme.textPrimary : currentTheme.textPrimary.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                    )
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(isColorLight(color) ? .black : .white)
                }
                
                if isDefault && !isSelected {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("★")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    /// Check if a color is light (for contrast)
    private func isColorLight(_ hex: String) -> Bool {
        let cleanHex = hex.replacingOccurrences(of: "#", with: "")
        guard cleanHex.count == 6,
              let rgb = Int(cleanHex, radix: 16) else { return false }
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        
        // Calculate relative luminance
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5
    }
}

// MARK: - Preview

#Preview {
    ThemePaletteView()
        .environment(AuthViewModel())
}
