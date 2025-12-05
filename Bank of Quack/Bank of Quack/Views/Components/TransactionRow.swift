import SwiftUI

struct TransactionRow: View {
    let transaction: TransactionView
    /// Total amount reimbursed for this expense (if any)
    var reimbursedAmount: Decimal = 0
    /// Optional: The portion amount when filtering by member(s) - only the selected members' share
    var portionAmount: Decimal? = nil
    /// Optional: The percentage of the total that this portion represents (0-100)
    var portionPercentage: Decimal? = nil
    
    /// Effective amount after reimbursements (full transaction amount)
    private var effectiveAmount: Decimal {
        if transaction.transactionType == .expense && reimbursedAmount > 0 {
            return max(transaction.amount - reimbursedAmount, 0)
        }
        return transaction.amount
    }
    
    /// Display amount - uses portion if provided and different from full amount
    private var displayAmount: Decimal {
        if let portion = portionAmount, portion != effectiveAmount {
            return portion
        }
        return effectiveAmount
    }
    
    /// Whether showing a member's portion (not full amount)
    private var isShowingPortion: Bool {
        if let portion = portionAmount, portion != effectiveAmount {
            return true
        }
        return false
    }
    
    /// Whether this expense has reimbursements
    private var hasReimbursements: Bool {
        transaction.transactionType == .expense && reimbursedAmount > 0
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Category Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                // Note: "folder" string is invalid (was a bug) - treat as nil
                if let icon = transaction.categoryIcon, !icon.isEmpty, icon != "folder" {
                    Text(icon)
                        .font(.title3)
                } else {
                    Image(systemName: transaction.transactionType.icon)
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    if let categoryName = transaction.categoryName {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    if transaction.categoryName != nil && transaction.paidByName != nil {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    if let paidByName = transaction.paidByName {
                        Text(paidByName)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            // Amount and Date
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    // Reimbursement indicator
                    if hasReimbursements {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.reimbursement)
                    }
                    
                    // Portion badge when showing member's share
                    if isShowingPortion, let percentage = portionPercentage {
                        PortionBadge(percentage: percentage)
                    }
                    
                    Text(amountText)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(amountColor)
                }
                
                Text(transaction.date.formatted(as: .dayMonth))
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .contentShape(Rectangle())
    }
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        return transaction.transactionType.color
    }
    
    private var amountText: String {
        let formatted = displayAmount.doubleValue.formattedAsMoney()
        switch transaction.transactionType {
        case .expense:
            return "-\(formatted)"
        case .income:
            return "+\(formatted)"
        case .settlement, .reimbursement:
            return formatted
        }
    }
    
    private var amountColor: Color {
        switch transaction.transactionType {
        case .expense:
            return Theme.Colors.expense
        case .income:
            return Theme.Colors.income
        case .settlement:
            return Theme.Colors.settlement
        case .reimbursement:
            return Theme.Colors.reimbursement
        }
    }
}

struct RecentTransactionsCard: View {
    let transactions: [TransactionView]
    var onSeeAll: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if let onSeeAll = onSeeAll {
                    Button("See All") {
                        onSeeAll()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            
            if transactions.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text("No transactions yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        TransactionRow(transaction: transaction)
                        
                        if transaction.id != transactions.last?.id {
                            Divider()
                                .background(Theme.Colors.borderLight)
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
    }
}

// MARK: - Portion Badge

/// Badge showing the percentage of a shared transaction when filtering by member
struct PortionBadge: View {
    let percentage: Decimal
    
    private var displayText: String {
        let rounded = NSDecimalNumber(decimal: percentage).intValue
        return "\(rounded)%"
    }
    
    var body: some View {
        Text(displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.Colors.accent.opacity(0.15))
            .clipShape(Capsule())
    }
}

#Preview {
    ScrollView {
        VStack {
            RecentTransactionsCard(transactions: [])
        }
        .padding()
    }
    .background(Theme.Colors.backgroundPrimary)
}

