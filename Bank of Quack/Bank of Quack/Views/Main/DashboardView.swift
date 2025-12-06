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
                        
                        // Net Saved (using filtered totals) - hide when income is hidden
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
                    allTransactions: transactionViewModel.transactions,
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
        .materialCardStyle()
    }
}

// MARK: - Settlement Pair (for sheet binding)

struct SettlementPair: Identifiable {
    let id = UUID()
    let from: MemberBalance
    let to: MemberBalance
    let amount: Double
}

// MARK: - Balance Details Sheet

struct BalanceDetailsSheet: View {
    let memberBalances: [MemberBalance]
    let transactions: [TransactionView]
    let transactionSplits: [UUID: [TransactionSplit]]
    let members: [HouseholdMember]
    let currentMemberId: UUID?
    
    @Environment(\.dismiss) private var dismiss
    @State private var expandedMemberId: UUID? = nil
    @State private var selectedTab: BalanceTab = .balances
    @State private var selectedSettlementPair: SettlementPair? = nil
    @State private var transactionsDisplayLimit: Int = 20
    @State private var ledgerDisplayLimit: Int = 20
    
    enum BalanceTab: String, CaseIterable {
        case balances = "Balances"
        case ledger = "Ledger"
    }
    
    /// Calculate suggested settlements to balance everyone out
    private var suggestedSettlements: [(from: MemberBalance, to: MemberBalance, amount: Double)] {
        let filteredBalances = memberBalances.filter { balance in
            // Hide inactive members with zero balance
            if let member = members.first(where: { $0.id == balance.memberId }),
               member.isInactive,
               abs(balance.balance.doubleValue) < 0.01 {
                return false
            }
            return true
        }
        
        let creditors = filteredBalances.filter { $0.balance.doubleValue > 0.01 }
            .sorted { $0.balance.doubleValue > $1.balance.doubleValue }
        let debtors = filteredBalances.filter { $0.balance.doubleValue < -0.01 }
            .sorted { $0.balance.doubleValue < $1.balance.doubleValue }
        
        var settlements: [(from: MemberBalance, to: MemberBalance, amount: Double)] = []
        var debtorsCopy = debtors.map { ($0, abs($0.balance.doubleValue)) }
        var creditorsCopy = creditors.map { ($0, $0.balance.doubleValue) }
        
        var i = 0, j = 0
        while i < debtorsCopy.count && j < creditorsCopy.count {
            let (debtor, debtAmount) = debtorsCopy[i]
            let (creditor, creditAmount) = creditorsCopy[j]
            
            let settlementAmount = min(debtAmount, creditAmount)
            if settlementAmount >= 0.01 {
                settlements.append((from: debtor, to: creditor, amount: settlementAmount))
            }
            
            debtorsCopy[i].1 -= settlementAmount
            creditorsCopy[j].1 -= settlementAmount
            
            if debtorsCopy[i].1 < 0.01 { i += 1 }
            if creditorsCopy[j].1 < 0.01 { j += 1 }
        }
        
        return settlements
    }
    
    private func memberName(for memberId: UUID) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Unknown"
    }
    
    private func member(for memberId: UUID) -> HouseholdMember? {
        members.first { $0.id == memberId }
    }
    
    /// Calculate detailed breakdown for a member
    private func breakdown(for memberId: UUID) -> MemberBalanceBreakdown {
        var expensesPaid: Decimal = 0
        var expensesOwed: Decimal = 0
        var settlementsPaid: Decimal = 0
        var settlementsReceived: Decimal = 0
        var reimbursementsReceived: Decimal = 0
        var reimbursementsOwedReduction: Decimal = 0
        
        for transaction in transactions {
            switch transaction.transactionType {
            case .expense:
                if let splits = transactionSplits[transaction.id] {
                    for split in splits where split.memberId == memberId {
                        expensesPaid += split.paidAmount
                        expensesOwed += split.owedAmount
                    }
                }
                
            case .settlement:
                if transaction.paidByMemberId == memberId {
                    settlementsPaid += transaction.amount
                }
                if transaction.paidToMemberId == memberId {
                    settlementsReceived += transaction.amount
                }
                
            case .reimbursement:
                // Reimbursements reduce the original payer's "paid" and everyone's "owed" proportionally
                if let linkedExpenseId = transaction.reimbursesTransactionId,
                   let linkedSplits = transactionSplits[linkedExpenseId] {
                    let totalOwed = linkedSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
                    
                    // Member's owed reduction
                    if let memberSplit = linkedSplits.first(where: { $0.memberId == memberId }) {
                        let owedPercentage = totalOwed > 0 ? memberSplit.owedAmount / totalOwed : 0
                        reimbursementsOwedReduction += transaction.amount * owedPercentage
                    }
                    
                    // If this member received the reimbursement
                    if transaction.paidByMemberId == memberId {
                        reimbursementsReceived += transaction.amount
                    }
                }
                
            case .income:
                break
            }
        }
        
        return MemberBalanceBreakdown(
            expensesPaid: expensesPaid,
            expensesOwed: expensesOwed,
            settlementsPaid: settlementsPaid,
            settlementsReceived: settlementsReceived,
            reimbursementsReceived: reimbursementsReceived,
            reimbursementsOwedReduction: reimbursementsOwedReduction
        )
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
    
    /// Ledger entries for the current member, showing running balance
    private var ledgerEntries: [LedgerEntry] {
        guard let currentMemberId = currentMemberId else { return [] }
        
        // Sort transactions by date (oldest first for running total)
        let sortedTransactions = transactions.sorted { $0.date < $1.date }
        
        var entries: [LedgerEntry] = []
        var runningBalance: Decimal = 0
        
        for transaction in sortedTransactions {
            var balanceChange: Decimal = 0
            let description = transaction.description
            var detail: String? = nil
            
            switch transaction.transactionType {
            case .expense:
                if let splits = transactionSplits[transaction.id] {
                    for split in splits where split.memberId == currentMemberId {
                        balanceChange = split.paidAmount - split.owedAmount
                    }
                }
                if balanceChange > 0 {
                    detail = "You paid more than your share"
                } else if balanceChange < 0 {
                    detail = "You owe for this expense"
                }
                
            case .settlement:
                if transaction.paidByMemberId == currentMemberId {
                    balanceChange = transaction.amount
                    detail = "You paid \(transaction.paidToName ?? "someone")"
                } else if transaction.paidToMemberId == currentMemberId {
                    balanceChange = -transaction.amount
                    detail = "\(transaction.paidByName ?? "Someone") paid you"
                }
                
            case .reimbursement:
                if let linkedExpenseId = transaction.reimbursesTransactionId,
                   let linkedSplits = transactionSplits[linkedExpenseId] {
                    let totalOwed = linkedSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
                    
                    if let memberSplit = linkedSplits.first(where: { $0.memberId == currentMemberId }) {
                        let owedPercentage = totalOwed > 0 ? memberSplit.owedAmount / totalOwed : 0
                        let owedReduction = transaction.amount * owedPercentage
                        
                        if transaction.paidByMemberId == currentMemberId {
                            // We received the reimbursement
                            let effectivePaidReduction = min(transaction.amount, memberSplit.paidAmount)
                            let remaining = transaction.amount - effectivePaidReduction
                            balanceChange = owedReduction - effectivePaidReduction - remaining
                            detail = "Reimbursement received"
                        } else {
                            // Someone else received - our owed decreased
                            balanceChange = owedReduction
                            detail = "Expense reimbursed"
                        }
                    }
                }
                
            case .income:
                continue
            }
            
            // Only include if this transaction affected the current member's balance
            if abs(balanceChange) > 0.001 {
                runningBalance += balanceChange
                entries.append(LedgerEntry(
                    id: transaction.id,
                    date: transaction.date,
                    description: description,
                    detail: detail,
                    transactionType: transaction.transactionType,
                    balanceChange: balanceChange,
                    runningBalance: runningBalance
                ))
            }
        }
        
        // Reverse to show newest first
        return entries.reversed()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab selector
                    Picker("View", selection: $selectedTab) {
                        ForEach(BalanceTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                
                ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            if selectedTab == .balances {
                                balancesView
                            } else {
                                ledgerView
                            }
                            
                            Spacer(minLength: 40)
                        }
                        .padding(Theme.Spacing.md)
                    }
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
            .sheet(item: $selectedSettlementPair) { pair in
                PairwiseBalanceSheet(
                    fromMember: pair.from,
                    toMember: pair.to,
                    settlementAmount: pair.amount,
                    transactions: transactions,
                    transactionSplits: transactionSplits,
                    members: members
                )
            }
        }
    }
    
    // MARK: - Balances Tab View
    
    private var balancesView: some View {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Bank Balances Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label("Bank Balances", systemImage: "person.2.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                Text("Tap a member to see their breakdown")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                            
                            if sortedMemberBalances.isEmpty {
                                Text("No balance data available")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.vertical, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(sortedMemberBalances, id: \.memberId) { balance in
                            ExpandableMemberBalanceRow(
                                            balance: balance,
                                breakdown: breakdown(for: balance.memberId),
                                            isCurrentMember: balance.memberId == currentMemberId,
                                isInactive: member(for: balance.memberId)?.isInactive ?? false,
                                isExpanded: expandedMemberId == balance.memberId,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedMemberId == balance.memberId {
                                            expandedMemberId = nil
                                        } else {
                                            expandedMemberId = balance.memberId
                                        }
                                    }
                                }
                                        )
                                        
                                        if balance.memberId != sortedMemberBalances.last?.memberId {
                                            Divider()
                                                .background(Theme.Colors.textMuted.opacity(0.3))
                                        }
                                    }
                                }
                                .materialCardStyle()
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
            
            // Suggested Settlements with Pairwise Drill-down
            if !suggestedSettlements.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label("Suggested Settlements", systemImage: "arrow.left.arrow.right.circle")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("Tap to see why this debt exists")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(suggestedSettlements.indices, id: \.self) { index in
                            let settlement = suggestedSettlements[index]
                            let fromMember = members.first { $0.id == settlement.from.memberId }
                            let toMember = members.first { $0.id == settlement.to.memberId }
                            
                            Button {
                                selectedSettlementPair = SettlementPair(from: settlement.from, to: settlement.to, amount: settlement.amount)
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    // From member
                                    VStack(spacing: 2) {
                                        if let member = fromMember {
                                            InlineMemberAvatar(member: member, size: 32)
                                        }
                                        Text(settlement.from.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 70)
                                    
                                    // Arrow with amount
                                    VStack(spacing: 2) {
                                        Image(systemName: "arrow.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.accent)
                                        Text(settlement.amount.formattedAsMoney(showSign: false))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    // To member
                                    VStack(spacing: 2) {
                                        if let member = toMember {
                                            InlineMemberAvatar(member: member, size: 32)
                                        }
                                        Text(settlement.to.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 70)
                                    
                                    // Info icon
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                        .strokeBorder(Theme.Colors.settlement.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
                        
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
                                    ForEach(transactions.prefix(transactionsDisplayLimit)) { transaction in
                                        BalanceTransactionRow(
                                            transaction: transaction,
                                            splits: transactionSplits[transaction.id] ?? [],
                                            allSplits: transactionSplits,
                                            memberName: memberName
                                        )
                                        
                                        if transaction.id != transactions.prefix(transactionsDisplayLimit).last?.id {
                                            Divider()
                                                .background(Theme.Colors.textMuted.opacity(0.3))
                                        }
                                    }
                                    
                                    if transactions.count > transactionsDisplayLimit {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                transactionsDisplayLimit += 20
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("Load \(min(20, transactions.count - transactionsDisplayLimit)) more (\(transactions.count - transactionsDisplayLimit) remaining)")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.md)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .materialCardStyle()
                }
            }
        }
    }
    
    // MARK: - Ledger Tab View
    
    private var ledgerView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Your Balance History", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("How your balance changed over time")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            
            if ledgerEntries.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text("No balance history yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(ledgerEntries.prefix(ledgerDisplayLimit)) { entry in
                        LedgerEntryRow(entry: entry)
                        
                        if entry.id != ledgerEntries.prefix(ledgerDisplayLimit).last?.id {
                            Divider()
                                .background(Theme.Colors.textMuted.opacity(0.3))
                                .padding(.leading, 60)
                        }
                    }
                    
                    if ledgerEntries.count > ledgerDisplayLimit {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                ledgerDisplayLimit += 20
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "arrow.down.circle")
                                Text("Load \(min(20, ledgerEntries.count - ledgerDisplayLimit)) more (\(ledgerEntries.count - ledgerDisplayLimit) remaining)")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .materialCardStyle()
            }
        }
    }
}

