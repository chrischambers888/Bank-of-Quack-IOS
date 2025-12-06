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
    @State private var selectedPhotoUrl = ""
    @State private var selectedPhotoImage: UIImage? = nil
    @State private var selectedColor = "#26A69A"
    @State private var selectedSectorId: UUID? = nil
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPhotoPicker = false
    @State private var imageUsage: (current: Int, limit: Int) = (0, 50)
    @State private var isLoadingUsage = false
    @State private var showLimitAlert = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name
        case icon
    }
    
    private let dataService = DataService()
    private let imageService = ImageService()
    
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
    
    /// Returns true if user has a photo selected (either new or existing)
    private var hasPhoto: Bool {
        selectedPhotoImage != nil || selectedPhotoUrl.isPhotoUrl
    }
    
    /// Returns the owner user ID for image counting/uploading
    private var ownerUserId: UUID? {
        authViewModel.members.first { $0.role == .owner }?.userId
    }
    
    init(mode: Mode) {
        self.mode = mode
        
        if case .edit(let category) = mode {
            _name = State(initialValue: category.name)
            _icon = State(initialValue: category.icon ?? "")
            _selectedColor = State(initialValue: category.color)
            // Initialize photo URL if it's a photo
            if let imageUrl = category.imageUrl, imageUrl.isPhotoUrl {
                _selectedPhotoUrl = State(initialValue: imageUrl)
            }
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
                        
                        // Icon Selection (Photo or Emoji)
                        iconSelectionSection
                        
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
                loadImageUsage()
            }
            .sheet(isPresented: $showPhotoPicker) {
                ImagePickerView(selectedImage: $selectedPhotoImage)
            }
            .onChange(of: icon) { _, newValue in
                // Clear photo when emoji is selected
                if !newValue.isEmpty {
                    selectedPhotoImage = nil
                    selectedPhotoUrl = ""
                }
            }
            .onChange(of: selectedPhotoImage) { _, newValue in
                // Clear emoji when photo is selected
                if newValue != nil {
                    icon = ""
                    selectedPhotoUrl = ""
                }
            }
            .alert("Photo Limit Reached", isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You've used all \(imageUsage.limit) photo slots. Remove some photos from members or categories to add more.")
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @ViewBuilder
    private var iconSelectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Icon (Optional)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                if hasPhoto || !icon.isEmpty {
                    Button("Clear") {
                        icon = ""
                        selectedPhotoImage = nil
                        selectedPhotoUrl = ""
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            // Photo usage indicator
            if isLoadingUsage {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading photo usage...")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            } else {
                Text("\(imageUsage.current) of \(imageUsage.limit) photos used")
                    .font(.caption2)
                    .foregroundStyle(imageUsage.current >= imageUsage.limit ? Theme.Colors.warning : Theme.Colors.textMuted)
            }
            
            HStack(spacing: Theme.Spacing.md) {
                // Photo picker button
                Button {
                    checkLimitAndShowPicker()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(hasPhoto ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.backgroundCard)
                            .frame(width: 70, height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(hasPhoto ? Theme.Colors.accent : Color.clear, lineWidth: 2)
                            )
                        
                        if let photoImage = selectedPhotoImage {
                            Image(uiImage: photoImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 66, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md - 2))
                        } else if selectedPhotoUrl.isPhotoUrl {
                            AsyncImage(url: URL(string: selectedPhotoUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 66, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md - 2))
                                default:
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                            }
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("Photo")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
                
                // Emoji input
                HStack {
                    TextField("Tap for emoji", text: $icon)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .icon)
                        .onChange(of: icon) { _, newValue in
                            // Only keep the first emoji
                            if let first = newValue.first, first.isEmoji {
                                icon = String(first)
                            } else if !newValue.isEmpty && newValue.first?.isEmoji != true {
                                icon = ""
                            }
                        }
                }
                .frame(width: 70, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .fill(!icon.isEmpty ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.backgroundInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                        .stroke(!icon.isEmpty ? Theme.Colors.accent : Color.clear, lineWidth: 2)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    if hasPhoto {
                        Text("Photo selected")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    } else if !icon.isEmpty {
                        Text("Emoji selected")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    } else {
                        Text("Choose photo or emoji")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Text("Or leave blank for default icon")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    private func loadImageUsage() {
        guard let ownerId = ownerUserId else { return }
        
        isLoadingUsage = true
        Task {
            do {
                let (_, current, limit) = try await imageService.canAddImage(ownerUserId: ownerId)
                await MainActor.run {
                    imageUsage = (current, limit)
                    isLoadingUsage = false
                }
            } catch {
                await MainActor.run {
                    isLoadingUsage = false
                }
            }
        }
    }
    
    private func checkLimitAndShowPicker() {
        // If user already has a photo, they can replace it
        if hasPhoto {
            showPhotoPicker = true
            return
        }
        
        if imageUsage.current >= imageUsage.limit {
            showLimitAlert = true
            return
        }
        
        showPhotoPicker = true
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
                    ForEach(authViewModel.sectors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { sector in
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
                
                if let photoImage = selectedPhotoImage {
                    Image(uiImage: photoImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else if selectedPhotoUrl.isPhotoUrl {
                    AsyncImage(url: URL(string: selectedPhotoUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        default:
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundStyle(Color(hex: selectedColor.replacingOccurrences(of: "#", with: "")))
                        }
                    }
                } else if !icon.isEmpty {
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
                var imageUrlToSave: String? = nil
                var iconToSave: String? = icon.isEmpty ? nil : icon
                
                // Handle photo upload if new photo selected
                if let photoImage = selectedPhotoImage, let ownerId = ownerUserId {
                    // Get existing URL for potential deletion
                    var existingUrl: String? = nil
                    if case .edit(let category) = mode {
                        existingUrl = category.imageUrl
                    }
                    
                    // Upload new photo
                    let uploadedUrl = try await imageService.uploadImage(
                        photoImage,
                        ownerUserId: ownerId,
                        existingUrl: existingUrl?.isPhotoUrl == true ? existingUrl : nil
                    )
                    imageUrlToSave = uploadedUrl
                    iconToSave = nil // Clear emoji when using photo
                } else if selectedPhotoUrl.isPhotoUrl {
                    // Keep existing photo URL
                    imageUrlToSave = selectedPhotoUrl
                    iconToSave = nil
                } else if !icon.isEmpty {
                    // Using emoji - clear any existing photo
                    if case .edit(let category) = mode, let existingUrl = category.imageUrl, existingUrl.isPhotoUrl {
                        try? await imageService.deleteImage(at: existingUrl)
                    }
                    imageUrlToSave = nil
                } else {
                    // Cleared both - delete any existing photo
                    if case .edit(let category) = mode, let existingUrl = category.imageUrl, existingUrl.isPhotoUrl {
                        try? await imageService.deleteImage(at: existingUrl)
                    }
                    imageUrlToSave = nil
                }
                
                let categoryId: UUID
                
                switch mode {
                case .create:
                    let dto = CreateCategoryDTO(
                        householdId: householdId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: iconToSave,
                        color: selectedColor,
                        imageUrl: imageUrlToSave,
                        sortOrder: authViewModel.categories.count
                    )
                    let category = try await dataService.createCategory(dto)
                    categoryId = category.id
                    
                case .edit(let category):
                    // When editing, don't change the color - it's managed by theme
                    let dto = UpdateCategoryDTO(
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: iconToSave,
                        color: nil,
                        imageUrl: imageUrlToSave
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
