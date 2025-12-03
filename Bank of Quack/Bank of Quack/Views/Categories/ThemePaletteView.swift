import SwiftUI
import Combine

// MARK: - Color Palette Model

struct ColorPalette: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let sectorColors: [String]
    let categoryColors: [String]
    
    var previewGradient: [Color] {
        let colors = sectorColors.prefix(3)
        return colors.map { Color(hex: $0.replacingOccurrences(of: "#", with: "")) }
    }
    
    var allColors: [String] {
        sectorColors + categoryColors
    }
    
    init(id: String, name: String, description: String, sectorColors: [String], categoryColors: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.sectorColors = sectorColors
        self.categoryColors = categoryColors
    }
}

// MARK: - Applied Theme Manager

class AppliedThemeManager: ObservableObject {
    static let shared = AppliedThemeManager()
    
    @Published var appliedThemeId: String?
    @Published var appliedThemeName: String?
    
    private let themeIdKey = "appliedThemeId"
    private let themeNameKey = "appliedThemeName"
    private let colorOrderPrefix = "themeColorOrder_"
    
    init() {
        appliedThemeId = UserDefaults.standard.string(forKey: themeIdKey)
        appliedThemeName = UserDefaults.standard.string(forKey: themeNameKey)
    }
    
    func setAppliedTheme(id: String, name: String) {
        appliedThemeId = id
        appliedThemeName = name
        UserDefaults.standard.set(id, forKey: themeIdKey)
        UserDefaults.standard.set(name, forKey: themeNameKey)
    }
    
    func clearAppliedTheme() {
        appliedThemeId = nil
        appliedThemeName = nil
        UserDefaults.standard.removeObject(forKey: themeIdKey)
        UserDefaults.standard.removeObject(forKey: themeNameKey)
    }
    
    /// Sets "Quack Classic" as the default theme if no theme is currently applied
    func setDefaultThemeIfNeeded() {
        if appliedThemeId == nil {
            setAppliedTheme(id: "quack", name: "Quack Classic")
        }
    }
    
    // MARK: - Custom Color Order
    
    /// Get the custom color order for a theme, or nil if using default order
    func getCustomColorOrder(for themeId: String, colorType: ColorType) -> [Int]? {
        let key = colorOrderPrefix + themeId + "_" + colorType.rawValue
        return UserDefaults.standard.array(forKey: key) as? [Int]
    }
    
    /// Save a custom color order for a theme
    func saveCustomColorOrder(for themeId: String, colorType: ColorType, order: [Int]) {
        let key = colorOrderPrefix + themeId + "_" + colorType.rawValue
        UserDefaults.standard.set(order, forKey: key)
    }
    
    /// Reset color order to default for a theme
    func resetColorOrder(for themeId: String, colorType: ColorType) {
        let key = colorOrderPrefix + themeId + "_" + colorType.rawValue
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    /// Reset all color orders for a theme
    func resetAllColorOrders(for themeId: String) {
        resetColorOrder(for: themeId, colorType: .sector)
        resetColorOrder(for: themeId, colorType: .category)
    }
    
    enum ColorType: String {
        case sector
        case category
    }
    
    /// Get the current theme palette
    func getCurrentPalette() -> ColorPalette? {
        guard let themeId = appliedThemeId else { return nil }
        return ColorPalettes.all.first(where: { $0.id == themeId })
    }
    
    /// Get colors in the custom order (or default if no custom order)
    func getOrderedColors(for themeId: String, colorType: ColorType) -> [String] {
        guard let palette = ColorPalettes.all.first(where: { $0.id == themeId }) else { return [] }
        
        let baseColors = colorType == .sector ? palette.sectorColors : palette.categoryColors
        
        guard let customOrder = getCustomColorOrder(for: themeId, colorType: colorType),
              customOrder.count == baseColors.count else {
            return baseColors
        }
        
        // Reorder based on custom indices
        return customOrder.compactMap { index in
            guard index >= 0, index < baseColors.count else { return nil }
            return baseColors[index]
        }
    }
    
    /// Get the next sector color based on current sector count
    func getNextSectorColor(sectorCount: Int) -> String? {
        guard let themeId = appliedThemeId else { return nil }
        let colors = getOrderedColors(for: themeId, colorType: .sector)
        guard !colors.isEmpty else { return nil }
        return colors[sectorCount % colors.count]
    }
    
    /// Get the next category color based on current category count
    func getNextCategoryColor(categoryCount: Int) -> String? {
        guard let themeId = appliedThemeId else { return nil }
        let colors = getOrderedColors(for: themeId, colorType: .category)
        guard !colors.isEmpty else { return nil }
        return colors[categoryCount % colors.count]
    }
}

// MARK: - Predefined Palettes

enum ColorPalettes {
    // Diverse/Rainbow palettes
    static let rainbow = ColorPalette(
        id: "rainbow",
        name: "Rainbow Spectrum",
        description: "Full spectrum of vibrant colors",
        sectorColors: [
            "#E53935", "#F57C00", "#FDD835", "#43A047",
            "#1E88E5", "#5E35B1", "#D81B60", "#00ACC1"
        ],
        categoryColors: [
            "#EF5350", "#FF9800", "#FFEE58", "#66BB6A",
            "#42A5F5", "#7E57C2", "#EC407A", "#26C6DA"
        ]
    )
    
