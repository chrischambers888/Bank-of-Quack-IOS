import SwiftUI

struct CategoriesView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddCategory = false
    @State private var categoryToEdit: Category?
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
    // Multi-select state
    @State private var isSelectionMode = false
    @State private var selectedCategoryIds: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    
    private let dataService = DataService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if authViewModel.categories.isEmpty {
                    emptyStateView
                } else {
                    categoryList
                }
                
                // Bulk delete button
                if isSelectionMode && !selectedCategoryIds.isEmpty {
                    VStack {
                        Spacer()
                        
                        Button {
                            showBulkDeleteConfirm = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "trash")
                                Text("Delete \(selectedCategoryIds.count) Categor\(selectedCategoryIds.count == 1 ? "y" : "ies")")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.error)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isSelectionMode ? "Cancel" : "Done") {
                        if isSelectionMode {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = false
                                selectedCategoryIds.removeAll()
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        if !authViewModel.categories.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedCategoryIds.removeAll()
                                    }
                                }
                            } label: {
                                Text(isSelectionMode ? "Done" : "Select")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        
                        if !isSelectionMode {
                            Button {
                                showAddCategory = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            CategoryFormView(mode: .create)
        }
        .sheet(item: $categoryToEdit) { category in
            CategoryFormView(mode: .edit(category))
        }
        .alert("Delete Category?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let category = categoryToDelete {
                    deleteCategory(category)
                }
            }
        } message: {
            Text("This will remove the category. Transactions using this category will have their category set to none.")
        }
        .alert("Delete \(selectedCategoryIds.count) Categor\(selectedCategoryIds.count == 1 ? "y" : "ies")?", isPresented: $showBulkDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                bulkDeleteCategories()
            }
        } message: {
            Text("This will remove the selected categories. Transactions using these categories will have their category set to none.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.textMuted)
            
            Text("No Categories Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Categories help you organize your expenses.\nTap + to create your first category.")
                .font(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                showAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.lg)
    }
    
    private var categoryList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                // Select all row when in selection mode
                if isSelectionMode {
                    Button {
                        let allIds = Set(authViewModel.categories.map { $0.id })
                        if allIds == selectedCategoryIds {
                            selectedCategoryIds.removeAll()
                        } else {
                            selectedCategoryIds = allIds
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: Set(authViewModel.categories.map { $0.id }) == selectedCategoryIds ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundStyle(Set(authViewModel.categories.map { $0.id }) == selectedCategoryIds ? Theme.Colors.accent : Theme.Colors.textMuted)
                            
                            Text("Select All")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.backgroundCard.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                    }
                }
                
                ForEach(authViewModel.categories.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { category in
                    if isSelectionMode {
                        CategoryRowSelectable(
                            category: category,
                            isSelected: selectedCategoryIds.contains(category.id),
                            onTap: {
                                toggleSelection(category.id)
                            }
                        )
                    } else {
                        CategoryRow(
                            category: category,
                            onEdit: {
                                categoryToEdit = category
                            },
                            onDelete: {
                                categoryToDelete = category
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, isSelectionMode && !selectedCategoryIds.isEmpty ? 150 : 100)
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedCategoryIds.contains(id) {
            selectedCategoryIds.remove(id)
        } else {
            selectedCategoryIds.insert(id)
        }
    }
    
    private func deleteCategory(_ category: Category) {
        isDeleting = true
        
        Task {
            do {
                try await dataService.deleteCategory(id: category.id)
                await authViewModel.refreshCategories()
            } catch {
                await MainActor.run {
                    authViewModel.error = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isDeleting = false
                categoryToDelete = nil
            }
        }
    }
    
    private func bulkDeleteCategories() {
        guard !selectedCategoryIds.isEmpty else { return }
        isDeleting = true
        
        Task {
            do {
                for id in selectedCategoryIds {
                    try await dataService.deleteCategory(id: id)
                }
                await authViewModel.refreshCategories()
            } catch {
                await MainActor.run {
                    authViewModel.error = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isDeleting = false
                selectedCategoryIds.removeAll()
                isSelectionMode = false
            }
        }
    }
}

// MARK: - Selectable Category Row

struct CategoryRowSelectable: View {
    let category: Category
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                
                // Icon or default folder icon
                if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                    Text(icon)
                        .font(.title2)
                } else {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.accent)
                }
                
                Text(category.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CategoryRow: View {
    let category: Category
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon or default folder icon
            // Note: "folder" string is invalid (was a bug) - treat as nil
            if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                Text(icon)
                    .font(.title2)
            } else {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
            }
            
            Text(category.name)
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Spacer()
            
            // Actions
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.error)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }
}

#Preview {
    CategoriesView()
        .environment(AuthViewModel())
}