// MARK: - Member Balance Breakdown Data

struct MemberBalanceBreakdown {
    let expensesPaid: Decimal
    let expensesOwed: Decimal
    let settlementsPaid: Decimal
    let settlementsReceived: Decimal
    let reimbursementsReceived: Decimal
    let reimbursementsOwedReduction: Decimal
    
    var netBalance: Decimal {
        // Balance = (paid + settlements paid - reimbursements received) - (owed + settlements received - owed reduction)
        let totalPaid = expensesPaid + settlementsPaid - reimbursementsReceived
        let totalOwed = expensesOwed + settlementsReceived - reimbursementsOwedReduction
        return totalPaid - totalOwed
    }
    
    var hasSettlements: Bool {
        settlementsPaid > 0 || settlementsReceived > 0
    }
    
    var hasReimbursements: Bool {
        reimbursementsReceived > 0 || reimbursementsOwedReduction > 0
    }
}

// MARK: - Ledger Entry

struct LedgerEntry: Identifiable {
    let id: UUID
    let date: Date
    let description: String
    let detail: String?
    let transactionType: TransactionType
    let balanceChange: Decimal
    let runningBalance: Decimal
}

// MARK: - Ledger Entry Row

struct LedgerEntryRow: View {
    let entry: LedgerEntry
    
    private var changeColor: Color {
        if abs(entry.balanceChange.doubleValue) < 0.01 {
            return Theme.Colors.textMuted
        }
        return entry.balanceChange > 0 ? Theme.Colors.success : Theme.Colors.error
    }
    
