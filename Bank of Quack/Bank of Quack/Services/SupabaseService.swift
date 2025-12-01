import Foundation
import Supabase

enum SupabaseConfig {
    // TODO: Replace with your actual Supabase credentials
    static let url = URL(string: "https://ezskjnrdwtdgpmdxkvml.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV6c2tqbnJkd3RkZ3BtZHhrdm1sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MTk4NTAsImV4cCI6MjA4MDA5NTg1MH0.Oqy6Jp40R1rzCw57UjSgTy3Bi8ultE37aGrkGwjCtcQ"
}

final class SupabaseService: Sendable {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
    }
}

// MARK: - Convenience Accessors

extension SupabaseService {
    var auth: AuthClient {
        client.auth
    }
    
    var database: PostgrestClient {
        client.database
    }
    
    func from(_ table: Table) -> PostgrestQueryBuilder {
        client.from(table.rawValue)
    }
}

// MARK: - Table Names

enum Table: String {
    case households
    case householdMembers = "household_members"
    case categories
    case sectors
    case sectorCategories = "sector_categories"
    case transactions
    case transactionSplits = "transaction_splits"
    case budgets
    case memberBudgets = "member_budgets"
    case transactionTemplates = "transaction_templates"
    case householdSettings = "household_settings"
    
    // Views
    case transactionsView = "transactions_view"
    case memberBalances = "member_balances"
}

// MARK: - RPC Functions

enum RPCFunction: String {
    case createHousehold = "create_household"
    case joinHousehold = "join_household"
    case regenerateInviteCode = "regenerate_invite_code"
}

