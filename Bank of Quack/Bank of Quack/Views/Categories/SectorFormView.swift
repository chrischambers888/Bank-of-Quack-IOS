import SwiftUI

struct SectorFormView: View {
    enum Mode {
        case create
        case edit(Sector)
        
        var title: String {
            switch self {
            case .create: return "New Sector"
            case .edit: return "Edit Sector"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .create: return "Create Sector"
            case .edit: return "Save Changes"
            }
        }
    }
    
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var customThemeStorage = CustomThemeStorage()
    
    let mode: Mode
    
    @State private var name = ""
    @State private var selectedColor = "#004D40"
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var useThemeColor = true
    @State private var showColorPicker = false
    
    @FocusState private var isNameFocused: Bool
    
    private let dataService = DataService()
    
    private let colorOptions = [
        "#004D40", "#00695C", "#00796B", "#00897B",
        "#1565C0", "#1976D2", "#1E88E5", "#2196F3",
        "#7B1FA2", "#8E24AA", "#9C27B0", "#AB47BC",
        "#C62828", "#D32F2F", "#E53935", "#F44336",
        "#EF6C00", "#F57C00", "#FB8C00", "#FF9800",
        "#26A69A", "#4DB6AC", "#80CBC4", "#B2DFDB",
        "#FFCA28", "#FFB300", "#FF8F00", "#FF6F00",
        "#66BB6A", "#43A047", "#2E7D32", "#1B5E20"
    ]
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var hasAppliedTheme: Bool {
        AppliedThemeManager.shared.appliedThemeId != nil
    }
    
    private var appliedThemeName: String {
        AppliedThemeManager.shared.appliedThemeName ?? "Theme"
    }
    
    private var themeColor: String? {
        AppliedThemeManager.shared.getNextSectorColor(
            sectorCount: authViewModel.sectors.count,
            customStorage: customThemeStorage
        )
    }
    
    init(mode: Mode) {
        self.mode = mode
        
        if case .edit(let sector) = mode {
            _name = State(initialValue: sector.name)
            _selectedColor = State(initialValue: sector.color)
            _useThemeColor = State(initialValue: false)
            _showColorPicker = State(initialValue: true)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Preview
                        sectorPreview
                        
                        // Name Field
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Name")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            TextField("Sector name", text: $name)
                                .inputFieldStyle()
                                .focused($isNameFocused)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Color Section
                        colorSection
                        
                        // Category Selection
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("Categories")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Spacer()
                                
                                Text("\(selectedCategoryIds.count) selected")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if authViewModel.categories.isEmpty {
                                Text("No categories available. Create some categories first.")
                                    .font(.body)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .italic()
                                    .padding(Theme.Spacing.md)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                    .padding(.horizontal, Theme.Spacing.md)
                            } else {
                                LazyVStack(spacing: Theme.Spacing.xs) {
                                    ForEach(authViewModel.categories) { category in
                                        CategorySelectionRow(
                                            category: category,
                                            isSelected: selectedCategoryIds.contains(category.id)
                                        ) {
                                            toggleCategory(category.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Submit Button
                        Button {
                            submit()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .tint(Theme.Colors.textInverse)
                            } else {
                                Text(mode.buttonTitle)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isFormValid || isSubmitting)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, Theme.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(mode.title)
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
                        isNameFocused = false
                    }
                }
            }
            .onAppear {
                loadExistingCategories()
                // Set theme color if creating and theme is applied
                if case .create = mode, let color = themeColor {
                    selectedColor = color
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
            
            if hasAppliedTheme && !showColorPicker {
                // Theme color indicator
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showColorPicker = true
                        useThemeColor = false
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "paintpalette.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.accent)
                                
                                Text("Using \(appliedThemeName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("Tap to choose a different color")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
            } else {
                // Full color picker
                VStack(spacing: Theme.Spacing.sm) {
                    if hasAppliedTheme {
                        // Option to revert to theme color
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if let color = themeColor {
                                    selectedColor = color
                                }
                                showColorPicker = false
                                useThemeColor = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "paintpalette.fill")
                                    .font(.caption)
                                Text("Use \(appliedThemeName) color")
                                    .font(.caption)
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color.replacingOccurrences(of: "#", with: "")))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    private var sectorPreview: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                .frame(width: 6, height: 44)
            
            Text(name.isEmpty ? "Sector Name" : name)
                .font(.headline)
                .foregroundStyle(name.isEmpty ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
            
            Spacer()
            
            // Color indicator
            Circle()
                .fill(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                .frame(width: 16, height: 16)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    private func loadExistingCategories() {
        if case .edit(let sector) = mode {
            let existingIds = authViewModel.sectorCategories[sector.id] ?? []
            selectedCategoryIds = Set(existingIds)
        }
    }
    
    private func toggleCategory(_ id: UUID) {
        if selectedCategoryIds.contains(id) {
            selectedCategoryIds.remove(id)
        } else {
            selectedCategoryIds.insert(id)
        }
    }
    
    private func submit() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        isSubmitting = true
        
        Task {
            do {
                let sectorId: UUID
                
                switch mode {
                case .create:
                    let dto = CreateSectorDTO(
                        householdId: householdId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        color: selectedColor,
                        sortOrder: authViewModel.sectors.count
                    )
                    let sector = try await dataService.createSector(dto)
                    sectorId = sector.id
                    
                case .edit(let sector):
                    let dto = UpdateSectorDTO(
                        name: name.trimmingCharacters(in: .whitespaces),
                        color: selectedColor
                    )
                    _ = try await dataService.updateSector(id: sector.id, dto: dto)
                    sectorId = sector.id
                }
                
                // Update category links
                try await dataService.updateSectorCategories(
                    sectorId: sectorId,
                    categoryIds: Array(selectedCategoryIds)
                )
                
                await authViewModel.refreshSectors()
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct CategorySelectionRow: View {
    let category: Category
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .font(.title3)
                
                // Color indicator
                Circle()
                    .fill(category.swiftUIColor)
                    .frame(width: 12, height: 12)
                
                // Icon & Name
                HStack(spacing: Theme.Spacing.xs) {
                    if let icon = category.icon {
                        Text(icon)
                            .font(.body)
                    }
                    
                    Text(category.name)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                
                Spacer()
            }
            .padding(Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accent.opacity(0.15) : Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
        }
    }
}

#Preview("Create") {
    SectorFormView(mode: .create)
        .environment(AuthViewModel())
}
