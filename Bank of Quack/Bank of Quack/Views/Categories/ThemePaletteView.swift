import SwiftUI
import Combine

// MARK: - Color Palette Model

struct ColorPalette: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let colors: [String]
    
    var previewGradient: [Color] {
        let previewColors = colors.prefix(3)
        return previewColors.map { Color(hex: $0.replacingOccurrences(of: "#", with: "")) }
    }
    
    init(id: String, name: String, description: String, colors: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.colors = colors
    }
}

// MARK: - Applied Theme Manager

class AppliedThemeManager: ObservableObject {
    static let shared = AppliedThemeManager()
    
    @Published var appliedThemeId: String?
    @Published var appliedThemeName: String?
    
    private let themeIdKey = "appliedThemeId"
    private let themeNameKey = "appliedThemeName"
    private let colorOrderKey = "themeColorOrder"
    
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
    func getCustomColorOrder(for themeId: String) -> [Int]? {
        let key = colorOrderKey + "_" + themeId
        return UserDefaults.standard.array(forKey: key) as? [Int]
    }
    
    /// Save a custom color order for a theme
    func saveCustomColorOrder(for themeId: String, order: [Int]) {
        let key = colorOrderKey + "_" + themeId
        UserDefaults.standard.set(order, forKey: key)
    }
    
