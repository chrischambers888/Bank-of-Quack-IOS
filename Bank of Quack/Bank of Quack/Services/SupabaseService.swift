import Foundation
import Supabase

enum AppConfig {
    static let supabaseURL = URL(string: "https://ezskjnrdwtdgpmdxkvml.supabase.co")!
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV6c2tqbnJkd3RkZ3BtZHhrdm1sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MTk4NTAsImV4cCI6MjA4MDA5NTg1MH0.Oqy6Jp40R1rzCw57UjSgTy3Bi8ultE37aGrkGwjCtcQ"
    static let redirectURL = URL(string: "bankofquack://auth-callback")!
}

final class SupabaseService: Sendable {
    nonisolated static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    redirectToURL: AppConfig.redirectURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}

// MARK: - Convenience Accessors

extension SupabaseService {
    nonisolated var auth: AuthClient {
        client.auth
    }
    
    nonisolated func from(_ table: Table) -> PostgrestQueryBuilder {
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
    case approveMember = "approve_member"
    case rejectMember = "reject_member"
    case getPendingMembers = "get_pending_members"
    case getMyPendingHouseholds = "get_my_pending_households"
    case deleteHousehold = "delete_household"
    case leaveHousehold = "leave_household"
    case createTransactionWithSplits = "create_transaction_with_splits"
    case updateTransactionWithSplits = "update_transaction_with_splits"
    
    // Managed members
    case createManagedMember = "create_managed_member"
    case claimManagedMember = "claim_managed_member"
    case regenerateClaimCode = "regenerate_claim_code"
    case deleteManagedMember = "delete_managed_member"
    case checkInactiveMembership = "check_inactive_membership"
}

