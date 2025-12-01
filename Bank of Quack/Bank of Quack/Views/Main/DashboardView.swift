import SwiftUI

struct DashboardView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    
    @State private var memberBalance: Decimal = 0
    
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
                        if authViewModel.members.count > 1 {
                            MemberBalanceCard(
                                balance: memberBalance,
                                memberCount: authViewModel.members.count
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
        
        await transactionViewModel.fetchTransactions(householdId: householdId)
        
        // Calculate member balance
        if let memberId = authViewModel.currentMember?.id {
            memberBalance = calculateMemberBalance(memberId: memberId)
        }
    }
    
    private func calculateMemberBalance(memberId: UUID) -> Decimal {
        let memberCount = authViewModel.members.count
        guard memberCount > 0 else { return 0 }
        
        var totalPaid: Decimal = 0
        var totalShare: Decimal = 0
        
        for transaction in transactionViewModel.transactions {
            guard transaction.transactionType == .expense else { continue }
            
            // What this member paid
            if transaction.paidByMemberId == memberId {
                totalPaid += transaction.amount
            }
            
            // What this member owes (their share)
            switch transaction.splitType {
            case .equal:
                totalShare += transaction.amount / Decimal(memberCount)
            case .payerOnly:
                if transaction.paidByMemberId == memberId {
                    totalShare += transaction.amount
                }
            case .custom:
                // Would need to fetch splits - for now assume equal
                totalShare += transaction.amount / Decimal(memberCount)
            }
        }
        
        return totalPaid - totalShare
    }
}

#Preview {
    DashboardView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}

