import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    @State private var showSwitchHousehold = false
    @State private var showSignOutConfirm = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Profile Section
                        VStack(spacing: Theme.Spacing.md) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(authViewModel.currentMember?.swiftUIColor ?? Theme.Colors.accent)
                                    .frame(width: 80, height: 80)
                                
                                Text(authViewModel.currentMember?.initials ?? "?")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.textInverse)
                            }
                            
                            Text(authViewModel.currentMember?.displayName ?? "User")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text(authViewModel.currentMember?.role.displayName ?? "Member")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(Capsule())
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Household Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("HOUSEHOLD")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            VStack(spacing: 0) {
                                SettingsRow(
                                    icon: "house.fill",
                                    title: authViewModel.currentHousehold?.name ?? "Household",
                                    subtitle: "Invite code: \(authViewModel.currentHousehold?.inviteCode ?? "---")"
                                )
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                Button {
                                    showSwitchHousehold = true
                                } label: {
                                    SettingsRow(
                                        icon: "arrow.left.arrow.right",
                                        title: "Switch Household",
                                        showChevron: true
                                    )
                                }
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Members Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("MEMBERS (\(authViewModel.members.count))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            VStack(spacing: 0) {
                                ForEach(authViewModel.members) { member in
                                    MemberRow(member: member)
                                    
                                    if member.id != authViewModel.members.last?.id {
                                        Divider()
                                            .background(Theme.Colors.borderLight)
                                    }
                                }
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Account Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("ACCOUNT")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            VStack(spacing: 0) {
                                Button {
                                    showSignOutConfirm = true
                                } label: {
                                    SettingsRow(
                                        icon: "rectangle.portrait.and.arrow.right",
                                        title: "Sign Out",
                                        iconColor: Theme.Colors.error
                                    )
                                }
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Version
                        Text("Bank of Quack v1.0.0")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .padding(.top, Theme.Spacing.lg)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showSwitchHousehold) {
            SwitchHouseholdView()
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    await authViewModel.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var showChevron: Bool = false
    var iconColor: Color = Theme.Colors.accent
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}

struct MemberRow: View {
    let member: HouseholdMember
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(member.swiftUIColor)
                    .frame(width: 36, height: 36)
                
                Text(member.initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textInverse)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(member.role.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(Theme.Spacing.md)
    }
}

struct SwitchHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.lg) {
                    // Household List
                    ScrollView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(authViewModel.households) { household in
                                Button {
                                    Task {
                                        await authViewModel.selectHousehold(household)
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(household.name)
                                                .font(.headline)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            
                                            Text("Code: \(household.inviteCode)")
                                                .font(.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if household.id == authViewModel.currentHousehold?.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.Colors.success)
                                        }
                                    }
                                    .padding(Theme.Spacing.md)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    
                    // Actions
                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("Create New Household", systemImage: "plus.circle")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        
                        Button {
                            showJoinSheet = true
                        } label: {
                            Label("Join Another Household", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Switch Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
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
    SettingsView()
        .environment(AuthViewModel())
}

