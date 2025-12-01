import Foundation
import Observation

@Observable
final class TransactionViewModel {
    // MARK: - State
    
    var transactions: [TransactionView] = []
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
            calculateMonthlyTotals()
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
            calculateMonthlyTotals()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
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
        excludedFromBudget: Bool = false,
        notes: String? = nil,
        createdByUserId: UUID?
    ) async throws {
        let dto = CreateTransactionDTO(
            householdId: householdId,
            date: date,
            description: description,
            amount: amount,
            transactionType: transactionType,
            paidByMemberId: paidByMemberId,
            paidToMemberId: paidToMemberId,
            categoryId: categoryId,
            splitType: splitType,
            reimbursesTransactionId: nil,
            excludedFromBudget: excludedFromBudget,
            notes: notes,
            createdByUserId: createdByUserId
        )
        
        try await dataService.createTransaction(dto)
        
        // Refresh transactions
        await fetchTransactions(householdId: householdId)
    }
    
    // MARK: - Delete Transaction
    
    @MainActor
    func deleteTransaction(id: UUID, householdId: UUID) async {
        do {
            try await dataService.deleteTransaction(id: id)
            transactions.removeAll { $0.id == id }
            calculateMonthlyTotals()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Calculations
    
    private func calculateMonthlyTotals() {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        // Filter transactions by matching month/year components (avoids timezone issues)
        let monthTransactions = transactions.filter { t in
            let transactionMonth = calendar.component(.month, from: t.date)
            let transactionYear = calendar.component(.year, from: t.date)
            return transactionMonth == currentMonth && transactionYear == currentYear
        }
        
        // Calculate totals directly
        var expenses: Decimal = 0
        var income: Decimal = 0
        
        for transaction in monthTransactions {
            switch transaction.transactionType {
            case .expense:
                expenses += transaction.amount
            case .income:
                income += transaction.amount
            case .settlement, .reimbursement:
                break
            }
        }
        
        totalExpenses = expenses
        totalIncome = income
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
}

