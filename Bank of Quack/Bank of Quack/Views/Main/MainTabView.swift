import SwiftUI

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
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
        .tint(themeProvider.accent)
        .onAppear {
            updateTabBarAppearance()
        }
        .onChange(of: themeProvider.currentPalette.id) { _, _ in
            updateTabBarAppearance()
        }
        .task {
            if let householdId = authViewModel.currentHousehold?.id {
                await transactionViewModel.fetchTransactions(householdId: householdId)
            }
        }
        // Force tab bar to rebuild when theme changes
        .id(themeProvider.currentPalette.id)
    }
    
    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(themeProvider.backgroundPrimary)
        
        // Configure item colors based on theme
        let normalColor = UIColor(themeProvider.textSecondary)
        let selectedColor = UIColor(themeProvider.accent)
        
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
}
