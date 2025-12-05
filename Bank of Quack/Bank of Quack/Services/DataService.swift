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
    
    func fetchBalanceHealthCheck(householdId: UUID) async throws -> BalanceHealthCheck? {
        let results: [BalanceHealthCheck] = try await supabase
            .from(.balanceHealthCheck)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .execute()
            .value
        return results.first
    }
    
    func fetchProblematicTransactions(householdId: UUID) async throws -> [ProblematicTransaction] {
        try await supabase
            .from(.problematicTransactions)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("date", ascending: false)
            .execute()
            .value
    }
    
    // MARK: - Member Approval
    
    func fetchPendingMembers(householdId: UUID) async throws -> [HouseholdMember] {
        let request = GetPendingMembersRequest(pHouseholdId: householdId)
        
        return try await supabase.client
            .rpc(RPCFunction.getPendingMembers.rawValue, params: request)
            .execute()
            .value
    }
    
    func fetchMyPendingHouseholds() async throws -> [PendingHousehold] {
        try await supabase.client
            .rpc(RPCFunction.getMyPendingHouseholds.rawValue)
            .execute()
            .value
    }
    
    func approveMember(memberId: UUID) async throws {
        let request = ApproveMemberRequest(pMemberId: memberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.approveMember.rawValue, params: request)
            .execute()
            .value
    }
    
    func rejectMember(memberId: UUID) async throws {
        let request = RejectMemberRequest(pMemberId: memberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.rejectMember.rawValue, params: request)
            .execute()
            .value
    }
    
    // MARK: - Member Profile
    
    /// Updates the current user's own profile using RPC function
    func updateMyProfile(memberId: UUID, displayName: String?, avatarEmoji: String?, color: String?) async throws -> HouseholdMember {
        let request = UpdateMyProfileRequest(
            memberId: memberId,
            displayName: displayName,
            avatarUrl: avatarEmoji,
            color: color
        )
        
        return try await supabase.client
            .rpc(RPCFunction.updateMyProfile.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Updates a member's profile (for managed members or when called by owner)
    func updateMemberProfile(memberId: UUID, displayName: String?, avatarEmoji: String?, color: String?) async throws -> HouseholdMember {
        let dto = UpdateMemberProfileDTO(
            displayName: displayName,
            avatarUrl: avatarEmoji,
            color: color
        )
        
        return try await supabase
            .from(.householdMembers)
            .update(dto)
            .eq("id", value: memberId.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
    
    // MARK: - Managed Members
    
    /// Creates a managed member (no user account) that can later be claimed
    func createManagedMember(householdId: UUID, displayName: String, color: String) async throws -> UUID {
        let request = CreateManagedMemberRequest(
            pHouseholdId: householdId,
            pDisplayName: displayName,
            pColor: color
        )
        
        return try await supabase.client
            .rpc(RPCFunction.createManagedMember.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Claims a managed member using the claim code, linking it to the current user
    func claimManagedMember(claimCode: String) async throws -> UUID {
        let request = ClaimManagedMemberRequest(pClaimCode: claimCode)
        
        return try await supabase.client
            .rpc(RPCFunction.claimManagedMember.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Regenerates the claim code for a managed member
    func regenerateClaimCode(memberId: UUID) async throws -> String {
        let request = RegenerateClaimCodeRequest(pMemberId: memberId)
        
        return try await supabase.client
            .rpc(RPCFunction.regenerateClaimCode.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Deletes a managed member (or sets to inactive if they have transaction history)
    func deleteManagedMember(memberId: UUID) async throws {
        let request = DeleteManagedMemberRequest(pMemberId: memberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.deleteManagedMember.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Fetches all managed members for the current user across all households
    func fetchManagedMembers(userId: UUID) async throws -> [HouseholdMember] {
        try await supabase
            .from(.householdMembers)
            .select()
            .eq("managed_by_user_id", value: userId.uuidString)
            .order("created_at")
            .execute()
            .value
    }
    
    /// Checks if the current user has an inactive membership for the given invite code
    func checkInactiveMembership(inviteCode: String) async throws -> InactiveMemberInfo? {
        let request = CheckInactiveMembershipRequest(pInviteCode: inviteCode)
        
        let results: [InactiveMemberInfo] = try await supabase.client
            .rpc(RPCFunction.checkInactiveMembership.rawValue, params: request)
            .execute()
            .value
        
        return results.first
    }
    
    // MARK: - Owner Member Management
    
    /// Removes a member from the household (owner only)
    /// If they have transactions, sets them to inactive; otherwise deletes them
    func removeMember(memberId: UUID) async throws {
        let request = RemoveMemberRequest(pMemberId: memberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.removeMember.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Reactivates an inactive member (owner only)
    func reactivateMember(memberId: UUID) async throws {
        let request = ReactivateMemberRequest(pMemberId: memberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.reactivateMember.rawValue, params: request)
            .execute()
            .value
    }
    
    // MARK: - Ownership Transfer
    
    /// Initiates ownership transfer to a target member (owner only)
    func initiateOwnershipTransfer(householdId: UUID, targetMemberId: UUID) async throws {
        let request = InitiateOwnershipTransferRequest(pHouseholdId: householdId, pTargetMemberId: targetMemberId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.initiateOwnershipTransfer.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Revokes a pending ownership transfer (owner only)
    func revokeOwnershipTransfer(householdId: UUID) async throws {
        let request = RevokeOwnershipTransferRequest(pHouseholdId: householdId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.revokeOwnershipTransfer.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Accepts a pending ownership transfer (target member only)
    func acceptOwnershipTransfer(householdId: UUID) async throws {
        let request = AcceptOwnershipTransferRequest(pHouseholdId: householdId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.acceptOwnershipTransfer.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Declines a pending ownership transfer (target member only)
    func declineOwnershipTransfer(householdId: UUID) async throws {
        let request = DeclineOwnershipTransferRequest(pHouseholdId: householdId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.declineOwnershipTransfer.rawValue, params: request)
            .execute()
            .value
    }
    
    // MARK: - Member Permissions
    
    /// Fetches permissions for a specific member
    func fetchMemberPermissions(memberId: UUID) async throws -> MemberPermissions {
        let request = GetMemberPermissionsRequest(pMemberId: memberId)
        
        let results: [MemberPermissions] = try await supabase.client
            .rpc(RPCFunction.getMemberPermissions.rawValue, params: request)
            .execute()
            .value
        
        // Return the first result or default permissions
        return results.first ?? MemberPermissions.defaultPermissions(for: memberId)
    }
    
    /// Fetches permissions for all members in a household
    func fetchAllMemberPermissions(householdId: UUID) async throws -> [UUID: MemberPermissions] {
        let permissions: [MemberPermissions] = try await supabase
            .from(.memberPermissions)
            .select()
            .execute()
            .value
        
        // Filter to only members in the given household and create a dictionary
        let members = try await fetchMembers(householdId: householdId)
        let memberIds = Set(members.map { $0.id })
        
        var result: [UUID: MemberPermissions] = [:]
        for permission in permissions where memberIds.contains(permission.memberId) {
            result[permission.memberId] = permission
        }
        
        return result
    }
    
    /// Updates permissions for a member (owner only)
    func updateMemberPermissions(
        memberId: UUID,
        canCreateManagedMembers: Bool? = nil,
        canRemoveMembers: Bool? = nil,
        canReactivateMembers: Bool? = nil,
        canApproveJoinRequests: Bool? = nil
    ) async throws {
        let request = UpdateMemberPermissionsRequest(
            pMemberId: memberId,
            pCanCreateManagedMembers: canCreateManagedMembers,
            pCanRemoveMembers: canRemoveMembers,
            pCanReactivateMembers: canReactivateMembers,
            pCanApproveJoinRequests: canApproveJoinRequests
        )
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.updateMemberPermissions.rawValue, params: request)
            .execute()
            .value
    }
    
    /// Updates all permissions for a member at once (owner only)
    func updateMemberPermissions(_ permissions: MemberPermissions) async throws {
        try await updateMemberPermissions(
            memberId: permissions.memberId,
            canCreateManagedMembers: permissions.canCreateManagedMembers,
            canRemoveMembers: permissions.canRemoveMembers,
            canReactivateMembers: permissions.canReactivateMembers,
            canApproveJoinRequests: permissions.canApproveJoinRequests
        )
    }
    
    // MARK: - Household Management
    
    func deleteHousehold(householdId: UUID) async throws {
        let request = DeleteHouseholdRequest(pHouseholdId: householdId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.deleteHousehold.rawValue, params: request)
            .execute()
            .value
    }
    
    func leaveHousehold(householdId: UUID) async throws {
        let request = LeaveHouseholdRequest(pHouseholdId: householdId)
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.leaveHousehold.rawValue, params: request)
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
    
    func createCategory(_ dto: CreateCategoryDTO) async throws -> Category {
        try await supabase
            .from(.categories)
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }
    
    func updateCategory(id: UUID, dto: UpdateCategoryDTO) async throws -> Category {
        try await supabase
            .from(.categories)
            .update(dto)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
    
    func deleteCategory(id: UUID) async throws {
        try await supabase
            .from(.categories)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Sectors
    
    func fetchSectors(householdId: UUID) async throws -> [Sector] {
        try await supabase
            .from(.sectors)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("sort_order")
            .execute()
            .value
    }
    
    func createSector(_ dto: CreateSectorDTO) async throws -> Sector {
        try await supabase
            .from(.sectors)
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }
    
    func updateSector(id: UUID, dto: UpdateSectorDTO) async throws -> Sector {
        try await supabase
            .from(.sectors)
            .update(dto)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
    
    func deleteSector(id: UUID) async throws {
        try await supabase
            .from(.sectors)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Sector Categories (linking)
    
    func fetchSectorCategories(sectorId: UUID) async throws -> [SectorCategory] {
        try await supabase
            .from(.sectorCategories)
            .select()
            .eq("sector_id", value: sectorId.uuidString)
            .execute()
            .value
    }
    
    func addCategoryToSector(sectorId: UUID, categoryId: UUID) async throws {
        let dto = CreateSectorCategoryDTO(sectorId: sectorId, categoryId: categoryId)
        try await supabase
            .from(.sectorCategories)
            .insert(dto)
            .execute()
    }
    
    func removeCategoryFromSector(sectorId: UUID, categoryId: UUID) async throws {
        try await supabase
            .from(.sectorCategories)
            .delete()
            .eq("sector_id", value: sectorId.uuidString)
            .eq("category_id", value: categoryId.uuidString)
            .execute()
    }
    
    func updateSectorCategories(sectorId: UUID, categoryIds: [UUID]) async throws {
        // Delete all existing links
        try await supabase
            .from(.sectorCategories)
            .delete()
            .eq("sector_id", value: sectorId.uuidString)
            .execute()
        
        // Insert new links
        if !categoryIds.isEmpty {
            let dtos = categoryIds.map { CreateSectorCategoryDTO(sectorId: sectorId, categoryId: $0) }
            try await supabase
                .from(.sectorCategories)
                .insert(dtos)
                .execute()
        }
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
    
    func createTransaction(_ dto: CreateTransactionDTO) async throws {
        try await supabase
            .from(.transactions)
            .insert(dto)
            .execute()
    }
    
    /// Creates a transaction with member splits using the RPC function.
    /// This properly snapshots members at transaction time.
    func createTransactionWithSplits(
        householdId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID?,
        categoryId: UUID?,
        splitType: SplitType,
        paidByType: PaidByType,
        splitMemberId: UUID?,
        reimbursesTransactionId: UUID?,
        excludedFromBudget: Bool,
        notes: String?,
        createdByUserId: UUID?,
        splits: [MemberSplit]?
    ) async throws -> UUID {
        let request = CreateTransactionWithSplitsRequest(
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
        
        let transactionId: UUID = try await supabase.client
            .rpc(RPCFunction.createTransactionWithSplits.rawValue, params: request)
            .execute()
            .value
        
        return transactionId
    }
    
    func deleteTransaction(id: UUID) async throws {
        try await supabase
            .from(.transactions)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    /// Updates a transaction with member splits using the RPC function.
    /// This replaces existing splits with new ones based on current settings.
    func updateTransactionWithSplits(
        transactionId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID?,
        categoryId: UUID?,
        splitType: SplitType,
        paidByType: PaidByType,
        splitMemberId: UUID?,
        reimbursesTransactionId: UUID?,
        excludedFromBudget: Bool,
        notes: String?,
        splits: [MemberSplit]?
    ) async throws {
        let request = UpdateTransactionWithSplitsRequest(
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
        
        let _: Bool = try await supabase.client
            .rpc(RPCFunction.updateTransactionWithSplits.rawValue, params: request)
            .execute()
            .value
    }
    
    // MARK: - Transaction Splits
    
    func fetchTransactionSplits(transactionId: UUID) async throws -> [TransactionSplit] {
        try await supabase
            .from(.transactionSplits)
            .select()
            .eq("transaction_id", value: transactionId.uuidString)
            .execute()
            .value
    }
    
    func fetchAllSplitsForHousehold(householdId: UUID) async throws -> [TransactionSplit] {
        // First get all transaction IDs for this household
        let transactions: [TransactionView] = try await fetchTransactions(householdId: householdId)
        let transactionIds = transactions.map { $0.id.uuidString }
        
        guard !transactionIds.isEmpty else { return [] }
        
        return try await supabase
            .from(.transactionSplits)
            .select()
            .in("transaction_id", values: transactionIds)
            .execute()
            .value
    }
    
    // MARK: - Transaction Totals
    
    nonisolated func calculateMonthlyTotals(
        transactions: [TransactionView]
    ) -> (expenses: Decimal, income: Decimal) {
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
        
        return (expenses, income)
    }
    
    // MARK: - Transaction Templates
    
    func fetchTemplates(householdId: UUID) async throws -> [TransactionTemplate] {
        try await supabase
            .from(.transactionTemplates)
            .select()
            .eq("household_id", value: householdId.uuidString)
            .order("sort_order")
            .order("name")
            .execute()
            .value
    }
    
    func createTemplate(_ dto: CreateTemplateDTO) async throws -> TransactionTemplate {
        try await supabase
            .from(.transactionTemplates)
            .insert(dto)
            .select()
            .single()
            .execute()
            .value
    }
    
    func updateTemplate(id: UUID, dto: UpdateTemplateDTO) async throws -> TransactionTemplate {
        try await supabase
            .from(.transactionTemplates)
            .update(dto)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
    }
    
    func deleteTemplate(id: UUID) async throws {
        try await supabase
            .from(.transactionTemplates)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

