import SwiftUI

struct TransactionsListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    @State private var privacyManager = PrivacyManager.shared
    
    @State private var searchText = ""
    @State private var selectedTransaction: TransactionView?
    @State private var isSelectionMode = false
    @State private var selectedTransactionIds: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    
    private var filteredTransactions: [TransactionView] {
        var transactions = transactionViewModel.transactions
        
        // Filter out income transactions when privacy mode is enabled
        if privacyManager.hideIncomeData {
            transactions = transactions.filter { $0.transactionType != .income }
        }
        
        if !searchText.isEmpty {
            transactions = transactions.filter {
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.categoryName?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        return transactions
    }
    
    /// Computed reimbursements by expense ID
    private var reimbursementsByExpense: [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for transaction in transactionViewModel.transactions where transaction.transactionType == .reimbursement {
            if let linkedExpenseId = transaction.reimbursesTransactionId {
                result[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        return result
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
    
    /// Count of linked reimbursements for selected expenses
    private var linkedReimbursementsCount: Int {
        var count = 0
        for id in selectedTransactionIds {
            if let transaction = transactionViewModel.transactions.first(where: { $0.id == id }),
               transaction.transactionType == .expense {
                count += transactionViewModel.reimbursementsForExpense(id).count
            }
        }
        return count
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
                                        TransactionRowSelectable(
                                            transaction: transaction,
                                            reimbursedAmount: reimbursementsByExpense[transaction.id] ?? 0,
                                            isSelectionMode: isSelectionMode,
                                            isSelected: selectedTransactionIds.contains(transaction.id),
                                            onTap: {
                                                if isSelectionMode {
                                                    toggleSelection(transaction.id)
                                                } else {
                                                    selectedTransaction = transaction
                                                }
                                            }
                                        )
                                        
                                        if transaction.id != transactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, isSelectionMode ? 100 : 60)
                                        }
                                    }
                                } header: {
                                    HStack {
                                        if isSelectionMode {
                                            // Select all in month button
                                            Button {
                                                let monthIds = Set(transactions.map { $0.id })
                                                let allSelected = monthIds.isSubset(of: selectedTransactionIds)
                                                if allSelected {
                                                    selectedTransactionIds.subtract(monthIds)
                                                } else {
                                                    selectedTransactionIds.formUnion(monthIds)
                                                }
                                            } label: {
                                                Image(systemName: Set(transactions.map { $0.id }).isSubset(of: selectedTransactionIds) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 22))
                                                    .foregroundStyle(Set(transactions.map { $0.id }).isSubset(of: selectedTransactionIds) ? Theme.Colors.accent : Theme.Colors.textMuted)
                                            }
                                            .padding(.trailing, Theme.Spacing.sm)
                                        }
                                        
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
                            
                            // Add space at bottom for the delete button when in selection mode
                            Spacer(minLength: isSelectionMode && !selectedTransactionIds.isEmpty ? 150 : 100)
                        }
                    }
                    .refreshable {
                        if let householdId = authViewModel.currentHousehold?.id {
                            await transactionViewModel.fetchTransactions(householdId: householdId)
                        }
                    }
                }
                
                // Bulk delete button
                if isSelectionMode && !selectedTransactionIds.isEmpty {
                    VStack {
                        Spacer()
                        
                        Button {
                            showBulkDeleteConfirm = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "trash")
                                Text("Delete \(selectedTransactionIds.count) Transaction\(selectedTransactionIds.count == 1 ? "" : "s")")
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
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectionMode.toggle()
                            if !isSelectionMode {
                                selectedTransactionIds.removeAll()
                            }
                        }
                    } label: {
                        Text(isSelectionMode ? "Done" : "Select")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
            .alert("Delete \(selectedTransactionIds.count) Transaction\(selectedTransactionIds.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let householdId = authViewModel.currentHousehold?.id {
                        Task {
                            await transactionViewModel.bulkDeleteTransactions(
                                ids: selectedTransactionIds,
                                householdId: householdId
                            )
                            withAnimation {
                                selectedTransactionIds.removeAll()
                                isSelectionMode = false
                            }
                        }
                    }
                }
            } message: {
                if linkedReimbursementsCount > 0 {
                    Text("This will also delete \(linkedReimbursementsCount) linked reimbursement\(linkedReimbursementsCount == 1 ? "" : "s"). This action cannot be undone.")
                } else {
                    Text("This action cannot be undone.")
                }
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedTransactionIds.contains(id) {
            selectedTransactionIds.remove(id)
        } else {
            selectedTransactionIds.insert(id)
        }
    }
}

// MARK: - Selectable Transaction Row

struct TransactionRowSelectable: View {
    let transaction: TransactionView
    let reimbursedAmount: Decimal
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
                
