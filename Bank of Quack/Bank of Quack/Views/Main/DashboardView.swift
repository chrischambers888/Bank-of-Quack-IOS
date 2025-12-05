import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    @State private var privacyManager = PrivacyManager.shared
    
    @State private var memberBalances: [MemberBalance] = []
    @State private var allSplits: [UUID: [TransactionSplit]] = [:] // Keyed by transaction ID
    @State private var isLoadingBalances = false
    @State private var showBalanceDetails = false
    @State private var showFilterSheet = false
    @State private var showExpensesDetail = false
    @State private var showIncomeDetail = false
    @State private var showNetBalanceDetail = false
    
    // Shared filter state (passed from MainTabView)
    @Bindable var filterManager: DashboardFilterManager
    
    // Use authViewModel's data for sectors/categories (same source as Settings)
    // This ensures consistency and avoids potential fetch issues
    private var sectors: [Sector] { authViewModel.sectors }
    private var categories: [Category] { authViewModel.categories }
    private var sectorCategories: [UUID: [UUID]] { authViewModel.sectorCategories }
    
    private let dataService = DataService()
    
    private var currentMemberBalance: Decimal {
        guard let memberId = authViewModel.currentMember?.id else { return 0 }
        return memberBalances.first { $0.memberId == memberId }?.balance ?? 0
    }
    
    /// Filtered member balances calculated from filtered transactions
    private var filteredMemberBalances: [MemberBalance] {
        var balancesByMember: [UUID: (paid: Decimal, owed: Decimal, name: String)] = [:]
        
        // Initialize all members
        for member in authViewModel.members {
            balancesByMember[member.id] = (paid: 0, owed: 0, name: member.displayName)
        }
        
        // Track visible expense IDs for reimbursement processing
        var visibleExpenseIds = Set<UUID>()
        
        // Process filtered transactions (expenses, settlements, income - but NOT reimbursements yet)
        for transaction in filteredTransactions {
            switch transaction.transactionType {
            case .expense:
                // Track this expense as visible
                visibleExpenseIds.insert(transaction.id)
                
                // Use splits to determine paid and owed amounts
                if let splits = allSplits[transaction.id] {
                    for split in splits {
                        if var memberData = balancesByMember[split.memberId] {
                            memberData.paid += split.paidAmount
                            memberData.owed += split.owedAmount
                            balancesByMember[split.memberId] = memberData
                        }
                    }
                }
                
            case .settlement:
                // Settlement: payer's balance increases, recipient's decreases
                if let payerId = transaction.paidByMemberId,
                   let recipientId = transaction.paidToMemberId {
                    if var payerData = balancesByMember[payerId] {
                        payerData.paid += transaction.amount
                        balancesByMember[payerId] = payerData
                    }
                    if var recipientData = balancesByMember[recipientId] {
                        recipientData.owed += transaction.amount // Increases their share, reducing balance
                        balancesByMember[recipientId] = recipientData
                    }
                }
                
            case .reimbursement:
                // Reimbursements are processed separately below to include ALL reimbursements
                // linked to visible expenses (regardless of filters)
                break
                
            case .income:
                // Income doesn't affect member balances
                break
            }
        }
        
        // Process ALL reimbursements linked to visible expenses (from ALL transactions, not just filtered)
        // Reimbursements always follow their linked expense - if expense is visible, include all its reimbursements
        for transaction in transactionViewModel.transactions {
            guard transaction.transactionType == .reimbursement,
                  let linkedExpenseId = transaction.reimbursesTransactionId,
                  visibleExpenseIds.contains(linkedExpenseId),
                  let linkedSplits = allSplits[linkedExpenseId],
                  let recipientId = transaction.paidByMemberId else {
                continue
            }
            
            // Reimbursements always affect balances when linked to an expense
            // The logic depends on whether the recipient was a payer:
            //
            // Example 1: A pays $100 for A,B (50/50); B gets $100 reimbursement
            //   - Expense reduced to $0, everyone's owed reduced proportionally
            //   - But B received $100 that "belonged" to the payers (A paid it all)
            //   - So B now owes A $100 → A: +$100, B: -$100
            //
            // Example 2: A pays $100 for A,B (50/50); A gets $100 reimbursement
            //   - A's paid reduced by $100, expense effectively $0
            //   - Everyone's owed reduced proportionally
            //   - → A: $0, B: $0 (all settled)
            
            let reimbursementAmount = transaction.amount
            let totalOwed = linkedSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
            
            // Step 1: Reduce everyone's owed proportionally (expense is smaller)
            for split in linkedSplits {
                let owedPercentage = totalOwed > 0 ? split.owedAmount / totalOwed : 0
                let owedReduction = reimbursementAmount * owedPercentage
                
                if var memberData = balancesByMember[split.memberId] {
                    memberData.owed -= owedReduction
                    balancesByMember[split.memberId] = memberData
                }
            }
            
            // Step 2: If recipient was a payer, reduce their paid
            let recipientSplit = linkedSplits.first { $0.memberId == recipientId }
            let recipientPaidAmount = recipientSplit?.paidAmount ?? 0
            let effectivePaidReduction = min(reimbursementAmount, recipientPaidAmount)
            
            if effectivePaidReduction > 0 {
                if var recipientData = balancesByMember[recipientId] {
                    recipientData.paid -= effectivePaidReduction
                    balancesByMember[recipientId] = recipientData
                }
            }
            
            // Step 3: Remaining reimbursement (what recipient got but didn't pay for)
            // is owed to the original payers
            let remainingReimbursement = reimbursementAmount - effectivePaidReduction
            if remainingReimbursement > 0 {
                if var recipientData = balancesByMember[recipientId] {
                    recipientData.owed += remainingReimbursement
                    balancesByMember[recipientId] = recipientData
                }
            }
        }
        
        // Convert to MemberBalance array
        guard let householdId = authViewModel.currentHousehold?.id else { return [] }
        
        return balancesByMember.map { memberId, data in
            MemberBalance(
                householdId: householdId,
                memberId: memberId,
                displayName: data.name,
                totalPaid: data.paid,
                totalShare: data.owed,
                balance: data.paid - data.owed
            )
        }.sorted { $0.displayName < $1.displayName }
    }
    
    /// Current member's filtered balance
    private var filteredCurrentMemberBalance: Decimal {
        guard let memberId = authViewModel.currentMember?.id else { return 0 }
        return filteredMemberBalances.first { $0.memberId == memberId }?.balance ?? 0
    }
    
    /// Member lookup for expense breakdown (includes inactive members for historical data)
    private var memberLookup: [UUID: HouseholdMember] {
        Dictionary(uniqueKeysWithValues: authViewModel.members.map { ($0.id, $0) })
    }
    
    /// Active members only (for counting purposes where inactive shouldn't be included)
    private var activeMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isActive }
    }
    
    /// First transaction date (earliest) for "All Time" filter display
    private var firstTransactionDate: Date? {
        transactionViewModel.transactions.map { $0.date }.min()
    }
    
    /// Last transaction date (latest) for "All Time" filter display
    private var lastTransactionDate: Date? {
        transactionViewModel.transactions.map { $0.date }.max()
    }
    
    /// Count of members with non-zero balances (for display in balance card)
    private var membersWithNonZeroBalance: Int {
        filteredMemberBalances.filter { abs($0.balance.doubleValue) >= 0.01 }.count
    }
    
    /// Whether to show the balance widget on the dashboard
    /// Show when: multiple active members OR single active member with non-zero balance
    /// Hide when: any member filtering is active (balance concept is confusing when filtering by members)
    private var shouldShowBalanceWidget: Bool {
        // Hide when member filtering is active - balance is confusing in this context
        if !filterManager.filter.selectedMemberIds.isEmpty || filterManager.filter.sharedOnly {
            return false
        }
        
        // Multiple active members - always show (balance tracking makes sense)
        if activeMembers.count > 1 {
            return true
        }
        
        // Single active member - only show if they have a non-zero balance
        // (could happen from inactive members or old shared transactions)
        return abs(filteredCurrentMemberBalance.doubleValue) >= 0.01
    }
    
    /// Get all category IDs within selected sectors
    private var categoriesInSelectedSectors: Set<UUID> {
        guard !filterManager.filter.selectedSectorIds.isEmpty else { return [] }
        var categoryIds = Set<UUID>()
        for sectorId in filterManager.filter.selectedSectorIds {
            if let cats = sectorCategories[sectorId] {
                categoryIds.formUnion(cats)
            }
        }
        return categoryIds
    }
    
    /// Filtered transactions based on current filter state
    private var filteredTransactions: [TransactionView] {
        let filter = filterManager.filter
        
        return transactionViewModel.transactions.filter { transaction in
            // 1. Date filter
            if let dateRange = filter.dateRange {
                guard transaction.date >= dateRange.start && transaction.date <= dateRange.end else {
                    return false
                }
            }
            
            // 2. Transaction type filter
            guard filter.selectedTransactionTypes.contains(transaction.transactionType.rawValue) else {
                return false
            }
            
            // 3. Category/Sector filter (only applies to transactions with categories)
            if !filter.selectedCategoryIds.isEmpty || !filter.selectedSectorIds.isEmpty {
                // Get all valid category IDs (directly selected + those in selected sectors)
                var validCategoryIds = filter.selectedCategoryIds
                validCategoryIds.formUnion(categoriesInSelectedSectors)
                
                // If we have category filters, check the transaction's category
                if !validCategoryIds.isEmpty {
                    // Transactions without categories don't match category filters
                    guard let categoryId = transaction.categoryId,
                          validCategoryIds.contains(categoryId) else {
                        return false
                    }
                }
            }
            
            // 4. Member filter
            if filter.sharedOnly && filter.selectedMemberIds.isEmpty {
                // Shared only mode: show only expenses that are shared between multiple people
                guard transactionIsShared(transaction) else { return false }
            } else if !filter.selectedMemberIds.isEmpty {
                let matchesMember = transactionMatchesMemberFilter(transaction, filter: filter)
                guard matchesMember else { return false }
            }
            
            // 5. Text search
            if !filter.searchText.isEmpty {
                let searchLower = filter.searchText.lowercased()
                let descriptionMatch = transaction.description.lowercased().contains(searchLower)
                let notesMatch = transaction.notes?.lowercased().contains(searchLower) ?? false
                guard descriptionMatch || notesMatch else { return false }
            }
            
            return true
        }
    }
    
    /// Check if a transaction is shared between multiple people
    private func transactionIsShared(_ transaction: TransactionView) -> Bool {
        // Only expenses can be shared
        guard transaction.transactionType == .expense else { return false }
        
        // Check if the expense has splits with more than one person owing money
        if let splits = allSplits[transaction.id] {
            let membersWithOwedAmount = splits.filter { $0.owedAmount > 0 }.count
            return membersWithOwedAmount > 1
        }
        
        // Fallback based on split type
        switch transaction.splitType {
        case .equal:
            // Equal split among all members is shared if there are multiple active members
            return authViewModel.members.filter { $0.isActive }.count > 1
        case .custom:
            // Custom splits are assumed shared (would need splits data to confirm)
            return true
        case .memberOnly, .payerOnly:
            // Single person expenses are not shared
            return false
        }
    }
    
    /// Check if a transaction matches the member filter
    private func transactionMatchesMemberFilter(_ transaction: TransactionView, filter: DashboardFilter) -> Bool {
        let selectedMembers = filter.selectedMemberIds
        
        switch transaction.transactionType {
        case .expense:
            if filter.includeShared {
                // Include if any selected member has an owed amount in splits
                if let splits = allSplits[transaction.id] {
                    return splits.contains { split in
                        split.owedAmount > 0 && selectedMembers.contains(split.memberId)
                    }
                }
                // Fallback: check if expense is for a selected member
                if let splitMemberId = transaction.splitMemberId {
                    return selectedMembers.contains(splitMemberId)
                }
                // For equal splits, all members are involved
                if transaction.splitType == .equal {
                    return true
                }
                return selectedMembers.contains(transaction.paidByMemberId ?? UUID())
            } else {
                // Only show if expense is for a single selected member (not shared)
                guard transaction.splitType == .memberOnly,
                      let splitMemberId = transaction.splitMemberId else {
                    return false
                }
                return selectedMembers.contains(splitMemberId)
            }
            
        case .income:
            // Income: check received by (paidByMemberId stores the recipient)
            if let receivedBy = transaction.paidByMemberId {
                return selectedMembers.contains(receivedBy)
            }
            return false
            
        case .settlement:
            // Settlement: show if paid by OR paid to is selected
            let paidByMatch = transaction.paidByMemberId.map { selectedMembers.contains($0) } ?? false
            let paidToMatch = transaction.paidToMemberId.map { selectedMembers.contains($0) } ?? false
            return paidByMatch || paidToMatch
            
        case .reimbursement:
            // Reimbursement: check received by
            if let receivedBy = transaction.paidByMemberId {
                return selectedMembers.contains(receivedBy)
            }
            return false
        }
    }
    
    /// Filtered totals for expenses (uses portion amounts when filtering by members with include shared)
    private var filteredTotalExpenses: Decimal {
        // Get IDs of expenses that are visible in the filtered view
        let visibleExpenseIds = Set(filteredTransactions.filter { $0.transactionType == .expense }.map { $0.id })
        
        // Build reimbursement map from ALL transactions (not just filtered)
        // Reimbursements always follow their linked expense - if expense is visible, include all its reimbursements
        var reimbursementsByExpense: [UUID: Decimal] = [:]
        for transaction in transactionViewModel.transactions {
            if transaction.transactionType == .reimbursement,
               let linkedExpenseId = transaction.reimbursesTransactionId,
               visibleExpenseIds.contains(linkedExpenseId) {
                reimbursementsByExpense[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        
        var total: Decimal = 0
        for transaction in filteredTransactions where transaction.transactionType == .expense {
            let reimbursedAmount = reimbursementsByExpense[transaction.id] ?? 0
            // Use portion amount when in portion mode, otherwise full effective amount
            total += effectivePortionAmount(for: transaction, reimbursedAmount: reimbursedAmount)
        }
        return total
    }
    
    /// Filtered totals for income
    private var filteredTotalIncome: Decimal {
        filteredTransactions
            .filter { $0.transactionType == .income || ($0.transactionType == .reimbursement && $0.reimbursesTransactionId == nil) }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// Builds the sector expense breakdown for the donut chart (uses filtered transactions)
    private var sectorExpenses: [SectorExpense] {
        // Get only expense transactions from filtered set
        let expenses = filteredTransactions.filter { $0.transactionType == .expense }
        
        // Get IDs of visible expenses
        let visibleExpenseIds = Set(expenses.map { $0.id })
        
        // Build reimbursement map from ALL transactions (not just filtered)
        // Reimbursements always follow their linked expense - if expense is visible, include all its reimbursements
        var reimbursementsByExpense: [UUID: Decimal] = [:]
        for transaction in transactionViewModel.transactions {
            if transaction.transactionType == .reimbursement,
               let linkedExpenseId = transaction.reimbursesTransactionId,
               visibleExpenseIds.contains(linkedExpenseId) {
                reimbursementsByExpense[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        
        // Group expenses by categoryId
        var expensesByCategory: [UUID: Decimal] = [:]
        var uncategorizedAmount: Decimal = 0
        
        // Track expenses by member per category using "expense for" (owed amounts from splits)
        var expensesByCategoryAndMember: [UUID: [UUID: Decimal]] = [:] // categoryId -> (memberId -> amount)
        var uncategorizedByMember: [UUID: Decimal] = [:]
        
        // Track total adjusted expense for percentage calculation
        var totalAdjustedExpense: Decimal = 0
        
        // Check if we're in portion mode (filtering by members with include shared)
        let selectedMembers = filterManager.filter.selectedMemberIds
        let usePortionMode = isPortionModeActive
        
        for expense in expenses {
            // Calculate the effective amount after reimbursements
            let reimbursedAmount = reimbursementsByExpense[expense.id] ?? 0
            let fullEffectiveAmount = max(expense.amount - reimbursedAmount, 0)
            
            // Skip fully reimbursed expenses
            guard fullEffectiveAmount > 0 else { continue }
            
            // Calculate the reimbursement ratio to apply to member splits
            let reimbursementRatio = expense.amount > 0 ? fullEffectiveAmount / expense.amount : 1
            
            // In portion mode, use only the selected members' share
            let effectiveAmount: Decimal
            if usePortionMode, let portionData = portionInfo(for: expense, reimbursedAmount: reimbursedAmount) {
                effectiveAmount = portionData.amount
            } else {
                effectiveAmount = fullEffectiveAmount
            }
            
            // Skip if effective amount is zero
            guard effectiveAmount > 0 else { continue }
            
            // Add to total adjusted expense
            totalAdjustedExpense += effectiveAmount
            
            if let categoryId = expense.categoryId {
                expensesByCategory[categoryId, default: 0] += effectiveAmount
                
                // Use splits to determine who the expense is FOR (owedAmount), adjusted for reimbursements
                // In portion mode, only include selected members' amounts
                if let splits = allSplits[expense.id] {
                    for split in splits where split.owedAmount > 0 {
                        // In portion mode, only include selected members
                        if usePortionMode && !selectedMembers.contains(split.memberId) {
                            continue
                        }
                        let adjustedOwedAmount = split.owedAmount * reimbursementRatio
                        expensesByCategoryAndMember[categoryId, default: [:]][split.memberId, default: 0] += adjustedOwedAmount
                    }
                }
            } else {
                uncategorizedAmount += effectiveAmount
                
                // Use splits for uncategorized expenses too, adjusted for reimbursements
                if let splits = allSplits[expense.id] {
                    for split in splits where split.owedAmount > 0 {
                        // In portion mode, only include selected members
                        if usePortionMode && !selectedMembers.contains(split.memberId) {
                            continue
                        }
                        let adjustedOwedAmount = split.owedAmount * reimbursementRatio
                        uncategorizedByMember[split.memberId, default: 0] += adjustedOwedAmount
                    }
                }
            }
        }
        
        // Build category lookup
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        
        // Use total adjusted expense (after reimbursements) for percentage calculation
        guard totalAdjustedExpense > 0 else { return [] }
        
        // Build sector expenses
        var sectorExpenseList: [SectorExpense] = []
        
        for sector in sectors {
            let categoryIds = sectorCategories[sector.id] ?? []
            
            // Build categories within this sector
            var sectorTotal: Decimal = 0
            var categoryExpenses: [CategoryExpense] = []
            var sectorMemberTotals: [UUID: Decimal] = [:] // Track member totals for this sector
            
            for categoryId in categoryIds {
                guard let category = categoryLookup[categoryId],
                      let amount = expensesByCategory[categoryId], amount > 0 else { continue }
                
                sectorTotal += amount
                
                // Build member breakdown for this category
                let categoryMemberBreakdown = buildMemberBreakdown(
                    from: expensesByCategoryAndMember[categoryId] ?? [:],
                    sectorTotal: amount
                )
                
                categoryExpenses.append(CategoryExpense(
                    id: categoryId,
                    name: category.name,
                    icon: category.icon,
                    color: category.swiftUIColor,
                    amount: amount,
                    percentage: 0, // Will calculate after we know sector total
                    memberBreakdown: categoryMemberBreakdown
                ))
                
                // Aggregate member expenses for this sector
                if let categoryMemberExpenses = expensesByCategoryAndMember[categoryId] {
                    for (memberId, memberAmount) in categoryMemberExpenses {
                        sectorMemberTotals[memberId, default: 0] += memberAmount
                    }
                }
                
                // Remove from expensesByCategory so we can track uncategorized-to-sector
                expensesByCategory.removeValue(forKey: categoryId)
                expensesByCategoryAndMember.removeValue(forKey: categoryId)
            }
            
            // Skip sectors with no expenses
            guard sectorTotal > 0 else { continue }
            
            // Update category percentages relative to sector total
            categoryExpenses = categoryExpenses.map { cat in
                CategoryExpense(
                    id: cat.id,
                    name: cat.name,
                    icon: cat.icon,
                    color: cat.color,
                    amount: cat.amount,
                    percentage: (cat.amount.doubleValue / sectorTotal.doubleValue) * 100,
                    memberBreakdown: cat.memberBreakdown
                )
            }.sorted { $0.amount > $1.amount }
            
            // Build member breakdown for this sector
            let memberBreakdown = buildMemberBreakdown(from: sectorMemberTotals, sectorTotal: sectorTotal)
            
            sectorExpenseList.append(SectorExpense(
                id: sector.id,
                name: sector.name,
                color: sector.swiftUIColor,
                amount: sectorTotal,
                percentage: (sectorTotal.doubleValue / totalAdjustedExpense.doubleValue) * 100,
                categories: categoryExpenses,
                memberBreakdown: memberBreakdown
            ))
        }
        
        // Add "Other" sector for categories not in any sector
        let remainingCategoryTotal = expensesByCategory.values.reduce(Decimal(0), +)
        let otherTotal = remainingCategoryTotal + uncategorizedAmount
        
        if otherTotal > 0 {
            var otherCategories: [CategoryExpense] = []
            var otherMemberTotals: [UUID: Decimal] = uncategorizedByMember
            
            for (categoryId, amount) in expensesByCategory where amount > 0 {
                if let category = categoryLookup[categoryId] {
                    // Build member breakdown for this category
                    let categoryMemberBreakdown = buildMemberBreakdown(
                        from: expensesByCategoryAndMember[categoryId] ?? [:],
                        sectorTotal: amount
                    )
                    
                    otherCategories.append(CategoryExpense(
                        id: categoryId,
                        name: category.name,
                        icon: category.icon,
                        color: category.swiftUIColor,
                        amount: amount,
                        percentage: (amount.doubleValue / otherTotal.doubleValue) * 100,
                        memberBreakdown: categoryMemberBreakdown
                    ))
                    
                    // Add member expenses for this category (already using owed amounts from splits)
                    if let categoryMemberExpenses = expensesByCategoryAndMember[categoryId] {
                        for (memberId, memberAmount) in categoryMemberExpenses {
                            otherMemberTotals[memberId, default: 0] += memberAmount
                        }
                    }
                }
            }
            
            if uncategorizedAmount > 0 {
                // Build member breakdown for uncategorized expenses
                let uncategorizedMemberBreakdown = buildMemberBreakdown(
                    from: uncategorizedByMember,
                    sectorTotal: uncategorizedAmount
                )
                
                otherCategories.append(CategoryExpense(
                    id: UUID(),
                    name: "Uncategorized",
                    icon: "questionmark.circle",
                    color: Theme.Colors.textMuted,
                    amount: uncategorizedAmount,
                    percentage: (uncategorizedAmount.doubleValue / otherTotal.doubleValue) * 100,
                    memberBreakdown: uncategorizedMemberBreakdown
                ))
            }
            
            otherCategories.sort { $0.amount > $1.amount }
            
            // Build member breakdown for "Other"
            let otherMemberBreakdown = buildMemberBreakdown(from: otherMemberTotals, sectorTotal: otherTotal)
            
            sectorExpenseList.append(SectorExpense(
                id: UUID(),
                name: "Other",
                color: Theme.Colors.textSecondary,
                amount: otherTotal,
                percentage: (otherTotal.doubleValue / totalAdjustedExpense.doubleValue) * 100,
                categories: otherCategories,
                memberBreakdown: otherMemberBreakdown
            ))
        }
        
        return sectorExpenseList.sorted { $0.amount > $1.amount }
    }
    
    /// Helper to build member breakdown from totals
    private func buildMemberBreakdown(from memberTotals: [UUID: Decimal], sectorTotal: Decimal) -> [MemberExpenseBreakdown] {
        memberTotals.compactMap { memberId, amount in
            guard amount > 0, let member = memberLookup[memberId] else { return nil }
            return MemberExpenseBreakdown(
                id: memberId,
                name: member.displayName,
                color: member.swiftUIColor,
                emoji: member.avatarUrl, // avatarUrl stores the emoji
                amount: amount,
                percentage: (amount.doubleValue / sectorTotal.doubleValue) * 100,
                isInactive: member.isInactive
            )
        }.sorted { $0.amount > $1.amount }
    }
    
    // MARK: - Portion Mode (Member Share Filtering)
    
    /// Whether "portion mode" is active - showing only selected members' share of shared transactions
    private var isPortionModeActive: Bool {
        let filter = filterManager.filter
        return !filter.selectedMemberIds.isEmpty && filter.includeShared
    }
    
    /// Calculate the portion amount and percentage for a transaction based on selected members
    /// Returns nil if the transaction should show full amount (not shared or portion mode not active)
    private func portionInfo(for transaction: TransactionView, reimbursedAmount: Decimal = 0) -> (amount: Decimal, percentage: Decimal)? {
        guard isPortionModeActive,
              transaction.transactionType == .expense else {
            return nil
        }
        
        let selectedMembers = filterManager.filter.selectedMemberIds
        
        // Get splits for this transaction
        guard let splits = allSplits[transaction.id] else {
            return nil
        }
        
        // Calculate effective amount after reimbursements
        let effectiveAmount = max(transaction.amount - reimbursedAmount, 0)
        guard effectiveAmount > 0 else { return nil }
        
        // Calculate the reimbursement ratio to apply to portions
        let reimbursementRatio = transaction.amount > 0 ? effectiveAmount / transaction.amount : 1
        
        // Sum the owed amounts for selected members
        let selectedMembersOwed = splits
            .filter { selectedMembers.contains($0.memberId) && $0.owedAmount > 0 }
            .reduce(Decimal(0)) { $0 + $1.owedAmount }
        
        // Calculate total owed (for percentage)
        let totalOwed = splits
            .filter { $0.owedAmount > 0 }
            .reduce(Decimal(0)) { $0 + $1.owedAmount }
        
        // If selected members' share equals the full amount, no need for portion display
        guard selectedMembersOwed > 0, selectedMembersOwed < totalOwed else {
            return nil
        }
        
        // Apply reimbursement ratio to the portion
        let portionAmount = selectedMembersOwed * reimbursementRatio
        let percentage = totalOwed > 0 ? (selectedMembersOwed / totalOwed) * 100 : 0
        
        return (amount: portionAmount, percentage: percentage)
    }
    
    /// Get the portion amount for a transaction (or full effective amount if not in portion mode)
    private func effectivePortionAmount(for transaction: TransactionView, reimbursedAmount: Decimal = 0) -> Decimal {
        let effectiveAmount = max(transaction.amount - reimbursedAmount, 0)
        
        if let portion = portionInfo(for: transaction, reimbursedAmount: reimbursedAmount) {
            return portion.amount
        }
        
        return effectiveAmount
    }
    
    /// Returns filtered transactions that impact member balances (expenses where paid != owed, and settlements)
    private var balanceImpactingTransactions: [TransactionView] {
        // Get expenses and settlements that impact balances from filtered transactions
        var result = filteredTransactions.filter { transaction in
            // Settlements always impact balances - they transfer money between members
            if transaction.transactionType == .settlement {
                return true
            }
            
            // Skip reimbursements here - we'll add them separately based on linked expense
            if transaction.transactionType == .reimbursement {
                return false
            }
            
            // Only expenses affect balances (income doesn't)
            guard transaction.transactionType == .expense else { return false }
            
            // payer_only never impacts balance (payer pays 100% and owes 100%)
            if transaction.splitType == .payerOnly {
                return false
            }
            
            // member_only impacts balance only when payer is different from the split member
            if transaction.splitType == .memberOnly {
                // For single payer: check if payer == split member
                if transaction.paidByType == .single {
                    if let splitMemberId = transaction.splitMemberId {
                        return transaction.paidByMemberId != splitMemberId
                    }
                    return false
                }
                // For shared/custom payment with member_only split, need to check splits
            }
            
            // Equal split with shared payment = everyone pays and owes equally = no impact
            if transaction.splitType == .equal && transaction.paidByType == .shared {
                return false
            }
            
            // Equal split with single payer impacts balance (one person paid for everyone)
            if transaction.splitType == .equal && transaction.paidByType == .single {
                return authViewModel.members.count > 1
            }
            
            // For custom splits or other combinations, check the actual split data
            if let splits = allSplits[transaction.id] {
                // A transaction impacts balance if ANY member has paid != owed
                return splits.contains { split in
                    abs(split.paidAmount - split.owedAmount) > 0.001
                }
            }
            
            // If we don't have split data yet, include it to be safe (will be filtered when data loads)
            return true
        }
        
        // Get the set of expense IDs that actually impact balances
        let balanceImpactingExpenseIds = Set(result.filter { $0.transactionType == .expense }.map { $0.id })
        
        // Add reimbursements only if their linked expense impacts balances
        // (if linked expense has no balance impact, neither does the reimbursement)
        let linkedReimbursements = transactionViewModel.transactions.filter { transaction in
            guard transaction.transactionType == .reimbursement,
                  let linkedExpenseId = transaction.reimbursesTransactionId else {
                return false
            }
            // Only include if the linked expense actually impacts balances
            return balanceImpactingExpenseIds.contains(linkedExpenseId)
        }
        
        result.append(contentsOf: linkedReimbursements)
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient (dynamic from current theme)
                LinearGradient(
                    colors: [Theme.Colors.gradientEnd, Theme.Colors.gradientStart],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        // Header with Mascot Background
                        ZStack(alignment: .bottom) {
                            // Mascot background image
                            Image("QuackMascot")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 180)
                                .clipped()
                                .overlay(
                                    // Gradient overlay for text readability
                                    LinearGradient(
                                        colors: [
                                            Theme.Colors.gradientEnd.opacity(0.3),
                                            Theme.Colors.gradientEnd.opacity(0.7),
                                            Theme.Colors.gradientEnd
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            // Header content overlaid on mascot
                            headerSection
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.bottom, Theme.Spacing.md)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Balance Cards (using filtered totals)
                        HStack(spacing: Theme.Spacing.md) {
                            Button {
                                showExpensesDetail = true
                            } label: {
                                BalanceCard(
                                    title: "Total Expenses",
                                    amount: filteredTotalExpenses,
                                    icon: "arrow.down.circle.fill",
                                    color: Theme.Colors.expense
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Hide income card when privacy mode is enabled
                            if !privacyManager.hideIncomeData {
                                Button {
                                    showIncomeDetail = true
                                } label: {
                                    BalanceCard(
                                        title: "Total Income",
                                        amount: filteredTotalIncome,
                                        icon: "arrow.up.circle.fill",
                                        color: Theme.Colors.income
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Net Balance (using filtered totals) - hide when income is hidden
                        if !privacyManager.hideIncomeData {
                            Button {
                                showNetBalanceDetail = true
                            } label: {
                                NetBalanceCard(
                                    income: filteredTotalIncome,
                                    expenses: filteredTotalExpenses
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Member Balance - show when:
                        // - Multiple active members, OR
                        // - Only one active member but has non-zero balance (due to inactive members/old transactions)
                        if shouldShowBalanceWidget {
                            MemberBalanceCardWithInfo(
                                balance: filteredCurrentMemberBalance,
                                memberCount: membersWithNonZeroBalance,
                                onInfoTapped: { showBalanceDetails = true }
                            )
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Expense Breakdown by Sector (using filtered data)
                        if sectorExpenses.isEmpty {
                            ExpenseDonutEmptyState()
                                .padding(.horizontal, Theme.Spacing.md)
                        } else {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Expenses by Sector")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                ExpenseDonutChart(
                                    sectors: sectorExpenses,
                                    totalExpenses: filteredTotalExpenses,
                                    filteredTransactions: filteredTransactions,
                                    sectorCategories: sectorCategories,
                                    allTransactions: transactionViewModel.transactions
                                )
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, Theme.Spacing.md)
                }
                .refreshable {
                    await refreshData()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showBalanceDetails) {
                BalanceDetailsSheet(
                    memberBalances: filteredMemberBalances,
                    transactions: balanceImpactingTransactions,
                    transactionSplits: allSplits,
                    members: authViewModel.members,
                    currentMemberId: authViewModel.currentMember?.id
                )
            }
            .sheet(isPresented: $showFilterSheet) {
                DashboardFilterSheet(
                    filter: $filterManager.filter,
                    members: authViewModel.members,
                    sectors: sectors,
                    categories: categories,
                    sectorCategories: sectorCategories
                )
            }
            .sheet(isPresented: $showExpensesDetail) {
                TotalExpensesDetailSheet(
                    totalExpenses: filteredTotalExpenses,
                    filteredTransactions: filteredTransactions,
                    allTransactions: transactionViewModel.transactions,
                    allSplits: allSplits,
                    members: authViewModel.members
                )
            }
            .sheet(isPresented: $showIncomeDetail) {
                TotalIncomeDetailSheet(
                    totalIncome: filteredTotalIncome,
                    filteredTransactions: filteredTransactions,
                    members: authViewModel.members
                )
            }
            .sheet(isPresented: $showNetBalanceDetail) {
                NetBalanceDetailSheet(
                    totalIncome: filteredTotalIncome,
                    totalExpenses: filteredTotalExpenses,
                    filteredTransactions: filteredTransactions,
                    allTransactions: transactionViewModel.transactions,
                    allSplits: allSplits,
                    members: authViewModel.members
                )
            }
        }
        .task {
            await refreshData()
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello, \(authViewModel.currentMember?.displayName ?? "there")!")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                // Show filter summary or household name
                VStack(alignment: .leading, spacing: 2) {
                    Text(authViewModel.currentHousehold?.name ?? "Your Bank")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    if filterManager.filter.isFiltered {
                        Text(filterManager.filter.summary(firstTransactionDate: firstTransactionDate, lastTransactionDate: lastTransactionDate))
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                            .lineLimit(2)
                    } else {
                        Text(filterManager.filter.dateDescription(firstTransactionDate: firstTransactionDate, lastTransactionDate: lastTransactionDate))
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            
            Spacer()
            
            // Filter Button
            Button {
                showFilterSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(filterManager.filter.isFiltered ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(filterManager.filter.isFiltered ? Theme.Colors.accent : Theme.Colors.borderDefault, lineWidth: 2)
                            )
                        
                        Image(systemName: filterManager.filter.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(filterManager.filter.isFiltered ? Theme.Colors.textInverse : Theme.Colors.textPrimary)
                    }
                    
                    // Badge showing active filter count
                    if filterManager.filter.activeFilterCount > 0 {
                        Text("\(filterManager.filter.activeFilterCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textInverse)
                            .frame(width: 18, height: 18)
                            .background(Theme.Colors.error)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Spacing.lg)
    }
    
    private func refreshData() async {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        // Ensure filter is for the current household (resets if household changed)
        filterManager.setHousehold(householdId)
        
        // Refresh authViewModel's data (categories, sectors, sectorCategories)
        // This ensures we have the same data that Settings uses
        await authViewModel.refreshCategories()
        await authViewModel.refreshSectors()
        
        // Fetch transactions
        await transactionViewModel.fetchTransactions(householdId: householdId)
        
        // Fetch member balances and splits from database
        do {
            async let balancesTask = dataService.fetchMemberBalances(householdId: householdId)
            async let splitsTask = dataService.fetchAllSplitsForHousehold(householdId: householdId)
            
            let (balances, splits) = try await (balancesTask, splitsTask)
            memberBalances = balances
            
            // Group splits by transaction ID
            allSplits = Dictionary(grouping: splits, by: { $0.transactionId })
            
            // Validate filter against current data to remove any stale IDs
            // (e.g., from deleted categories/sectors/members)
            filterManager.validateFilter(
                validSectorIds: Set(sectors.map { $0.id }),
                validCategoryIds: Set(categories.map { $0.id }),
                validMemberIds: Set(authViewModel.members.map { $0.id })
            )
        } catch {
            print("Failed to fetch data: \(error)")
        }
    }
}

// MARK: - Member Balance Card with Info Button

struct MemberBalanceCardWithInfo: View {
    let balance: Decimal
    let memberCount: Int
    let onInfoTapped: () -> Void
    
    private var isZero: Bool {
        abs(balance.doubleValue) < 0.01
    }
    
    private var isPositive: Bool {
        balance >= 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Your Balance")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Button(action: onInfoTapped) {
                    Image(systemName: "info.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            if isZero {
                Text("You're all settled up! 🎉")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(abs(balance.doubleValue).formattedAsMoney())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
                    
                    Text(isPositive ? "owed to you" : "you owe")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Text("Between \(memberCount) bank members")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Balance Details Sheet

struct BalanceDetailsSheet: View {
    let memberBalances: [MemberBalance]
    let transactions: [TransactionView]
    let transactionSplits: [UUID: [TransactionSplit]]
    let members: [HouseholdMember]
    let currentMemberId: UUID?
    
    @Environment(\.dismiss) private var dismiss
    
    private func memberName(for memberId: UUID) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Unknown"
    }
    
    private func member(for memberId: UUID) -> HouseholdMember? {
        members.first { $0.id == memberId }
    }
    
    /// Sorted and filtered member balances:
    /// - Hide inactive members with zero balance
    /// - Sort inactive members to the bottom
    /// - Sort by name within active/inactive groups
    private var sortedMemberBalances: [MemberBalance] {
        memberBalances
            .filter { balance in
                let memberInfo = member(for: balance.memberId)
                let isInactive = memberInfo?.isInactive ?? false
                let hasZeroBalance = abs(balance.balance.doubleValue) < 0.01
                
                // Hide inactive members with zero balance
                if isInactive && hasZeroBalance {
                    return false
                }
                return true
            }
            .sorted { balance1, balance2 in
                let member1 = member(for: balance1.memberId)
                let member2 = member(for: balance2.memberId)
                let isInactive1 = member1?.isInactive ?? false
                let isInactive2 = member2?.isInactive ?? false
                
                // Sort inactive members to the bottom
                if isInactive1 != isInactive2 {
                    return !isInactive1 // Active members come first
                }
                
                // Within same status, sort by name
                return balance1.displayName < balance2.displayName
            }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Bank Balances Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label("Bank Balances", systemImage: "person.2.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            if sortedMemberBalances.isEmpty {
                                Text("No balance data available")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.vertical, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(sortedMemberBalances, id: \.memberId) { balance in
                                        MemberBalanceRow(
                                            balance: balance,
                                            isCurrentMember: balance.memberId == currentMemberId,
                                            isInactive: member(for: balance.memberId)?.isInactive ?? false
                                        )
                                        
                                        if balance.memberId != sortedMemberBalances.last?.memberId {
                                            Divider()
                                                .background(Theme.Colors.textMuted.opacity(0.3))
                                        }
                                    }
                                }
                                .cardStyle()
                            }
                        }
                        
                        // Explanation
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(Theme.Colors.warning)
                            
                            Text("A positive balance means you've paid more than your share. Negative means you owe others.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.warning.opacity(0.1))
                        .cornerRadius(Theme.CornerRadius.md)
                        
                        // Transactions that affected balances
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label("Transactions Affecting Balance", systemImage: "arrow.left.arrow.right")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            if transactions.isEmpty {
                                Text("No transactions have affected balances yet")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.vertical, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(transactions.prefix(20)) { transaction in
                                        BalanceTransactionRow(
                                            transaction: transaction,
                                            splits: transactionSplits[transaction.id] ?? [],
                                            allSplits: transactionSplits,
                                            memberName: memberName
                                        )
                                        
                                        if transaction.id != transactions.prefix(20).last?.id {
                                            Divider()
                                                .background(Theme.Colors.textMuted.opacity(0.3))
                                        }
                                    }
                                    
                                    if transactions.count > 20 {
                                        Text("And \(transactions.count - 20) more transactions...")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textMuted)
                                            .padding(.top, Theme.Spacing.sm)
                                    }
                                }
                                .cardStyle()
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Balance Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Member Balance Row

struct MemberBalanceRow: View {
    let balance: MemberBalance
    var isCurrentMember: Bool = false
    var isInactive: Bool = false
    
    private var isZero: Bool {
        abs(balance.balance.doubleValue) < 0.01
    }
    
    private var isPositive: Bool {
        balance.balance >= 0
    }
    
    private var balanceColor: Color {
        if isZero { return Theme.Colors.textPrimary }
        return isPositive ? Theme.Colors.success : Theme.Colors.error
    }
    
    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.xs) {
                Text(balance.displayName)
                    .font(.subheadline)
                    .fontWeight(isCurrentMember ? .semibold : .regular)
                    .foregroundStyle(isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                
                if isCurrentMember {
                    Text("(You)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                
                if isInactive {
                    Text("Inactive")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.textMuted.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            HStack(spacing: Theme.Spacing.xs) {
                if isZero {
                    Text("$0.00")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(balanceColor)
                    
                    Text("settled")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                } else {
                    Text(isPositive ? "+\(abs(balance.balance.doubleValue).formattedAsMoney())" : "-\(abs(balance.balance.doubleValue).formattedAsMoney())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(balanceColor)
                    
                    Text(isPositive ? "owed" : "owes")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .background(isCurrentMember ? Theme.Colors.accent.opacity(0.05) : Color.clear)
    }
}

// MARK: - Balance Transaction Row

struct BalanceTransactionRow: View {
    let transaction: TransactionView
    let splits: [TransactionSplit]
    let allSplits: [UUID: [TransactionSplit]] // All splits, keyed by transaction ID
    let memberName: (UUID) -> String
    
    @State private var isExpanded = false
    
    /// Each member's net balance impact (paid - owed) for expenses
    private var balanceImpacts: [(name: String, net: Decimal)] {
        splits.compactMap { split in
            let net = split.paidAmount - split.owedAmount
            // Only include if there's a meaningful impact
            if abs(net) > 0.001 {
                return (memberName(split.memberId), net)
            }
            return nil
        }.sorted { abs($0.net) > abs($1.net) } // Sort by largest impact first
    }
    
    /// Reimbursement balance impacts based on linked expense splits
    /// - All members: owed decreases proportionally (expense is smaller)
    /// - Recipient who paid: paid also decreases
    /// - Recipient who didn't pay: owes the remaining to payers
    private var reimbursementBalanceImpacts: [(name: String, net: Decimal)] {
        guard let linkedExpenseId = transaction.reimbursesTransactionId,
              let linkedSplits = allSplits[linkedExpenseId],
              let recipientId = transaction.paidByMemberId else {
            return []
        }
        
        let reimbursementAmount = transaction.amount
        let totalOwed = linkedSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
        
        // Calculate how much of the reimbursement the recipient "absorbed" via their paid amount
        let recipientSplit = linkedSplits.first { $0.memberId == recipientId }
        let recipientPaidAmount = recipientSplit?.paidAmount ?? 0
        let effectivePaidReduction = min(reimbursementAmount, recipientPaidAmount)
        let remainingReimbursement = reimbursementAmount - effectivePaidReduction
        
        return linkedSplits.compactMap { split -> (String, Decimal)? in
            // Everyone's owed decreases proportionally
            let owedPercentage = totalOwed > 0 ? split.owedAmount / totalOwed : 0
            let owedReduction = reimbursementAmount * owedPercentage
            
            // Balance = paid - owed
            // When owed decreases, balance increases by that amount
            var balanceChange: Decimal = owedReduction
            
            if split.memberId == recipientId {
                // Recipient: paid decreases (if they paid), and may owe remaining to payers
                // paid decrease → balance decreases
                // remaining owed → balance decreases
                balanceChange = owedReduction - effectivePaidReduction - remainingReimbursement
            }
            
            // Only include if there's a meaningful impact
            if abs(balanceChange) > 0.001 {
                return (memberName(split.memberId), balanceChange)
            }
            return nil
        }.sorted { abs($0.1) > abs($1.1) } // Sort by largest impact first
    }
    
    private var isSettlement: Bool {
        transaction.transactionType == .settlement
    }
    
    private var isReimbursement: Bool {
        transaction.transactionType == .reimbursement
    }
    
    private var transactionColor: Color {
        if isSettlement { return Theme.Colors.settlement }
        if isReimbursement { return Theme.Colors.reimbursement }
        return Theme.Colors.expense
    }
    
    /// Summary text for collapsed state
    private var collapsedSummary: String {
        if isSettlement {
            if let paidByName = transaction.paidByName, let paidToName = transaction.paidToName {
                return "\(paidByName) → \(paidToName)"
            }
            return "Settlement"
        } else if isReimbursement {
            let count = reimbursementBalanceImpacts.count
            if count == 0, let receivedByName = transaction.paidByName {
                return "Received by \(receivedByName)"
            }
            return "\(count) member\(count == 1 ? "" : "s") affected"
        } else {
            let count = balanceImpacts.count
            if count == 0 {
                if let paidByName = transaction.paidByName {
                    return "Paid by \(paidByName)"
                }
                return ""
            }
            return "\(count) member\(count == 1 ? "" : "s") affected"
        }
    }
    
    /// Whether this row has expandable details
    private var hasExpandableDetails: Bool {
        if isSettlement {
            return transaction.paidByName != nil && transaction.paidToName != nil
        } else if isReimbursement {
            return !reimbursementBalanceImpacts.isEmpty
        } else {
            return !balanceImpacts.isEmpty
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Transaction header
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    if isSettlement {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.settlement)
                    } else if isReimbursement {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.reimbursement)
                    }
                    Text(transaction.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(transaction.amount.doubleValue.formattedAsMoney())
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(transactionColor)
            }
            
            // Date
            Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textMuted)
            
            // Expandable summary row
            if hasExpandableDetails {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .frame(width: 10)
                        
                        Text(collapsedSummary)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                
                // Expanded details
                if isExpanded {
                    expandedDetailsView
                        .padding(.leading, 18)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else if !collapsedSummary.isEmpty {
                // Non-expandable summary (e.g., no split data)
                Text(collapsedSummary)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
    
    @ViewBuilder
    private var expandedDetailsView: some View {
        if isSettlement {
            // Settlement: show who paid whom with impacts
            if let paidByName = transaction.paidByName, let paidToName = transaction.paidToName {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(paidByName)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text("+\(transaction.amount.doubleValue.formattedAsMoney())")
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.success)
                    }
                    HStack {
                        Text(paidToName)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text("-\(transaction.amount.doubleValue.formattedAsMoney())")
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                .font(.caption)
            }
        } else if isReimbursement {
            // Reimbursement: show balance impact for each member
            VStack(alignment: .leading, spacing: 6) {
                if let receivedByName = transaction.paidByName {
                    Text("Received by \(receivedByName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.bottom, 2)
                }
                ForEach(reimbursementBalanceImpacts, id: \.name) { impact in
                    HStack {
                        Text(impact.name)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text(impact.net > 0 ? "+\(impact.net.doubleValue.formattedAsMoney())" : "\(impact.net.doubleValue.formattedAsMoney())")
                            .fontWeight(.medium)
                            .foregroundStyle(impact.net > 0 ? Theme.Colors.success : Theme.Colors.error)
                    }
                    .font(.caption)
                }
            }
        } else {
            // Expense: show balance impact for each member
            VStack(alignment: .leading, spacing: 6) {
                ForEach(balanceImpacts, id: \.name) { impact in
                    HStack {
                        Text(impact.name)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text(impact.net > 0 ? "+\(impact.net.doubleValue.formattedAsMoney())" : "-\(abs(impact.net).doubleValue.formattedAsMoney())")
                            .fontWeight(.medium)
                            .foregroundStyle(impact.net > 0 ? Theme.Colors.success : Theme.Colors.error)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

// MARK: - Total Expenses Detail Sheet

struct TotalExpensesDetailSheet: View {
    let totalExpenses: Decimal
    let filteredTransactions: [TransactionView]
    let allTransactions: [TransactionView]
    let allSplits: [UUID: [TransactionSplit]]
    let members: [HouseholdMember]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransaction: TransactionView?
    
    /// Expense transactions only, sorted by date
    private var expenseTransactions: [TransactionView] {
        filteredTransactions
            .filter { $0.transactionType == .expense }
            .sorted { $0.date < $1.date }
    }
    
    /// Active members only (for the chart)
    private var activeMembers: [HouseholdMember] {
        members.filter { $0.isActive }
    }
    
    /// Reimbursements by expense ID (includes ALL reimbursements linked to visible expenses)
    private var reimbursementsByExpense: [UUID: Decimal] {
        let visibleExpenseIds = Set(expenseTransactions.map { $0.id })
        var result: [UUID: Decimal] = [:]
        for transaction in allTransactions where transaction.transactionType == .reimbursement {
            if let linkedExpenseId = transaction.reimbursesTransactionId,
               visibleExpenseIds.contains(linkedExpenseId) {
                result[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        return result
    }
    
    /// Combined chart data including total and per-member lines
    private var multiLineChartData: MultiLineExpenseData {
        guard !expenseTransactions.isEmpty else {
            return MultiLineExpenseData(totalLine: [], memberLines: [])
        }
        
        // Track expenses by date for total and per member
        var totalByDate: [Date: Decimal] = [:]
        var memberExpensesByDate: [UUID: [Date: Decimal]] = [:]
        
        // Initialize member tracking
        for member in activeMembers {
            memberExpensesByDate[member.id] = [:]
        }
        
        for expense in expenseTransactions {
            let dateKey = Calendar.current.startOfDay(for: expense.date)
            let reimbursedAmount = reimbursementsByExpense[expense.id] ?? 0
            let effectiveAmount = max(expense.amount - reimbursedAmount, 0)
            
            // Skip fully reimbursed expenses
            guard effectiveAmount > 0 else { continue }
            
            // Add to total
            totalByDate[dateKey, default: 0] += effectiveAmount
            
            // Calculate reimbursement ratio to apply to member splits
            let reimbursementRatio = expense.amount > 0 ? effectiveAmount / expense.amount : 1
            
            // Add to member amounts based on owed (expense for)
            if let splits = allSplits[expense.id], !splits.isEmpty {
                for split in splits where split.owedAmount > 0 {
                    let adjustedOwed = split.owedAmount * reimbursementRatio
                    memberExpensesByDate[split.memberId, default: [:]][dateKey, default: 0] += adjustedOwed
                }
            } else if let payerId = expense.paidByMemberId {
                // Fallback: attribute full expense to payer when splits are missing
                memberExpensesByDate[payerId, default: [:]][dateKey, default: 0] += effectiveAmount
            } else if !activeMembers.isEmpty {
                // Last resort: distribute equally among active members
                let shareAmount = effectiveAmount / Decimal(activeMembers.count)
                for member in activeMembers {
                    memberExpensesByDate[member.id, default: [:]][dateKey, default: 0] += shareAmount
                }
            }
        }
        
        // Get all unique dates and sort them
        let allDates = totalByDate.keys.sorted()
        
        // Build total line with cumulative values
        var totalLine: [ExpenseChartPoint] = []
        var totalCumulative: Decimal = 0
        for date in allDates {
            let dailyAmount = totalByDate[date] ?? 0
            totalCumulative += dailyAmount
            totalLine.append(ExpenseChartPoint(
                date: date,
                dailyAmount: dailyAmount,
                cumulativeAmount: totalCumulative
            ))
        }
        
        // Build member lines with cumulative values
        var memberLines: [MemberExpenseLine] = []
        for member in activeMembers {
            var points: [ExpenseChartPoint] = []
            var cumulative: Decimal = 0
            let memberDates = memberExpensesByDate[member.id] ?? [:]
            
            for date in allDates {
                let dailyAmount = memberDates[date] ?? 0
                cumulative += dailyAmount
                points.append(ExpenseChartPoint(
                    date: date,
                    dailyAmount: dailyAmount,
                    cumulativeAmount: cumulative
                ))
            }
            
            // Only include members who have some expenses
            if cumulative > 0 {
                memberLines.append(MemberExpenseLine(
                    memberId: member.id,
                    memberName: member.displayName,
                    color: member.swiftUIColor,
                    emoji: member.avatarUrl,
                    points: points,
                    total: cumulative
                ))
            }
        }
        
        // Sort member lines by total (highest first)
        memberLines.sort { $0.total > $1.total }
        
        return MultiLineExpenseData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Expenses sorted by date descending for the list
    private var sortedExpenses: [TransactionView] {
        expenseTransactions.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Total header
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.Colors.expense)
                            
                            Text("Total Expenses")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            Text(totalExpenses.doubleValue.formattedAsMoney())
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Theme.Colors.expense)
                            
                            Text("\(expenseTransactions.count) expenses")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.top, Theme.Spacing.md)
                        
                        // Chart section
                        if multiLineChartData.totalLine.count >= 2 {
                            MultiLineExpenseChart(data: multiLineChartData)
                                .padding(.horizontal, Theme.Spacing.md)
                        } else if multiLineChartData.totalLine.count == 1 {
                            // Single data point - show as simple stat
                            VStack(spacing: Theme.Spacing.sm) {
                                Text("Expense on \(multiLineChartData.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Text(multiLineChartData.totalLine[0].dailyAmount.doubleValue.formattedAsMoney())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.expense)
                            }
                            .frame(maxWidth: .infinity)
                            .cardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Expenses list
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("All Expenses")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\(sortedExpenses.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if sortedExpenses.isEmpty {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "tray")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No expenses found")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(sortedExpenses) { expense in
                                        Button {
                                            selectedTransaction = expense
                                        } label: {
                                            ExpenseDetailRow(
                                                transaction: expense,
                                                reimbursedAmount: reimbursementsByExpense[expense.id] ?? 0
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if expense.id != sortedExpenses.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
        }
    }
}

// MARK: - Expense Chart Data Structures

struct ExpenseChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let dailyAmount: Decimal
    let cumulativeAmount: Decimal
}

struct MemberExpenseLine: Identifiable {
    let id: UUID
    let memberId: UUID
    let memberName: String
    let color: Color
    let emoji: String?
    let points: [ExpenseChartPoint]
    let total: Decimal
    
    init(memberId: UUID, memberName: String, color: Color, emoji: String?, points: [ExpenseChartPoint], total: Decimal) {
        self.id = memberId
        self.memberId = memberId
        self.memberName = memberName
        self.color = color
        self.emoji = emoji
        self.points = points
        self.total = total
    }
}

struct MultiLineExpenseData {
    let totalLine: [ExpenseChartPoint]
    let memberLines: [MemberExpenseLine]
}

// MARK: - Multi-Line Expense Chart

struct MultiLineExpenseChart: View {
    let data: MultiLineExpenseData
    
    @State private var selectedDate: Date?
    @State private var showMemberBreakdown = false
    
    private var maxAmount: Double {
        data.totalLine.map { $0.cumulativeAmount.doubleValue }.max() ?? 0
    }
    
    /// Get values at selected date
    private var selectedValues: (total: ExpenseChartPoint?, members: [(MemberExpenseLine, ExpenseChartPoint)])? {
        guard let date = selectedDate else { return nil }
        
        let totalPoint = data.totalLine.min { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        }
        
        let memberPoints: [(MemberExpenseLine, ExpenseChartPoint)] = data.memberLines.compactMap { line in
            guard let point = line.points.min(by: { point1, point2 in
                abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
            }) else { return nil }
            return (line, point)
        }
        
        return (totalPoint, memberPoints)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header with member breakdown toggle
            HStack {
                Text("Expenses Over Time")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if !data.memberLines.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMemberBreakdown.toggle()
                        }
                    } label: {
                        Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                            .font(.title3)
                            .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted)
                    }
                }
            }
            
            // Selected point info
            if let selected = selectedValues, let totalPoint = selected.total {
                VStack(spacing: Theme.Spacing.xs) {
                    // Date and total
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(totalPoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.expense)
                                    .frame(width: 8, height: 8)
                                Text("Total: \(totalPoint.cumulativeAmount.doubleValue.formattedAsMoney())")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.expense)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("That day")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            Text("+\(totalPoint.dailyAmount.doubleValue.formattedAsMoney())")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.expense.opacity(0.8))
                        }
                    }
                    
                    // Member breakdown for selected date (only when member breakdown is enabled)
                    if showMemberBreakdown && !selected.members.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(selected.members.prefix(4), id: \.0.id) { (line, point) in
                                HStack(spacing: 4) {
                                    if let emoji = line.emoji, !emoji.isEmpty {
                                        Text(emoji)
                                            .font(.caption2)
                                    } else {
                                        Circle()
                                            .fill(line.color)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(point.cumulativeAmount.doubleValue.formattedAsMoney())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(line.color)
                                }
                            }
                            
                            if selected.members.count > 4 {
                                Text("+\(selected.members.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity)
            }
            
            // Chart
            Chart {
                // Member lines (render first so total line is on top) - only when toggled on
                if showMemberBreakdown {
                    ForEach(data.memberLines) { memberLine in
                        ForEach(memberLine.points) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Amount", point.cumulativeAmount.doubleValue),
                                series: .value("Member", memberLine.memberName)
                            )
                            .foregroundStyle(memberLine.color.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                
                // Total line (area fill)
                ForEach(data.totalLine) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Total", point.cumulativeAmount.doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Colors.expense.opacity(0.15), Theme.Colors.expense.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                // Total line
                ForEach(data.totalLine) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Total", point.cumulativeAmount.doubleValue),
                        series: .value("Member", "Total")
                    )
                    .foregroundStyle(Theme.Colors.expense)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                
                // Selection rule line
                if let date = selectedDate {
                    RuleMark(x: .value("Date", date, unit: .day))
                        .foregroundStyle(Theme.Colors.textMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatAxisLabel(amount))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(data.totalLine.count, 5))) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight.opacity(0.5))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let location = value.location
                                    if let date: Date = proxy.value(atX: location.x) {
                                        selectedDate = date
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedDate = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.15), value: selectedDate)
            
            // Legend (only when member breakdown is enabled)
            if showMemberBreakdown && !data.memberLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Total row
                    HStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Colors.expense)
                                .frame(width: 16, height: 3)
                            
                            Text("Total")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Text(data.totalLine.last?.cumulativeAmount.doubleValue.formattedAsMoney() ?? "$0")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.expense)
                    }
                    
                    // Member rows
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 16)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(line.color)
                                        .frame(width: 16, height: 3)
                                }
                                
                                Text(line.memberName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(line.total.doubleValue.formattedAsMoney())
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(line.color)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
    
    private func formatAxisLabel(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(Int(value / 1000))k"
        } else if value >= 1 {
            return "$\(Int(value))"
        }
        return "$0"
    }
}

// MARK: - Expense Detail Row

struct ExpenseDetailRow: View {
    let transaction: TransactionView
    var reimbursedAmount: Decimal = 0
    
    private var effectiveAmount: Decimal {
        if reimbursedAmount > 0 {
            return max(transaction.amount - reimbursedAmount, 0)
        }
        return transaction.amount
    }
    
    private var hasReimbursements: Bool {
        reimbursedAmount > 0
    }
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        return Theme.Colors.expense
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if let icon = transaction.categoryIcon, !icon.isEmpty {
                    if isSFSymbol(icon) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(categoryColor)
                    } else {
                        Text(icon)
                            .font(.system(size: 18))
                    }
                } else {
                    Image(systemName: "cart")
                        .font(.system(size: 16))
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    if let categoryName = transaction.categoryName {
                        Text(categoryName)
                            .font(.caption2)
                            .foregroundStyle(categoryColor)
                    }
                    
                    if transaction.categoryName != nil {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if hasReimbursements {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.reimbursement)
                    }
                    
                    Text("-\(effectiveAmount.doubleValue.formattedAsMoney())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.expense)
                }
                
                if hasReimbursements {
                    Text("was \(transaction.amount.doubleValue.formattedAsMoney())")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .strikethrough()
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Total Income Detail Sheet

struct TotalIncomeDetailSheet: View {
    let totalIncome: Decimal
    let filteredTransactions: [TransactionView]
    let members: [HouseholdMember]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransaction: TransactionView?
    
    /// Income transactions only (income + unlinked reimbursements), sorted by date
    private var incomeTransactions: [TransactionView] {
        filteredTransactions
            .filter { transaction in
                transaction.transactionType == .income ||
                (transaction.transactionType == .reimbursement && transaction.reimbursesTransactionId == nil)
            }
            .sorted { $0.date < $1.date }
    }
    
    /// Active members only (for the chart)
    private var activeMembers: [HouseholdMember] {
        members.filter { $0.isActive }
    }
    
    /// Combined chart data including total and per-member lines
    private var multiLineChartData: MultiLineIncomeData {
        guard !incomeTransactions.isEmpty else {
            return MultiLineIncomeData(totalLine: [], memberLines: [])
        }
        
        // Track income by date for total and per member
        var totalByDate: [Date: Decimal] = [:]
        var memberIncomeByDate: [UUID: [Date: Decimal]] = [:]
        
        // Initialize member tracking
        for member in activeMembers {
            memberIncomeByDate[member.id] = [:]
        }
        
        for income in incomeTransactions {
            let dateKey = Calendar.current.startOfDay(for: income.date)
            
            // Add to total
            totalByDate[dateKey, default: 0] += income.amount
            
            // Add to member amounts based on paidByMemberId (who received the income)
            if let receivedById = income.paidByMemberId {
                memberIncomeByDate[receivedById, default: [:]][dateKey, default: 0] += income.amount
            } else if !activeMembers.isEmpty {
                // Fallback: distribute equally among active members so member totals add up
                let shareAmount = income.amount / Decimal(activeMembers.count)
                for member in activeMembers {
                    memberIncomeByDate[member.id, default: [:]][dateKey, default: 0] += shareAmount
                }
            }
        }
        
        // Get all unique dates and sort them
        let allDates = totalByDate.keys.sorted()
        
        // Build total line with cumulative values
        var totalLine: [IncomeChartPoint] = []
        var totalCumulative: Decimal = 0
        for date in allDates {
            let dailyAmount = totalByDate[date] ?? 0
            totalCumulative += dailyAmount
            totalLine.append(IncomeChartPoint(
                date: date,
                dailyAmount: dailyAmount,
                cumulativeAmount: totalCumulative
            ))
        }
        
        // Build member lines with cumulative values
        var memberLines: [MemberIncomeLine] = []
        for member in activeMembers {
            var points: [IncomeChartPoint] = []
            var cumulative: Decimal = 0
            let memberDates = memberIncomeByDate[member.id] ?? [:]
            
            for date in allDates {
                let dailyAmount = memberDates[date] ?? 0
                cumulative += dailyAmount
                points.append(IncomeChartPoint(
                    date: date,
                    dailyAmount: dailyAmount,
                    cumulativeAmount: cumulative
                ))
            }
            
            // Only include members who have some income
            if cumulative > 0 {
                memberLines.append(MemberIncomeLine(
                    memberId: member.id,
                    memberName: member.displayName,
                    color: member.swiftUIColor,
                    emoji: member.avatarUrl,
                    points: points,
                    total: cumulative
                ))
            }
        }
        
        // Sort member lines by total (highest first)
        memberLines.sort { $0.total > $1.total }
        
        return MultiLineIncomeData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Income sorted by date descending for the list
    private var sortedIncome: [TransactionView] {
        incomeTransactions.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Total header
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Theme.Colors.income)
                            
                            Text("Total Income")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            Text(totalIncome.doubleValue.formattedAsMoney())
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(Theme.Colors.income)
                            
                            Text("\(incomeTransactions.count) transactions")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.top, Theme.Spacing.md)
                        
                        // Chart section
                        if multiLineChartData.totalLine.count >= 2 {
                            MultiLineIncomeChart(data: multiLineChartData)
                                .padding(.horizontal, Theme.Spacing.md)
                        } else if multiLineChartData.totalLine.count == 1 {
                            // Single data point - show as simple stat
                            VStack(spacing: Theme.Spacing.sm) {
                                Text("Income on \(multiLineChartData.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Text(multiLineChartData.totalLine[0].dailyAmount.doubleValue.formattedAsMoney())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.income)
                            }
                            .frame(maxWidth: .infinity)
                            .cardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Income list
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("All Income")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\(sortedIncome.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if sortedIncome.isEmpty {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "tray")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No income found")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(sortedIncome) { income in
                                        Button {
                                            selectedTransaction = income
                                        } label: {
                                            IncomeDetailRow(transaction: income)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if income.id != sortedIncome.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
        }
    }
}

// MARK: - Income Chart Data Structures

struct IncomeChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let dailyAmount: Decimal
    let cumulativeAmount: Decimal
}

struct MemberIncomeLine: Identifiable {
    let id: UUID
    let memberId: UUID
    let memberName: String
    let color: Color
    let emoji: String?
    let points: [IncomeChartPoint]
    let total: Decimal
    
    init(memberId: UUID, memberName: String, color: Color, emoji: String?, points: [IncomeChartPoint], total: Decimal) {
        self.id = memberId
        self.memberId = memberId
        self.memberName = memberName
        self.color = color
        self.emoji = emoji
        self.points = points
        self.total = total
    }
}

struct MultiLineIncomeData {
    let totalLine: [IncomeChartPoint]
    let memberLines: [MemberIncomeLine]
}

// MARK: - Multi-Line Income Chart

struct MultiLineIncomeChart: View {
    let data: MultiLineIncomeData
    
    @State private var selectedDate: Date?
    @State private var showMemberBreakdown = false
    
    private var maxAmount: Double {
        data.totalLine.map { $0.cumulativeAmount.doubleValue }.max() ?? 0
    }
    
    /// Get values at selected date
    private var selectedValues: (total: IncomeChartPoint?, members: [(MemberIncomeLine, IncomeChartPoint)])? {
        guard let date = selectedDate else { return nil }
        
        let totalPoint = data.totalLine.min { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        }
        
        let memberPoints: [(MemberIncomeLine, IncomeChartPoint)] = data.memberLines.compactMap { line in
            guard let point = line.points.min(by: { point1, point2 in
                abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
            }) else { return nil }
            return (line, point)
        }
        
        return (totalPoint, memberPoints)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header with member breakdown toggle
            HStack {
                Text("Income Over Time")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if !data.memberLines.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMemberBreakdown.toggle()
                        }
                    } label: {
                        Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                            .font(.title3)
                            .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted)
                    }
                }
            }
            
            // Selected point info
            if let selected = selectedValues, let totalPoint = selected.total {
                VStack(spacing: Theme.Spacing.xs) {
                    // Date and total
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(totalPoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.income)
                                    .frame(width: 8, height: 8)
                                Text("Total: \(totalPoint.cumulativeAmount.doubleValue.formattedAsMoney())")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.income)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("That day")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            Text("+\(totalPoint.dailyAmount.doubleValue.formattedAsMoney())")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.income.opacity(0.8))
                        }
                    }
                    
                    // Member breakdown for selected date (only when member breakdown is enabled)
                    if showMemberBreakdown && !selected.members.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(selected.members.prefix(4), id: \.0.id) { (line, point) in
                                HStack(spacing: 4) {
                                    if let emoji = line.emoji, !emoji.isEmpty {
                                        Text(emoji)
                                            .font(.caption2)
                                    } else {
                                        Circle()
                                            .fill(line.color)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(point.cumulativeAmount.doubleValue.formattedAsMoney())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(line.color)
                                }
                            }
                            
                            if selected.members.count > 4 {
                                Text("+\(selected.members.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity)
            }
            
            // Chart
            Chart {
                // Member lines (render first so total line is on top) - only when toggled on
                if showMemberBreakdown {
                    ForEach(data.memberLines) { memberLine in
                        ForEach(memberLine.points) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Amount", point.cumulativeAmount.doubleValue),
                                series: .value("Member", memberLine.memberName)
                            )
                            .foregroundStyle(memberLine.color.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                
                // Total line (area fill)
                ForEach(data.totalLine) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Total", point.cumulativeAmount.doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.Colors.income.opacity(0.15), Theme.Colors.income.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                // Total line
                ForEach(data.totalLine) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Total", point.cumulativeAmount.doubleValue),
                        series: .value("Member", "Total")
                    )
                    .foregroundStyle(Theme.Colors.income)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                
                // Selection rule line
                if let date = selectedDate {
                    RuleMark(x: .value("Date", date, unit: .day))
                        .foregroundStyle(Theme.Colors.textMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatAxisLabel(amount))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(data.totalLine.count, 5))) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight.opacity(0.5))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let location = value.location
                                    if let date: Date = proxy.value(atX: location.x) {
                                        selectedDate = date
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedDate = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.15), value: selectedDate)
            
            // Legend (only when member breakdown is enabled)
            if showMemberBreakdown && !data.memberLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Total row
                    HStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Colors.income)
                                .frame(width: 16, height: 3)
                            
                            Text("Total")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Text(data.totalLine.last?.cumulativeAmount.doubleValue.formattedAsMoney() ?? "$0")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.income)
                    }
                    
                    // Member rows
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 16)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(line.color)
                                        .frame(width: 16, height: 3)
                                }
                                
                                Text(line.memberName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(line.total.doubleValue.formattedAsMoney())
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(line.color)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
    
    private func formatAxisLabel(_ value: Double) -> String {
        if value >= 1000 {
            return "$\(Int(value / 1000))k"
        } else if value >= 1 {
            return "$\(Int(value))"
        }
        return "$0"
    }
}

// MARK: - Income Detail Row

struct IncomeDetailRow: View {
    let transaction: TransactionView
    
    private var isReimbursement: Bool {
        transaction.transactionType == .reimbursement
    }
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        return isReimbursement ? Theme.Colors.reimbursement : Theme.Colors.income
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if let icon = transaction.categoryIcon, !icon.isEmpty {
                    if isSFSymbol(icon) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(categoryColor)
                    } else {
                        Text(icon)
                            .font(.system(size: 18))
                    }
                } else {
                    Image(systemName: isReimbursement ? "arrow.uturn.backward" : "wallet.pass")
                        .font(.system(size: 16))
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    if isReimbursement {
                        Text("Reimbursement")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.reimbursement)
                    } else if let categoryName = transaction.categoryName {
                        Text(categoryName)
                            .font(.caption2)
                            .foregroundStyle(categoryColor)
                    }
                    
                    if isReimbursement || transaction.categoryName != nil {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    if let receivedByName = transaction.paidByName {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                        
                        Text(receivedByName)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            
            Spacer()
            
            // Amount
            Text("+\(transaction.amount.doubleValue.formattedAsMoney())")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.income)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Net Balance Detail Sheet

struct NetBalanceDetailSheet: View {
    let totalIncome: Decimal
    let totalExpenses: Decimal
    let filteredTransactions: [TransactionView]
    let allTransactions: [TransactionView]
    let allSplits: [UUID: [TransactionSplit]]
    let members: [HouseholdMember]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransaction: TransactionView?
    
    private var netBalance: Decimal {
        totalIncome - totalExpenses
    }
    
    private var isPositive: Bool {
        netBalance >= 0
    }
    
    /// Active members only (for the chart)
    private var activeMembers: [HouseholdMember] {
        members.filter { $0.isActive }
    }
    
    /// Expense transactions only
    private var expenseTransactions: [TransactionView] {
        filteredTransactions.filter { $0.transactionType == .expense }
    }
    
    /// Income transactions (income + unlinked reimbursements)
    private var incomeTransactions: [TransactionView] {
        filteredTransactions.filter { transaction in
            transaction.transactionType == .income ||
            (transaction.transactionType == .reimbursement && transaction.reimbursesTransactionId == nil)
        }
    }
    
    /// Reimbursements by expense ID
    private var reimbursementsByExpense: [UUID: Decimal] {
        let visibleExpenseIds = Set(expenseTransactions.map { $0.id })
        var result: [UUID: Decimal] = [:]
        for transaction in allTransactions where transaction.transactionType == .reimbursement {
            if let linkedExpenseId = transaction.reimbursesTransactionId,
               visibleExpenseIds.contains(linkedExpenseId) {
                result[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        return result
    }
    
    /// All transactions affecting net balance, sorted by date
    private var allNetTransactions: [TransactionView] {
        var transactions: [TransactionView] = []
        transactions.append(contentsOf: expenseTransactions)
        transactions.append(contentsOf: incomeTransactions)
        return transactions.sorted { $0.date < $1.date }
    }
    
    /// Combined chart data
    private var multiLineChartData: MultiLineNetBalanceData {
        guard !allNetTransactions.isEmpty else {
            return MultiLineNetBalanceData(totalLine: [], memberLines: [])
        }
        
        // Track net by date for total and per member
        var totalIncomeByDate: [Date: Decimal] = [:]
        var totalExpenseByDate: [Date: Decimal] = [:]
        var memberIncomeByDate: [UUID: [Date: Decimal]] = [:]
        var memberExpenseByDate: [UUID: [Date: Decimal]] = [:]
        
        // Initialize member tracking
        for member in activeMembers {
            memberIncomeByDate[member.id] = [:]
            memberExpenseByDate[member.id] = [:]
        }
        
        // Process income transactions
        for income in incomeTransactions {
            let dateKey = Calendar.current.startOfDay(for: income.date)
            totalIncomeByDate[dateKey, default: 0] += income.amount
            
            // Member income based on who received it
            if let receivedById = income.paidByMemberId {
                memberIncomeByDate[receivedById, default: [:]][dateKey, default: 0] += income.amount
            } else if !activeMembers.isEmpty {
                // Fallback: distribute equally among active members so member totals add up
                let shareAmount = income.amount / Decimal(activeMembers.count)
                for member in activeMembers {
                    memberIncomeByDate[member.id, default: [:]][dateKey, default: 0] += shareAmount
                }
            }
        }
        
        // Process expense transactions
        for expense in expenseTransactions {
            let dateKey = Calendar.current.startOfDay(for: expense.date)
            let reimbursedAmount = reimbursementsByExpense[expense.id] ?? 0
            let effectiveAmount = max(expense.amount - reimbursedAmount, 0)
            
            guard effectiveAmount > 0 else { continue }
            
            totalExpenseByDate[dateKey, default: 0] += effectiveAmount
            
            // Member expenses based on owed amounts from splits
            let reimbursementRatio = expense.amount > 0 ? effectiveAmount / expense.amount : 1
            if let splits = allSplits[expense.id], !splits.isEmpty {
                for split in splits where split.owedAmount > 0 {
                    let adjustedOwed = split.owedAmount * reimbursementRatio
                    memberExpenseByDate[split.memberId, default: [:]][dateKey, default: 0] += adjustedOwed
                }
            } else if let payerId = expense.paidByMemberId {
                // Fallback: attribute full expense to payer when splits are missing
                memberExpenseByDate[payerId, default: [:]][dateKey, default: 0] += effectiveAmount
            } else if !activeMembers.isEmpty {
                // Last resort: distribute equally among active members
                let shareAmount = effectiveAmount / Decimal(activeMembers.count)
                for member in activeMembers {
                    memberExpenseByDate[member.id, default: [:]][dateKey, default: 0] += shareAmount
                }
            }
        }
        
        // Get all unique dates and sort them
        let allDates = Set(totalIncomeByDate.keys).union(Set(totalExpenseByDate.keys)).sorted()
        
        // Build total line with cumulative net values
        var totalLine: [NetBalanceChartPoint] = []
        var cumulativeIncome: Decimal = 0
        var cumulativeExpense: Decimal = 0
        
        for date in allDates {
            let dailyIncome = totalIncomeByDate[date] ?? 0
            let dailyExpense = totalExpenseByDate[date] ?? 0
            cumulativeIncome += dailyIncome
            cumulativeExpense += dailyExpense
            let cumulativeNet = cumulativeIncome - cumulativeExpense
            let dailyNet = dailyIncome - dailyExpense
            
            totalLine.append(NetBalanceChartPoint(
                date: date,
                dailyIncome: dailyIncome,
                dailyExpense: dailyExpense,
                dailyNet: dailyNet,
                cumulativeNet: cumulativeNet
            ))
        }
        
        // Build member lines with cumulative net values
        var memberLines: [MemberNetBalanceLine] = []
        for member in activeMembers {
            var points: [NetBalanceChartPoint] = []
            var cumIncome: Decimal = 0
            var cumExpense: Decimal = 0
            let memberIncome = memberIncomeByDate[member.id] ?? [:]
            let memberExpense = memberExpenseByDate[member.id] ?? [:]
            
            for date in allDates {
                let dailyIncome = memberIncome[date] ?? 0
                let dailyExpense = memberExpense[date] ?? 0
                cumIncome += dailyIncome
                cumExpense += dailyExpense
                let cumNet = cumIncome - cumExpense
                let dailyNet = dailyIncome - dailyExpense
                
                points.append(NetBalanceChartPoint(
                    date: date,
                    dailyIncome: dailyIncome,
                    dailyExpense: dailyExpense,
                    dailyNet: dailyNet,
                    cumulativeNet: cumNet
                ))
            }
            
            let totalNet = cumIncome - cumExpense
            
            // Only include members who have some activity
            if cumIncome > 0 || cumExpense > 0 {
                memberLines.append(MemberNetBalanceLine(
                    memberId: member.id,
                    memberName: member.displayName,
                    color: member.swiftUIColor,
                    emoji: member.avatarUrl,
                    points: points,
                    totalIncome: cumIncome,
                    totalExpense: cumExpense,
                    totalNet: totalNet
                ))
            }
        }
        
        // Sort member lines by absolute net (highest first)
        memberLines.sort { abs($0.totalNet) > abs($1.totalNet) }
        
        return MultiLineNetBalanceData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Transactions sorted by date descending for the list
    private var sortedTransactions: [TransactionView] {
        allNetTransactions.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Total header
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: isPositive ? "arrow.up.arrow.down.circle.fill" : "arrow.down.arrow.up.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
                            
                            Text("Net Balance")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            Text(netBalance.doubleValue.formattedAsMoney(showSign: true))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
                            
                            // Breakdown
                            HStack(spacing: Theme.Spacing.lg) {
                                VStack(spacing: 2) {
                                    Text("Income")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    Text("+\(totalIncome.doubleValue.formattedAsMoney())")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Theme.Colors.income)
                                }
                                
                                Text("−")
                                    .font(.title3)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                VStack(spacing: 2) {
                                    Text("Expenses")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    Text(totalExpenses.doubleValue.formattedAsMoney())
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Theme.Colors.expense)
                                }
                            }
                            
                            Text("\(sortedTransactions.count) transactions")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.top, Theme.Spacing.md)
                        
                        // Chart section
                        if multiLineChartData.totalLine.count >= 2 {
                            MultiLineNetBalanceChart(data: multiLineChartData)
                                .padding(.horizontal, Theme.Spacing.md)
                        } else if multiLineChartData.totalLine.count == 1 {
                            // Single data point
                            VStack(spacing: Theme.Spacing.sm) {
                                Text("Activity on \(multiLineChartData.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Text(multiLineChartData.totalLine[0].dailyNet.doubleValue.formattedAsMoney(showSign: true))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(multiLineChartData.totalLine[0].dailyNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                            }
                            .frame(maxWidth: .infinity)
                            .cardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Transactions list
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("All Transactions")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\(sortedTransactions.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if sortedTransactions.isEmpty {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "tray")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No transactions found")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(sortedTransactions) { transaction in
                                        Button {
                                            selectedTransaction = transaction
                                        } label: {
                                            NetBalanceTransactionRow(
                                                transaction: transaction,
                                                reimbursedAmount: reimbursementsByExpense[transaction.id] ?? 0
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if transaction.id != sortedTransactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Net Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
        }
    }
}

// MARK: - Net Balance Chart Data Structures

struct NetBalanceChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let dailyIncome: Decimal
    let dailyExpense: Decimal
    let dailyNet: Decimal
    let cumulativeNet: Decimal
}

struct MemberNetBalanceLine: Identifiable {
    let id: UUID
    let memberId: UUID
    let memberName: String
    let color: Color
    let emoji: String?
    let points: [NetBalanceChartPoint]
    let totalIncome: Decimal
    let totalExpense: Decimal
    let totalNet: Decimal
    
    init(memberId: UUID, memberName: String, color: Color, emoji: String?, points: [NetBalanceChartPoint], totalIncome: Decimal, totalExpense: Decimal, totalNet: Decimal) {
        self.id = memberId
        self.memberId = memberId
        self.memberName = memberName
        self.color = color
        self.emoji = emoji
        self.points = points
        self.totalIncome = totalIncome
        self.totalExpense = totalExpense
        self.totalNet = totalNet
    }
}

struct MultiLineNetBalanceData {
    let totalLine: [NetBalanceChartPoint]
    let memberLines: [MemberNetBalanceLine]
}

// MARK: - Multi-Line Net Balance Chart

struct MultiLineNetBalanceChart: View {
    let data: MultiLineNetBalanceData
    
    @State private var selectedDate: Date?
    @State private var showMemberBreakdown = false
    
    private var finalNetBalance: Decimal {
        data.totalLine.last?.cumulativeNet ?? 0
    }
    
    private var isPositive: Bool {
        finalNetBalance >= 0
    }
    
    private var netColor: Color {
        isPositive ? Theme.Colors.success : Theme.Colors.error
    }
    
    /// Get values at selected date
    private var selectedValues: (total: NetBalanceChartPoint?, members: [(MemberNetBalanceLine, NetBalanceChartPoint)])? {
        guard let date = selectedDate else { return nil }
        
        let totalPoint = data.totalLine.min { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        }
        
        let memberPoints: [(MemberNetBalanceLine, NetBalanceChartPoint)] = data.memberLines.compactMap { line in
            guard let point = line.points.min(by: { point1, point2 in
                abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
            }) else { return nil }
            return (line, point)
        }
        
        return (totalPoint, memberPoints)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header with member breakdown toggle
            HStack {
                Text("Net Balance Over Time")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if !data.memberLines.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMemberBreakdown.toggle()
                        }
                    } label: {
                        Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                            .font(.title3)
                            .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted)
                    }
                }
            }
            
            // Selected point info
            if let selected = selectedValues, let totalPoint = selected.total {
                VStack(spacing: Theme.Spacing.xs) {
                    // Date and total
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(totalPoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(totalPoint.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                    .frame(width: 8, height: 8)
                                Text("Net: \(totalPoint.cumulativeNet.doubleValue.formattedAsMoney(showSign: true))")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(totalPoint.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("That day")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            Text(totalPoint.dailyNet.doubleValue.formattedAsMoney(showSign: true))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(totalPoint.dailyNet >= 0 ? Theme.Colors.success.opacity(0.8) : Theme.Colors.error.opacity(0.8))
                        }
                    }
                    
                    // Member breakdown for selected date (only when member breakdown is enabled)
                    if showMemberBreakdown && !selected.members.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(selected.members.prefix(4), id: \.0.id) { (line, point) in
                                HStack(spacing: 4) {
                                    if let emoji = line.emoji, !emoji.isEmpty {
                                        Text(emoji)
                                            .font(.caption2)
                                    } else {
                                        Circle()
                                            .fill(line.color)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(point.cumulativeNet.doubleValue.formattedAsMoney(showSign: true))
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(point.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                }
                            }
                            
                            if selected.members.count > 4 {
                                Text("+\(selected.members.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity)
            }
            
            // Chart
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.Colors.textMuted.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Member lines (render first so total line is on top) - only when toggled on
                if showMemberBreakdown {
                    ForEach(data.memberLines) { memberLine in
                        ForEach(memberLine.points) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Net", point.cumulativeNet.doubleValue),
                                series: .value("Member", memberLine.memberName)
                            )
                            .foregroundStyle(memberLine.color.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                
                // Total line (area fill) - different color above/below zero
                ForEach(data.totalLine) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Net", point.cumulativeNet.doubleValue)
                    )
                    .foregroundStyle(
                        point.cumulativeNet >= 0 ?
                        LinearGradient(
                            colors: [Theme.Colors.success.opacity(0.15), Theme.Colors.success.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ) :
                        LinearGradient(
                            colors: [Theme.Colors.error.opacity(0.02), Theme.Colors.error.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                // Total line
                ForEach(data.totalLine) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Net", point.cumulativeNet.doubleValue),
                        series: .value("Member", "Total")
                    )
                    .foregroundStyle(point.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                
                // Selection rule line
                if let date = selectedDate {
                    RuleMark(x: .value("Date", date, unit: .day))
                        .foregroundStyle(Theme.Colors.textMuted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatAxisLabel(amount))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(data.totalLine.count, 5))) { value in
                    AxisGridLine()
                        .foregroundStyle(Theme.Colors.borderLight.opacity(0.5))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let location = value.location
                                    if let date: Date = proxy.value(atX: location.x) {
                                        selectedDate = date
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedDate = nil
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.15), value: selectedDate)
            
            // Legend (only when member breakdown is enabled)
            if showMemberBreakdown && !data.memberLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Total row
                    HStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(netColor)
                                .frame(width: 16, height: 3)
                            
                            Text("Total")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Text(finalNetBalance.doubleValue.formattedAsMoney(showSign: true))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(netColor)
                    }
                    
                    // Member rows
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 16)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(line.color)
                                        .frame(width: 16, height: 3)
                                }
                                
                                Text(line.memberName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(line.totalNet.doubleValue.formattedAsMoney(showSign: true))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(line.color)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
    
    private func formatAxisLabel(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 1000 {
            return "\(sign)$\(Int(absValue / 1000))k"
        } else if absValue >= 1 {
            return "\(sign)$\(Int(absValue))"
        }
        return "$0"
    }
}

// MARK: - Net Balance Transaction Row

struct NetBalanceTransactionRow: View {
    let transaction: TransactionView
    var reimbursedAmount: Decimal = 0
    
    private var isExpense: Bool {
        transaction.transactionType == .expense
    }
    
    private var isReimbursement: Bool {
        transaction.transactionType == .reimbursement
    }
    
    private var effectiveAmount: Decimal {
        if isExpense && reimbursedAmount > 0 {
            return max(transaction.amount - reimbursedAmount, 0)
        }
        return transaction.amount
    }
    
    private var hasReimbursements: Bool {
        isExpense && reimbursedAmount > 0
    }
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        if isExpense { return Theme.Colors.expense }
        if isReimbursement { return Theme.Colors.reimbursement }
        return Theme.Colors.income
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if let icon = transaction.categoryIcon, !icon.isEmpty {
                    if isSFSymbol(icon) {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(categoryColor)
                    } else {
                        Text(icon)
                            .font(.system(size: 18))
                    }
                } else {
                    Image(systemName: isExpense ? "cart" : (isReimbursement ? "arrow.uturn.backward" : "wallet.pass"))
                        .font(.system(size: 16))
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    // Type indicator
                    Text(isExpense ? "Expense" : (isReimbursement ? "Reimbursement" : "Income"))
                        .font(.caption2)
                        .foregroundStyle(categoryColor)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Spacer()
            
            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if hasReimbursements {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.reimbursement)
                    }
                    
                    Text(isExpense ? "-\(effectiveAmount.doubleValue.formattedAsMoney())" : "+\(effectiveAmount.doubleValue.formattedAsMoney())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(isExpense ? Theme.Colors.expense : Theme.Colors.income)
                }
                
                if hasReimbursements {
                    Text("was \(transaction.amount.doubleValue.formattedAsMoney())")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .strikethrough()
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

#Preview {
    DashboardView(filterManager: DashboardFilterManager())
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
