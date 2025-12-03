import SwiftUI

struct TransactionsListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var searchText = ""
    @State private var selectedTransaction: TransactionView?
    
    private var filteredTransactions: [TransactionView] {
        if searchText.isEmpty {
            return transactionViewModel.transactions
        }
        return transactionViewModel.transactions.filter {
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.categoryName?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    private var groupedTransactions: [(String, [TransactionView])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            transaction.date.formatted(as: .monthYear)
        }
        // Sort groups by date (newest month first), and transactions within each group (newest first)
        return grouped
            .map { (key, transactions) in
                (key, transactions.sorted { $0.date > $1.date })
            }
            .sorted { first, second in
                // Compare by the first transaction's date in each group
                guard let firstDate = first.1.first?.date,
                      let secondDate = second.1.first?.date else {
                    return first.0 > second.0
                }
                return firstDate > secondDate
            }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if transactionViewModel.transactions.isEmpty && !transactionViewModel.isLoading {
                    EmptyTransactionsView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedTransactions, id: \.0) { month, transactions in
                                Section {
                                    ForEach(transactions) { transaction in
                                        Button {
                                            selectedTransaction = transaction
                                        } label: {
                                            TransactionRow(transaction: transaction)
                                        }
                                        
                                        if transaction.id != transactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 60)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        Text(month)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(Theme.Colors.backgroundPrimary)
                                }
                            }
                            
                            Spacer(minLength: 100)
                        }
                    }
                    .refreshable {
                        if let householdId = authViewModel.currentHousehold?.id {
                            await transactionViewModel.fetchTransactions(householdId: householdId)
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search transactions")
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
        }
    }
}

