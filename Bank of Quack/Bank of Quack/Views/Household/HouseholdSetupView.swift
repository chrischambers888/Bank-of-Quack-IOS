import SwiftUI

struct HouseholdSetupView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Theme.Colors.primary900, Theme.Colors.primary700],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                
                // Icon
                Image(systemName: "house.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.Colors.accent)
                
                // Title
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Welcome!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("Create or join a household to get started")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Actions
                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Create Household", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("Join with Invite Code", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    
                    Button {
                        Task {
                            await authViewModel.signOut()
                        }
                    } label: {
                        Text("Sign Out")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdView()
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinHouseholdView()
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environment(AuthViewModel())
}

