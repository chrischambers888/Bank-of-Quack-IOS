import SwiftUI

struct TemplatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let templates: [TransactionTemplate]
    let categories: [Category]
    let onSelect: (TransactionTemplate) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if templates.isEmpty {
                    emptyState
                } else {
                    templatesList
                }
            }
            .navigationTitle("Use Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textMuted)
            
            Text("No Templates")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Create templates in Settings to quickly fill in common transactions")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Templates List
    
    private var templatesList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(templates) { template in
                    TemplatePickerRow(
                        template: template,
                        categories: categories
                    ) {
                        onSelect(template)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }
}

// MARK: - Template Picker Row

struct TemplatePickerRow: View {
    let template: TransactionTemplate
    let categories: [Category]
    let onTap: () -> Void
    
    private var category: Category? {
        categories.first { $0.id == template.categoryId }
    }
    
    var body: some View {
        Button(action: onTap) {
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatAmount(template.amount))
                        .font(.headline)
                        .foregroundStyle(template.transactionType.color)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCardSolid)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
        .buttonStyle(.plain)
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
    TemplatePickerSheet(
        templates: [],
        categories: [],
        onSelect: { _ in }
    )
}