    static let jewels = ColorPalette(
        id: "jewels",
        name: "Precious Jewels",
        description: "Rich gemstone-inspired colors",
        sectorColors: [
            "#B71C1C", "#1A237E", "#004D40", "#E65100",
            "#4A148C", "#006064", "#880E4F", "#33691E"
        ],
        categoryColors: [
            "#D32F2F", "#303F9F", "#00796B", "#F57C00",
            "#7B1FA2", "#0097A7", "#C2185B", "#558B2F"
        ]
    )
    
    static let tropical = ColorPalette(
        id: "tropical",
        name: "Tropical Paradise",
        description: "Vibrant island-inspired hues",
        sectorColors: [
            "#FF6F00", "#00BFA5", "#F50057", "#00B0FF",
            "#FFD600", "#64DD17", "#AA00FF", "#FF3D00"
        ],
        categoryColors: [
            "#FFAB00", "#1DE9B6", "#FF4081", "#40C4FF",
            "#FFFF00", "#76FF03", "#E040FB", "#FF6E40"
        ]
    )
    
    static let pastel = ColorPalette(
        id: "pastel",
        name: "Soft Pastels",
        description: "Gentle, muted tones",
        sectorColors: [
            "#F8BBD0", "#B3E5FC", "#C8E6C9", "#FFE0B2",
            "#E1BEE7", "#B2EBF2", "#FFCCBC", "#D1C4E9"
        ],
        categoryColors: [
            "#FCE4EC", "#E1F5FE", "#E8F5E9", "#FFF3E0",
            "#F3E5F5", "#E0F7FA", "#FBE9E7", "#EDE7F6"
        ]
    )
    
    static let retro = ColorPalette(
        id: "retro",
        name: "Retro Vibes",
        description: "70s inspired warm contrasts",
        sectorColors: [
            "#D84315", "#FFA000", "#7CB342", "#00897B",
            "#5D4037", "#F4511E", "#C0CA33", "#0097A7"
        ],
        categoryColors: [
            "#FF7043", "#FFC107", "#8BC34A", "#26A69A",
            "#795548", "#FF8A65", "#CDDC39", "#00BCD4"
        ]
    )
    
    static let cyberpunk = ColorPalette(
        id: "cyberpunk",
        name: "Cyberpunk",
        description: "Futuristic neon contrasts",
        sectorColors: [
            "#00FFFF", "#FF00FF", "#FFFF00", "#00FF00",
            "#FF0080", "#8000FF", "#FF8000", "#0080FF"
        ],
        categoryColors: [
            "#00E5FF", "#EA80FC", "#EEFF41", "#69F0AE",
            "#FF4081", "#B388FF", "#FFD180", "#82B1FF"
        ]
    )
    
    static let autumn = ColorPalette(
        id: "autumn",
        name: "Autumn Harvest",
        description: "Warm fall colors with contrast",
        sectorColors: [
            "#BF360C", "#E65100", "#F9A825", "#558B2F",
            "#4E342E", "#D84315", "#FF8F00", "#33691E"
        ],
        categoryColors: [
            "#FF5722", "#FF9800", "#FFC107", "#8BC34A",
            "#795548", "#FF7043", "#FFB300", "#689F38"
        ]
    )
    
    static let ocean = ColorPalette(
        id: "ocean",
        name: "Ocean Depths",
        description: "Cool blues and teals",
        sectorColors: [
            "#0D47A1", "#1565C0", "#1976D2", "#1E88E5",
            "#006064", "#00838F", "#0097A7", "#00ACC1"
        ],
        categoryColors: [
            "#42A5F5", "#64B5F6", "#90CAF9", "#BBDEFB",
            "#26C6DA", "#4DD0E1", "#80DEEA", "#B2EBF2"
        ]
    )
    
