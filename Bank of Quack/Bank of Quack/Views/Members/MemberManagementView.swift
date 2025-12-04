import SwiftUI
import Auth

struct MemberManagementView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddManagedMember = false
    @State private var selectedManagedMember: HouseholdMember?
    @State private var selectedRegularMember: HouseholdMember?
    @State private var selectedInactiveMember: HouseholdMember?
    @State private var showTransferOwnership = false
    @State private var showRevokeTransferConfirm = false
    @State private var showAcceptTransferConfirm = false
    @State private var showDeclineTransferConfirm = false
    
    private var isOwner: Bool {
        authViewModel.isOwner
    }
    
    private var regularMembers: [HouseholdMember] {
        authViewModel.members.filter { !$0.isManaged && !$0.isInactive }
    }
    
    private var managedMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isManaged && !$0.isInactive }
    }
    
    private var inactiveMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isInactive }
    }
    
    /// Members eligible for ownership transfer (active, non-managed, not owner)
    private var eligibleForOwnership: [HouseholdMember] {
        authViewModel.members.filter { member in
            !member.isManaged && 
            !member.isInactive && 
            member.role != .owner &&
            member.userId != nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Pending Ownership Transfer Card (for target member)
                        if authViewModel.isCurrentUserPendingOwner {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Theme.Colors.warning)
                                    Text("Ownership Transfer")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                                
                                Text("You have been offered ownership of this household. As owner, you'll have full control over members, settings, and can delete the household.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                HStack(spacing: Theme.Spacing.md) {
                                    Button {
                                        showDeclineTransferConfirm = true
                                    } label: {
                                        Text("Decline")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.sm)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(Theme.Colors.textSecondary)
                                    
                                    Button {
                                        showAcceptTransferConfirm = true
                                    } label: {
                                        Text("Accept Ownership")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Theme.Spacing.sm)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.Colors.warning)
                                }
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.warning.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                                    .stroke(Theme.Colors.warning.opacity(0.5), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Regular Members Section
                        if !regularMembers.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("MEMBERS WITH ACCOUNTS")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(regularMembers) { member in
                                        // Users with management permissions can tap non-owner members
                                        if (isOwner || authViewModel.canRemoveMembers) && member.role != .owner {
                                            Button {
                                                selectedRegularMember = member
                                            } label: {
                                                MemberManagementRow(
                                                    member: member,
                                                    showManagedBadge: false,
                                                    showChevron: true
                                                )
                                            }
                                        } else {
                                            MemberManagementRow(
                                                member: member,
                                                showManagedBadge: false
                                            )
                                        }
                                        
                                        if member.id != regularMembers.last?.id {
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
                        
                        // Managed Members Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("MANAGED MEMBERS")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                Spacer()
                                
                                if authViewModel.canCreateManagedMembers {
                                    Button {
                                        showAddManagedMember = true
                                    } label: {
                                        Label("Add", systemImage: "plus.circle.fill")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if managedMembers.isEmpty {
                                VStack(spacing: Theme.Spacing.md) {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .font(.system(size: 40))
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No managed members")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text("Create members for people without their own account (children, family members, etc.)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(Theme.Spacing.xl)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                .padding(.horizontal, Theme.Spacing.md)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(managedMembers) { member in
                                        Button {
                                            selectedManagedMember = member
                                        } label: {
                                            MemberManagementRow(
                                                member: member,
                                                showManagedBadge: true,
                                                showChevron: true
                                            )
                                        }
                                        
                                        if member.id != managedMembers.last?.id {
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
                        
                        // Info Card
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("About Managed Members")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("Managed members are for people who don't have their own phone or account. You can track their expenses and they can later claim their account using a special code.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Ownership Transfer Section (Owner only)
                        if isOwner {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("OWNERSHIP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                if let pendingMember = authViewModel.pendingOwnerMember {
                                    // Show pending transfer status
                                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Image(systemName: "clock.fill")
                                                .foregroundStyle(Theme.Colors.warning)
                                            Text("Transfer Pending")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                        }
                                        
                                        HStack(spacing: Theme.Spacing.md) {
                                            ZStack {
                                                Circle()
                                                    .fill(pendingMember.swiftUIColor)
                                                    .frame(width: 36, height: 36)
                                                
                                                if let emoji = pendingMember.avatarUrl, !emoji.isEmpty {
                                                    Text(emoji)
                                                        .font(.system(size: 20))
                                                } else {
                                                    Text(pendingMember.initials)
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(pendingMember.displayName)
                                                    .font(.body)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                Text("Waiting to accept ownership")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.Colors.warning)
                                            }
                                        }
                                        
                                        Button {
                                            showRevokeTransferConfirm = true
                                        } label: {
                                            Label("Cancel Transfer", systemImage: "xmark.circle")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundStyle(Theme.Colors.error)
                                    }
                                    .padding(Theme.Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.Colors.warning.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                    .padding(.horizontal, Theme.Spacing.md)
                                } else if !eligibleForOwnership.isEmpty {
                                    // Show transfer ownership button
                                    Button {
                                        showTransferOwnership = true
                                    } label: {
                                        HStack(spacing: Theme.Spacing.md) {
                                            Image(systemName: "crown.fill")
                                                .font(.body)
                                                .foregroundStyle(Theme.Colors.warning)
                                                .frame(width: 24)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Transfer Ownership")
                                                    .font(.body)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                
                                                Text("Give another member full control")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(Theme.Colors.textMuted)
                                        }
                                        .padding(Theme.Spacing.md)
                                        .contentShape(Rectangle())
                                    }
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                    .padding(.horizontal, Theme.Spacing.md)
                                }
                            }
                        }
                        
                        // Inactive Members Section
                        if !inactiveMembers.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("INACTIVE MEMBERS")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(inactiveMembers) { member in
                                        // Users with reactivate permission can tap inactive members
                                        if authViewModel.canReactivateMembers {
                                            Button {
                                                selectedInactiveMember = member
                                            } label: {
                                                MemberManagementRow(
                                                    member: member,
                                                    showManagedBadge: member.isManaged,
                                                    showChevron: true
                                                )
                                            }
                                        } else {
                                            MemberManagementRow(
                                                member: member,
                                                showManagedBadge: member.isManaged
                                            )
                                        }
                                        
                                        if member.id != inactiveMembers.last?.id {
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
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, Theme.Spacing.md)
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .sheet(isPresented: $showAddManagedMember) {
            AddManagedMemberView()
        }
        .sheet(item: $selectedManagedMember) { member in
            ManagedMemberDetailView(member: member)
        }
        .sheet(item: $selectedRegularMember) { member in
            RegularMemberDetailView(member: member)
        }
        .sheet(item: $selectedInactiveMember) { member in
            InactiveMemberDetailView(member: member)
        }
        .sheet(isPresented: $showTransferOwnership) {
            TransferOwnershipView()
        }
        .alert("Revoke Transfer?", isPresented: $showRevokeTransferConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Revoke", role: .destructive) {
                Task {
                    await authViewModel.revokeOwnershipTransfer()
                }
            }
        } message: {
            if let pendingMember = authViewModel.pendingOwnerMember {
                Text("\(pendingMember.displayName) will no longer be able to accept ownership.")
            }
        }
        .alert("Accept Ownership?", isPresented: $showAcceptTransferConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Accept") {
                Task {
                    await authViewModel.acceptOwnershipTransfer()
                }
            }
        } message: {
            Text("You will become the owner of this household with full control over members, settings, and the ability to delete the household. The current owner will become a regular member.")
        }
        .alert("Decline Ownership?", isPresented: $showDeclineTransferConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Decline", role: .destructive) {
                Task {
                    await authViewModel.declineOwnershipTransfer()
                }
            }
        } message: {
            Text("The ownership transfer will be cancelled. The current owner will remain as owner.")
        }
    }
}

// MARK: - Member Management Row

struct MemberManagementRow: View {
    let member: HouseholdMember
    var showManagedBadge: Bool = false
    var showChevron: Bool = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(member.swiftUIColor.opacity(member.isInactive ? 0.5 : 1.0))
                    .frame(width: 44, height: 44)
                
                if let emoji = member.avatarUrl, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 24))
                        .opacity(member.isInactive ? 0.6 : 1.0)
                } else {
                    Text(member.initials)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textInverse)
                        .opacity(member.isInactive ? 0.6 : 1.0)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(member.displayName)
                        .font(.body)
                        .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    
                    if member.isInactive {
                        BadgeView(text: "Inactive", color: Theme.Colors.textMuted)
                    } else if showManagedBadge {
                        BadgeView(text: "Managed", color: Theme.Colors.accent)
                    }
                }
                
                Text(member.role.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
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

// MARK: - Badge View

struct BadgeView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - Add Managed Member View

struct AddManagedMemberView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayName = ""
    @State private var selectedColor = "#4ECDC4"
    @State private var selectedEmoji = ""
    @State private var isSaving = false
    @State private var showEmojiPicker = false
    @State private var createdMember: HouseholdMember?
    
    private let colorOptions = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
        "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        "#BB8FCE", "#85C1E9", "#F8B500", "#FF8C00",
        "#00CED1", "#FF69B4", "#32CD32", "#FFD700"
    ]
    
    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var previewInitials: String {
        displayName.initials(count: 2)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if let member = createdMember {
                    // Success state - show claim code
                    MemberCreatedSuccessView(member: member) {
                        dismiss()
                    }
                }                 else {
                    // Form state
                    ScrollView {
                        VStack(spacing: Theme.Spacing.xl) {
                            // Error Display (at top for visibility)
                            if let error = authViewModel.error {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.Colors.error)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.error)
                                }
                                .padding(Theme.Spacing.md)
                                .frame(maxWidth: .infinity)
                                .background(Theme.Colors.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.top, Theme.Spacing.md)
                            }
                            
                            // Preview
                            VStack(spacing: Theme.Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: selectedColor))
                                        .frame(width: 100, height: 100)
                                    
                                    if selectedEmoji.isEmpty {
                                        Text(previewInitials.isEmpty ? "?" : previewInitials)
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    } else {
                                        Text(selectedEmoji)
                                            .font(.system(size: 50))
                                    }
                                }
                                
                                Text(displayName.isEmpty ? "Member Name" : displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                BadgeView(text: "Managed Member", color: Theme.Colors.accent)
                            }
                            .padding(.top, authViewModel.error == nil ? Theme.Spacing.lg : 0)
                            
                            // Display Name
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Display Name")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                TextField("Enter their name", text: $displayName)
                                    .inputFieldStyle()
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            // Emoji Selection
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack {
                                    Text("Profile Emoji (Optional)")
                                        .font(.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    
                                    Spacer()
                                    
                                    if !selectedEmoji.isEmpty {
                                        Button("Clear") {
                                            selectedEmoji = ""
                                        }
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.accent)
                                    }
                                }
                                
                                Button {
                                    showEmojiPicker = true
                                } label: {
                                    HStack(spacing: Theme.Spacing.md) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                                .fill(Theme.Colors.backgroundCard)
                                                .frame(width: 60, height: 60)
                                            
                                            if selectedEmoji.isEmpty {
                                                Image(systemName: "face.smiling")
                                                    .font(.title)
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                            } else {
                                                Text(selectedEmoji)
                                                    .font(.system(size: 36))
                                            }
                                        }
                                        
                                        Text(selectedEmoji.isEmpty ? "Tap to select emoji" : "Tap to change")
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                        
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            // Color Selection
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Profile Color")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm) {
                                    ForEach(colorOptions, id: \.self) { color in
                                        Button {
                                            selectedColor = color
                                        } label: {
                                            Circle()
                                                .fill(Color(hex: color))
                                                .frame(width: 36, height: 36)
                                                .overlay(
                                                    Circle()
                                                        .stroke(selectedColor == color ? Theme.Colors.accent : Color.clear, lineWidth: 3)
                                                )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            Spacer(minLength: 100)
                        }
                    }
                }
            }
            .navigationTitle("Add Managed Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if createdMember == nil {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if createdMember == nil {
                        Button {
                            saveMember()
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(Theme.Colors.accent)
                            } else {
                                Text("Create")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(canSave ? Theme.Colors.accent : Theme.Colors.textMuted)
                        .disabled(isSaving || !canSave)
                    }
                }
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerSheet(
                    selectedEmoji: $selectedEmoji,
                    profileColor: selectedColor
                )
            }
            .onAppear {
                authViewModel.clearError()
            }
        }
    }
    
    private func saveMember() {
        isSaving = true
        
        Task {
            print("DEBUG: Starting createManagedMember...")
            let member = await authViewModel.createManagedMember(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                color: selectedColor
            )
            
            print("DEBUG: createManagedMember returned: \(String(describing: member))")
            print("DEBUG: authViewModel.error: \(String(describing: authViewModel.error))")
            
            if let member = member {
                // If emoji was selected, update the profile
                if !selectedEmoji.isEmpty {
                    _ = await authViewModel.updateManagedMemberProfile(
                        memberId: member.id,
                        displayName: nil,
                        emoji: selectedEmoji,
                        color: nil
                    )
                }
                
                // Refresh to get updated member with emoji
                if let household = authViewModel.currentHousehold {
                    await authViewModel.selectHousehold(household)
                }
                
                // Get the updated member
                if let updatedMember = authViewModel.members.first(where: { $0.id == member.id }) {
                    createdMember = updatedMember
                } else {
                    createdMember = member
                }
            } else {
                print("DEBUG: Member creation failed, error should be displayed")
            }
            
            isSaving = false
        }
    }
}

