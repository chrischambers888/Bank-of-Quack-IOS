import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    @State private var showSwitchHousehold = false
    @State private var showCategories = false
    @State private var showSectors = false
    @State private var showSignOutConfirm = false
    @State private var showInviteCodeWarning = false
    @State private var showInviteCode = false
    @State private var showDeleteHouseholdConfirm = false
    @State private var deleteConfirmationText = ""
    
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
                                    subtitle: nil
                                )
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                HStack(spacing: 0) {
                                    Button {
                                        if showInviteCode {
                                            // Hide the code
                                            showInviteCode = false
                                        } else {
                                            showInviteCodeWarning = true
                                        }
                                    } label: {
                                        HStack(spacing: Theme.Spacing.md) {
                                            Image(systemName: showInviteCode ? "eye.fill" : "eye.slash.fill")
                                                .font(.body)
                                                .foregroundStyle(Theme.Colors.accent)
                                                .frame(width: 24)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Invite Code")
                                                    .font(.body)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                
                                                if showInviteCode {
                                                    Text(authViewModel.currentHousehold?.inviteCode ?? "---")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundStyle(Theme.Colors.accent)
                                                } else {
                                                    Text("Tap to reveal")
                                                        .font(.caption)
                                                        .foregroundStyle(Theme.Colors.textSecondary)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(Theme.Spacing.md)
                                        .contentShape(Rectangle())
                                    }
                                    
                                    if showInviteCode {
                                        Button {
                                            if let code = authViewModel.currentHousehold?.inviteCode {
                                                UIPasteboard.general.string = code
                                            }
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.body)
                                                .foregroundStyle(Theme.Colors.accent)
                                                .frame(width: 44, height: 44)
                                        }
                                        .padding(.trailing, Theme.Spacing.sm)
                                    }
                                }
                                
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
                                
                                // Delete Household (owner only)
                                if authViewModel.currentMember?.role == .owner {
                                    Divider()
                                        .background(Theme.Colors.borderLight)
                                    
                                    Button {
                                        showDeleteHouseholdConfirm = true
                                    } label: {
                                        SettingsRow(
                                            icon: "trash.fill",
                                            title: "Delete Household",
                                            subtitle: "Permanently delete all data",
                                            iconColor: Theme.Colors.error
                                        )
                                    }
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
                        
                        // Pending Requests Section (only for admins/owners)
                        if authViewModel.currentMember?.role.canApproveMembers == true,
                           !authViewModel.pendingMembers.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack {
                                    Text("PENDING REQUESTS (\(authViewModel.pendingMembers.count))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.warning)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(authViewModel.pendingMembers) { member in
                                        PendingMemberRow(member: member)
                                        
                                        if member.id != authViewModel.pendingMembers.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Categories & Sectors Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("ORGANIZATION")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            VStack(spacing: 0) {
                                Button {
                                    showCategories = true
                                } label: {
                                    SettingsRow(
                                        icon: "folder.fill",
                                        title: "Categories",
                                        subtitle: "\(authViewModel.categories.count) categories",
                                        showChevron: true
                                    )
                                }
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                Button {
                                    showSectors = true
                                } label: {
                                    SettingsRow(
                                        icon: "rectangle.3.group.fill",
                                        title: "Sectors",
                                        subtitle: "\(authViewModel.sectors.count) sectors",
                                        showChevron: true
                                    )
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
            .onDisappear {
                showInviteCode = false
            }
        }
        .sheet(isPresented: $showSwitchHousehold) {
            SwitchHouseholdView()
        }
        .sheet(isPresented: $showCategories) {
            CategoriesView()
        }
        .sheet(isPresented: $showSectors) {
            SectorsView()
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
        .alert("Reveal Invite Code?", isPresented: $showInviteCodeWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Show Code") {
                showInviteCode = true
            }
        } message: {
            Text("Anyone with this code can join your household and see all transaction history, including amounts and who made each purchase. Only share with people you trust.")
        }
        .sheet(isPresented: $showDeleteHouseholdConfirm) {
            DeleteHouseholdConfirmView(
                householdName: authViewModel.currentHousehold?.name ?? "",
                onConfirm: {
                    Task {
                        if let household = authViewModel.currentHousehold {
                            let success = await authViewModel.deleteHousehold(household)
                            if success {
                                showDeleteHouseholdConfirm = false
                            }
                        }
                    }
                }
            )
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

struct PendingMemberRow: View {
    @Environment(AuthViewModel.self) private var authViewModel
    let member: HouseholdMember
    
    @State private var showApproveConfirm = false
    @State private var showRejectConfirm = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(member.swiftUIColor.opacity(0.5))
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
                
                Text("Wants to join")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            
            Spacer()
            
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    showRejectConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.error)
                }
                
                Button {
                    showApproveConfirm = true
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.success)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .alert("Approve Member?", isPresented: $showApproveConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Approve") {
                Task {
                    await authViewModel.approveMember(member)
                }
            }
        } message: {
            Text("\(member.displayName) will be able to see all household transaction history and add their own transactions.")
        }
        .alert("Decline Request?", isPresented: $showRejectConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Decline", role: .destructive) {
                Task {
                    await authViewModel.rejectMember(member)
                }
            }
        } message: {
            Text("\(member.displayName) will not be added to the household. They can request again with a new invite code.")
        }
    }
}

struct SwitchHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var showInviteCodeWarning = false
    @State private var revealedHouseholdId: UUID? = nil
    @State private var pendingRevealHouseholdId: UUID? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.lg) {
                    // Household List
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            // Pending Requests (awaiting approval)
                            if !authViewModel.pendingHouseholds.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text("AWAITING APPROVAL")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.warning)
                                        .padding(.horizontal, Theme.Spacing.xs)
                                    
                                    ForEach(authViewModel.pendingHouseholds) { pending in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(pending.householdName)
                                                    .font(.headline)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                
                                                Text("Waiting for approval...")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.Colors.warning)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "clock.fill")
                                                .foregroundStyle(Theme.Colors.warning)
                                        }
                                        .padding(Theme.Spacing.md)
                                        .background(Theme.Colors.backgroundCard.opacity(0.7))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                                .stroke(Theme.Colors.warning.opacity(0.3), lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                    }
                                }
                            }
                            
                            // Active Households
                            ForEach(authViewModel.households) { household in
                                HStack {
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
                                                
                                                if revealedHouseholdId == household.id {
                                                    Text("Code: \(household.inviteCode)")
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundStyle(Theme.Colors.accent)
                                                } else {
                                                    Text("Code hidden")
                                                        .font(.caption)
                                                        .foregroundStyle(Theme.Colors.textMuted)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if household.id == authViewModel.currentHousehold?.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Theme.Colors.success)
                                            }
                                        }
                                    }
                                    
                                    Button {
                                        if revealedHouseholdId == household.id {
                                            // Hide the code
                                            revealedHouseholdId = nil
                                        } else {
                                            pendingRevealHouseholdId = household.id
                                            showInviteCodeWarning = true
                                        }
                                    } label: {
                                        Image(systemName: revealedHouseholdId == household.id ? "eye.fill" : "eye.slash")
                                            .font(.body)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(width: 32, height: 32)
                                    }
                                    
                                    if revealedHouseholdId == household.id {
                                        Button {
                                            UIPasteboard.general.string = household.inviteCode
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.body)
                                                .foregroundStyle(Theme.Colors.accent)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
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
            .onDisappear {
                revealedHouseholdId = nil
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdView()
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinHouseholdView()
        }
        .alert("Reveal Invite Code?", isPresented: $showInviteCodeWarning) {
            Button("Cancel", role: .cancel) {
                pendingRevealHouseholdId = nil
            }
            Button("Show Code") {
                revealedHouseholdId = pendingRevealHouseholdId
                pendingRevealHouseholdId = nil
            }
        } message: {
            Text("Anyone with this code can join your household and see all transaction history, including amounts and who made each purchase. Only share with people you trust.")
        }
    }
}

