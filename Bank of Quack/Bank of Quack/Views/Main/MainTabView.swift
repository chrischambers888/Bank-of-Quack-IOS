import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var selectedTab = 0
    @State private var transactionViewModel = TransactionViewModel()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .environment(transactionViewModel)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            TransactionsListView()
                .environment(transactionViewModel)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet")
                }
                .tag(1)
            
            AddTransactionView()
                .environment(transactionViewModel)
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Theme.Colors.accent)
        .onAppear {
            // Configure tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Theme.Colors.primary900)
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .task {
            if let householdId = authViewModel.currentHousehold?.id {
                await transactionViewModel.fetchTransactions(householdId: householdId)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
}

