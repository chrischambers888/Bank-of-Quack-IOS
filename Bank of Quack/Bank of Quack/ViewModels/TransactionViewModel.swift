import Foundation
import Observation

@Observable
final class TransactionViewModel {
    // MARK: - State
    
    var transactions: [TransactionView] = []
    var transactionSplits: [UUID: [TransactionSplit]] = [:] // Keyed by transaction ID
    var isLoading = false
    var error: String?
    
    // Monthly stats
    var totalExpenses: Decimal = 0
    var totalIncome: Decimal = 0
    var netAmount: Decimal { totalIncome - totalExpenses }
    
    // MARK: - Services
    
    private let dataService = DataService()
    
    // MARK: - Fetch Transactions
    
    @MainActor
    func fetchTransactions(householdId: UUID) async {
        isLoading = true
        error = nil
        
        do {
            transactions = try await dataService.fetchTransactions(householdId: householdId)
            calculateTotals()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func fetchCurrentMonthTransactions(householdId: UUID) async {
        isLoading = true
        error = nil
        
        let now = Date()
        let startOfMonth = now.startOfMonth
        let endOfMonth = now.endOfMonth
        
        do {
            transactions = try await dataService.fetchTransactions(
                householdId: householdId,
                startDate: startOfMonth,
                endDate: endOfMonth
            )
            calculateTotals()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func fetchTransactionSplits(transactionId: UUID) async {
        do {
            let splits = try await dataService.fetchTransactionSplits(transactionId: transactionId)
            transactionSplits[transactionId] = splits
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Create Transaction
    
    @MainActor
    func createTransaction(
        householdId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID? = nil,
        categoryId: UUID? = nil,
        splitType: SplitType = .equal,
        paidByType: PaidByType = .single,
        splitMemberId: UUID? = nil,
        reimbursesTransactionId: UUID? = nil,
        excludedFromBudget: Bool = false,
        notes: String? = nil,
        createdByUserId: UUID?,
        splits: [MemberSplit]? = nil
    ) async throws {
        _ = try await dataService.createTransactionWithSplits(
            householdId: householdId,
            date: date,
            description: description,
            amount: amount,
            transactionType: transactionType,
            paidByMemberId: paidByMemberId,
            paidToMemberId: paidToMemberId,
            categoryId: categoryId,
            splitType: splitType,
            paidByType: paidByType,
            splitMemberId: splitMemberId,
            reimbursesTransactionId: reimbursesTransactionId,
            excludedFromBudget: excludedFromBudget,
            notes: notes,
            createdByUserId: createdByUserId,
            splits: splits
        )
        
        // Refresh transactions
        await fetchTransactions(householdId: householdId)
    }
    
    // MARK: - Update Transaction
    
    @MainActor
    func updateTransaction(
        transactionId: UUID,
        householdId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID? = nil,
        categoryId: UUID? = nil,
        splitType: SplitType = .equal,
        paidByType: PaidByType = .single,
        splitMemberId: UUID? = nil,
        reimbursesTransactionId: UUID? = nil,
        excludedFromBudget: Bool = false,
        notes: String? = nil,
        splits: [MemberSplit]? = nil
    ) async throws {
        try await dataService.updateTransactionWithSplits(
            transactionId: transactionId,
            date: date,
            description: description,
            amount: amount,
            transactionType: transactionType,
            paidByMemberId: paidByMemberId,
            paidToMemberId: paidToMemberId,
            categoryId: categoryId,
            splitType: splitType,
            paidByType: paidByType,
            splitMemberId: splitMemberId,
            reimbursesTransactionId: reimbursesTransactionId,
            excludedFromBudget: excludedFromBudget,
            notes: notes,
            splits: splits
        )
        
        // Clear cached splits for this transaction
        transactionSplits.removeValue(forKey: transactionId)
        
        // Refresh transactions
        await fetchTransactions(householdId: householdId)
    }
    
    // MARK: - Delete Transaction
    
    @MainActor
    func deleteTransaction(id: UUID, householdId: UUID) async {
        do {
            try await dataService.deleteTransaction(id: id)
            transactions.removeAll { $0.id == id }
            transactionSplits.removeValue(forKey: id)
            calculateTotals()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Calculations
    
    private func calculateTotals() {
        var expenses: Decimal = 0
        var income: Decimal = 0
        
        // First, build a map of linked reimbursements per expense
        var reimbursementsByExpense: [UUID: Decimal] = [:]
        for transaction in transactions {
            if transaction.transactionType == .reimbursement,
               let linkedExpenseId = transaction.reimbursesTransactionId {
                reimbursementsByExpense[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        
        for transaction in transactions {
            switch transaction.transactionType {
            case .expense:
                // Subtract any linked reimbursements from this expense
                let reimbursedAmount = reimbursementsByExpense[transaction.id] ?? 0
                let effectiveExpense = max(transaction.amount - reimbursedAmount, 0)
                expenses += effectiveExpense
            case .income:
                income += transaction.amount
            case .reimbursement:
                // Unlinked reimbursements count as income
                if transaction.reimbursesTransactionId == nil {
                    income += transaction.amount
                }
                // Linked reimbursements are already handled by reducing expenses above
            case .settlement:
                break
            }
        }
        
        totalExpenses = expenses
        totalIncome = income
    }
    
    // MARK: - Reimbursements
    
    /// Returns all reimbursements linked to a specific expense
    func reimbursementsForExpense(_ expenseId: UUID) -> [TransactionView] {
        transactions.filter { $0.transactionType == .reimbursement && $0.reimbursesTransactionId == expenseId }
    }
    
    /// Returns the total amount reimbursed for an expense
    func totalReimbursedAmount(for expenseId: UUID) -> Decimal {
        reimbursementsForExpense(expenseId).reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// Deletes an expense and all its linked reimbursements
    @MainActor
    func deleteExpenseWithReimbursements(id: UUID, householdId: UUID) async {
        do {
            // First delete all linked reimbursements
            let linkedReimbursements = reimbursementsForExpense(id)
            for reimbursement in linkedReimbursements {
                try await dataService.deleteTransaction(id: reimbursement.id)
                transactions.removeAll { $0.id == reimbursement.id }
                transactionSplits.removeValue(forKey: reimbursement.id)
            }
            
            // Then delete the expense itself
            try await dataService.deleteTransaction(id: id)
            transactions.removeAll { $0.id == id }
            transactionSplits.removeValue(forKey: id)
            calculateTotals()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Filtering
    
    func recentTransactions(limit: Int = 5) -> [TransactionView] {
        Array(transactions.prefix(limit))
    }
    
    func transactionsByCategory() -> [UUID: [TransactionView]] {
        Dictionary(grouping: transactions.filter { $0.transactionType == .expense }) {
            $0.categoryId ?? UUID()
        }
    }
    
    func clearError() {
        error = nil
    }
    
    // MARK: - Bulk Delete
    
    /// Deletes multiple transactions at once
    @MainActor
    func bulkDeleteTransactions(ids: Set<UUID>, householdId: UUID) async {
        guard !ids.isEmpty else { return }
        
        do {
            // Get all transactions to delete, including any linked reimbursements
            var allIdsToDelete = ids
            
            // For each expense being deleted, also delete its linked reimbursements
            for id in ids {
                if let transaction = transactions.first(where: { $0.id == id }),
                   transaction.transactionType == .expense {
                    let linkedReimbursements = reimbursementsForExpense(id)
                    for reimbursement in linkedReimbursements {
                        allIdsToDelete.insert(reimbursement.id)
                    }
                }
            }
            
            // Delete all transactions
            for id in allIdsToDelete {
                try await dataService.deleteTransaction(id: id)
                transactions.removeAll { $0.id == id }
                transactionSplits.removeValue(forKey: id)
            }
            
            calculateTotals()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