    private var balanceColor: Color {
        if abs(entry.runningBalance.doubleValue) < 0.01 {
            return Theme.Colors.textPrimary
        }
        return entry.runningBalance > 0 ? Theme.Colors.success : Theme.Colors.error
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Date column
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(entry.date.formatted(.dateTime.year()))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .frame(width: 45, alignment: .leading)
            
            // Transaction info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: entry.transactionType.icon)
                        .font(.caption2)
                        .foregroundStyle(entry.transactionType.color)
                    
                    Text(entry.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Spacer()
            
            // Balance change and running total
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.balanceChange >= 0 ? "+\(abs(entry.balanceChange.doubleValue).formattedAsMoney())" : "-\(abs(entry.balanceChange.doubleValue).formattedAsMoney())")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(changeColor)
                
                Text("Balance: \(entry.runningBalance >= 0 ? "" : "-")\(abs(entry.runningBalance.doubleValue).formattedAsMoney())")
                    .font(.caption2)
                    .foregroundStyle(balanceColor)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Expandable Member Balance Row

struct ExpandableMemberBalanceRow: View {
    let balance: MemberBalance
    let breakdown: MemberBalanceBreakdown
    var isCurrentMember: Bool = false
    var isInactive: Bool = false
    let isExpanded: Bool
    let onTap: () -> Void
    
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
        VStack(spacing: 0) {
            // Main row (tappable)
            Button(action: onTap) {
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
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .background(isCurrentMember ? Theme.Colors.accent.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded breakdown
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    VStack(spacing: Theme.Spacing.xs) {
                        // Expenses paid
                        BreakdownRow(
                            icon: "creditcard",
                            label: "Paid for expenses",
                            amount: breakdown.expensesPaid,
                            isPositive: true
                        )
                        
                        // Expenses owed
                        BreakdownRow(
                            icon: "cart",
                            label: "Share of expenses",
                            amount: breakdown.expensesOwed,
                            isPositive: false
                        )
                        
                        // Settlements paid (if any)
                        if breakdown.settlementsPaid > 0 {
                            BreakdownRow(
                                icon: "arrow.right.circle",
                                label: "Settlements paid",
                                amount: breakdown.settlementsPaid,
                                isPositive: true
                            )
                        }
                        
                        // Settlements received (if any)
                        if breakdown.settlementsReceived > 0 {
                            BreakdownRow(
                                icon: "arrow.left.circle",
                                label: "Settlements received",
                                amount: breakdown.settlementsReceived,
                                isPositive: false
                            )
                        }
                        
                        // Reimbursements received (if any)
                        if breakdown.reimbursementsReceived > 0 {
                            BreakdownRow(
                                icon: "arrow.uturn.backward.circle",
                                label: "Reimbursements received",
                                amount: breakdown.reimbursementsReceived,
                                isPositive: false,
                                note: "(reduces what you paid)"
                            )
                        }
                        
                        // Reimbursement owed reduction (if any)
                        if breakdown.reimbursementsOwedReduction > 0 {
                            BreakdownRow(
                                icon: "arrow.uturn.backward.circle",
                                label: "Expense reimbursements",
                                amount: breakdown.reimbursementsOwedReduction,
                                isPositive: true,
                                note: "(reduces what you owe)"
                            )
                        }
                        
                        Divider()
                            .background(Theme.Colors.borderLight)
                            .padding(.vertical, Theme.Spacing.xs)
                        
                        // Net balance
                        HStack {
                            Text("Net Balance")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                            
                            Text(balance.balance >= 0 ? "+\(abs(balance.balance.doubleValue).formattedAsMoney())" : "-\(abs(balance.balance.doubleValue).formattedAsMoney())")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(balanceColor)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.backgroundSecondary.opacity(0.5))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Breakdown Row

struct BreakdownRow: View {
    let icon: String
    let label: String
    let amount: Decimal
    let isPositive: Bool
    var note: String? = nil
    
    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    if let note = note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            
            Spacer()
            
            Text("\(isPositive ? "+" : "-")\(abs(amount.doubleValue).formattedAsMoney())")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
        }
    }
}

// MARK: - Pairwise Balance Sheet

struct PairwiseBalanceSheet: View {
    let fromMember: MemberBalance
    let toMember: MemberBalance
    let settlementAmount: Double
    let transactions: [TransactionView]
    let transactionSplits: [UUID: [TransactionSplit]]
    let members: [HouseholdMember]
    
    @Environment(\.dismiss) private var dismiss
    @State private var transactionsDisplayLimit: Int = 20
    
    private func member(for memberId: UUID) -> HouseholdMember? {
        members.first { $0.id == memberId }
    }
    
    /// Transactions where both members are involved
    private var relevantTransactions: [(transaction: TransactionView, fromPaid: Decimal, fromOwed: Decimal, toPaid: Decimal, toOwed: Decimal)] {
        transactions.compactMap { transaction in
            switch transaction.transactionType {
            case .expense:
                guard let splits = transactionSplits[transaction.id] else { return nil }
                
                let fromSplit = splits.first { $0.memberId == fromMember.memberId }
                let toSplit = splits.first { $0.memberId == toMember.memberId }
                
                // Only include if both members are involved
                guard (fromSplit?.paidAmount ?? 0) > 0 || (fromSplit?.owedAmount ?? 0) > 0 ||
                      (toSplit?.paidAmount ?? 0) > 0 || (toSplit?.owedAmount ?? 0) > 0 else {
                    return nil
                }
                
                return (transaction,
                        fromSplit?.paidAmount ?? 0,
                        fromSplit?.owedAmount ?? 0,
                        toSplit?.paidAmount ?? 0,
                        toSplit?.owedAmount ?? 0)
                
            case .settlement:
                // Only include settlements between these two members
                guard (transaction.paidByMemberId == fromMember.memberId && transaction.paidToMemberId == toMember.memberId) ||
                      (transaction.paidByMemberId == toMember.memberId && transaction.paidToMemberId == fromMember.memberId) else {
                    return nil
                }
                
                let fromPaid = transaction.paidByMemberId == fromMember.memberId ? transaction.amount : 0
                let fromOwed = transaction.paidToMemberId == fromMember.memberId ? transaction.amount : 0
                let toPaid = transaction.paidByMemberId == toMember.memberId ? transaction.amount : 0
                let toOwed = transaction.paidToMemberId == toMember.memberId ? transaction.amount : 0
                
                return (transaction, fromPaid, fromOwed, toPaid, toOwed)
                
            default:
                return nil
            }
        }.sorted { $0.transaction.date > $1.transaction.date }
    }
    
    /// Calculate the net between the two members (bidirectional)
    private var netCalculation: (toPaidForFrom: Decimal, fromPaidForTo: Decimal, settlementsFromToTo: Decimal, settlementsToToFrom: Decimal, netOwed: Decimal) {
        var toPaidForFrom: Decimal = 0    // Amount "to" covered for "from"'s share
        var fromPaidForTo: Decimal = 0    // Amount "from" covered for "to"'s share
        var settlementsFromToTo: Decimal = 0  // Settlements from "from" to "to"
        var settlementsToToFrom: Decimal = 0  // Settlements from "to" to "from"
        
        for item in relevantTransactions {
            switch item.transaction.transactionType {
            case .expense:
                // Calculate each member's balance impact (paid - owed)
                let fromImpact = item.fromPaid - item.fromOwed
                let toImpact = item.toPaid - item.toOwed
                
                // If "to" has positive impact and "from" has negative, "to" covered some of "from"'s share
                if toImpact > 0 && fromImpact < 0 {
                    toPaidForFrom += min(toImpact, abs(fromImpact))
                }
                
                // If "from" has positive impact and "to" has negative, "from" covered some of "to"'s share
                if fromImpact > 0 && toImpact < 0 {
                    fromPaidForTo += min(fromImpact, abs(toImpact))
                }
                
            case .settlement:
                // Track settlements in both directions
                if item.transaction.paidByMemberId == fromMember.memberId &&
                   item.transaction.paidToMemberId == toMember.memberId {
                    settlementsFromToTo += item.transaction.amount
                }
                if item.transaction.paidByMemberId == toMember.memberId &&
                   item.transaction.paidToMemberId == fromMember.memberId {
                    settlementsToToFrom += item.transaction.amount
                }
                
            default:
                break
            }
        }
        
        // Net = what "from" owes "to" - what "to" owes "from" - settlements already made
        let netOwed = toPaidForFrom - fromPaidForTo - settlementsFromToTo + settlementsToToFrom
        return (toPaidForFrom, fromPaidForTo, settlementsFromToTo, settlementsToToFrom, netOwed)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Header showing the relationship
                        VStack(spacing: Theme.Spacing.md) {
                            HStack(spacing: Theme.Spacing.lg) {
                                // From member
                                VStack(spacing: Theme.Spacing.xs) {
                                    if let member = member(for: fromMember.memberId) {
                                        MemberAvatarView(member: member, size: 60, fontSize: 28)
                                    }
                                    Text(fromMember.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                                
                                // Arrow
                                VStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "arrow.right")
                                        .font(.title2)
                                        .foregroundStyle(Theme.Colors.accent)
                                    
                                    Text(settlementAmount > 0.01 ? "owes" : "settled")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                
                                // To member
                                VStack(spacing: Theme.Spacing.xs) {
                                    if let member = member(for: toMember.memberId) {
                                        MemberAvatarView(member: member, size: 60, fontSize: 28)
                                    }
                                    Text(toMember.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                            }
                            
                            // Net amount
                            if settlementAmount > 0.01 {
                                Text(settlementAmount.formattedAsMoney())
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Theme.Colors.error)
                            } else {
                                Text("All settled!")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.success)
                            }
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Summary breakdown
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Summary")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            VStack(spacing: 0) {
                                // What "to" paid for "from" (creates debt)
                                if netCalculation.toPaidForFrom > 0 {
                                    SummaryRow(
                                        label: "\(toMember.displayName) covered for \(fromMember.displayName)",
                                        amount: netCalculation.toPaidForFrom,
                                        color: Theme.Colors.error
                                    )
                                    Divider().background(Theme.Colors.borderLight)
                                }
                                
                                // What "from" paid for "to" (reduces debt)
                                if netCalculation.fromPaidForTo > 0 {
                                    SummaryRow(
                                        label: "\(fromMember.displayName) covered for \(toMember.displayName)",
                                        amount: -netCalculation.fromPaidForTo,
                                        color: Theme.Colors.success
                                    )
                                    Divider().background(Theme.Colors.borderLight)
                                }
                                
                                // Settlements from "from" to "to" (reduces debt)
                                if netCalculation.settlementsFromToTo > 0 {
                                    SummaryRow(
                                        label: "Settlements \(fromMember.displayName) → \(toMember.displayName)",
                                        amount: -netCalculation.settlementsFromToTo,
                                        color: Theme.Colors.success
                                    )
                                    Divider().background(Theme.Colors.borderLight)
                                }
                                
                                // Settlements from "to" to "from" (increases debt)
                                if netCalculation.settlementsToToFrom > 0 {
                                    SummaryRow(
                                        label: "Settlements \(toMember.displayName) → \(fromMember.displayName)",
                                        amount: netCalculation.settlementsToToFrom,
                                        color: Theme.Colors.error
                                    )
                                    Divider().background(Theme.Colors.borderLight)
                                }
                                
                                HStack {
                                    Text("Suggested settlement")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    
                                    Spacer()
                                    
                                    Text(settlementAmount > 0.01 ? settlementAmount.formattedAsMoney() : "$0.00")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(settlementAmount > 0.01 ? Theme.Colors.error : Theme.Colors.success)
                                }
                                .padding(Theme.Spacing.md)
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        }
                        
                        // Transaction list
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Transactions Between Them")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            if relevantTransactions.isEmpty {
                                Text("No transactions found between these members")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.vertical, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(relevantTransactions.prefix(transactionsDisplayLimit), id: \.transaction.id) { item in
                                        PairwiseTransactionRow(
                                            transaction: item.transaction,
                                            fromName: fromMember.displayName,
                                            toName: toMember.displayName,
                                            fromPaid: item.fromPaid,
                                            fromOwed: item.fromOwed,
                                            toPaid: item.toPaid,
                                            toOwed: item.toOwed
                                        )
                                        
                                        if item.transaction.id != relevantTransactions.prefix(transactionsDisplayLimit).last?.transaction.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                        }
                                    }
                                    
                                    if relevantTransactions.count > transactionsDisplayLimit {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                transactionsDisplayLimit += 20
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("Load \(min(20, relevantTransactions.count - transactionsDisplayLimit)) more (\(relevantTransactions.count - transactionsDisplayLimit) remaining)")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.md)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Why This Debt?")
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

// MARK: - Summary Row

struct SummaryRow: View {
    let label: String
    let amount: Decimal
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            Spacer()
            
            Text(amount >= 0 ? amount.doubleValue.formattedAsMoney() : "-\(abs(amount.doubleValue).formattedAsMoney())")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(Theme.Spacing.md)
    }
}

// MARK: - Pairwise Transaction Row

struct PairwiseTransactionRow: View {
    let transaction: TransactionView
    let fromName: String
    let toName: String
    let fromPaid: Decimal
    let fromOwed: Decimal
    let toPaid: Decimal
    let toOwed: Decimal
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    if transaction.transactionType == .settlement {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.settlement)
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
                    .foregroundStyle(transaction.transactionType == .settlement ? Theme.Colors.settlement : Theme.Colors.expense)
            }
            
            Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textMuted)
            
            // Show who paid/owed what
            if transaction.transactionType == .expense {
                HStack(spacing: Theme.Spacing.lg) {
                    if fromPaid > 0 || fromOwed > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fromName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: Theme.Spacing.xs) {
                                if fromPaid > 0 {
                                    Text("paid \(fromPaid.doubleValue.formattedAsMoney())")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.success)
                                }
                                if fromOwed > 0 {
                                    Text("owes \(fromOwed.doubleValue.formattedAsMoney())")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.error)
                                }
                            }
                        }
                    }
                    
                    if toPaid > 0 || toOwed > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toName)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            HStack(spacing: Theme.Spacing.xs) {
                                if toPaid > 0 {
                                    Text("paid \(toPaid.doubleValue.formattedAsMoney())")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.success)
                                }
                                if toOwed > 0 {
                                    Text("owes \(toOwed.doubleValue.formattedAsMoney())")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.Colors.error)
                                }
                            }
                        }
                    }
                }
            } else if transaction.transactionType == .settlement {
                Text("\(transaction.paidByName ?? "Someone") paid \(transaction.paidToName ?? "someone")")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(Theme.Spacing.sm)
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
    @State private var chartData: MultiLineExpenseData?
    @State private var isLoadingChart = true
    @State private var displayLimit: Int = 50
    
    /// Maximum number of chart data points before downsampling
    private let maxChartPoints = 100
    
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
    
    /// Expenses sorted by date descending for the list
    private var sortedExpenses: [TransactionView] {
        expenseTransactions.sorted { $0.date > $1.date }
    }
    
    /// Compute chart data asynchronously with dynamic aggregation
    private func computeChartData() async -> MultiLineExpenseData {
        let expenses = expenseTransactions
        let activeMembersList = activeMembers
        let reimbursements = reimbursementsByExpense
        let splits = allSplits
        let calendar = Calendar.current
        
        guard !expenses.isEmpty else {
            return MultiLineExpenseData(totalLine: [], memberLines: [])
        }
        
        // Determine aggregation period based on date range
        let sortedDates = expenses.map { $0.date }.sorted()
        guard let firstDate = sortedDates.first, let lastDate = sortedDates.last else {
            return MultiLineExpenseData(totalLine: [], memberLines: [])
        }
        let aggregation = AggregationPeriod.forDateRange(from: firstDate, to: lastDate)
        
        // Helper to get period key for a date
        func periodKey(for date: Date) -> Date {
            switch aggregation {
            case .daily:
                return calendar.startOfDay(for: date)
            case .weekly:
                // Start of week (Sunday)
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            case .monthly:
                let components = calendar.dateComponents([.year, .month], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            }
        }
        
        // Helper to format period label
        func periodLabel(for date: Date) -> String {
            let formatter = DateFormatter()
            switch aggregation {
            case .daily:
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            case .weekly:
                formatter.dateFormat = "MMM d"
                return "Week of \(formatter.string(from: date))"
            case .monthly:
                formatter.dateFormat = "MMMM"
                return formatter.string(from: date)
            }
        }
        
        // Track data by period
        var totalByPeriod: [Date: Decimal] = [:]
        var memberExpensesByPeriod: [UUID: [Date: Decimal]] = [:]
        var transactionIdsByPeriod: [Date: [UUID]] = [:]
        
        // Initialize member tracking
        for member in activeMembersList {
            memberExpensesByPeriod[member.id] = [:]
        }
        
        for expense in expenses {
            let key = periodKey(for: expense.date)
            let reimbursedAmount = reimbursements[expense.id] ?? 0
            let effectiveAmount = max(expense.amount - reimbursedAmount, 0)
            
            // Skip fully reimbursed expenses
            guard effectiveAmount > 0 else { continue }
            
            // Add to total and track transaction ID
            totalByPeriod[key, default: 0] += effectiveAmount
            transactionIdsByPeriod[key, default: []].append(expense.id)
            
            // Calculate reimbursement ratio to apply to member splits
            let reimbursementRatio = expense.amount > 0 ? effectiveAmount / expense.amount : 1
            
            // Add to member amounts based on owed (expense for)
            if let expenseSplits = splits[expense.id], !expenseSplits.isEmpty {
                for split in expenseSplits where split.owedAmount > 0 {
                    let adjustedOwed = split.owedAmount * reimbursementRatio
                    memberExpensesByPeriod[split.memberId, default: [:]][key, default: 0] += adjustedOwed
                }
            } else if let payerId = expense.paidByMemberId {
                memberExpensesByPeriod[payerId, default: [:]][key, default: 0] += effectiveAmount
            } else if !activeMembersList.isEmpty {
                let shareAmount = effectiveAmount / Decimal(activeMembersList.count)
                for member in activeMembersList {
                    memberExpensesByPeriod[member.id, default: [:]][key, default: 0] += shareAmount
                }
            }
        }
        
        // Get all periods and sort them
        var allPeriods = totalByPeriod.keys.sorted()
        
        // Downsample if too many data points
        if allPeriods.count > maxChartPoints {
            allPeriods = downsampleDates(allPeriods, to: maxChartPoints)
            totalByPeriod = aggregateByDownsampledDates(totalByPeriod, sampledDates: allPeriods)
            for memberId in memberExpensesByPeriod.keys {
                memberExpensesByPeriod[memberId] = aggregateByDownsampledDates(memberExpensesByPeriod[memberId] ?? [:], sampledDates: allPeriods)
            }
        }
        
        // Build rolling average data (30-period window for daily, adjust for weekly/monthly)
        let rollingWindow: Int
        switch aggregation {
        case .daily: rollingWindow = 30
        case .weekly: rollingWindow = 4  // ~1 month of weeks
        case .monthly: rollingWindow = 3  // 3 months
        }
        var rollingAmounts: [Decimal] = []
        
        // Build total line with member shares
        var totalLine: [ExpenseChartPoint] = []
        var totalCumulative: Decimal = 0
        
        for (index, period) in allPeriods.enumerated() {
            let periodAmount = totalByPeriod[period] ?? 0
            totalCumulative += periodAmount
            
            // Update rolling window
            rollingAmounts.append(periodAmount)
            if rollingAmounts.count > rollingWindow {
                rollingAmounts.removeFirst()
            }
            
            // Calculate rolling average
            let rollingAvg: Decimal? = index >= rollingWindow - 1
                ? rollingAmounts.reduce(0, +) / Decimal(rollingAmounts.count)
                : nil
            
            // Build member shares for this period
            var shares: [MemberShare] = []
            for member in activeMembersList {
                let memberAmount = memberExpensesByPeriod[member.id]?[period] ?? 0
                if memberAmount > 0 {
                    shares.append(MemberShare(
                        id: member.id,
                        memberName: member.displayName,
                        memberColor: member.swiftUIColor,
                        memberEmoji: member.avatarUrl,
                        amount: memberAmount
                    ))
                }
            }
            // Sort shares by amount (largest first for consistent stacking)
            shares.sort { $0.amount > $1.amount }
            
            totalLine.append(ExpenseChartPoint(
                date: period,
                periodLabel: periodLabel(for: period),
                dailyAmount: periodAmount,
                cumulativeAmount: totalCumulative,
                rollingAverage: rollingAvg,
                memberShares: shares,
                transactionIds: transactionIdsByPeriod[period] ?? []
            ))
        }
        
        // Build member lines (still needed for legend totals)
        var memberLines: [MemberExpenseLine] = []
        for member in activeMembersList {
            var points: [ExpenseChartPoint] = []
            var cumulative: Decimal = 0
            let memberPeriods = memberExpensesByPeriod[member.id] ?? [:]
            var memberRollingAmounts: [Decimal] = []
            
            for (index, period) in allPeriods.enumerated() {
                let periodAmount = memberPeriods[period] ?? 0
                cumulative += periodAmount
                
                memberRollingAmounts.append(periodAmount)
                if memberRollingAmounts.count > rollingWindow {
                    memberRollingAmounts.removeFirst()
                }
                
                let rollingAvg: Decimal? = index >= rollingWindow - 1
                    ? memberRollingAmounts.reduce(0, +) / Decimal(memberRollingAmounts.count)
                    : nil
                
                points.append(ExpenseChartPoint(
                    date: period,
                    periodLabel: periodLabel(for: period),
                    dailyAmount: periodAmount,
                    cumulativeAmount: cumulative,
                    rollingAverage: rollingAvg,
                    memberShares: [],
                    transactionIds: []
                ))
            }
            
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
        
        memberLines.sort { $0.total > $1.total }
        
        return MultiLineExpenseData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Downsample dates to target count using even distribution
    private func downsampleDates(_ dates: [Date], to targetCount: Int) -> [Date] {
        guard dates.count > targetCount else { return dates }
        let step = Double(dates.count) / Double(targetCount)
        var result: [Date] = []
        var index: Double = 0
        while Int(index) < dates.count && result.count < targetCount {
            result.append(dates[Int(index)])
            index += step
        }
        // Always include the last date
        if let lastDate = dates.last, result.last != lastDate {
            result[result.count - 1] = lastDate
        }
        return result
    }
    
    /// Aggregate data by downsampled dates (assign each original date's data to nearest sampled date)
    private func aggregateByDownsampledDates(_ data: [Date: Decimal], sampledDates: [Date]) -> [Date: Decimal] {
        var result: [Date: Decimal] = [:]
        for (date, amount) in data {
            // Find the nearest sampled date
            let nearestDate = sampledDates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) } ?? date
            result[nearestDate, default: 0] += amount
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
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
                        if isLoadingChart {
                            VStack(spacing: Theme.Spacing.sm) {
                                ProgressView()
                                    .tint(Theme.Colors.expense)
                                Text("Loading chart...")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .materialCardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        } else if let data = chartData {
                            if data.totalLine.count >= 2 {
                                MultiLineExpenseChart(data: data, allTransactions: filteredTransactions)
                                    .padding(.horizontal, Theme.Spacing.md)
                            } else if data.totalLine.count == 1 {
                                // Single data point - show as simple stat
                                VStack(spacing: Theme.Spacing.sm) {
                                    Text("Expense on \(data.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text(data.totalLine[0].dailyAmount.doubleValue.formattedAsMoney())
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Theme.Colors.expense)
                                }
                                .frame(maxWidth: .infinity)
                                .materialCardStyle()
                                .padding(.horizontal, Theme.Spacing.md)
                            }
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
                                    let displayedExpenses = Array(sortedExpenses.prefix(displayLimit))
                                    ForEach(displayedExpenses) { expense in
                                        Button {
                                            selectedTransaction = expense
                                        } label: {
                                            ExpenseDetailRow(
                                                transaction: expense,
                                                reimbursedAmount: reimbursementsByExpense[expense.id] ?? 0
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if expense.id != displayedExpenses.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                    
                                    // Load more button
                                    if sortedExpenses.count > displayLimit {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                displayLimit += 50
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("Load \(min(50, sortedExpenses.count - displayLimit)) more (\(sortedExpenses.count - displayLimit) remaining)")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.md)
                                        }
                                        .buttonStyle(.plain)
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
            .task {
                // Compute chart data asynchronously
                let data = await computeChartData()
                await MainActor.run {
                    chartData = data
                    isLoadingChart = false
                }
            }
        }
    }
}

// MARK: - Expense Chart Data Structures

// MARK: - Chart Aggregation

enum AggregationPeriod {
    case daily, weekly, monthly
    
    static func forDateRange(from start: Date, to end: Date) -> AggregationPeriod {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        if days <= 31 { return .daily }
        if days <= 180 { return .weekly }
        return .monthly
    }
}

struct MemberShare: Identifiable {
    let id: UUID  // memberId
    let memberName: String
    let memberColor: Color
    let memberEmoji: String?
    let amount: Decimal
}

struct ExpenseChartPoint: Identifiable {
    // Use date as ID to avoid UUID allocation overhead
    var id: Date { date }
    let date: Date
    let periodLabel: String             // "Dec 5" or "Week of Dec 1" or "December"
    let dailyAmount: Decimal            // Total for this bar (renamed but kept for compatibility)
    let cumulativeAmount: Decimal
    let rollingAverage: Decimal?        // 30-day rolling avg (nil if insufficient data)
    let memberShares: [MemberShare]     // For stacked bar rendering
    let transactionIds: [UUID]          // Transaction IDs for this period (for tap sheet)
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
    let allTransactions: [TransactionView]
    
    @State private var showMemberBreakdown = false
    @State private var showRollingAverage = false
    @State private var selectedPoint: ExpenseChartPoint?
    @State private var showPeriodTransactions = false
    
    /// Check if rolling average data is available
    private var hasRollingAverageData: Bool {
        data.totalLine.contains { $0.rollingAverage != nil }
    }
    
    /// Calculate average amount
    private var averageAmount: Double {
        let amounts = data.totalLine.map { $0.dailyAmount.doubleValue }
        guard !amounts.isEmpty else { return 0 }
        return amounts.reduce(0, +) / Double(amounts.count)
    }
    
    /// Detect aggregation period based on date gaps in data
    private var detectedAggregation: AggregationPeriod {
        guard data.totalLine.count >= 2 else { return .daily }
        let sortedDates = data.totalLine.map { $0.date }.sorted()
        guard let first = sortedDates.first, let last = sortedDates.last else { return .daily }
        
        // Calculate average gap between consecutive points
        let totalDays = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        let avgGapDays = Double(totalDays) / Double(sortedDates.count - 1)
        
        if avgGapDays > 20 { return .monthly }
        if avgGapDays > 5 { return .weekly }
        return .daily
    }
    
    /// Get the appropriate Calendar.Component for x-axis unit
    private var xAxisUnit: Calendar.Component {
        switch detectedAggregation {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }
    
    /// Calculate bar width ratio - wider for fewer data points
    private var barWidthRatio: Double {
        switch detectedAggregation {
        case .monthly: return 0.8
        case .weekly: return 0.7
        case .daily: return 0.5
        }
    }
    
    /// Find the nearest chart point to a date
    private func findNearestPoint(to date: Date) -> ExpenseChartPoint? {
        data.totalLine.min { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header with toggle controls
            HStack {
                Text("Expenses")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                HStack(spacing: Theme.Spacing.sm) {
                    // Rolling average toggle
                    if hasRollingAverageData {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRollingAverage.toggle()
                            }
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.body)
                                .foregroundStyle(showRollingAverage ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.5))
                        }
                        .help("Rolling average")
                    }
                    
                    // Member breakdown toggle
                    if !data.memberLines.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMemberBreakdown.toggle()
                            }
                        } label: {
                            Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                                .font(.body)
                                .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.5))
                        }
                    }
                }
            }
            
            // Selected point info
            if let point = selectedPoint {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.periodLabel)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.expense)
                                    .frame(width: 8, height: 8)
                                Text(point.dailyAmount.doubleValue.formattedAsMoney())
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.expense)
                            }
                        }
                        
                        Spacer()
                        
                        if showRollingAverage, let avg = point.rollingAverage {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Avg:")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text(avg.doubleValue.formattedAsMoney())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    
                    // Member breakdown for selected period
                    if showMemberBreakdown && !point.memberShares.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(point.memberShares.prefix(4)) { share in
                                HStack(spacing: 4) {
                                    if let emoji = share.memberEmoji, !emoji.isEmpty, !emoji.isPhotoUrl {
                                        Text(emoji)
                                            .font(.caption2)
                                    } else {
                                        Circle()
                                            .fill(share.memberColor)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(share.amount.doubleValue.formattedAsMoney())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(share.memberColor)
                                }
                            }
                            
                            if point.memberShares.count > 4 {
                                Text("+\(point.memberShares.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                    
                    // View transactions button
                    Button {
                        showPeriodTransactions = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("View \(point.transactionIds.count) transaction\(point.transactionIds.count == 1 ? "" : "s")")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity)
            }
            
            // Chart
            Chart {
                // Stacked bars when member breakdown is enabled
                if showMemberBreakdown {
                    ForEach(data.totalLine) { point in
                        ForEach(point.memberShares) { share in
                            BarMark(
                                x: .value("Date", point.date, unit: xAxisUnit),
                                y: .value("Amount", share.amount.doubleValue),
                                width: .ratio(barWidthRatio)
                            )
                            .foregroundStyle(share.memberColor.opacity(0.8))
                        }
                    }
                } else {
                    // Solid bars
                    ForEach(data.totalLine) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: xAxisUnit),
                            y: .value("Amount", point.dailyAmount.doubleValue),
                            width: .ratio(barWidthRatio)
                        )
                        .foregroundStyle(Theme.Colors.expense.opacity(0.7))
                    }
                }
                
                // Average line
                RuleMark(y: .value("Average", averageAmount))
                    .foregroundStyle(Theme.Colors.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                
                // Rolling average line
                if showRollingAverage {
                    ForEach(data.totalLine.filter { $0.rollingAverage != nil }, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: xAxisUnit),
                            y: .value("Rolling", point.rollingAverage!.doubleValue),
                            series: .value("Series", "Rolling")
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                
                // Selection highlight
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date, unit: xAxisUnit))
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
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if let date: Date = proxy.value(atX: value.location.x) {
                                        withAnimation(.easeInOut(duration: 0.1)) {
                                            selectedPoint = findNearestPoint(to: date)
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 180)
            
            // Legend
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Divider()
                    .background(Theme.Colors.borderLight)
                
                HStack(spacing: Theme.Spacing.md) {
                    // Average legend
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.Colors.warning.opacity(0.6))
                            .frame(width: 12, height: 2)
                        Text("Avg: \(averageAmount.formattedAsMoney())")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    if showRollingAverage {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.Colors.accent)
                                .frame(width: 12, height: 2)
                            Text("30d rolling")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                
                // Member legend rows when breakdown is active
                if showMemberBreakdown && !data.memberLines.isEmpty {
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty, !emoji.isPhotoUrl {
                                    Text(emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 16)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(line.color)
                                        .frame(width: 16, height: 8)
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
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .materialCardStyle()
        .sheet(isPresented: $showPeriodTransactions) {
            if let point = selectedPoint {
                PeriodTransactionsSheet(
                    periodLabel: point.periodLabel,
                    totalAmount: point.dailyAmount,
                    transactionIds: point.transactionIds,
                    allTransactions: allTransactions,
                    transactionType: .expense
                )
            }
        }
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
    let allTransactions: [TransactionView]
    let members: [HouseholdMember]
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTransaction: TransactionView?
    @State private var chartData: MultiLineIncomeData?
    @State private var isLoadingChart = true
    @State private var displayLimit: Int = 50
    
    /// Maximum number of chart data points before downsampling
    private let maxChartPoints = 100
    
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
    
    /// Income sorted by date descending for the list
    private var sortedIncome: [TransactionView] {
        incomeTransactions.sorted { $0.date > $1.date }
    }
    
    /// Compute chart data asynchronously
    /// Compute chart data asynchronously with dynamic aggregation
    private func computeChartData() async -> MultiLineIncomeData {
        let incomeList = incomeTransactions
        let activeMembersList = activeMembers
        let calendar = Calendar.current
        
        guard !incomeList.isEmpty else {
            return MultiLineIncomeData(totalLine: [], memberLines: [])
        }
        
        // Determine aggregation period based on date range
        let sortedDates = incomeList.map { $0.date }.sorted()
        guard let firstDate = sortedDates.first, let lastDate = sortedDates.last else {
            return MultiLineIncomeData(totalLine: [], memberLines: [])
        }
        let aggregation = AggregationPeriod.forDateRange(from: firstDate, to: lastDate)
        
        // Helper to get period key for a date
        func periodKey(for date: Date) -> Date {
            switch aggregation {
            case .daily:
                return calendar.startOfDay(for: date)
            case .weekly:
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            case .monthly:
                let components = calendar.dateComponents([.year, .month], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            }
        }
        
        // Helper to format period label
        func periodLabel(for date: Date) -> String {
            let formatter = DateFormatter()
            switch aggregation {
            case .daily:
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            case .weekly:
                formatter.dateFormat = "MMM d"
                return "Week of \(formatter.string(from: date))"
            case .monthly:
                formatter.dateFormat = "MMMM"
                return formatter.string(from: date)
            }
        }
        
        // Track data by period
        var totalByPeriod: [Date: Decimal] = [:]
        var memberIncomeByPeriod: [UUID: [Date: Decimal]] = [:]
        var transactionIdsByPeriod: [Date: [UUID]] = [:]
        
        // Initialize member tracking
        for member in activeMembersList {
            memberIncomeByPeriod[member.id] = [:]
        }
        
        for income in incomeList {
            let key = periodKey(for: income.date)
            
            // Add to total and track transaction ID
            totalByPeriod[key, default: 0] += income.amount
            transactionIdsByPeriod[key, default: []].append(income.id)
            
            // Add to member amounts based on paidByMemberId (who received the income)
            if let receivedById = income.paidByMemberId {
                memberIncomeByPeriod[receivedById, default: [:]][key, default: 0] += income.amount
            } else if !activeMembersList.isEmpty {
                let shareAmount = income.amount / Decimal(activeMembersList.count)
                for member in activeMembersList {
                    memberIncomeByPeriod[member.id, default: [:]][key, default: 0] += shareAmount
                }
            }
        }
        
        // Get all periods and sort them
        var allPeriods = totalByPeriod.keys.sorted()
        
        // Downsample if too many data points
        if allPeriods.count > maxChartPoints {
            allPeriods = downsampleDates(allPeriods, to: maxChartPoints)
            totalByPeriod = aggregateByDownsampledDates(totalByPeriod, sampledDates: allPeriods)
            for memberId in memberIncomeByPeriod.keys {
                memberIncomeByPeriod[memberId] = aggregateByDownsampledDates(memberIncomeByPeriod[memberId] ?? [:], sampledDates: allPeriods)
            }
        }
        
        // Build rolling average data
        let rollingWindow: Int
        switch aggregation {
        case .daily: rollingWindow = 30
        case .weekly: rollingWindow = 4
        case .monthly: rollingWindow = 3
        }
        var rollingAmounts: [Decimal] = []
        
        // Build total line with member shares
        var totalLine: [IncomeChartPoint] = []
        var totalCumulative: Decimal = 0
        
        for (index, period) in allPeriods.enumerated() {
            let periodAmount = totalByPeriod[period] ?? 0
            totalCumulative += periodAmount
            
            // Update rolling window
            rollingAmounts.append(periodAmount)
            if rollingAmounts.count > rollingWindow {
                rollingAmounts.removeFirst()
            }
            
            let rollingAvg: Decimal? = index >= rollingWindow - 1
                ? rollingAmounts.reduce(0, +) / Decimal(rollingAmounts.count)
                : nil
            
            // Build member shares for this period
            var shares: [MemberShare] = []
            for member in activeMembersList {
                let memberAmount = memberIncomeByPeriod[member.id]?[period] ?? 0
                if memberAmount > 0 {
                    shares.append(MemberShare(
                        id: member.id,
                        memberName: member.displayName,
                        memberColor: member.swiftUIColor,
                        memberEmoji: member.avatarUrl,
                        amount: memberAmount
                    ))
                }
            }
            shares.sort { $0.amount > $1.amount }
            
            totalLine.append(IncomeChartPoint(
                date: period,
                periodLabel: periodLabel(for: period),
                dailyAmount: periodAmount,
                cumulativeAmount: totalCumulative,
                rollingAverage: rollingAvg,
                memberShares: shares,
                transactionIds: transactionIdsByPeriod[period] ?? []
            ))
        }
        
        // Build member lines (for legend totals)
        var memberLines: [MemberIncomeLine] = []
        for member in activeMembersList {
            var points: [IncomeChartPoint] = []
            var cumulative: Decimal = 0
            let memberPeriods = memberIncomeByPeriod[member.id] ?? [:]
            var memberRollingAmounts: [Decimal] = []
            
            for (index, period) in allPeriods.enumerated() {
                let periodAmount = memberPeriods[period] ?? 0
                cumulative += periodAmount
                
                memberRollingAmounts.append(periodAmount)
                if memberRollingAmounts.count > rollingWindow {
                    memberRollingAmounts.removeFirst()
                }
                
                let rollingAvg: Decimal? = index >= rollingWindow - 1
                    ? memberRollingAmounts.reduce(0, +) / Decimal(memberRollingAmounts.count)
                    : nil
                
                points.append(IncomeChartPoint(
                    date: period,
                    periodLabel: periodLabel(for: period),
                    dailyAmount: periodAmount,
                    cumulativeAmount: cumulative,
                    rollingAverage: rollingAvg,
                    memberShares: [],
                    transactionIds: []
                ))
            }
            
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
        
        memberLines.sort { $0.total > $1.total }
        
        return MultiLineIncomeData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Downsample dates to target count using even distribution
    private func downsampleDates(_ dates: [Date], to targetCount: Int) -> [Date] {
        guard dates.count > targetCount else { return dates }
        let step = Double(dates.count) / Double(targetCount)
        var result: [Date] = []
        var index: Double = 0
        while Int(index) < dates.count && result.count < targetCount {
            result.append(dates[Int(index)])
            index += step
        }
        // Always include the last date
        if let lastDate = dates.last, result.last != lastDate {
            result[result.count - 1] = lastDate
        }
        return result
    }
    
    /// Aggregate data by downsampled dates (assign each original date's data to nearest sampled date)
    private func aggregateByDownsampledDates(_ data: [Date: Decimal], sampledDates: [Date]) -> [Date: Decimal] {
        var result: [Date: Decimal] = [:]
        for (date, amount) in data {
            // Find the nearest sampled date
            let nearestDate = sampledDates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) } ?? date
            result[nearestDate, default: 0] += amount
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
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
                        if isLoadingChart {
                            VStack(spacing: Theme.Spacing.sm) {
                                ProgressView()
                                    .tint(Theme.Colors.income)
                                Text("Loading chart...")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .materialCardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        } else if let data = chartData {
                            if data.totalLine.count >= 2 {
                                MultiLineIncomeChart(data: data, allTransactions: filteredTransactions)
                                    .padding(.horizontal, Theme.Spacing.md)
                            } else if data.totalLine.count == 1 {
                                // Single data point - show as simple stat
                                VStack(spacing: Theme.Spacing.sm) {
                                    Text("Income on \(data.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text(data.totalLine[0].dailyAmount.doubleValue.formattedAsMoney())
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(Theme.Colors.income)
                                }
                                .frame(maxWidth: .infinity)
                                .materialCardStyle()
                                .padding(.horizontal, Theme.Spacing.md)
                            }
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
                                    let displayedIncome = Array(sortedIncome.prefix(displayLimit))
                                    ForEach(displayedIncome) { income in
                                        Button {
                                            selectedTransaction = income
                                        } label: {
                                            IncomeDetailRow(transaction: income)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if income.id != displayedIncome.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                    
                                    // Load more button
                                    if sortedIncome.count > displayLimit {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                displayLimit += 50
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("Load \(min(50, sortedIncome.count - displayLimit)) more (\(sortedIncome.count - displayLimit) remaining)")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.md)
                                        }
                                        .buttonStyle(.plain)
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
            .task {
                // Compute chart data asynchronously
                let data = await computeChartData()
                await MainActor.run {
                    chartData = data
                    isLoadingChart = false
                }
            }
        }
    }
}

// MARK: - Income Chart Data Structures

struct IncomeChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let periodLabel: String             // "Dec 5" or "Week of Dec 1" or "December"
    let dailyAmount: Decimal            // Total for this bar
    let cumulativeAmount: Decimal
    let rollingAverage: Decimal?        // 30-day rolling avg (nil if insufficient data)
    let memberShares: [MemberShare]     // For stacked bar rendering
    let transactionIds: [UUID]          // Transaction IDs for this period (for tap sheet)
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
    let allTransactions: [TransactionView]
    
    @State private var showMemberBreakdown = false
    @State private var showRollingAverage = false
    @State private var selectedPoint: IncomeChartPoint?
    @State private var showPeriodTransactions = false
    
    /// Check if rolling average data is available
    private var hasRollingAverageData: Bool {
        data.totalLine.contains { $0.rollingAverage != nil }
    }
    
    /// Calculate average amount
    private var averageAmount: Double {
        let amounts = data.totalLine.map { $0.dailyAmount.doubleValue }
        guard !amounts.isEmpty else { return 0 }
        return amounts.reduce(0, +) / Double(amounts.count)
    }
    
    /// Detect aggregation period based on date gaps in data
    private var detectedAggregation: AggregationPeriod {
        guard data.totalLine.count >= 2 else { return .daily }
        let sortedDates = data.totalLine.map { $0.date }.sorted()
        guard let first = sortedDates.first, let last = sortedDates.last else { return .daily }
        
        let totalDays = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        let avgGapDays = Double(totalDays) / Double(sortedDates.count - 1)
        
        if avgGapDays > 20 { return .monthly }
        if avgGapDays > 5 { return .weekly }
        return .daily
    }
    
    /// Get the appropriate Calendar.Component for x-axis unit
    private var xAxisUnit: Calendar.Component {
        switch detectedAggregation {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }
    
    /// Calculate bar width ratio
    private var barWidthRatio: Double {
        switch detectedAggregation {
        case .monthly: return 0.8
        case .weekly: return 0.7
        case .daily: return 0.5
        }
    }
    
    /// Find the nearest chart point to a date
    private func findNearestPoint(to date: Date) -> IncomeChartPoint? {
        data.totalLine.min { point1, point2 in
            abs(point1.date.timeIntervalSince(date)) < abs(point2.date.timeIntervalSince(date))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header with toggle controls
            HStack {
                Text("Income")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                HStack(spacing: Theme.Spacing.sm) {
                    // Rolling average toggle
                    if hasRollingAverageData {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRollingAverage.toggle()
                            }
                        } label: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.body)
                                .foregroundStyle(showRollingAverage ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.5))
                        }
                        .help("Rolling average")
                    }
                    
                    // Member breakdown toggle
                    if !data.memberLines.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMemberBreakdown.toggle()
                            }
                        } label: {
                            Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                                .font(.body)
                                .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.5))
                        }
                    }
                }
            }
            
            // Selected point info
            if let point = selectedPoint {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.periodLabel)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.Colors.income)
                                    .frame(width: 8, height: 8)
                                Text(point.dailyAmount.doubleValue.formattedAsMoney())
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.income)
                            }
                        }
                        
                        Spacer()
                        
                        if showRollingAverage, let avg = point.rollingAverage {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Avg:")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text(avg.doubleValue.formattedAsMoney())
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    
                    // Member breakdown for selected period
                    if showMemberBreakdown && !point.memberShares.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(point.memberShares.prefix(4)) { share in
                                HStack(spacing: 4) {
                                    if let emoji = share.memberEmoji, !emoji.isEmpty, !emoji.isPhotoUrl {
                                        Text(emoji)
                                            .font(.caption2)
                                    } else {
                                        Circle()
                                            .fill(share.memberColor)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(share.amount.doubleValue.formattedAsMoney())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(share.memberColor)
                                }
                            }
                            
                            if point.memberShares.count > 4 {
                                Text("+\(point.memberShares.count - 4)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                    
                    // View transactions button
                    Button {
                        showPeriodTransactions = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("View \(point.transactionIds.count) transaction\(point.transactionIds.count == 1 ? "" : "s")")
                                .font(.caption2)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity)
            }
            
            // Chart
            Chart {
                // Stacked bars when member breakdown is enabled
                if showMemberBreakdown {
                    ForEach(data.totalLine) { point in
                        ForEach(point.memberShares) { share in
                            BarMark(
                                x: .value("Date", point.date, unit: xAxisUnit),
                                y: .value("Amount", share.amount.doubleValue),
                                width: .ratio(barWidthRatio)
                            )
                            .foregroundStyle(share.memberColor.opacity(0.8))
                        }
                    }
                } else {
                    // Solid bars
                    ForEach(data.totalLine) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: xAxisUnit),
                            y: .value("Amount", point.dailyAmount.doubleValue),
                            width: .ratio(barWidthRatio)
                        )
                        .foregroundStyle(Theme.Colors.income.opacity(0.7))
                    }
                }
                
                // Average line
                RuleMark(y: .value("Average", averageAmount))
                    .foregroundStyle(Theme.Colors.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                
                // Rolling average line
                if showRollingAverage {
                    ForEach(data.totalLine.filter { $0.rollingAverage != nil }, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: xAxisUnit),
                            y: .value("Rolling", point.rollingAverage!.doubleValue),
                            series: .value("Series", "Rolling")
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                
                // Selection highlight
                if let point = selectedPoint {
                    RuleMark(x: .value("Date", point.date, unit: xAxisUnit))
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
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if let date: Date = proxy.value(atX: value.location.x) {
                                        withAnimation(.easeInOut(duration: 0.1)) {
                                            selectedPoint = findNearestPoint(to: date)
                                        }
                                    }
                                }
                        )
                }
            }
            .frame(height: 180)
            
            // Legend
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Divider()
                    .background(Theme.Colors.borderLight)
                
                HStack(spacing: Theme.Spacing.md) {
                    // Average legend
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.Colors.warning.opacity(0.6))
                            .frame(width: 12, height: 2)
                        Text("Avg: \(averageAmount.formattedAsMoney())")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    if showRollingAverage {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.Colors.accent)
                                .frame(width: 12, height: 2)
                            Text("30d rolling")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                
                // Member legend rows when breakdown is active
                if showMemberBreakdown && !data.memberLines.isEmpty {
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty, !emoji.isPhotoUrl {
                                    Text(emoji)
                                        .font(.system(size: 14))
                                        .frame(width: 16)
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(line.color)
                                        .frame(width: 16, height: 8)
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
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .materialCardStyle()
        .sheet(isPresented: $showPeriodTransactions) {
            if let point = selectedPoint {
                PeriodTransactionsSheet(
                    periodLabel: point.periodLabel,
                    totalAmount: point.dailyAmount,
                    transactionIds: point.transactionIds,
                    allTransactions: allTransactions,
                    transactionType: .income
                )
            }
        }
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
    @State private var chartData: MultiLineNetBalanceData?
    @State private var isLoadingChart = true
    @State private var displayLimit: Int = 50
    
    /// Maximum number of chart data points before downsampling
    private let maxChartPoints = 100
    
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
    
    /// Transactions sorted by date descending for the list
    private var sortedTransactions: [TransactionView] {
        allNetTransactions.sorted { $0.date > $1.date }
    }
    
    /// Compute chart data asynchronously
    /// Compute chart data asynchronously with dynamic aggregation
    private func computeChartData() async -> MultiLineNetBalanceData {
        let expenses = expenseTransactions
        let income = incomeTransactions
        let activeMembersList = activeMembers
        let reimbursements = reimbursementsByExpense
        let splits = allSplits
        let calendar = Calendar.current
        
        guard !expenses.isEmpty || !income.isEmpty else {
            return MultiLineNetBalanceData(totalLine: [], memberLines: [])
        }
        
        // Determine aggregation period based on date range
        let allTransactionDates = (expenses + income).map { $0.date }.sorted()
        guard let firstDate = allTransactionDates.first, let lastDate = allTransactionDates.last else {
            return MultiLineNetBalanceData(totalLine: [], memberLines: [])
        }
        let aggregation = AggregationPeriod.forDateRange(from: firstDate, to: lastDate)
        
        // Helper to get period key for a date
        func periodKey(for date: Date) -> Date {
            switch aggregation {
            case .daily:
                return calendar.startOfDay(for: date)
            case .weekly:
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            case .monthly:
                let components = calendar.dateComponents([.year, .month], from: date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            }
        }
        
        // Helper to format period label
        func periodLabel(for date: Date) -> String {
            let formatter = DateFormatter()
            switch aggregation {
            case .daily:
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            case .weekly:
                formatter.dateFormat = "MMM d"
                return "Week of \(formatter.string(from: date))"
            case .monthly:
                formatter.dateFormat = "MMMM"
                return formatter.string(from: date)
            }
        }
        
        // Track data by period
        var totalIncomeByPeriod: [Date: Decimal] = [:]
        var totalExpenseByPeriod: [Date: Decimal] = [:]
        var memberIncomeByPeriod: [UUID: [Date: Decimal]] = [:]
        var memberExpenseByPeriod: [UUID: [Date: Decimal]] = [:]
        var transactionIdsByPeriod: [Date: [UUID]] = [:]
        
        // Initialize member tracking
        for member in activeMembersList {
            memberIncomeByPeriod[member.id] = [:]
            memberExpenseByPeriod[member.id] = [:]
        }
        
        // Process income transactions
        for incomeItem in income {
            let key = periodKey(for: incomeItem.date)
            totalIncomeByPeriod[key, default: 0] += incomeItem.amount
            transactionIdsByPeriod[key, default: []].append(incomeItem.id)
            
            if let receivedById = incomeItem.paidByMemberId {
                memberIncomeByPeriod[receivedById, default: [:]][key, default: 0] += incomeItem.amount
            } else if !activeMembersList.isEmpty {
                let shareAmount = incomeItem.amount / Decimal(activeMembersList.count)
                for member in activeMembersList {
                    memberIncomeByPeriod[member.id, default: [:]][key, default: 0] += shareAmount
                }
            }
        }
        
        // Process expense transactions
        for expense in expenses {
            let key = periodKey(for: expense.date)
            let reimbursedAmount = reimbursements[expense.id] ?? 0
            let effectiveAmount = max(expense.amount - reimbursedAmount, 0)
            
            guard effectiveAmount > 0 else { continue }
            
            totalExpenseByPeriod[key, default: 0] += effectiveAmount
            transactionIdsByPeriod[key, default: []].append(expense.id)
            
            let reimbursementRatio = expense.amount > 0 ? effectiveAmount / expense.amount : 1
            if let expenseSplits = splits[expense.id], !expenseSplits.isEmpty {
                for split in expenseSplits where split.owedAmount > 0 {
                    let adjustedOwed = split.owedAmount * reimbursementRatio
                    memberExpenseByPeriod[split.memberId, default: [:]][key, default: 0] += adjustedOwed
                }
            } else if let payerId = expense.paidByMemberId {
                memberExpenseByPeriod[payerId, default: [:]][key, default: 0] += effectiveAmount
            } else if !activeMembersList.isEmpty {
                let shareAmount = effectiveAmount / Decimal(activeMembersList.count)
                for member in activeMembersList {
                    memberExpenseByPeriod[member.id, default: [:]][key, default: 0] += shareAmount
                }
            }
        }
        
        // Get all periods and sort them
        var allPeriods = Set(totalIncomeByPeriod.keys).union(Set(totalExpenseByPeriod.keys)).sorted()
        
        // Downsample if too many data points
        if allPeriods.count > maxChartPoints {
            allPeriods = downsampleDates(Array(allPeriods), to: maxChartPoints)
            totalIncomeByPeriod = aggregateByDownsampledDates(totalIncomeByPeriod, sampledDates: allPeriods)
            totalExpenseByPeriod = aggregateByDownsampledDates(totalExpenseByPeriod, sampledDates: allPeriods)
            for memberId in memberIncomeByPeriod.keys {
                memberIncomeByPeriod[memberId] = aggregateByDownsampledDates(memberIncomeByPeriod[memberId] ?? [:], sampledDates: allPeriods)
            }
            for memberId in memberExpenseByPeriod.keys {
                memberExpenseByPeriod[memberId] = aggregateByDownsampledDates(memberExpenseByPeriod[memberId] ?? [:], sampledDates: allPeriods)
            }
        }
        
        // Build rolling average data
        let rollingWindow: Int
        switch aggregation {
        case .daily: rollingWindow = 30
        case .weekly: rollingWindow = 4
        case .monthly: rollingWindow = 3
        }
        var rollingNetAmounts: [Decimal] = []
        
        // Build total line with member shares
        var totalLine: [NetBalanceChartPoint] = []
        var cumulativeIncome: Decimal = 0
        var cumulativeExpense: Decimal = 0
        
        for (index, period) in allPeriods.enumerated() {
            let periodIncome = totalIncomeByPeriod[period] ?? 0
            let periodExpense = totalExpenseByPeriod[period] ?? 0
            cumulativeIncome += periodIncome
            cumulativeExpense += periodExpense
            let cumulativeNet = cumulativeIncome - cumulativeExpense
            let periodNet = periodIncome - periodExpense
            
            // Update rolling window
            rollingNetAmounts.append(periodNet)
            if rollingNetAmounts.count > rollingWindow {
                rollingNetAmounts.removeFirst()
            }
            
            let rollingAvg: Decimal? = index >= rollingWindow - 1
                ? rollingNetAmounts.reduce(0, +) / Decimal(rollingNetAmounts.count)
                : nil
            
            // Build member shares for this period (net per member)
            var shares: [MemberShare] = []
            for member in activeMembersList {
                let memberIncome = memberIncomeByPeriod[member.id]?[period] ?? 0
                let memberExpense = memberExpenseByPeriod[member.id]?[period] ?? 0
                let memberNet = memberIncome - memberExpense
                if memberNet != 0 {
                    shares.append(MemberShare(
                        id: member.id,
                        memberName: member.displayName,
                        memberColor: member.swiftUIColor,
                        memberEmoji: member.avatarUrl,
                        amount: memberNet
                    ))
                }
            }
            // Sort by absolute amount
            shares.sort { abs($0.amount) > abs($1.amount) }
            
            totalLine.append(NetBalanceChartPoint(
                date: period,
                periodLabel: periodLabel(for: period),
                dailyIncome: periodIncome,
                dailyExpense: periodExpense,
                dailyNet: periodNet,
                cumulativeNet: cumulativeNet,
                rollingAverage: rollingAvg,
                memberShares: shares,
                transactionIds: transactionIdsByPeriod[period] ?? []
            ))
        }
        
        // Build member lines (for legend totals)
        var memberLines: [MemberNetBalanceLine] = []
        for member in activeMembersList {
            var points: [NetBalanceChartPoint] = []
            var cumIncome: Decimal = 0
            var cumExpense: Decimal = 0
            let memberIncome = memberIncomeByPeriod[member.id] ?? [:]
            let memberExpense = memberExpenseByPeriod[member.id] ?? [:]
            var memberRollingNetAmounts: [Decimal] = []
            
            for (index, period) in allPeriods.enumerated() {
                let periodIncome = memberIncome[period] ?? 0
                let periodExpense = memberExpense[period] ?? 0
                cumIncome += periodIncome
                cumExpense += periodExpense
                let cumNet = cumIncome - cumExpense
                let periodNet = periodIncome - periodExpense
                
                memberRollingNetAmounts.append(periodNet)
                if memberRollingNetAmounts.count > rollingWindow {
                    memberRollingNetAmounts.removeFirst()
                }
                
                let rollingAvg: Decimal? = index >= rollingWindow - 1
                    ? memberRollingNetAmounts.reduce(0, +) / Decimal(memberRollingNetAmounts.count)
                    : nil
                
                points.append(NetBalanceChartPoint(
                    date: period,
                    periodLabel: periodLabel(for: period),
                    dailyIncome: periodIncome,
                    dailyExpense: periodExpense,
                    dailyNet: periodNet,
                    cumulativeNet: cumNet,
                    rollingAverage: rollingAvg,
                    memberShares: [],
                    transactionIds: []
                ))
            }
            
            let totalNet = cumIncome - cumExpense
            
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
        
        memberLines.sort { abs($0.totalNet) > abs($1.totalNet) }
        
        return MultiLineNetBalanceData(totalLine: totalLine, memberLines: memberLines)
    }
    
    /// Downsample dates to target count using even distribution
    private func downsampleDates(_ dates: [Date], to targetCount: Int) -> [Date] {
        guard dates.count > targetCount else { return dates }
        let step = Double(dates.count) / Double(targetCount)
        var result: [Date] = []
        var index: Double = 0
        while Int(index) < dates.count && result.count < targetCount {
            result.append(dates[Int(index)])
            index += step
        }
        // Always include the last date
        if let lastDate = dates.last, result.last != lastDate {
            result[result.count - 1] = lastDate
        }
        return result
    }
    
    /// Aggregate data by downsampled dates (assign each original date's data to nearest sampled date)
    private func aggregateByDownsampledDates(_ data: [Date: Decimal], sampledDates: [Date]) -> [Date: Decimal] {
        var result: [Date: Decimal] = [:]
        for (date, amount) in data {
            // Find the nearest sampled date
            let nearestDate = sampledDates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) } ?? date
            result[nearestDate, default: 0] += amount
        }
        return result
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
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
                        if isLoadingChart {
                            VStack(spacing: Theme.Spacing.sm) {
                                ProgressView()
                                    .tint(isPositive ? Theme.Colors.success : Theme.Colors.error)
                                Text("Loading chart...")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .materialCardStyle()
                            .padding(.horizontal, Theme.Spacing.md)
                        } else if let data = chartData {
                            if data.totalLine.count >= 2 {
                                MultiLineNetBalanceChart(data: data, allTransactions: filteredTransactions)
                                    .padding(.horizontal, Theme.Spacing.md)
                            } else if data.totalLine.count == 1 {
                                // Single data point
                                VStack(spacing: Theme.Spacing.sm) {
                                    Text("Activity on \(data.totalLine[0].date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text(data.totalLine[0].dailyNet.doubleValue.formattedAsMoney(showSign: true))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(data.totalLine[0].dailyNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                }
                                .frame(maxWidth: .infinity)
                                .materialCardStyle()
                                .padding(.horizontal, Theme.Spacing.md)
                            }
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
                                    let displayedTransactions = Array(sortedTransactions.prefix(displayLimit))
                                    ForEach(displayedTransactions) { transaction in
                                        Button {
                                            selectedTransaction = transaction
                                        } label: {
                                            NetBalanceTransactionRow(
                                                transaction: transaction,
                                                reimbursedAmount: reimbursementsByExpense[transaction.id] ?? 0
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        if transaction.id != displayedTransactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                    
                                    // Load more button
                                    if sortedTransactions.count > displayLimit {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                displayLimit += 50
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("Load \(min(50, sortedTransactions.count - displayLimit)) more (\(sortedTransactions.count - displayLimit) remaining)")
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.md)
                                        }
                                        .buttonStyle(.plain)
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
            .task {
                // Compute chart data asynchronously
                let data = await computeChartData()
                await MainActor.run {
                    chartData = data
                    isLoadingChart = false
                }
            }
        }
    }
}

// MARK: - Net Balance Chart Data Structures

struct NetBalanceChartPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let periodLabel: String            // "Dec 5" or "Week of Dec 1" or "December"
    let dailyIncome: Decimal
    let dailyExpense: Decimal
    let dailyNet: Decimal
    let cumulativeNet: Decimal
    let rollingAverage: Decimal?       // 30-day rolling avg of dailyNet (nil if insufficient data)
    let memberShares: [MemberShare]    // For stacked bar rendering (net per member)
    let transactionIds: [UUID]         // Transaction IDs for this period (for tap sheet)
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
    let allTransactions: [TransactionView]
    
    @State private var showMemberBreakdown = false
    @State private var selectedDate: Date?
    
    /// Final cumulative net balance
    private var finalNetBalance: Decimal {
        data.totalLine.last?.cumulativeNet ?? 0
    }
    
    /// Color based on final balance
    private var netColor: Color {
        finalNetBalance >= 0 ? Theme.Colors.success : Theme.Colors.error
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
            // Header with toggle controls
            HStack {
                Text("Net Saved")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                // Member breakdown toggle
                if !data.memberLines.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMemberBreakdown.toggle()
                        }
                    } label: {
                        Image(systemName: showMemberBreakdown ? "person.2.fill" : "person.2")
                            .font(.body)
                            .foregroundStyle(showMemberBreakdown ? Theme.Colors.accent : Theme.Colors.textMuted.opacity(0.5))
                    }
                }
            }
            
            // Selected point info
            if let selected = selectedValues, let totalPoint = selected.total {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(totalPoint.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(totalPoint.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                    .frame(width: 8, height: 8)
                                Text(totalPoint.cumulativeNet.doubleValue.formattedAsMoney(showSign: true))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(totalPoint.cumulativeNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                            }
                        }
                        
                        Spacer()
                        
                        // Show daily change
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Change:")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                            Text(totalPoint.dailyNet.doubleValue.formattedAsMoney(showSign: true))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(totalPoint.dailyNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                        }
                    }
                    
                    // Member breakdown for selected date
                    if showMemberBreakdown && !selected.members.isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(selected.members.prefix(4), id: \.0.id) { (line, point) in
                                HStack(spacing: 4) {
                                    if let emoji = line.emoji, !emoji.isEmpty, !emoji.isPhotoUrl {
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
            
            // Chart - Cumulative Line Graph
            Chart {
                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.Colors.textMuted.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Area fill under the line
                ForEach(data.totalLine) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Net", point.cumulativeNet.doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [netColor.opacity(0.3), netColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                
                // Main cumulative net line
                ForEach(data.totalLine) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Net", point.cumulativeNet.doubleValue)
                    )
                    .foregroundStyle(netColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                
                // Member lines when toggled
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
            
            // Legend
            if showMemberBreakdown && !data.memberLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Total line legend
                    HStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(netColor)
                                .frame(width: 16, height: 3)
                            
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Text(finalNetBalance.doubleValue.formattedAsMoney(showSign: true))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(netColor)
                    }
                    
                    // Member legend rows
                    ForEach(data.memberLines) { line in
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: 6) {
                                if let emoji = line.emoji, !emoji.isEmpty, !emoji.isPhotoUrl {
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
                                .foregroundStyle(line.totalNet >= 0 ? Theme.Colors.success : Theme.Colors.error)
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .materialCardStyle()
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

// MARK: - Period Transactions Sheet

struct PeriodTransactionsSheet: View {
    let periodLabel: String
    let totalAmount: Decimal
    let transactionIds: [UUID]
    let allTransactions: [TransactionView]
    let transactionType: TransactionType?  // nil for mixed (net balance)
    
    @Environment(\.dismiss) private var dismiss
    
    private var filteredTransactions: [TransactionView] {
        let transactionSet = Set(transactionIds)
        return allTransactions
            .filter { transactionSet.contains($0.id) }
            .sorted { $0.date > $1.date }
    }
    
    private var title: String {
        switch transactionType {
        case .expense:
            return "Expenses"
        case .income:
            return "Income"
        default:
            return "Transactions"
        }
    }
    
    private var amountColor: Color {
        switch transactionType {
        case .expense:
            return Theme.Colors.expense
        case .income:
            return Theme.Colors.income
        default:
            return totalAmount >= 0 ? Theme.Colors.success : Theme.Colors.error
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with period info
                VStack(spacing: Theme.Spacing.sm) {
                    Text(periodLabel)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(totalAmount.doubleValue.formattedAsMoney(showSign: transactionType == nil))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(amountColor)
                    
                    Text("\(filteredTransactions.count) transaction\(filteredTransactions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(.vertical, Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.backgroundCard)
                
                Divider()
                    .background(Theme.Colors.borderLight)
                
                // Transaction list
                if filteredTransactions.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.Colors.textMuted)
                        Text("No transactions found")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTransactions) { transaction in
                                PeriodTransactionRow(transaction: transaction)
                                
                                if transaction.id != filteredTransactions.last?.id {
                                    Divider()
                                        .background(Theme.Colors.borderLight)
                                        .padding(.leading, Theme.Spacing.xl)
                                }
                            }
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                }
            }
            .background(Theme.Colors.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Period Transaction Row

struct PeriodTransactionRow: View {
    let transaction: TransactionView
    
    private var isExpense: Bool {
        transaction.transactionType == .expense
    }
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        return Theme.Colors.textMuted
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Category indicator
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
            
            // Transaction details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    if let categoryName = transaction.categoryName {
                        Text(categoryName)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Spacer()
            
            // Amount
            Text(isExpense ? "-\(transaction.amount.doubleValue.formattedAsMoney())" : "+\(transaction.amount.doubleValue.formattedAsMoney())")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isExpense ? Theme.Colors.expense : Theme.Colors.income)
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
