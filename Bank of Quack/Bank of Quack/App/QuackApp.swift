import SwiftUI

@main
struct QuackApp: App {
    @State private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        Group {
            if authViewModel.isLoading {
                LoadingView()
            } else if authViewModel.isAuthenticated {
                if authViewModel.currentHousehold != nil {
                    MainTabView()
                } else {
                    HouseholdSetupView()
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .animation(.easeInOut, value: authViewModel.currentHousehold != nil)
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Theme.Colors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.accent)
                
                ProgressView()
                    .tint(Theme.Colors.accent)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthViewModel())
}