                TransactionRow(
                    transaction: transaction,
                    reimbursedAmount: reimbursedAmount
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @State private var showExpenseForDetails = false
    @State private var showPaidByDetails = false
    
    /// Transaction splits for this expense
    private var transactionSplits: [TransactionSplit] {
        transactionViewModel.transactionSplits[currentTransaction.id] ?? []
    }
    
    /// Members who owe money (non-zero owed amount)
    private var membersWhoOwe: [(name: String, amount: Decimal)] {
        transactionSplits
            .filter { $0.owedAmount > 0 }
            .compactMap { split -> (String, Decimal)? in
                if let member = authViewModel.members.first(where: { $0.id == split.memberId }) {
                    return (member.displayName, split.owedAmount)
                }
                return nil
            }
            .sorted { $0.1 > $1.1 }
    }
    
    /// Members who paid (non-zero paid amount)
    private var membersWhoPaid: [(name: String, amount: Decimal)] {
        transactionSplits
            .filter { $0.paidAmount > 0 }
            .compactMap { split -> (String, Decimal)? in
                if let member = authViewModel.members.first(where: { $0.id == split.memberId }) {
                    return (member.displayName, split.paidAmount)
                }
                return nil
            }
            .sorted { $0.1 > $1.1 }
    }
    
    private var splitDisplayText: String {
        // First check for member_only split type
        if currentTransaction.splitType == .memberOnly {
            if let memberName = currentTransaction.splitMemberName {
                return "\(memberName) Only"
            }
            return "Member Only"
        }
        
        // For payerOnly (legacy)
        if currentTransaction.splitType == .payerOnly {
            if let paidByName = currentTransaction.paidByName {
                return "\(paidByName) Only"
            }
            return "Payer Only"
        }
        
        // For custom/equal splits, show member names from splits
        let owingMembers = membersWhoOwe
        if owingMembers.isEmpty {
            return "No splits"
        } else if owingMembers.count == 1 {
            return "\(owingMembers[0].name) Only"
        } else if owingMembers.count == 2 {
            return "Split between \(owingMembers[0].name) & \(owingMembers[1].name)"
        } else {
            return "Split between \(owingMembers.count) members"
        }
    }
    
    private var paidByDisplayText: String {
        // For single payer
        if currentTransaction.paidByType == .single {
            return currentTransaction.paidByName ?? "Single Member"
        }
        
        // For custom/shared, show member names from splits
        let payingMembers = membersWhoPaid
        if payingMembers.isEmpty {
            return currentTransaction.paidByName ?? "Unknown"
        } else if payingMembers.count == 1 {
            return payingMembers[0].name
        } else if payingMembers.count == 2 {
            return "Shared by \(payingMembers[0].name) & \(payingMembers[1].name)"
        } else {
            return "Shared by \(payingMembers.count) members"
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
    
    /// Total amount reimbursed for this expense
    private var totalReimbursed: Decimal {
        linkedReimbursements.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// Cost after reimbursements
    private var costAfterReimbursements: Decimal {
        max(currentTransaction.amount - totalReimbursed, 0)
    }
    
    /// Whether this expense has any reimbursements
    private var hasReimbursements: Bool {
        !linkedReimbursements.isEmpty
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
                            
                            // Show cost after reimbursements for expenses with reimbursements
                            if currentTransaction.transactionType == .expense && hasReimbursements {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .foregroundStyle(Theme.Colors.reimbursement)
                                    
                                    Text("Cost after reimbursements:")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text(costAfterReimbursements.doubleValue.formattedAsMoney())
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                                .padding(.top, Theme.Spacing.sm)
                            }
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
                                
                                // Paid By with expandable details for multiple payers
                                if membersWhoPaid.count > 1 {
                                    ExpandableSplitDetailRow(
                                        label: "Paid By",
                                        summaryText: paidByDisplayText,
                                        memberAmounts: membersWhoPaid,
                                        isExpanded: $showPaidByDetails
                                    )
                                } else {
                                    DetailRow(label: "Paid By", value: paidByDisplayText)
                                }
                                
                                Divider().background(Theme.Colors.borderLight)
                                
                                // Expense For with expandable details for multiple members
                                if membersWhoOwe.count > 1 && currentTransaction.splitType != .memberOnly {
                                    ExpandableSplitDetailRow(
                                        label: "Expense For",
                                        summaryText: splitDisplayText,
                                        memberAmounts: membersWhoOwe,
                                        isExpanded: $showExpenseForDetails
                                    )
                                } else {
                                    DetailRow(label: "Expense For", value: splitDisplayText)
                                }
                                
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
        .task {
            // Fetch splits for expense transactions
            if currentTransaction.transactionType == .expense {
                await transactionViewModel.fetchTransactionSplits(transactionId: currentTransaction.id)
            }
        }
        .fullScreenCover(isPresented: $showEditSheet, onDismiss: {
            // Re-fetch splits after editing to update the displayed values
            if currentTransaction.transactionType == .expense {
                Task {
                    await transactionViewModel.fetchTransactionSplits(transactionId: currentTransaction.id)
                }
            }
        }) {
            EditTransactionView(transaction: currentTransaction)
        }
        .alert(hasReimbursements ? "Delete Expense & Reimbursements?" : "Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button(hasReimbursements ? "Delete All" : "Delete", role: .destructive) {
                if let householdId = authViewModel.currentHousehold?.id {
                    Task {
                        if currentTransaction.transactionType == .expense && hasReimbursements {
                            await transactionViewModel.deleteExpenseWithReimbursements(
                                id: currentTransaction.id,
                                householdId: householdId
                            )
                        } else {
                            await transactionViewModel.deleteTransaction(
                                id: currentTransaction.id,
                                householdId: householdId
                            )
                        }
                        dismiss()
                    }
                }
            }
        } message: {
            if hasReimbursements {
                Text("This expense has \(linkedReimbursements.count) linked reimbursement\(linkedReimbursements.count == 1 ? "" : "s") totaling \(totalReimbursed.doubleValue.formattedAsMoney()). Deleting this expense will also delete all linked reimbursements. This action cannot be undone.")
            } else {
                Text("This action cannot be undone.")
            }
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

struct ExpandableSplitDetailRow: View {
    let label: String
    let summaryText: String
    let memberAmounts: [(name: String, amount: Decimal)]
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.leading, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded details
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(memberAmounts, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            Spacer()
                            
                            Text(item.amount.doubleValue.formattedAsMoney())
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                .padding(.bottom, Theme.Spacing.sm)
                .background(Theme.Colors.backgroundSecondary.opacity(0.5))
            }
        }
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

