import SwiftUI
import Auth

@main
struct QuackApp: App {
    @State private var authViewModel = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        Task {
            do {
                // Handle the auth callback from email confirmation
                try await SupabaseService.shared.auth.session(from: url)
                // Refresh auth state after successful callback
                await authViewModel.checkAuthState()
            } catch {
                print("Deep link auth error: \(error.localizedDescription)")
            }
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
            } else if let email = authViewModel.awaitingConfirmationEmail {
                AwaitingConfirmationView(email: email)
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .animation(.easeInOut, value: authViewModel.currentHousehold != nil)
        .animation(.easeInOut, value: authViewModel.awaitingConfirmationEmail)
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