struct EmptyTransactionsView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundStyle(Theme.Colors.textMuted)
            
            Text("No Transactions Yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Add your first transaction using the + tab")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct TransactionDetailView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @Environment(\.dismiss) private var dismiss
    
    let transaction: TransactionView
    
    // Look up the current transaction from the view model for live updates after editing
    private var currentTransaction: TransactionView {
        transactionViewModel.transactions.first { $0.id == transaction.id } ?? transaction
    }
    
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    
    private var splitDisplayText: String {
        switch currentTransaction.splitType {
        case .equal:
            return "Split Equally"
        case .memberOnly:
            if let memberName = currentTransaction.splitMemberName {
                return "\(memberName) Only"
            }
            return "Member Only"
        case .custom:
            return "Custom Split"
        case .payerOnly:
            if let paidByName = currentTransaction.paidByName {
                return "\(paidByName) Only"
            }
            return "Payer Only"
        }
    }
    
    private var paidByDisplayText: String {
        switch currentTransaction.paidByType {
        case .single:
            return currentTransaction.paidByName ?? "Single Member"
        case .shared:
            return "Shared Equally"
        case .custom:
            return "Custom Split"
        }
    }
    
    /// For reimbursements: the expense this reimbursement is linked to
    private var linkedExpense: TransactionView? {
        guard currentTransaction.transactionType == .reimbursement,
              let linkedId = currentTransaction.reimbursesTransactionId else { return nil }
        return transactionViewModel.transactions.first { $0.id == linkedId }
    }
    
    /// For expenses: any reimbursements linked to this expense
    private var linkedReimbursements: [TransactionView] {
        guard currentTransaction.transactionType == .expense else { return [] }
        return transactionViewModel.transactions.filter {
            $0.transactionType == .reimbursement && $0.reimbursesTransactionId == currentTransaction.id
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Amount
                        VStack(spacing: Theme.Spacing.xs) {
                            Text(currentTransaction.amount.doubleValue.formattedAsMoney())
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(currentTransaction.transactionType.color)
                            
                            Text(currentTransaction.transactionType.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.xl)
                        
                        // Details Card
                        VStack(spacing: 0) {
                            DetailRow(label: "Description", value: currentTransaction.description)
                            Divider().background(Theme.Colors.borderLight)
                            DetailRow(label: "Date", value: currentTransaction.date.formatted(as: .long))
                            
                            if let categoryName = currentTransaction.categoryName {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(
                                    label: "Category",
                                    value: "\(currentTransaction.categoryIcon ?? "") \(categoryName)"
                                )
                            }
                            
                            if currentTransaction.transactionType == .expense {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Paid By", value: paidByDisplayText)
                                
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Expense For", value: splitDisplayText)
                                
                                // Show reimbursements linked to this expense
                                if !linkedReimbursements.isEmpty {
                                    Divider().background(Theme.Colors.borderLight)
                                    ReimbursementsDetailRow(reimbursements: linkedReimbursements)
                                }
                            } else if currentTransaction.transactionType == .income {
                                if let paidByName = currentTransaction.paidByName {
                                    Divider().background(Theme.Colors.borderLight)
                                    DetailRow(label: "Received By", value: paidByName)
                                }
                            } else if currentTransaction.transactionType == .reimbursement {
                                if let paidByName = currentTransaction.paidByName {
                                    Divider().background(Theme.Colors.borderLight)
                                    DetailRow(label: "Received By", value: paidByName)
                                }
                                
                                // Show linked expense info
                                if let linkedExpense = linkedExpense {
                                    Divider().background(Theme.Colors.borderLight)
                                    LinkedExpenseDetailRow(expense: linkedExpense)
                                } else {
                                    Divider().background(Theme.Colors.borderLight)
                                    DetailRow(label: "Linked Expense", value: "None (counts as income)")
                                }
                            } else {
                                if let paidByName = currentTransaction.paidByName {
                                    Divider().background(Theme.Colors.borderLight)
                                    DetailRow(label: "Paid By", value: paidByName)
                                }
                            }
                            
                            if let paidToName = currentTransaction.paidToName {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Paid To", value: paidToName)
                            }
                            
                            if let notes = currentTransaction.notes, !notes.isEmpty {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Notes", value: notes)
                            }
                        }
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Action Buttons
                        VStack(spacing: Theme.Spacing.sm) {
                            // Edit Button
                            Button {
                                showEditSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit Transaction")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.md)
                                .background(Theme.Colors.accent)
                                .foregroundStyle(Theme.Colors.textInverse)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            }
                            
                            // Delete Button
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Transaction")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.md)
                                .background(Theme.Colors.error.opacity(0.1))
                                .foregroundStyle(Theme.Colors.error)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .fullScreenCover(isPresented: $showEditSheet) {
            EditTransactionView(transaction: currentTransaction)
        }
        .alert("Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let householdId = authViewModel.currentHousehold?.id {
                    Task {
                        await transactionViewModel.deleteTransaction(
                            id: currentTransaction.id,
                            householdId: householdId
                        )
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(Theme.Spacing.md)
    }
}

struct LinkedExpenseDetailRow: View {
    let expense: TransactionView
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Linked Expense")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(expense.amount.doubleValue.formattedAsMoney())
                            .font(.caption)
                        Text("•")
                            .font(.caption)
                        Text(expense.date.formatted(as: .dayMonth))
                            .font(.caption)
                        if let categoryName = expense.categoryName {
                            Text("•")
                                .font(.caption)
                            Text(categoryName)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.md)
    }
}

struct ReimbursementsDetailRow: View {
    let reimbursements: [TransactionView]
    
    private var totalReimbursed: Decimal {
        reimbursements.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Reimbursements")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                Text("-\(totalReimbursed.doubleValue.formattedAsMoney())")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.success)
            }
            
            ForEach(reimbursements) { reimbursement in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reimbursement.description)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(reimbursement.date.formatted(as: .dayMonth))
                            if let receivedBy = reimbursement.paidByName {
                                Text("•")
                                Text("Received by \(receivedBy)")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Spacer()
                    
                    Text(reimbursement.amount.doubleValue.formattedAsMoney())
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.success)
                }
                .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.md)
    }
}

#Preview {
    TransactionsListView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}

