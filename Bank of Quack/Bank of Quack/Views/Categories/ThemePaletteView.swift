import SwiftUI
import Combine

// MARK: - Color Palette Model

struct ColorPalette: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let sectorColors: [String]
    let categoryColors: [String]
    let isCustom: Bool
    
    var previewGradient: [Color] {
        let colors = sectorColors.prefix(3)
        return colors.map { Color(hex: $0.replacingOccurrences(of: "#", with: "")) }
    }
    
    var allColors: [String] {
        sectorColors + categoryColors
    }
    
    init(id: String, name: String, description: String, sectorColors: [String], categoryColors: [String], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.sectorColors = sectorColors
        self.categoryColors = categoryColors
        self.isCustom = isCustom
    }
}

// MARK: - Custom Theme Storage

class CustomThemeStorage: ObservableObject {
    @Published var customThemes: [ColorPalette] = []
    
    private let storageKey = "customColorThemes"
    
    init() {
        loadThemes()
    }
    
    func loadThemes() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let themes = try? JSONDecoder().decode([ColorPalette].self, from: data) {
            customThemes = themes
        }
    }
    
    func saveTheme(_ theme: ColorPalette) {
        // Remove existing theme with same id if updating
        customThemes.removeAll { $0.id == theme.id }
        customThemes.append(theme)
        persist()
    }
    
    func deleteTheme(id: String) {
        customThemes.removeAll { $0.id == id }
        persist()
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Applied Theme Manager

class AppliedThemeManager: ObservableObject {
    static let shared = AppliedThemeManager()
    
    @Published var appliedThemeId: String?
    @Published var appliedThemeName: String?
    
    private let themeIdKey = "appliedThemeId"
    private let themeNameKey = "appliedThemeName"
    
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
    
    /// Get the current theme palette (built-in or custom)
    func getCurrentPalette(customStorage: CustomThemeStorage) -> ColorPalette? {
        guard let themeId = appliedThemeId else { return nil }
        
        // Check built-in themes first
        if let builtIn = ColorPalettes.all.first(where: { $0.id == themeId }) {
            return builtIn
        }
        
        // Check custom themes
        return customStorage.customThemes.first(where: { $0.id == themeId })
    }
    
    /// Get the next sector color based on current sector count
    func getNextSectorColor(sectorCount: Int, customStorage: CustomThemeStorage) -> String? {
        guard let palette = getCurrentPalette(customStorage: customStorage) else { return nil }
        let index = sectorCount % palette.sectorColors.count
        return palette.sectorColors[index]
    }
    
    /// Get the next category color based on current category count
    func getNextCategoryColor(categoryCount: Int, customStorage: CustomThemeStorage) -> String? {
        guard let palette = getCurrentPalette(customStorage: customStorage) else { return nil }
        let index = categoryCount % palette.categoryColors.count
        return palette.categoryColors[index]
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
    
    @StateObject private var customStorage = CustomThemeStorage()
    @State private var selectedPalette: ColorPalette?
    @State private var isApplying = false
    @State private var showConfirmation = false
    @State private var showSuccess = false
    @State private var showCustomThemeBuilder = false
    @State private var editingCustomTheme: ColorPalette?
    @State private var showDeleteConfirmation = false
    @State private var themeToDelete: ColorPalette?
    
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
                            
                            Text("Select a theme or create your own custom palette")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Custom Theme Button
                        Button {
                            editingCustomTheme = nil
                            showCustomThemeBuilder = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                Text("Create Custom Theme")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                    .stroke(Theme.Colors.accent.opacity(0.5), lineWidth: 2)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            )
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Custom Themes Section
                        if !customStorage.customThemes.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("YOUR THEMES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                                    ForEach(customStorage.customThemes) { palette in
                                        PaletteCard(
                                            palette: palette,
                                            isSelected: selectedPalette?.id == palette.id,
                                            isCustom: true,
                                            onSelect: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    selectedPalette = palette
                                                }
                                            },
                                            onEdit: {
                                                editingCustomTheme = palette
                                                showCustomThemeBuilder = true
                                            },
                                            onDelete: {
                                                themeToDelete = palette
                                                showDeleteConfirmation = true
                                            },
                                            onDuplicate: {
                                                duplicateTheme(palette)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Built-in Themes Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("BUILT-IN THEMES")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                                ForEach(ColorPalettes.all) { palette in
                                    PaletteCard(
                                        palette: palette,
                                        isSelected: selectedPalette?.id == palette.id,
                                        isCustom: false,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedPalette = palette
                                            }
                                        },
                                        onDuplicate: {
                                            duplicateTheme(palette)
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
            .alert("Delete Theme?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { themeToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let theme = themeToDelete {
                        customStorage.deleteTheme(id: theme.id)
                        if selectedPalette?.id == theme.id {
                            selectedPalette = nil
                        }
                    }
                    themeToDelete = nil
                }
            } message: {
                Text("This will permanently delete \"\(themeToDelete?.name ?? "this theme")\".")
            }
            .sheet(isPresented: $showCustomThemeBuilder) {
                CustomThemeBuilderView(
                    existingTheme: editingCustomTheme,
                    onSave: { theme in
                        customStorage.saveTheme(theme)
                        showCustomThemeBuilder = false
                    }
                )
            }
        }
    }
    
    private func duplicateTheme(_ palette: ColorPalette) {
        let newTheme = ColorPalette(
            id: UUID().uuidString,
            name: "\(palette.name) Copy",
            description: palette.description,
            sectorColors: palette.sectorColors,
            categoryColors: palette.categoryColors,
            isCustom: true
        )
        editingCustomTheme = newTheme
        showCustomThemeBuilder = true
    }
    
    private func applyPalette() {
        guard let palette = selectedPalette else { return }
        
        isApplying = true
        
        Task {
            do {
                let sectors = authViewModel.sectors
                for (index, sector) in sectors.enumerated() {
                    let colorIndex = index % palette.sectorColors.count
                    let dto = UpdateSectorDTO(color: palette.sectorColors[colorIndex])
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                }
                
                let categories = authViewModel.categories
                for (index, category) in categories.enumerated() {
                    let colorIndex = index % palette.categoryColors.count
                    let dto = UpdateCategoryDTO(color: palette.categoryColors[colorIndex])
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
    var isCustom: Bool = false
    let onSelect: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Gradient preview
                ZStack(alignment: .topTrailing) {
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
                    
                    // Action buttons
                    HStack(spacing: 4) {
                        // Duplicate button (for all themes)
                        if onDuplicate != nil {
                            Button {
                                onDuplicate?()
                            } label: {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                        
                        // Edit/Delete buttons for custom themes only
                        if isCustom {
                            Button {
                                onEdit?()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                            
                            Button {
                                onDelete?()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(4)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(palette.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        if isCustom {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    
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
                    .stroke(isSelected ? Theme.Colors.accent : Color.clear, lineWidth: 3)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Theme Builder

struct CustomThemeBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    
    let existingTheme: ColorPalette?
    let onSave: (ColorPalette) -> Void
    
    @State private var themeName = ""
    @State private var themeDescription = ""
    @State private var sectorColors: [String] = ["#E53935", "#F57C00", "#FDD835", "#43A047", "#1E88E5", "#5E35B1", "#D81B60", "#00ACC1"]
    @State private var categoryColors: [String] = ["#EF5350", "#FF9800", "#FFEE58", "#66BB6A", "#42A5F5", "#7E57C2", "#EC407A", "#26C6DA"]
    
    @State private var editingColorIndex: Int?
    @State private var editingColorType: ColorType = .sector
    @State private var showColorPicker = false
    @State private var tempColor = Color.red
    @State private var hexInput = ""
    
    @FocusState private var isAnyFieldFocused: Bool
    
    enum ColorType {
        case sector
        case category
    }
    
    init(existingTheme: ColorPalette?, onSave: @escaping (ColorPalette) -> Void) {
        self.existingTheme = existingTheme
        self.onSave = onSave
        
        if let theme = existingTheme {
            _themeName = State(initialValue: theme.name)
            _themeDescription = State(initialValue: theme.description)
            _sectorColors = State(initialValue: theme.sectorColors)
            _categoryColors = State(initialValue: theme.categoryColors)
        }
    }
    
    private var isValid: Bool {
        !themeName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                    .onTapGesture {
                        isAnyFieldFocused = false
                    }
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Preview
                        themePreview
                        
                        // Name & Description
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Theme Details")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            TextField("Theme Name", text: $themeName)
                                .inputFieldStyle()
                                .focused($isAnyFieldFocused)
                            
                            TextField("Description (optional)", text: $themeDescription)
                                .inputFieldStyle()
                                .focused($isAnyFieldFocused)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Sector Colors
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Sector Colors")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Used for main sector groupings in charts")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            colorGrid(colors: $sectorColors, type: .sector)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Category Colors
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Category Colors")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Used for categories within sectors")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            colorGrid(colors: $categoryColors, type: .category)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Save Button
                        Button {
                            saveTheme()
                        } label: {
                            Text(existingTheme != nil ? "Update Theme" : "Save Theme")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, Theme.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isAnyFieldFocused = false
                }
            }
            .navigationTitle(existingTheme != nil ? "Edit Theme" : "Create Theme")
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
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isAnyFieldFocused = false
                    }
                }
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerSheet(
                    color: $tempColor,
                    hexInput: $hexInput,
                    onSave: {
                        if let index = editingColorIndex {
                            let hexColor = hexInput.hasPrefix("#") ? hexInput : "#\(hexInput)"
                            switch editingColorType {
                            case .sector:
                                sectorColors[index] = hexColor.uppercased()
                            case .category:
                                categoryColors[index] = hexColor.uppercased()
                            }
                        }
                        showColorPicker = false
                    }
                )
                .presentationDetents([.large])
            }
        }
    }
    
    private var themePreview: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Gradient preview
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .fill(
                    LinearGradient(
                        colors: sectorColors.prefix(3).map { Color(hex: $0.replacingOccurrences(of: "#", with: "")) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 80)
                .overlay(
                    VStack {
                        Text(themeName.isEmpty ? "Theme Preview" : themeName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                        
                        if !themeDescription.isEmpty {
                            Text(themeDescription)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .shadow(radius: 1)
                        }
                    }
                )
            
            // Color dots preview
            HStack(spacing: 8) {
                ForEach(0..<min(8, sectorColors.count), id: \.self) { index in
                    Circle()
                        .fill(Color(hex: sectorColors[index].replacingOccurrences(of: "#", with: "")))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    private func colorGrid(colors: Binding<[String]>, type: ColorType) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Reorderable color list
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.Spacing.sm) {
                ForEach(Array(colors.wrappedValue.enumerated()), id: \.offset) { index, color in
                    ColorGridItem(
                        color: color,
                        index: index,
                        onEdit: {
                            editingColorIndex = index
                            editingColorType = type
                            let colorHex = colors.wrappedValue[index].replacingOccurrences(of: "#", with: "")
                            tempColor = Color(hex: colorHex)
                            hexInput = colorHex
                            showColorPicker = true
                        },
                        onMoveLeft: index > 0 ? {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                colors.wrappedValue.swapAt(index, index - 1)
                            }
                        } : nil,
                        onMoveRight: index < colors.wrappedValue.count - 1 ? {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                colors.wrappedValue.swapAt(index, index + 1)
                            }
                        } : nil,
                        onDelete: colors.wrappedValue.count > 2 ? {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                _ = colors.wrappedValue.remove(at: index)
                            }
                        } : nil
                    )
                }
                
                // Add color button
                if colors.wrappedValue.count < 12 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            colors.wrappedValue.append("#808080")
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .fill(Theme.Colors.backgroundInput)
                                .frame(height: 50)
                            
                            Image(systemName: "plus")
                                .font(.title3)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            
            // Shuffle button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    colors.wrappedValue.shuffle()
                }
            } label: {
                Label("Shuffle Order", systemImage: "shuffle")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }
    
    private func saveTheme() {
        let id = existingTheme?.id ?? UUID().uuidString
        let theme = ColorPalette(
            id: id,
            name: themeName.trimmingCharacters(in: .whitespaces),
            description: themeDescription.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom theme" : themeDescription.trimmingCharacters(in: .whitespaces),
            sectorColors: sectorColors,
            categoryColors: categoryColors,
            isCustom: true
        )
        onSave(theme)
    }
}

// MARK: - Color Grid Item

struct ColorGridItem: View {
    let color: String
    let index: Int
    let onEdit: () -> Void
    var onMoveLeft: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onDelete: (() -> Void)?
    
    @State private var showActions = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                .frame(height: 50)
            
            if showActions {
                // Action overlay
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color.black.opacity(0.6))
                    .frame(height: 50)
                
                HStack(spacing: 4) {
                    if let moveLeft = onMoveLeft {
                        Button {
                            moveLeft()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    
                    Button {
                        onEdit()
                        showActions = false
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Theme.Colors.accent.opacity(0.8))
                            .clipShape(Circle())
                    }
                    
                    if let moveRight = onMoveRight {
                        Button {
                            moveRight()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    
                    if let delete = onDelete {
                        Button {
                            delete()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.Colors.error.opacity(0.8))
                                .clipShape(Circle())
                        }
                    }
                }
            } else {
                // Position indicator
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                showActions.toggle()
            }
        }
        .onLongPressGesture {
            onEdit()
        }
    }
}

// MARK: - Color Picker Sheet

struct ColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var color: Color
    @Binding var hexInput: String
    let onSave: () -> Void
    
    @State private var showInvalidHex = false
    @FocusState private var isHexFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                    .onTapGesture {
                        isHexFieldFocused = false
                    }
                
                VStack(spacing: Theme.Spacing.lg) {
                    // Color preview
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .fill(color)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                    
                    // Color Wheel
                    ColorPicker("Select Color", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .scaleEffect(1.5)
                        .frame(height: 60)
                        .onChange(of: color) { _, newColor in
                            hexInput = newColor.toHex() ?? "000000"
                        }
                    
                    // Hex Input
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Or enter hex code:")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        HStack {
                            Text("#")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            TextField("FFFFFF", text: $hexInput)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .focused($isHexFieldFocused)
                                .onChange(of: hexInput) { _, newValue in
                                    // Clean input
                                    let cleaned = newValue.replacingOccurrences(of: "#", with: "").uppercased()
                                    if cleaned.count <= 6 {
                                        hexInput = cleaned
                                    }
                                    
                                    // Update color if valid
                                    if cleaned.count == 6, isValidHex(cleaned) {
                                        color = Color(hex: cleaned)
                                        showInvalidHex = false
                                    } else if cleaned.count == 6 {
                                        showInvalidHex = true
                                    }
                                }
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.backgroundInput)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        
                        if showInvalidHex {
                            Text("Invalid hex code")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.error)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    
                    // Quick Colors
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Quick colors:")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm) {
                            ForEach(quickColors, id: \.self) { hex in
                                Button {
                                    hexInput = hex
                                    color = Color(hex: hex)
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(hexInput.uppercased() == hex.uppercased() ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    
                    Spacer()
                    
                    // Save Button
                    Button {
                        onSave()
                    } label: {
                        Text("Apply Color")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(hexInput.count != 6 || !isValidHex(hexInput))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                }
                .padding(.top, Theme.Spacing.lg)
            }
            .navigationTitle("Choose Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isHexFieldFocused = false
                    }
                }
            }
            .onTapGesture {
                isHexFieldFocused = false
            }
        }
    }
    
    private let quickColors = [
        "E53935", "F57C00", "FDD835", "43A047",
        "1E88E5", "5E35B1", "D81B60", "00ACC1",
        "00E676", "FF1744", "651FFF", "FFEA00",
        "795548", "607D8B", "000000", "FFFFFF"
    ]
    
    private func isValidHex(_ hex: String) -> Bool {
        let hexSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        return hex.unicodeScalars.allSatisfy { hexSet.contains($0) }
    }
}

// MARK: - Color Extension for Hex Output

extension Color {
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        
        if components.count >= 3 {
            r = components[0]
            g = components[1]
            b = components[2]
        } else {
            r = components[0]
            g = components[0]
            b = components[0]
        }
        
        return String(
            format: "%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }
}

// MARK: - Preview

#Preview {
    ThemePaletteView()
        .environment(AuthViewModel())
}
