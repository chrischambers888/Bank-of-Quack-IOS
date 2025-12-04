import SwiftUI

struct TemplatesView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var showAddTemplate = false
    @State private var templateToEdit: TransactionTemplate?
    @State private var templateToDelete: TransactionTemplate?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
    private let dataService = DataService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if authViewModel.templates.isEmpty {
                    emptyState
                } else {
                    templatesList
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTemplate = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showAddTemplate) {
                TemplateFormView(mode: .create)
            }
            .sheet(item: $templateToEdit) { template in
                TemplateFormView(mode: .edit(template))
            }
            .alert("Delete Template?", isPresented: $showDeleteConfirm, presenting: templateToDelete) { template in
                Button("Cancel", role: .cancel) {
                    templateToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteTemplate(template)
                    }
                }
            } message: { template in
                Text("Are you sure you want to delete \"\(template.name)\"? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.textMuted)
            
            VStack(spacing: Theme.Spacing.xs) {
                Text("No Templates")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Create templates for transactions you enter frequently")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showAddTemplate = true
            } label: {
                Label("Create Template", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 200)
        }
        .padding()
    }
    
    // MARK: - Templates List
    
    private var templatesList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(authViewModel.templates) { template in
                    TemplateRow(
                        template: template,
                        categories: authViewModel.categories,
                        onEdit: {
                            templateToEdit = template
                        },
                        onDelete: {
                            templateToDelete = template
                            showDeleteConfirm = true
                        }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
    
    // MARK: - Actions
    
    private func deleteTemplate(_ template: TransactionTemplate) async {
        isDeleting = true
        
        do {
            try await dataService.deleteTemplate(id: template.id)
            await authViewModel.refreshTemplates()
        } catch {
            authViewModel.error = error.localizedDescription
        }
        
        templateToDelete = nil
        isDeleting = false
    }
}

// MARK: - Template Row

struct TemplateRow: View {
    let template: TransactionTemplate
    let categories: [Category]
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var category: Category? {
        categories.first { $0.id == template.categoryId }
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                if let icon = category?.icon {
                    Text(icon)
                        .font(.title2)
                } else {
                    Image(systemName: template.transactionType.icon)
                        .font(.title3)
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Template Info
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                HStack(spacing: Theme.Spacing.xs) {
                    Text(template.description)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    
                    if let categoryName = category?.name {
                        Text("•")
                            .foregroundStyle(Theme.Colors.textMuted)
                        Text(categoryName)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            
            Spacer()
            
            // Amount
            Text(formatAmount(template.amount))
                .font(.headline)
                .foregroundStyle(template.transactionType.color)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCardSolid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onTapGesture {
            onEdit()
        }
    }
    
    private var categoryColor: Color {
        if let colorHex = category?.color {
            return Color(hex: colorHex)
        }
        return template.transactionType.color
    }
    
    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.internationalCurrencySymbol = "$"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

#Preview {
    TemplatesView()
        .environment(AuthViewModel())
}