    static let midnight = ColorPalette(
        id: "midnight",
        name: "Midnight Galaxy",
        description: "Deep space colors with stars",
        sectorColors: [
            "#1A237E", "#4A148C", "#311B92", "#0D47A1",
            "#880E4F", "#006064", "#263238", "#4527A0"
        ],
        categoryColors: [
            "#3F51B5", "#9C27B0", "#673AB7", "#2196F3",
            "#E91E63", "#009688", "#607D8B", "#7C4DFF"
        ]
    )
    
    static let garden = ColorPalette(
        id: "garden",
        name: "Spring Garden",
        description: "Fresh floral palette",
        sectorColors: [
            "#C2185B", "#7B1FA2", "#388E3C", "#F57C00",
            "#1976D2", "#D32F2F", "#00796B", "#FBC02D"
        ],
        categoryColors: [
            "#E91E63", "#9C27B0", "#4CAF50", "#FF9800",
            "#2196F3", "#F44336", "#009688", "#FFEB3B"
        ]
    )
    
    static let monochrome = ColorPalette(
        id: "monochrome",
        name: "Monochrome Mix",
        description: "Elegant grayscale with accents",
        sectorColors: [
            "#212121", "#424242", "#616161", "#757575",
            "#00BCD4", "#FF5722", "#4CAF50", "#9C27B0"
        ],
        categoryColors: [
            "#9E9E9E", "#BDBDBD", "#E0E0E0", "#EEEEEE",
            "#26C6DA", "#FF7043", "#66BB6A", "#AB47BC"
        ]
    )
    
    static let sunset = ColorPalette(
        id: "sunset",
        name: "Golden Sunset",
        description: "Warm dusk colors",
        sectorColors: [
            "#BF360C", "#D84315", "#E64A19", "#F4511E",
            "#E65100", "#EF6C00", "#F57C00", "#FB8C00"
        ],
        categoryColors: [
            "#FF7043", "#FF8A65", "#FFAB91", "#FFCCBC",
            "#FFA726", "#FFB74D", "#FFCC80", "#FFE0B2"
        ]
    )
    
    static let neon = ColorPalette(
        id: "neon",
        name: "Neon Nights",
        description: "Electric bold colors",
        sectorColors: [
            "#00E676", "#00E5FF", "#651FFF", "#D500F9",
            "#FF1744", "#F50057", "#FF9100", "#FFEA00"
        ],
        categoryColors: [
            "#69F0AE", "#84FFFF", "#B388FF", "#EA80FC",
            "#FF8A80", "#FF80AB", "#FFD180", "#FFFF8D"
        ]
    )
    
    static let corporate = ColorPalette(
        id: "corporate",
        name: "Professional",
        description: "Clean business colors",
        sectorColors: [
            "#1565C0", "#2E7D32", "#F57F17", "#C62828",
            "#6A1B9A", "#00838F", "#37474F", "#AD1457"
        ],
        categoryColors: [
            "#1976D2", "#388E3C", "#F9A825", "#D32F2F",
            "#7B1FA2", "#0097A7", "#546E7A", "#C2185B"
        ]
    )
    
    static let candy = ColorPalette(
        id: "candy",
        name: "Candy Shop",
        description: "Playful sweet colors",
        sectorColors: [
            "#D32F2F", "#C2185B", "#7B1FA2", "#512DA8",
            "#1976D2", "#0288D1", "#0097A7", "#00796B"
        ],
        categoryColors: [
            "#F44336", "#E91E63", "#9C27B0", "#673AB7",
            "#2196F3", "#03A9F4", "#00BCD4", "#009688"
        ]
    )
    
    static let nordic = ColorPalette(
        id: "nordic",
        name: "Nordic Frost",
        description: "Cool Scandinavian tones",
        sectorColors: [
            "#37474F", "#455A64", "#546E7A", "#607D8B",
            "#0277BD", "#0288D1", "#039BE5", "#03A9F4"
        ],
        categoryColors: [
            "#78909C", "#90A4AE", "#B0BEC5", "#CFD8DC",
            "#4FC3F7", "#81D4FA", "#B3E5FC", "#E1F5FE"
        ]
    )
    
    static let quack = ColorPalette(
        id: "quack",
        name: "Quack Classic",
        description: "Signature teal and gold palette",
        sectorColors: [
            "#00796B", "#F9A825", "#26A69A", "#FBC02D",
            "#4DB6AC", "#FFCA28", "#00897B", "#FFD54F"
        ],
        categoryColors: [
            "#80CBC4", "#FFEB3B", "#B2DFDB", "#FFF176",
            "#E0F2F1", "#FFF59D", "#A5D6A7", "#FFFDE7"
        ]
    )
    