    /// Reset color order to default for a theme
    func resetColorOrder(for themeId: String) {
        let key = colorOrderKey + "_" + themeId
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    /// Get the current theme palette
    func getCurrentPalette() -> ColorPalette? {
        guard let themeId = appliedThemeId else { return nil }
        return ColorPalettes.all.first(where: { $0.id == themeId })
    }
    
    /// Get colors in the custom order (or default if no custom order)
    func getOrderedColors(for themeId: String) -> [String] {
        guard let palette = ColorPalettes.all.first(where: { $0.id == themeId }) else { return [] }
        
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

// MARK: - Predefined Palettes

enum ColorPalettes {
    static let rainbow = ColorPalette(
        id: "rainbow",
        name: "Rainbow Spectrum",
        description: "Full spectrum of vibrant colors",
        colors: [
            "#E53935", "#F57C00", "#FDD835", "#43A047",
            "#1E88E5", "#5E35B1", "#D81B60", "#00ACC1"
        ]
    )
    
    static let jewels = ColorPalette(
        id: "jewels",
        name: "Precious Jewels",
        description: "Rich gemstone-inspired colors",
        colors: [
            "#B71C1C", "#1A237E", "#004D40", "#E65100",
            "#4A148C", "#006064", "#880E4F", "#33691E"
        ]
    )
    
    static let tropical = ColorPalette(
        id: "tropical",
        name: "Tropical Paradise",
        description: "Vibrant island-inspired hues",
        colors: [
            "#FF6F00", "#00BFA5", "#F50057", "#00B0FF",
            "#FFD600", "#64DD17", "#AA00FF", "#FF3D00"
        ]
    )
    
    static let pastel = ColorPalette(
        id: "pastel",
        name: "Soft Pastels",
        description: "Gentle, muted tones",
        colors: [
            "#F8BBD0", "#B3E5FC", "#C8E6C9", "#FFE0B2",
            "#E1BEE7", "#B2EBF2", "#FFCCBC", "#D1C4E9"
        ]
    )
    
    static let retro = ColorPalette(
        id: "retro",
        name: "Retro Vibes",
        description: "70s inspired warm contrasts",
        colors: [
            "#D84315", "#FFA000", "#7CB342", "#00897B",
            "#5D4037", "#F4511E", "#C0CA33", "#0097A7"
        ]
    )
    
    static let cyberpunk = ColorPalette(
        id: "cyberpunk",
        name: "Cyberpunk",
        description: "Futuristic neon contrasts",
        colors: [
            "#00FFFF", "#FF00FF", "#FFFF00", "#00FF00",
            "#FF0080", "#8000FF", "#FF8000", "#0080FF"
        ]
    )
    
    static let autumn = ColorPalette(
        id: "autumn",
        name: "Autumn Harvest",
        description: "Warm fall colors with contrast",
        colors: [
            "#BF360C", "#E65100", "#F9A825", "#558B2F",
            "#4E342E", "#D84315", "#FF8F00", "#33691E"
        ]
    )
    
    static let ocean = ColorPalette(
        id: "ocean",
        name: "Ocean Depths",
        description: "Cool blues and teals",
        colors: [
            "#0D47A1", "#1565C0", "#1976D2", "#1E88E5",
            "#006064", "#00838F", "#0097A7", "#00ACC1"
        ]
    )
    
    static let midnight = ColorPalette(
        id: "midnight",
        name: "Midnight Galaxy",
        description: "Deep space colors with stars",
        colors: [
            "#1A237E", "#4A148C", "#311B92", "#0D47A1",
            "#880E4F", "#006064", "#263238", "#4527A0"
        ]
    )
    
    static let garden = ColorPalette(
        id: "garden",
        name: "Spring Garden",
        description: "Fresh floral palette",
        colors: [
            "#C2185B", "#7B1FA2", "#388E3C", "#F57C00",
            "#1976D2", "#D32F2F", "#00796B", "#FBC02D"
        ]
    )
    
    static let monochrome = ColorPalette(
        id: "monochrome",
        name: "Monochrome Mix",
        description: "Elegant grayscale with accents",
        colors: [
            "#212121", "#424242", "#616161", "#757575",
            "#00BCD4", "#FF5722", "#4CAF50", "#9C27B0"
        ]
    )
    
    static let sunset = ColorPalette(
        id: "sunset",
        name: "Golden Sunset",
        description: "Warm dusk colors",
        colors: [
            "#BF360C", "#D84315", "#E64A19", "#F4511E",
            "#E65100", "#EF6C00", "#F57C00", "#FB8C00"
        ]
    )
    
    static let neon = ColorPalette(
        id: "neon",
        name: "Neon Nights",
        description: "Electric bold colors",
        colors: [
            "#00E676", "#00E5FF", "#651FFF", "#D500F9",
            "#FF1744", "#F50057", "#FF9100", "#FFEA00"
        ]
    )
    
    static let corporate = ColorPalette(
        id: "corporate",
        name: "Professional",
        description: "Clean business colors",
        colors: [
            "#1565C0", "#2E7D32", "#F57F17", "#C62828",
            "#6A1B9A", "#00838F", "#37474F", "#AD1457"
        ]
    )
    
    static let candy = ColorPalette(
        id: "candy",
        name: "Candy Shop",
        description: "Playful sweet colors",
        colors: [
            "#D32F2F", "#C2185B", "#7B1FA2", "#512DA8",
            "#1976D2", "#0288D1", "#0097A7", "#00796B"
        ]
    )
    
    static let nordic = ColorPalette(
        id: "nordic",
        name: "Nordic Frost",
        description: "Cool Scandinavian tones",
        colors: [
            "#37474F", "#455A64", "#546E7A", "#607D8B",
            "#0277BD", "#0288D1", "#039BE5", "#03A9F4"
        ]
    )
    
    // Quack Classic uses the original category colors
    static let quack = ColorPalette(
        id: "quack",
        name: "Quack Classic",
        description: "Signature teal and gold palette",
        colors: [
            "#80CBC4", "#FFEB3B", "#B2DFDB", "#FFF176",
            "#E0F2F1", "#FFF59D", "#A5D6A7", "#FFFDE7"
        ]
    )
    
    static let quackVibrant = ColorPalette(
        id: "quack_vibrant",
        name: "Quack Vibrant",
        description: "Bold teal, gold, and accent pops",
        colors: [
            "#004D40", "#F57F17", "#00695C", "#F9A825",
            "#00897B", "#FBC02D", "#26A69A", "#FFCA28"
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
                            
                            Text("Tap a theme to select, then tap the checkmark to apply")
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
                                        isApplying: isApplying && selectedPalette?.id == palette.id,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if selectedPalette?.id == palette.id {
                                                    // Tapping already selected theme deselects it
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
            .navigationTitle("Color Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
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
                Button("OK") {
                    selectedPalette = nil
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
                let colors = AppliedThemeManager.shared.getOrderedColors(for: palette.id)
                
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
    var isApplying: Bool = false
    let onSelect: () -> Void
    var onApply: (() -> Void)? = nil
    
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
                                ForEach(palette.colors.prefix(4), id: \.self) { color in
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
                                            .background(Theme.Colors.accent)
                                            .clipShape(Circle())
                                            .shadow(radius: 3)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(Theme.Colors.accent)
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
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if isSelected && !isApplied {
                            Text("Tap ✓ to apply")
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
                    .stroke(isApplied ? Theme.Colors.accent : (isSelected ? Theme.Colors.accent : Color.clear), lineWidth: isApplied || isSelected ? 3 : 0)
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
    
    @State private var colorOrder: [Int] = []
    @State private var showResetConfirmation = false
    @State private var isApplying = false
    @State private var showSuccess = false
    
    private let dataService = DataService()
    
    private var currentPalette: ColorPalette? {
        AppliedThemeManager.shared.getCurrentPalette()
    }
    
    private var orderedColors: [String] {
        guard let palette = currentPalette else { return [] }
        return colorOrder.compactMap { index in
            guard index >= 0, index < palette.colors.count else { return nil }
            return palette.colors[index]
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Instructions
                    HStack {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Drag colors to reorder • New items use this order")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(Theme.Spacing.md)
                    
                    // Color List
                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ReorderableColorList(
                                colors: orderedColors,
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
        if let existingOrder = AppliedThemeManager.shared.getCustomColorOrder(for: palette.id) {
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
        
        AppliedThemeManager.shared.resetColorOrder(for: palette.id)
    }
    
    private func applyColorOrder() {
        guard let palette = currentPalette else { return }
        
        isApplying = true
        
        // Save the new order
        AppliedThemeManager.shared.saveCustomColorOrder(for: palette.id, order: colorOrder)
        
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
