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
    
    let mode: Mode
    
    @State private var name = ""
    @State private var selectedColor = "#004D40"
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var isNameFocused: Bool
    
    private let dataService = DataService()
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isDuplicateName
    }
    
    private var isDuplicateName: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty else { return false }
        
        return authViewModel.sectors.contains { sector in
            // When editing, exclude the current sector from the check
            if case .edit(let editingSector) = mode {
                return sector.id != editingSector.id && 
                       sector.name.lowercased() == trimmedName
            }
            return sector.name.lowercased() == trimmedName
        }
    }
    
    // Get categories that are available (not already in another sector)
    private var availableCategories: [Category] {
        authViewModel.categories.filter { category in
            // Check if this category is already in another sector
            for (sectorId, categoryIds) in authViewModel.sectorCategories {
                // If editing, allow categories from the current sector
                if case .edit(let editingSector) = mode {
                    if sectorId == editingSector.id {
                        continue // Skip checking the current sector
                    }
                }
                if categoryIds.contains(category.id) {
                    return false // Category is in another sector
                }
            }
            return true
        }
    }
    
    // Get categories that are unavailable (in other sectors)
    private var unavailableCategories: [(category: Category, sectorName: String)] {
        var result: [(Category, String)] = []
        
        for category in authViewModel.categories {
            for (sectorId, categoryIds) in authViewModel.sectorCategories {
                // If editing, skip the current sector
                if case .edit(let editingSector) = mode {
                    if sectorId == editingSector.id {
                        continue
                    }
                }
                if categoryIds.contains(category.id) {
                    if let sector = authViewModel.sectors.first(where: { $0.id == sectorId }) {
                        result.append((category, sector.name))
                    }
                    break
                }
            }
        }
        
        return result
    }
    
    private var appliedThemeName: String {
        AppliedThemeManager.shared.appliedThemeName ?? "Theme"
    }
    
    private var themeColor: String? {
        AppliedThemeManager.shared.getNextSectorColor(sectorCount: authViewModel.sectors.count)
    }
    
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    
    init(mode: Mode) {
        self.mode = mode
        
        if case .edit(let sector) = mode {
            _name = State(initialValue: sector.name)
            _selectedColor = State(initialValue: sector.color)
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
                            
                            if isDuplicateName {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                    Text("A sector with this name already exists")
                                        .font(.caption)
                                }
                                .foregroundStyle(Theme.Colors.error)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Color Display (read-only)
                        colorDisplaySection
                        
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
                                    // Available categories
                                    ForEach(availableCategories) { category in
                                        CategorySelectionRow(
                                            category: category,
                                            isSelected: selectedCategoryIds.contains(category.id),
                                            isDisabled: false,
                                            disabledReason: nil
                                        ) {
                                            toggleCategory(category.id)
                                        }
                                    }
                                    
                                    // Unavailable categories (in other sectors)
                                    ForEach(unavailableCategories, id: \.category.id) { item in
                                        CategorySelectionRow(
                                            category: item.category,
                                            isSelected: false,
                                            isDisabled: true,
                                            disabledReason: "In \(item.sectorName)"
                                        ) { }
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
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
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
                // Set theme color if creating
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
    private var colorDisplaySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Color")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
            
            HStack(spacing: Theme.Spacing.md) {
                // Color preview with theme badge
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                    
                    // Theme badge
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Theme.Colors.accent)
                        .clipShape(Circle())
                        .offset(x: 4, y: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if isEditing {
                        Text("Current Color")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Managed by theme settings")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Text("From Theme")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Using \(appliedThemeName) palette")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Theme.Colors.backgroundCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, Theme.Spacing.md)
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
                    // When editing, don't change the color - it's managed by theme
                    let dto = UpdateSectorDTO(
                        name: name.trimmingCharacters(in: .whitespaces),
                        color: nil
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
    var isDisabled: Bool = false
    var disabledReason: String? = nil
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            if !isDisabled {
                onToggle()
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Checkbox
                Image(systemName: isDisabled ? "minus.circle" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .foregroundStyle(isDisabled ? Theme.Colors.textMuted.opacity(0.5) : (isSelected ? Theme.Colors.accent : Theme.Colors.textMuted))
                    .font(.title3)
                
                // Color indicator
                Circle()
                    .fill(category.swiftUIColor.opacity(isDisabled ? 0.4 : 1.0))
                    .frame(width: 12, height: 12)
                
                // Icon & Name
                HStack(spacing: Theme.Spacing.xs) {
                    if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                        Text(icon)
                            .font(.body)
                            .opacity(isDisabled ? 0.5 : 1.0)
                    }
                    
                    Text(category.name)
                        .font(.body)
                        .foregroundStyle(isDisabled ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                }
                
                Spacer()
                
                // Disabled reason badge
                if let reason = disabledReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.backgroundPrimary.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .padding(Theme.Spacing.sm)
            .background(isSelected && !isDisabled ? Theme.Colors.accent.opacity(0.15) : Theme.Colors.backgroundCard.opacity(isDisabled ? 0.5 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
        }
        .disabled(isDisabled)
    }
}

#Preview("Create") {
    SectorFormView(mode: .create)
        .environment(AuthViewModel())
}
