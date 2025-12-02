import SwiftUI

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    
    @State private var memberBalances: [MemberBalance] = []
    @State private var allSplits: [UUID: [TransactionSplit]] = [:] // Keyed by transaction ID
    @State private var isLoadingBalances = false
    @State private var showBalanceDetails = false
    
    private let dataService = DataService()
    
    private var currentMemberBalance: Decimal {
        guard let memberId = authViewModel.currentMember?.id else { return 0 }
        return memberBalances.first { $0.memberId == memberId }?.balance ?? 0
    }
    
    /// Returns transactions that impact member balances (expenses where paid != owed, settlements, and linked reimbursements)
    private var balanceImpactingTransactions: [TransactionView] {
        transactionViewModel.transactions.filter { transaction in
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
                return authViewModel.members.filter { $0.isApproved }.count > 1
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
                // Background gradient
                LinearGradient(
                    colors: [Theme.Colors.primary900, Theme.Colors.primary700],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        // Header
                        headerSection
                            .padding(.horizontal, Theme.Spacing.md)
                        
                        // Balance Cards
                        HStack(spacing: Theme.Spacing.md) {
                            BalanceCard(
                                title: "Total Expenses",
                                amount: transactionViewModel.totalExpenses,
                                icon: "arrow.down.circle.fill",
                                color: Theme.Colors.expense
                            )
                            
                            BalanceCard(
                                title: "Total Income",
                                amount: transactionViewModel.totalIncome,
                                icon: "arrow.up.circle.fill",
                                color: Theme.Colors.income
                            )
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Net Balance
                        NetBalanceCard(
                            income: transactionViewModel.totalIncome,
                            expenses: transactionViewModel.totalExpenses
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Member Balance (only show if multiple members)
                        if authViewModel.members.filter({ $0.isApproved }).count > 1 {
                            MemberBalanceCardWithInfo(
                                balance: currentMemberBalance,
                                memberCount: authViewModel.members.filter { $0.isApproved }.count,
                                onInfoTapped: { showBalanceDetails = true }
                            )
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Recent Transactions
                        RecentTransactionsCard(
                            transactions: transactionViewModel.recentTransactions(limit: 5)
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                        
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
                    memberBalances: memberBalances,
                    transactions: balanceImpactingTransactions,
                    transactionSplits: allSplits,
                    members: authViewModel.members,
                    currentMemberId: authViewModel.currentMember?.id
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
                Text("Hello, \(authViewModel.currentMember?.displayName ?? "there")! 👋")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(authViewModel.currentHousehold?.name ?? "Your Household")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Avatar
            ZStack {
                Circle()
                    .fill(authViewModel.currentMember?.swiftUIColor ?? Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Theme.Colors.accent, lineWidth: 2)
                    )
                
                Text(authViewModel.currentMember?.initials ?? "?")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textInverse)
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }
    
    private func refreshData() async {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        // Fetch transactions
        await transactionViewModel.fetchTransactions(householdId: householdId)
        
        // Fetch member balances and all splits from database
        do {
            async let balancesTask = dataService.fetchMemberBalances(householdId: householdId)
            async let splitsTask = dataService.fetchAllSplitsForHousehold(householdId: householdId)
            
            let (balances, splits) = try await (balancesTask, splitsTask)
            memberBalances = balances
            
            // Group splits by transaction ID
            allSplits = Dictionary(grouping: splits, by: { $0.transactionId })
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
                            
                            if memberBalances.isEmpty {
                                Text("No balance data available")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.vertical, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(memberBalances, id: \.memberId) { balance in
                                        MemberBalanceRow(
                                            balance: balance,
                                            isCurrentMember: balance.memberId == currentMemberId
                                        )
                                        
                                        if balance.memberId != memberBalances.last?.memberId {
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
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                if isCurrentMember {
                    Text("(You)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
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
            
            // Settlement details - show who paid whom
            if isSettlement {
                if let paidByName = transaction.paidByName, let paidToName = transaction.paidToName {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(paidByName)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                        Text(paidToName)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                        
                        // Show impact on each party
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("\(paidByName) +\(transaction.amount.doubleValue.formattedAsMoney())")
                                .foregroundStyle(Theme.Colors.success)
                            Text("\(paidToName) -\(transaction.amount.doubleValue.formattedAsMoney())")
                                .foregroundStyle(Theme.Colors.error)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 2)
                }
            }
            // Reimbursement details - show balance impact for each member
            else if isReimbursement {
                if !reimbursementBalanceImpacts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if let receivedByName = transaction.paidByName {
                            Text("Received by \(receivedByName)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        HStack(spacing: Theme.Spacing.md) {
                            ForEach(reimbursementBalanceImpacts, id: \.name) { impact in
                                HStack(spacing: 2) {
                                    Text(impact.name)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    Text(impact.net > 0 ? "+\(impact.net.doubleValue.formattedAsMoney())" : "\(impact.net.doubleValue.formattedAsMoney())")
                                        .fontWeight(.medium)
                                        .foregroundStyle(impact.net > 0 ? Theme.Colors.success : Theme.Colors.error)
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 2)
                } else if let receivedByName = transaction.paidByName {
                    // Fallback if we don't have linked expense splits
                    Text("Received by \(receivedByName)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .padding(.top, 2)
                }
            }
            // Balance impact details for expenses - who owes/is owed what
            else if !balanceImpacts.isEmpty {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(balanceImpacts, id: \.name) { impact in
                        HStack(spacing: 2) {
                            Text(impact.name)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(impact.net > 0 ? "+\(impact.net.doubleValue.formattedAsMoney())" : "-\(abs(impact.net).doubleValue.formattedAsMoney())")
                                .fontWeight(.medium)
                                .foregroundStyle(impact.net > 0 ? Theme.Colors.success : Theme.Colors.error)
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 2)
            } else if splits.isEmpty {
                // Fallback for when we don't have split data
                if let paidByName = transaction.paidByName {
                    Text("Paid by \(paidByName)")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

#Preview {
    DashboardView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