struct DeleteHouseholdConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    
    let householdName: String
    let onConfirm: () -> Void
    
    @State private var confirmationText = ""
    @State private var isDeleting = false
    
    private var canDelete: Bool {
        confirmationText.lowercased() == householdName.lowercased()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Warning Icon
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Theme.Colors.error)
                            .padding(.top, Theme.Spacing.xl)
                        
                        // Title
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Delete Household?")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("This action cannot be undone")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.error)
                        }
                        
                        // Warning Details
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("This will permanently delete:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Label("All transactions", systemImage: "creditcard.fill")
                                Label("All categories & sectors", systemImage: "folder.fill")
                                Label("All budgets", systemImage: "chart.pie.fill")
                                Label("All member data", systemImage: "person.2.fill")
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Confirmation Input
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Type \"\(householdName)\" to confirm:")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            TextField("Household name", text: $confirmationText)
                                .inputFieldStyle()
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Buttons
                        VStack(spacing: Theme.Spacing.sm) {
                            Button {
                                isDeleting = true
                                onConfirm()
                            } label: {
                                if isDeleting {
                                    ProgressView()
                                        .tint(Theme.Colors.textInverse)
                                } else {
                                    Text("Delete Forever")
                                }
                            }
                            .buttonStyle(DestructiveButtonStyle())
                            .disabled(!canDelete || isDeleting)
                            
                            Button {
                                dismiss()
                            } label: {
                                Text("Cancel")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.Colors.textInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isEnabled ? Theme.Colors.error : Theme.Colors.error.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
}

