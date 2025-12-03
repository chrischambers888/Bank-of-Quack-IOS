import SwiftUI

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var memberBalances: [MemberBalance] = []
    @State private var allSplits: [UUID: [TransactionSplit]] = [:] // Keyed by transaction ID
    @State private var isLoadingBalances = false
    @State private var showBalanceDetails = false
    @State private var showFilterSheet = false
    
    // Filter state
    @State private var filterManager = DashboardFilterManager()
    
    // Sector breakdown data
    @State private var sectors: [Sector] = []
    @State private var categories: [Category] = []
    @State private var sectorCategories: [UUID: [UUID]] = [:] // sectorId -> [categoryId]
    
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
        
        // Process filtered transactions
        for transaction in filteredTransactions {
            switch transaction.transactionType {
            case .expense:
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
                        recipientData.owed -= transaction.amount // Reduces what they're owed
                        balancesByMember[recipientId] = recipientData
                    }
                }
                
            case .reimbursement:
                // Linked reimbursements affect balances inversely
                if let linkedExpenseId = transaction.reimbursesTransactionId,
                   let linkedSplits = allSplits[linkedExpenseId],
                   let recipientId = transaction.paidByMemberId {
                    let reimbursementAmount = transaction.amount
                    
                    for split in linkedSplits {
                        guard let owedPct = split.owedPercentage else { continue }
                        let owedPercentage = owedPct / 100
                        let owedReduction = reimbursementAmount * owedPercentage
                        
                        if var memberData = balancesByMember[split.memberId] {
                            if split.memberId == recipientId {
                                // Recipient: paid goes down, owed goes down
                                memberData.paid -= reimbursementAmount
                                memberData.owed -= owedReduction
                            } else {
                                // Others: only owed goes down
                                memberData.owed -= owedReduction
                            }
                            balancesByMember[split.memberId] = memberData
                        }
                    }
                }
                
            case .income:
                // Income doesn't affect member balances
                break
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
    
    /// Count of members with non-zero balances (for display in balance card)
    private var membersWithNonZeroBalance: Int {
        filteredMemberBalances.filter { abs($0.balance.doubleValue) >= 0.01 }.count
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
    
    /// Filtered totals for expenses
    private var filteredTotalExpenses: Decimal {
        // Build reimbursement map for filtered transactions
        var reimbursementsByExpense: [UUID: Decimal] = [:]
        for transaction in filteredTransactions {
            if transaction.transactionType == .reimbursement,
               let linkedExpenseId = transaction.reimbursesTransactionId {
                reimbursementsByExpense[linkedExpenseId, default: 0] += transaction.amount
            }
        }
        
        var total: Decimal = 0
        for transaction in filteredTransactions where transaction.transactionType == .expense {
            let reimbursedAmount = reimbursementsByExpense[transaction.id] ?? 0
            total += max(transaction.amount - reimbursedAmount, 0)
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
        
        // Group expenses by categoryId
        var expensesByCategory: [UUID: Decimal] = [:]
        var uncategorizedAmount: Decimal = 0
        
        // Track expenses by member per category using "expense for" (owed amounts from splits)
        var expensesByCategoryAndMember: [UUID: [UUID: Decimal]] = [:] // categoryId -> (memberId -> amount)
        var uncategorizedByMember: [UUID: Decimal] = [:]
        
        for expense in expenses {
            if let categoryId = expense.categoryId {
                expensesByCategory[categoryId, default: 0] += expense.amount
                
                // Use splits to determine who the expense is FOR (owedAmount)
                if let splits = allSplits[expense.id] {
                    for split in splits where split.owedAmount > 0 {
                        expensesByCategoryAndMember[categoryId, default: [:]][split.memberId, default: 0] += split.owedAmount
                    }
                }
            } else {
                uncategorizedAmount += expense.amount
                
                // Use splits for uncategorized expenses too
                if let splits = allSplits[expense.id] {
                    for split in splits where split.owedAmount > 0 {
                        uncategorizedByMember[split.memberId, default: 0] += split.owedAmount
                    }
                }
            }
        }
        
        // Build category lookup
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        
        // Calculate total expenses for percentage calculation
        let totalExpense = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        guard totalExpense > 0 else { return [] }
        
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
                percentage: (sectorTotal.doubleValue / totalExpense.doubleValue) * 100,
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
                percentage: (otherTotal.doubleValue / totalExpense.doubleValue) * 100,
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
    
    /// Returns filtered transactions that impact member balances (expenses where paid != owed, settlements, and linked reimbursements)
    private var balanceImpactingTransactions: [TransactionView] {
        filteredTransactions.filter { transaction in
            // Settlements always impact balances - they transfer money between members
            if transaction.transactionType == .settlement {
                return true
            }
            
            // Linked reimbursements impact balances (they inversely affect the original expense's balance impact)
            if transaction.transactionType == .reimbursement {
                // Only linked reimbursements affect balances
                return transaction.reimbursesTransactionId != nil
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
                        // Header
                        headerSection
                            .padding(.horizontal, Theme.Spacing.md)
                        
                        // Balance Cards (using filtered totals)
                        HStack(spacing: Theme.Spacing.md) {
                            BalanceCard(
                                title: "Total Expenses",
                                amount: filteredTotalExpenses,
                                icon: "arrow.down.circle.fill",
                                color: Theme.Colors.expense
                            )
                            
                            BalanceCard(
                                title: "Total Income",
                                amount: filteredTotalIncome,
                                icon: "arrow.up.circle.fill",
                                color: Theme.Colors.income
                            )
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Net Balance (using filtered totals)
                        NetBalanceCard(
                            income: filteredTotalIncome,
                            expenses: filteredTotalExpenses
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Member Balance (only show if multiple members have balance history)
                        if authViewModel.members.count > 1 {
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
                                    sectorCategories: sectorCategories
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
                    Text(authViewModel.currentHousehold?.name ?? "Your Household")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    if filterManager.filter.isFiltered {
                        Text(filterManager.filter.summary)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.accent)
                            .lineLimit(2)
                    } else {
                        Text(filterManager.filter.dateDescription)
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
        
        // Fetch transactions
        await transactionViewModel.fetchTransactions(householdId: householdId)
        
        // Fetch member balances, splits, and sector data from database
        do {
            async let balancesTask = dataService.fetchMemberBalances(householdId: householdId)
            async let splitsTask = dataService.fetchAllSplitsForHousehold(householdId: householdId)
            async let sectorsTask = dataService.fetchSectors(householdId: householdId)
            async let categoriesTask = dataService.fetchCategories(householdId: householdId)
            
            let (balances, splits, fetchedSectors, fetchedCategories) = try await (
                balancesTask, splitsTask, sectorsTask, categoriesTask
            )
            memberBalances = balances
            sectors = fetchedSectors
            categories = fetchedCategories
            
            // Group splits by transaction ID
            allSplits = Dictionary(grouping: splits, by: { $0.transactionId })
            
            // Fetch sector-category mappings for each sector
            var mappings: [UUID: [UUID]] = [:]
            for sector in fetchedSectors {
                let sectorCats = try await dataService.fetchSectorCategories(sectorId: sector.id)
                mappings[sector.id] = sectorCats.map { $0.categoryId }
            }
            sectorCategories = mappings
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
            
            Text("Between \(memberCount) household members")
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
                        // Household Balances Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Label("Household Balances", systemImage: "person.2.fill")
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
    /// - Recipient: paid decreases by full amount, owed decreases by their percentage
    /// - Others: only owed decreases by their percentage
    private var reimbursementBalanceImpacts: [(name: String, net: Decimal)] {
        guard let linkedExpenseId = transaction.reimbursesTransactionId,
              let linkedSplits = allSplits[linkedExpenseId],
              let recipientId = transaction.paidByMemberId else {
            return []
        }
        
        let reimbursementAmount = transaction.amount
        
        return linkedSplits.compactMap { split -> (String, Decimal)? in
            guard let owedPct = split.owedPercentage else { return nil }
            let owedPercentage = owedPct / 100
            let owedReduction = reimbursementAmount * owedPercentage
            
            let balanceChange: Decimal
            if split.memberId == recipientId {
                // Recipient: paid goes down by full amount, owed goes down by their percentage
                // balance change = -reimbursement + owedReduction
                balanceChange = -reimbursementAmount + owedReduction
            } else {
                // Others: only owed goes down by their percentage
                // balance change = 0 - (-owedReduction) = +owedReduction
                balanceChange = owedReduction
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

#Preview {
    DashboardView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
