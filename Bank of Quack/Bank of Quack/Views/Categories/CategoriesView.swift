import SwiftUI

struct CategoriesView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddCategory = false
    @State private var categoryToEdit: Category?
    @State private var categoryToDelete: Category?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
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
            }
            .navigationTitle("Categories")
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
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddCategory = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Colors.accent)
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
                ForEach(authViewModel.categories) { category in
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
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 100)
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
}

struct CategoryRow: View {
    let category: Category
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Icon or default folder icon
            if let icon = category.icon {
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

