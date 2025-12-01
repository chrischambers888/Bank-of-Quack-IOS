import Foundation
import Supabase

enum DataError: LocalizedError {
    case notFound
    case invalidData
    case unauthorized
    case networkError
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Data not found."
        case .invalidData:
            return "Invalid data received."
        case .unauthorized:
            return "You don't have permission to perform this action."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}

actor DataService {
    private let supabase = SupabaseService.shared
    
    // MARK: - Households
    
    func fetchUserHouseholds(userId: UUID) async throws -> [Household] {
        let memberRecords: [HouseholdMember] = try await supabase
            .from(.householdMembers)
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard !memberRecords.isEmpty else { return [] }
        
        let householdIds = memberRecords.map { $0.householdId.uuidString }
        
        let households: [Household] = try await supabase
            .from(.households)
            .select()
            .in("id", values: householdIds)
            .execute()
            .value
        
        return households
    }
    
    func createHousehold(name: String, displayName: String) async throws -> UUID {
        let request = CreateHouseholdRequest(pName: name, pDisplayName: displayName)
        
        let response: UUID = try await supabase.client
            .rpc(RPCFunction.createHousehold.rawValue, params: request)
            .execute()
            .value
        
        return response
    }
    
    func joinHousehold(inviteCode: String, displayName: String) async throws -> UUID {
        let request = JoinHouseholdRequest(pInviteCode: inviteCode, pDisplayName: displayName)
        
        let response: UUID = try await supabase.client
            .rpc(RPCFunction.joinHousehold.rawValue, params: request)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Members
    
    func fetchMembers(householdId: UUID) async throws -> [HouseholdMember] {
        try await supabase
            .from(.householdMembers)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("created_at")
            .execute()
            .value
    }
    
    func fetchCurrentMember(householdId: UUID, userId: UUID) async throws -> HouseholdMember? {
        let members: [HouseholdMember] = try await supabase
            .from(.householdMembers)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        
        return members.first
    }
    
    func fetchMemberBalances(householdId: UUID) async throws -> [MemberBalance] {
        try await supabase
            .from(.memberBalances)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .execute()
            .value
    }
    
    // MARK: - Categories
    
    func fetchCategories(householdId: UUID) async throws -> [Category] {
        try await supabase
            .from(.categories)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("sort_order")
            .execute()
            .value
    }
    
    // MARK: - Transactions
    
    func fetchTransactions(householdId: UUID, limit: Int? = nil) async throws -> [TransactionView] {
        var query = supabase
            .from(.transactionsView)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("date", ascending: false)
            .order("created_at", ascending: false)
        
        if let limit = limit {
            query = query.limit(limit)
        }
        
        return try await query.execute().value
    }
    
    func fetchTransactions(
        householdId: UUID,
        startDate: Date,
        endDate: Date
    ) async throws -> [TransactionView] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        return try await supabase
            .from(.transactionsView)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .gte("date", value: formatter.string(from: startDate))
            .lte("date", value: formatter.string(from: endDate))
            .order("date", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    func createTransaction(_ dto: CreateTransactionDTO) async throws -> Transaction {
        try await supabase
            .from(.transactions)
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }
    
    func deleteTransaction(id: UUID) async throws {
        try await supabase
            .from(.transactions)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Transaction Totals
    
    func calculateMonthlyTotals(
        transactions: [TransactionView]
    ) -> (expenses: Decimal, income: Decimal) {
        var expenses: Decimal = 0
        var income: Decimal = 0
        
        for transaction in transactions {
            switch transaction.transactionType {
            case .expense:
                expenses += transaction.amount
            case .income:
                income += transaction.amount
            case .settlement, .reimbursement:
                break
            }
        }
        
        return (expenses, income)
    }
}

