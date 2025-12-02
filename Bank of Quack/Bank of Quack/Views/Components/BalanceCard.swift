import SwiftUI

struct BalanceCard: View {
    let title: String
    let amount: Decimal
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Text(amount.doubleValue.formattedAsMoney())
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct NetBalanceCard: View {
    let income: Decimal
    let expenses: Decimal
    
    private var net: Decimal {
        income - expenses
    }
    
    private var isPositive: Bool {
        net >= 0
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("Net Balance")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            Text(net.doubleValue.formattedAsMoney(showSign: true))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

struct MemberBalanceCard: View {
    let balance: Decimal
    let memberCount: Int
    
    private var isPositive: Bool {
        balance >= 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Your Balance")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            HStack(spacing: 4) {
                Text(isPositive ? "You are owed" : "You owe")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Text(abs(balance.doubleValue).formattedAsMoney())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(isPositive ? Theme.Colors.success : Theme.Colors.error)
            }
            
            Text(isPositive ? "Others owe you money" : "You need to settle up")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        HStack(spacing: Theme.Spacing.md) {
            BalanceCard(
                title: "Total Expenses",
                amount: 1250.50,
                icon: "arrow.down.circle.fill",
                color: Theme.Colors.expense
            )
            
            BalanceCard(
                title: "Total Income",
                amount: 3500.00,
                icon: "arrow.up.circle.fill",
                color: Theme.Colors.income
            )
        }
        
        NetBalanceCard(income: 3500, expenses: 1250.50)
        
        MemberBalanceCard(balance: 125.75, memberCount: 2)
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}

