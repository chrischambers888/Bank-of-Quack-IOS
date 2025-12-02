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
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name
        case icon
    }
    
    private let dataService = DataService()
    
    // Default color for all categories
    private let defaultColor = "#26A69A"
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // Extract just the first emoji from input
    private var firstEmoji: String {
        guard let first = icon.first, first.isEmoji else { return "" }
        return String(first)
    }
    
    init(mode: Mode) {
        self.mode = mode
        
        if case .edit(let category) = mode {
            _name = State(initialValue: category.name)
            _icon = State(initialValue: category.icon ?? "")
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
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var categoryPreview: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if !icon.isEmpty {
                Text(icon)
                    .font(.title)
            } else {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.accent)
            }
            
            Text(name.isEmpty ? "Category Name" : name)
                .font(.headline)
                .foregroundStyle(name.isEmpty ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
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
                switch mode {
                case .create:
                    let dto = CreateCategoryDTO(
                        householdId: householdId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: icon.isEmpty ? nil : icon,
                        color: defaultColor,
                        imageUrl: nil,
                        sortOrder: authViewModel.categories.count
                    )
                    _ = try await dataService.createCategory(dto)
                    
                case .edit(let category):
                    let dto = UpdateCategoryDTO(
                        name: name.trimmingCharacters(in: .whitespaces),
                        icon: icon.isEmpty ? nil : icon,
                        color: nil // Keep existing color
                    )
                    _ = try await dataService.updateCategory(id: category.id, dto: dto)
                }
                
                await authViewModel.refreshCategories()
                
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