// MARK: - Member Created Success View

struct MemberCreatedSuccessView: View {
    let member: HouseholdMember
    let onDone: () -> Void
    
    @State private var codeCopied = false
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Success Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.success)
            
            // Member Preview
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(member.swiftUIColor)
                        .frame(width: 80, height: 80)
                    
                    if let emoji = member.avatarUrl, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 44))
                    } else {
                        Text(member.initials)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
                
                Text(member.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Managed member created!")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.success)
            }
            
            // Claim Code Card
            VStack(spacing: Theme.Spacing.md) {
                Text("Claim Code")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textMuted)
                
                if let code = member.claimCode {
                    Text(code)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                    
                    Button {
                        UIPasteboard.general.string = code
                        codeCopied = true
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            codeCopied = false
                        }
                    } label: {
                        Label(
                            codeCopied ? "Copied!" : "Copy Code",
                            systemImage: codeCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .foregroundStyle(codeCopied ? Theme.Colors.success : Theme.Colors.accent)
                }
                
                Text("Share this code with \(member.displayName). When they create an account, they can use this code to claim their profile and all transaction history.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
            
            Spacer()
            
            Button {
                onDone()
            } label: {
                Text("Done")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

// MARK: - Managed Member Detail View

struct ManagedMemberDetailView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let member: HouseholdMember
    
    @State private var showEditProfile = false
    @State private var showDeleteConfirm = false
    @State private var showRegenerateConfirm = false
    @State private var codeCopied = false
    @State private var isRegenerating = false
    @State private var currentClaimCode: String?
    @State private var showShareSheet = false
    
    /// Can share/regenerate claim codes (requires can_approve_join_requests permission)
    private var canShareClaimCode: Bool {
        authViewModel.canApproveJoinRequests
    }
    
    /// Can edit the managed member's profile (requires can_create_managed_members permission)
    private var canEditProfile: Bool {
        authViewModel.canCreateManagedMembers
    }
    
    /// Can remove the managed member (requires can_remove_members permission)
    private var canRemove: Bool {
        authViewModel.canRemoveMembers
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Member Profile
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(member.swiftUIColor)
                                    .frame(width: 100, height: 100)
                                
                                if let emoji = member.avatarUrl, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 50))
                                } else {
                                    Text(member.initials)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            
                            Text(member.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            BadgeView(text: "Managed Member", color: Theme.Colors.accent)
                            
                            if canEditProfile {
                                Button {
                                    showEditProfile = true
                                } label: {
                                    Label("Edit Profile", systemImage: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Claim Code Section
                        if canShareClaimCode {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("CLAIM CODE")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                VStack(spacing: Theme.Spacing.md) {
                                    if let code = currentClaimCode ?? member.claimCode {
                                        Text(code)
                                            .font(.system(.title2, design: .monospaced))
                                            .fontWeight(.bold)
                                            .foregroundStyle(Theme.Colors.accent)
                                        
                                        HStack(spacing: Theme.Spacing.md) {
                                            Button {
                                                UIPasteboard.general.string = code
                                                codeCopied = true
                                                
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                    codeCopied = false
                                                }
                                            } label: {
                                                Label(
                                                    codeCopied ? "Copied!" : "Copy",
                                                    systemImage: codeCopied ? "checkmark" : "doc.on.doc"
                                                )
                                                .font(.subheadline)
                                            }
                                            .foregroundStyle(codeCopied ? Theme.Colors.success : Theme.Colors.accent)
                                            
                                            Divider()
                                                .frame(height: 20)
                                            
                                            Button {
                                                showShareSheet = true
                                            } label: {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                                    .font(.subheadline)
                                            }
                                            .foregroundStyle(Theme.Colors.accent)
                                            
                                            Divider()
                                                .frame(height: 20)
                                            
                                            Button {
                                                showRegenerateConfirm = true
                                            } label: {
                                                if isRegenerating {
                                                    ProgressView()
                                                        .tint(Theme.Colors.warning)
                                                } else {
                                                    Label("New Code", systemImage: "arrow.clockwise")
                                                        .font(.subheadline)
                                                }
                                            }
                                            .foregroundStyle(Theme.Colors.warning)
                                            .disabled(isRegenerating)
                                        }
                                    }
                                    
                                    Text("Share this code with \(member.displayName). When they sign up, they can enter this code to claim their account.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(Theme.Spacing.lg)
                                .frame(maxWidth: .infinity)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("How Claiming Works")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                InfoRow(number: "1", text: "Share the claim code with \(member.displayName)")
                                InfoRow(number: "2", text: "They download the app and create an account")
                                InfoRow(number: "3", text: "Instead of joining with household code, they use the claim code")
                                InfoRow(number: "4", text: "They get access to all their transaction history")
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Delete Button
                        if canRemove {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Label("Remove Member", systemImage: "trash")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(Theme.Colors.error)
                            .padding(.top, Theme.Spacing.lg)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Member Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditManagedMemberView(member: member)
            }
            .alert("Generate New Code?", isPresented: $showRegenerateConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Generate") {
                    regenerateCode()
                }
            } message: {
                Text("The old code will stop working. Make sure to share the new code with \(member.displayName).")
            }
            .alert("Remove Member?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    deleteMember()
                }
            } message: {
                Text("If \(member.displayName) has any transaction history, they will be marked as inactive instead of deleted.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let code = currentClaimCode ?? member.claimCode {
                    ShareSheet(items: [shareText(for: code)])
                }
            }
        }
    }
    
    private func shareText(for code: String) -> String {
        "Join our household in Bank of Quack!\n\nUse this claim code when signing up: \(code)\n\nThis will link your account to your existing transaction history."
    }
    
    private func regenerateCode() {
        isRegenerating = true
        
        Task {
            if let newCode = await authViewModel.regenerateClaimCode(memberId: member.id) {
                currentClaimCode = newCode
            }
            isRegenerating = false
        }
    }
    
    private func deleteMember() {
        Task {
            let success = await authViewModel.deleteManagedMember(memberId: member.id)
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 16, height: 16)
                .background(Theme.Colors.accent.opacity(0.2))
                .clipShape(Circle())
            
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Edit Managed Member View

struct EditManagedMemberView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let member: HouseholdMember
    
    @State private var displayName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var selectedColor: String = ""
    @State private var isSaving = false
    @State private var showEmojiPicker = false
    
    private let colorOptions = [
        "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
        "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
        "#BB8FCE", "#85C1E9", "#F8B500", "#FF8C00",
        "#00CED1", "#FF69B4", "#32CD32", "#FFD700"
    ]
    
    private var previewInitials: String {
        displayName.initials(count: 2)
    }
    
    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Preview
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: selectedColor.isEmpty ? member.color : selectedColor))
                                    .frame(width: 100, height: 100)
                                
                                if selectedEmoji.isEmpty {
                                    Text(previewInitials.isEmpty ? "?" : previewInitials)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                } else {
                                    Text(selectedEmoji)
                                        .font(.system(size: 50))
                                }
                            }
                            
                            Text(displayName.isEmpty ? "Member Name" : displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Display Name
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Display Name")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            TextField("Enter their name", text: $displayName)
                                .inputFieldStyle()
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Emoji Selection
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("Profile Emoji")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                if !selectedEmoji.isEmpty {
                                    Button("Clear") {
                                        selectedEmoji = ""
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            
                            Button {
                                showEmojiPicker = true
                            } label: {
                                HStack(spacing: Theme.Spacing.md) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                            .fill(Theme.Colors.backgroundCard)
                                            .frame(width: 60, height: 60)
                                        
                                        if selectedEmoji.isEmpty {
                                            Image(systemName: "face.smiling")
                                                .font(.title)
                                                .foregroundStyle(Theme.Colors.textMuted)
                                        } else {
                                            Text(selectedEmoji)
                                                .font(.system(size: 36))
                                        }
                                    }
                                    
                                    Text(selectedEmoji.isEmpty ? "Tap to select emoji" : "Tap to change")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Color Selection
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Profile Color")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.Spacing.sm) {
                                ForEach(colorOptions, id: \.self) { color in
                                    Button {
                                        selectedColor = color
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: color))
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Circle()
                                                    .stroke(selectedColor == color ? Theme.Colors.accent : Color.clear, lineWidth: 3)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveProfile()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(Theme.Colors.accent)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(canSave ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .disabled(isSaving || !canSave)
                }
            }
            .onAppear {
                displayName = member.displayName
                selectedEmoji = member.avatarUrl ?? ""
                selectedColor = member.color
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerSheet(
                    selectedEmoji: $selectedEmoji,
                    profileColor: selectedColor.isEmpty ? member.color : selectedColor
                )
            }
        }
    }
    
    private func saveProfile() {
        isSaving = true
        
        Task {
            let nameToSave = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let emojiToSave = selectedEmoji.isEmpty ? nil : selectedEmoji
            let colorToSave = selectedColor.isEmpty ? nil : selectedColor
            
            let success = await authViewModel.updateManagedMemberProfile(
                memberId: member.id,
                displayName: nameToSave,
                emoji: emojiToSave,
                color: colorToSave
            )
            
            if success {
                dismiss()
            }
            
            isSaving = false
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Transfer Ownership View

struct TransferOwnershipView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedMember: HouseholdMember?
    @State private var showConfirmation = false
    @State private var isProcessing = false
    
    private var eligibleMembers: [HouseholdMember] {
        authViewModel.members.filter { member in
            !member.isManaged && 
            !member.isInactive && 
            member.role != .owner &&
            member.userId != nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Header
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(Theme.Colors.warning)
                            
                            Text("Transfer Ownership")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Select a member to transfer ownership to. They will need to accept before the transfer completes.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Error Display
                        if let error = authViewModel.error {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.error)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.error.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Eligible Members
                        if eligibleMembers.isEmpty {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "person.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                Text("No eligible members")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Text("Only active members with their own accounts can receive ownership.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.xl)
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        } else {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("SELECT NEW OWNER")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(eligibleMembers) { member in
                                        Button {
                                            selectedMember = member
                                            showConfirmation = true
                                        } label: {
                                            HStack(spacing: Theme.Spacing.md) {
                                                ZStack {
                                                    Circle()
                                                        .fill(member.swiftUIColor)
                                                        .frame(width: 44, height: 44)
                                                    
                                                    if let emoji = member.avatarUrl, !emoji.isEmpty {
                                                        Text(emoji)
                                                            .font(.system(size: 24))
                                                    } else {
                                                        Text(member.initials)
                                                            .font(.subheadline)
                                                            .fontWeight(.semibold)
                                                            .foregroundStyle(.white)
                                                    }
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
                                                
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                            }
                                            .padding(Theme.Spacing.md)
                                            .contentShape(Rectangle())
                                        }
                                        
                                        if member.id != eligibleMembers.last?.id {
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
                        
                        // Warning
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.warning)
                                Text("Important")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("After the transfer is accepted, you will become a regular member. The new owner will have full control over the household, including the ability to remove you.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
                
                // Loading overlay
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Transfer Ownership")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .disabled(isProcessing)
                }
            }
            .alert("Transfer Ownership?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedMember = nil
                }
                Button("Transfer") {
                    initiateTransfer()
                }
            } message: {
                if let member = selectedMember {
                    Text("\(member.displayName) will receive an ownership offer. The transfer will complete when they accept.")
                }
            }
            .onAppear {
                authViewModel.clearError()
            }
        }
    }
    
    private func initiateTransfer() {
        guard let member = selectedMember else { return }
        
        isProcessing = true
        
        Task {
            let success = await authViewModel.initiateOwnershipTransfer(to: member)
            isProcessing = false
            
            if success {
                dismiss()
            }
            
            selectedMember = nil
        }
    }
}

// MARK: - Inactive Member Detail View (Owner Actions)

struct InactiveMemberDetailView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let member: HouseholdMember
    
    @State private var showReactivateConfirm = false
    @State private var isProcessing = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Member Profile
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(member.swiftUIColor.opacity(0.5))
                                    .frame(width: 100, height: 100)
                                
                                if let emoji = member.avatarUrl, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 50))
                                        .opacity(0.6)
                                } else {
                                    Text(member.initials)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .opacity(0.6)
                                }
                            }
                            
                            Text(member.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: Theme.Spacing.sm) {
                                BadgeView(text: "Inactive", color: Theme.Colors.textMuted)
                                if member.isManaged {
                                    BadgeView(text: "Managed", color: Theme.Colors.accent)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Error Display
                        if let error = authViewModel.error {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.error)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.error.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("About Inactive Members")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("This member was removed from the household but their transaction history has been preserved. You can reactivate them to restore their active membership.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Reactivate Button
                        Button {
                            showReactivateConfirm = true
                        } label: {
                            Label("Reactivate Member", systemImage: "arrow.uturn.backward.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Theme.Colors.success)
                        .padding(.top, Theme.Spacing.lg)
                        
                        Spacer(minLength: 100)
                    }
                }
                
                // Loading overlay
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Inactive Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .disabled(isProcessing)
                }
            }
            .alert("Reactivate Member?", isPresented: $showReactivateConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Reactivate") {
                    reactivateMember()
                }
            } message: {
                Text("\(member.displayName) will be restored as an active member of the household.")
            }
            .onAppear {
                authViewModel.clearError()
            }
        }
    }
    
    private func reactivateMember() {
        isProcessing = true
        
        Task {
            let success = await authViewModel.reactivateMember(member)
            isProcessing = false
            
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Regular Member Detail View (Owner Actions)

struct RegularMemberDetailView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let member: HouseholdMember
    
    @State private var showRemoveConfirm = false
    @State private var showPermissions = false
    @State private var isProcessing = false
    
    private var memberPermissions: MemberPermissions {
        authViewModel.getPermissions(for: member.id)
    }
    
    private var permissionsSummary: String {
        if memberPermissions.hasNoPermissions {
            return "No special permissions"
        }
        var permissions: [String] = []
        if memberPermissions.canApproveJoinRequests { permissions.append("Approve requests") }
        if memberPermissions.canCreateManagedMembers { permissions.append("Create members") }
        if memberPermissions.canRemoveMembers { permissions.append("Remove members") }
        if memberPermissions.canReactivateMembers { permissions.append("Reactivate members") }
        return permissions.joined(separator: ", ")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Member Profile
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(member.swiftUIColor)
                                    .frame(width: 100, height: 100)
                                
                                if let emoji = member.avatarUrl, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 50))
                                } else {
                                    Text(member.initials)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            
                            Text(member.displayName)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            BadgeView(text: member.role.displayName, color: Theme.Colors.accent)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Error Display
                        if let error = authViewModel.error {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.error)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.error.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Permissions Section (Owner only)
                        if authViewModel.isOwner {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("PERMISSIONS")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                Button {
                                    showPermissions = true
                                } label: {
                                    HStack(spacing: Theme.Spacing.md) {
                                        Image(systemName: "lock.shield")
                                            .font(.body)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Manage Permissions")
                                                .font(.body)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            
                                            Text(permissionsSummary)
                                                .font(.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textMuted)
                                    }
                                    .padding(Theme.Spacing.md)
                                    .contentShape(Rectangle())
                                }
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("About Removing Members")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("If \(member.displayName) has any transaction history, they will be marked as inactive to preserve the records. Otherwise, they will be completely removed from the household. They can rejoin later with an invite code.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Remove Button
                        Button {
                            showRemoveConfirm = true
                        } label: {
                            Label("Remove Member", systemImage: "trash")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Theme.Colors.error)
                        .padding(.top, Theme.Spacing.lg)
                        
                        Spacer(minLength: 100)
                    }
                }
                
                // Loading overlay
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Member Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .disabled(isProcessing)
                }
            }
            .sheet(isPresented: $showPermissions) {
                MemberPermissionsView(member: member)
            }
            .alert("Remove Member?", isPresented: $showRemoveConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeMember()
                }
            } message: {
                Text("If \(member.displayName) has any transaction history, they will be marked as inactive instead of removed. They can rejoin later with an invite code.")
            }
            .onAppear {
                authViewModel.clearError()
            }
        }
    }
    
    private func removeMember() {
        isProcessing = true
        
        Task {
            let success = await authViewModel.removeMember(member)
            isProcessing = false
            
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Member Permissions View

struct MemberPermissionsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    let member: HouseholdMember
    
    @State private var canCreateManagedMembers = false
    @State private var canRemoveMembers = false
    @State private var canReactivateMembers = false
    @State private var canApproveJoinRequests = false
    @State private var isSaving = false
    @State private var hasChanges = false
    
    private var currentPermissions: MemberPermissions {
        authViewModel.getPermissions(for: member.id)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Member Info Header
                        VStack(spacing: Theme.Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(member.swiftUIColor)
                                    .frame(width: 80, height: 80)
                                
                                if let emoji = member.avatarUrl, !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: 40))
                                } else {
                                    Text(member.initials)
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                }
                            }
                            
                            Text(member.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Configure what this member can do")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        // Error Display
                        if let error = authViewModel.error {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Colors.error)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                            .padding(Theme.Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.error.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Permissions Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("PERMISSIONS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, Theme.Spacing.md)
                            
                            VStack(spacing: 0) {
                                PermissionToggleRow(
                                    title: "Approve Join Requests",
                                    subtitle: "Can approve or reject new member requests",
                                    icon: "person.badge.plus",
                                    isOn: $canApproveJoinRequests
                                )
                                .onChange(of: canApproveJoinRequests) { hasChanges = true }
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                PermissionToggleRow(
                                    title: "Create Managed Members",
                                    subtitle: "Can create members for people without accounts",
                                    icon: "person.crop.circle.badge.questionmark",
                                    isOn: $canCreateManagedMembers
                                )
                                .onChange(of: canCreateManagedMembers) { hasChanges = true }
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                PermissionToggleRow(
                                    title: "Remove Members",
                                    subtitle: "Can remove non-owner members from household",
                                    icon: "person.badge.minus",
                                    isOn: $canRemoveMembers
                                )
                                .onChange(of: canRemoveMembers) { hasChanges = true }
                                
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                
                                PermissionToggleRow(
                                    title: "Reactivate Members",
                                    subtitle: "Can restore inactive members",
                                    icon: "arrow.uturn.backward.circle",
                                    isOn: $canReactivateMembers
                                )
                                .onChange(of: canReactivateMembers) { hasChanges = true }
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Info Card
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("About Permissions")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            
                            Text("Grant specific capabilities to trusted members. As the owner, you always have all permissions. Member permissions can be changed at any time.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
                
                // Loading overlay
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        savePermissions()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(Theme.Colors.accent)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(hasChanges ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .disabled(isSaving || !hasChanges)
                }
            }
            .onAppear {
                loadCurrentPermissions()
                authViewModel.clearError()
            }
        }
    }
    
    private func loadCurrentPermissions() {
        let permissions = currentPermissions
        canCreateManagedMembers = permissions.canCreateManagedMembers
        canRemoveMembers = permissions.canRemoveMembers
        canReactivateMembers = permissions.canReactivateMembers
        canApproveJoinRequests = permissions.canApproveJoinRequests
        hasChanges = false
    }
    
    private func savePermissions() {
        isSaving = true
        
        Task {
            let permissions = MemberPermissions(
                memberId: member.id,
                canCreateManagedMembers: canCreateManagedMembers,
                canRemoveMembers: canRemoveMembers,
                canReactivateMembers: canReactivateMembers,
                canApproveJoinRequests: canApproveJoinRequests
            )
            
            let success = await authViewModel.updateMemberPermissions(permissions)
            isSaving = false
            
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Permission Toggle Row

struct PermissionToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .tint(Theme.Colors.accent)
        .padding(Theme.Spacing.md)
    }
}

#Preview {
    MemberManagementView()
        .environment(AuthViewModel())
}

