import SwiftUI

struct CategoryFormView: View {
    enum Mode {
        case create
        case edit(Category)
        
        var title: String {
            switch self {
            case .create: return "New Category"
            case .edit: return "Edit Category"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .create: return "Create Category"
            case .edit: return "Save Changes"
            }
        }
    }
    
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let mode: Mode
    
    @State private var name = ""
    @State private var icon = ""
    @State private var selectedColor = "#26A69A"
    @State private var selectedSectorId: UUID? = nil
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name
        case icon
    }
    
    private let dataService = DataService()
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isDuplicateName
    }
    
    private var isDuplicateName: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty else { return false }
        
        return authViewModel.categories.contains { category in
            // When editing, exclude the current category from the check
            if case .edit(let editingCategory) = mode {
                return category.id != editingCategory.id && 
                       category.name.lowercased() == trimmedName
            }
            return category.name.lowercased() == trimmedName
        }
    }
    
    // Get sectors that this category can be added to (for create mode)
    // or the current sector (for edit mode)
    private var currentSectorId: UUID? {
        if case .edit(let category) = mode {
            // Find if category is already in a sector
            for (sectorId, categoryIds) in authViewModel.sectorCategories {
                if categoryIds.contains(category.id) {
                    return sectorId
                }
            }
        }
        return nil
    }
    
    private var appliedThemeName: String {
        AppliedThemeManager.shared.appliedThemeName ?? "Theme"
    }
    
    private var themeColor: String? {
        AppliedThemeManager.shared.getNextCategoryColor(categoryCount: authViewModel.categories.count)
    }
    
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    
    init(mode: Mode) {
        self.mode = mode
        
        if case .edit(let category) = mode {
            _name = State(initialValue: category.name)
            _icon = State(initialValue: category.icon ?? "")
            _selectedColor = State(initialValue: category.color)
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
                        categoryPreview
                        
                        // Name Field
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Name")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            TextField("Category name", text: $name)
                                .inputFieldStyle()
                                .focused($focusedField, equals: .name)
                            
                            if isDuplicateName {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                    Text("A category with this name already exists")
                                        .font(.caption)
                                }
                                .foregroundStyle(Theme.Colors.error)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Icon Field (Emoji)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Icon (Optional)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            HStack {
                                TextField("Tap to add emoji", text: $icon)
                                    .font(.system(size: 32))
                                    .multilineTextAlignment(.center)
                                    .focused($focusedField, equals: .icon)
                                    .onChange(of: icon) { _, newValue in
                                        // Only keep the first emoji
                                        if let first = newValue.first, first.isEmoji {
                                            icon = String(first)
                                        } else if !newValue.isEmpty && newValue.first?.isEmoji != true {
                                            // If non-emoji character entered, clear it
                                            icon = ""
                                        }
                                    }
                                
                                if !icon.isEmpty {
                                    Button {
                                        icon = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Theme.Colors.textMuted)
                                    }
                                }
                            }
                            .padding(Theme.Spacing.md)
                            .frame(height: 60)
                            .background(Theme.Colors.backgroundInput)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            
                            Text("Tap the field and use your emoji keyboard")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Color Display (read-only)
                        colorDisplaySection
                        
                        // Sector Selection (only show if sectors exist)
                        if !authViewModel.sectors.isEmpty {
                            sectorSection
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
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                // Set theme color if creating
                if case .create = mode, let color = themeColor {
                    selectedColor = color
                }
                // Load current sector if editing
                if case .edit = mode {
                    selectedSectorId = currentSectorId
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
    private var sectorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Sector (Optional)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                if selectedSectorId != nil {
                    Button {
                        selectedSectorId = nil
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(authViewModel.sectors) { sector in
                        Button {
                            if selectedSectorId == sector.id {
                                selectedSectorId = nil
                            } else {
                                selectedSectorId = sector.id
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(sector.swiftUIColor)
                                    .frame(width: 4, height: 20)
                                
                                Text(sector.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                if selectedSectorId == sector.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                            }
                            .foregroundStyle(selectedSectorId == sector.id ? .white : Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .fill(selectedSectorId == sector.id ? sector.swiftUIColor : Theme.Colors.backgroundCard)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(selectedSectorId == sector.id ? Color.clear : sector.swiftUIColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            
            Text("Adding to a sector helps group related categories for budget analysis")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
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
    
    private var categoryPreview: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")).opacity(0.2))
                    .frame(width: 44, height: 44)
                
                if !icon.isEmpty {
                    Text(icon)
                        .font(.title2)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                }
            }
            
            Text(name.isEmpty ? "Category Name" : name)
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
    
    private func submit() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        isSubmitting = true
        
        Task {
            do {
                let categoryId: UUID
                
                switch mode {
                case .create:
                    let dto = CreateCategoryDTO(
                        householdId: householdId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: icon.isEmpty ? nil : icon,
                        color: selectedColor,
                        imageUrl: nil,
                        sortOrder: authViewModel.categories.count
                    )
                    let category = try await dataService.createCategory(dto)
                    categoryId = category.id
                    
                case .edit(let category):
                    // When editing, don't change the color - it's managed by theme
                    let dto = UpdateCategoryDTO(
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: icon.isEmpty ? nil : icon,
                        color: nil
                    )
                    _ = try await dataService.updateCategory(id: category.id, dto: dto)
                    categoryId = category.id
                }
                
                // Handle sector assignment
                let previousSectorId = currentSectorId
                
                // Remove from previous sector if it changed
                if let prevId = previousSectorId, prevId != selectedSectorId {
                    try await dataService.removeCategoryFromSector(sectorId: prevId, categoryId: categoryId)
                }
                
                // Add to new sector if selected and different from previous
                if let newSectorId = selectedSectorId, newSectorId != previousSectorId {
                    try await dataService.addCategoryToSector(sectorId: newSectorId, categoryId: categoryId)
                }
                
                await authViewModel.refreshCategories()
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

// MARK: - Character Extension for Emoji Detection

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

#Preview("Create") {
    CategoryFormView(mode: .create)
        .environment(AuthViewModel())
}