    static let quackVibrant = ColorPalette(
        id: "quack_vibrant",
        name: "Quack Vibrant",
        description: "Bold teal, gold, and accent pops",
        sectorColors: [
            "#004D40", "#F57F17", "#00695C", "#F9A825",
            "#00897B", "#FBC02D", "#26A69A", "#FFCA28"
        ],
        categoryColors: [
            "#4DB6AC", "#FFD54F", "#80CBC4", "#FFEB3B",
            "#B2DFDB", "#FFF176", "#E0F2F1", "#FFF59D"
        ]
    )
    
    static let all: [ColorPalette] = [
        quack, quackVibrant, rainbow, jewels, tropical, cyberpunk, neon, pastel,
        garden, autumn, retro, midnight, sunset, ocean,
        corporate, candy, nordic, monochrome
    ]
}

// MARK: - Theme Palette View

struct ThemePaletteView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPalette: ColorPalette?
    @State private var isApplying = false
    @State private var showConfirmation = false
    @State private var showSuccess = false
    @State private var showColorReorder = false
    
    private let dataService = DataService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Description
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "paintpalette.fill")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("Color Themes")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Choose a theme to color your sectors and categories")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Customize Color Order Button (only if a theme is applied)
                        if AppliedThemeManager.shared.appliedThemeId != nil {
                            Button {
                                showColorReorder = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Customize Color Order")
                                            .fontWeight(.semibold)
                                        Text("Reorder colors within \(AppliedThemeManager.shared.appliedThemeName ?? "theme")")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Themes Grid
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("THEMES")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                                ForEach(ColorPalettes.all) { palette in
                                    PaletteCard(
                                        palette: palette,
                                        isSelected: selectedPalette?.id == palette.id,
                                        isApplied: AppliedThemeManager.shared.appliedThemeId == palette.id,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedPalette = palette
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Apply Button
                        if selectedPalette != nil {
                            VStack(spacing: Theme.Spacing.sm) {
                                Button {
                                    showConfirmation = true
                                } label: {
                                    if isApplying {
                                        ProgressView()
                                            .tint(Theme.Colors.textInverse)
                                    } else {
                                        Label("Apply \(selectedPalette?.name ?? "Theme")", systemImage: "paintbrush.fill")
                                    }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(isApplying)
                                
                                Text("Updates \(authViewModel.sectors.count) sectors and \(authViewModel.categories.count) categories")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.md)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Color Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .alert("Apply Theme?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Apply") {
                    applyPalette()
                }
            } message: {
                Text("This will change the colors of all your sectors and categories to match the \(selectedPalette?.name ?? "selected") theme.")
            }
            .alert("Theme Applied!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your sectors and categories have been updated with the new color theme.")
            }
            .sheet(isPresented: $showColorReorder) {
                ColorReorderView()
            }
        }
    }
    
    private func applyPalette() {
        guard let palette = selectedPalette else { return }
        
        isApplying = true
        
        Task {
            do {
                // Get the ordered colors (respecting any custom order for this theme)
                let sectorColors = AppliedThemeManager.shared.getOrderedColors(for: palette.id, colorType: .sector)
                let categoryColors = AppliedThemeManager.shared.getOrderedColors(for: palette.id, colorType: .category)
                
                let sectors = authViewModel.sectors
                for (index, sector) in sectors.enumerated() {
                    let colorIndex = index % sectorColors.count
                    let dto = UpdateSectorDTO(color: sectorColors[colorIndex])
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                }
                
                let categories = authViewModel.categories
                for (index, category) in categories.enumerated() {
                    let colorIndex = index % categoryColors.count
                    let dto = UpdateCategoryDTO(color: categoryColors[colorIndex])
                    _ = try await dataService.updateCategory(id: category.id, dto: dto)
                }
                
                await authViewModel.refreshSectors()
                await authViewModel.refreshCategories()
                
                // Save the applied theme
                AppliedThemeManager.shared.setAppliedTheme(id: palette.id, name: palette.name)
                
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
    let isSelected: Bool
    var isApplied: Bool = false
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Gradient preview
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(
                            LinearGradient(
                                colors: palette.previewGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 60)
                        .overlay(
                            HStack(spacing: 4) {
                                ForEach(palette.sectorColors.prefix(4), id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(Theme.Spacing.sm),
                            alignment: .bottomLeading
                        )
                    
                    // Applied badge (top-left)
                    if isApplied {
                        VStack {
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                    Text("Applied")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.accent)
                                .clipShape(Capsule())
                                .shadow(radius: 2)
                                
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(palette.description)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .stroke(isApplied ? Theme.Colors.accent : (isSelected ? Theme.Colors.accent.opacity(0.5) : Color.clear), lineWidth: isApplied ? 3 : 2)
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
    
    @State private var sectorColorOrder: [Int] = []
    @State private var categoryColorOrder: [Int] = []
    @State private var selectedTab: AppliedThemeManager.ColorType = .sector
    @State private var showResetConfirmation = false
    @State private var isApplying = false
    @State private var showSuccess = false
    
    private let dataService = DataService()
    
    private var currentPalette: ColorPalette? {
        AppliedThemeManager.shared.getCurrentPalette()
    }
    
    private var orderedSectorColors: [String] {
        guard let palette = currentPalette else { return [] }
        return sectorColorOrder.compactMap { index in
            guard index >= 0, index < palette.sectorColors.count else { return nil }
            return palette.sectorColors[index]
        }
    }
    
    private var orderedCategoryColors: [String] {
        guard let palette = currentPalette else { return [] }
        return categoryColorOrder.compactMap { index in
            guard index >= 0, index < palette.categoryColors.count else { return nil }
            return palette.categoryColors[index]
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("Color Type", selection: $selectedTab) {
                        Text("Sector Colors").tag(AppliedThemeManager.ColorType.sector)
                        Text("Category Colors").tag(AppliedThemeManager.ColorType.category)
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.Spacing.md)
                    
                    // Instructions
                    HStack {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Drag colors to reorder • New items use this order")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    
                    // Color List
                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            if selectedTab == .sector {
                                ReorderableColorList(
                                    colors: orderedSectorColors,
                                    onMove: { from, to in
                                        sectorColorOrder.move(fromOffsets: from, toOffset: to)
                                    }
                                )
                            } else {
                                ReorderableColorList(
                                    colors: orderedCategoryColors,
                                    onMove: { from, to in
                                        categoryColorOrder.move(fromOffsets: from, toOffset: to)
                                    }
                                )
                            }
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
                                    .tint(Theme.Colors.textInverse)
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
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Customize Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shuffleColors()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .foregroundStyle(Theme.Colors.accent)
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
        if let existingOrder = AppliedThemeManager.shared.getCustomColorOrder(for: palette.id, colorType: .sector) {
            sectorColorOrder = existingOrder
        } else {
            sectorColorOrder = Array(0..<palette.sectorColors.count)
        }
        
        if let existingOrder = AppliedThemeManager.shared.getCustomColorOrder(for: palette.id, colorType: .category) {
            categoryColorOrder = existingOrder
        } else {
            categoryColorOrder = Array(0..<palette.categoryColors.count)
        }
    }
    
    private func shuffleColors() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedTab == .sector {
                sectorColorOrder.shuffle()
            } else {
                categoryColorOrder.shuffle()
            }
        }
    }
    
    private func resetColorOrder() {
        guard let palette = currentPalette else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            sectorColorOrder = Array(0..<palette.sectorColors.count)
            categoryColorOrder = Array(0..<palette.categoryColors.count)
        }
        
        AppliedThemeManager.shared.resetAllColorOrders(for: palette.id)
    }
    
    private func applyColorOrder() {
        guard let palette = currentPalette else { return }
        
        isApplying = true
        
        // Save the new order
        AppliedThemeManager.shared.saveCustomColorOrder(for: palette.id, colorType: .sector, order: sectorColorOrder)
        AppliedThemeManager.shared.saveCustomColorOrder(for: palette.id, colorType: .category, order: categoryColorOrder)
        
        Task {
            do {
                // Apply new colors to existing sectors
                let sectors = authViewModel.sectors
                for (index, sector) in sectors.enumerated() {
                    let colorIndex = index % orderedSectorColors.count
                    let dto = UpdateSectorDTO(color: orderedSectorColors[colorIndex])
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                }
                
                // Apply new colors to existing categories
                let categories = authViewModel.categories
                for (index, category) in categories.enumerated() {
                    let colorIndex = index % orderedCategoryColors.count
                    let dto = UpdateCategoryDTO(color: orderedCategoryColors[colorIndex])
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
    let onMove: (IndexSet, Int) -> Void
    
    var body: some View {
        ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
            HStack(spacing: Theme.Spacing.md) {
                // Position number
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(width: 24)
                
                // Color swatch
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.backgroundCard)
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

// MARK: - Preview

#Preview {
    ThemePaletteView()
        .environment(AuthViewModel())
}
