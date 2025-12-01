import SwiftUI

struct TransactionsListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    
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
        return grouped.sorted { $0.key > $1.key }
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
            .toolbarColorScheme(.dark, for: .navigationBar)
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
    
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Amount
                        VStack(spacing: Theme.Spacing.xs) {
                            Text(transaction.amount.doubleValue.formattedAsMoney())
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(transaction.transactionType.color)
                            
                            Text(transaction.transactionType.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.xl)
                        
                        // Details Card
                        VStack(spacing: 0) {
                            DetailRow(label: "Description", value: transaction.description)
                            Divider().background(Theme.Colors.borderLight)
                            DetailRow(label: "Date", value: transaction.date.formatted(as: .long))
                            
                            if let categoryName = transaction.categoryName {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(
                                    label: "Category",
                                    value: "\(transaction.categoryIcon ?? "") \(categoryName)"
                                )
                            }
                            
                            if let paidByName = transaction.paidByName {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Paid By", value: paidByName)
                            }
                            
                            if let paidToName = transaction.paidToName {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Paid To", value: paidToName)
                            }
                            
                            if transaction.transactionType == .expense {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Split", value: transaction.splitType.displayName)
                            }
                            
                            if let notes = transaction.notes, !notes.isEmpty {
                                Divider().background(Theme.Colors.borderLight)
                                DetailRow(label: "Notes", value: notes)
                            }
                        }
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Delete Button
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                                .foregroundStyle(Theme.Colors.error)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
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
        .alert("Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let householdId = authViewModel.currentHousehold?.id {
                    Task {
                        await transactionViewModel.deleteTransaction(
                            id: transaction.id,
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

#Preview {
    TransactionsListView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}

