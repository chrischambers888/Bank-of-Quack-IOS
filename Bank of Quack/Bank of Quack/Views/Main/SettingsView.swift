import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var showSwitchHousehold = false
    @State private var showCategories = false
    @State private var showSectors = false
    @State private var showThemePalette = false
    @State private var showSignOutConfirm = false
    @State private var showInviteCodeWarning = false
    @State private var showInviteCode = false
    @State private var showDeleteHouseholdConfirm = false
    @State private var deleteConfirmationText = ""
    @State private var showEditProfile = false
    @State private var showLeaveHouseholdConfirm = false
    @State private var showMemberManagement = false
    
    // Data import/export states
    @State private var showImportView = false
    @State private var showExportShare = false
    @State private var showTemplateShare = false
    @State private var exportURL: URL?
    @State private var templateURL: URL?
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    settingsContent
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
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
        .sheet(isPresented: $showThemePalette) {
            ThemePaletteView()
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
            Text("Anyone with this code can join your bank and see all transaction history, including amounts and who made each purchase. Only share with people you trust.")
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
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $showMemberManagement) {
            MemberManagementView()
        }
        .sheet(isPresented: $showImportView) {
            ImportStagingView()
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ExportShareSheet(exportDirectory: url)
            }
        }
        .sheet(isPresented: $showTemplateShare) {
            if let url = templateURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Leave Bank?", isPresented: $showLeaveHouseholdConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task {
                    let success = await authViewModel.leaveHousehold()
                    if success {
                        showLeaveHouseholdConfirm = false
                    }
                }
            }
        } message: {
            Text("Your transaction history will be preserved. You can rejoin anytime with an invite code.")
        }
    }
    
    // MARK: - Settings Content
    
    @ViewBuilder
    private var settingsContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            profileSection
            bankSection
            membersSection
            pendingRequestsSection
            organizationSection
            
            DataSettingsSection(
                isExporting: isExporting,
                onExport: exportHouseholdData,
                onImport: { showImportView = true },
                onDownloadTemplate: downloadTemplate
            )
            
            PrivacySettingsSection()
            accountSection
            
            Text("Bank of Quack v1.0.0")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.top, Theme.Spacing.lg)
            
            Spacer(minLength: 100)
        }
    }
    
    // MARK: - Profile Section
    
    @ViewBuilder
    private var profileSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(authViewModel.currentMember?.swiftUIColor ?? Theme.Colors.accent)
                    .frame(width: 80, height: 80)
                
                if let emoji = authViewModel.currentMember?.avatarUrl, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 40))
                } else {
                    Text(authViewModel.currentMember?.initials ?? "?")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textInverse)
                }
            }
            .onTapGesture {
                showEditProfile = true
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
            
            Button {
                showEditProfile = true
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }
    
    // MARK: - Bank Section
    
    @ViewBuilder
    private var bankSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("BANK")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "house.fill",
                    title: authViewModel.currentHousehold?.name ?? "Bank",
                    subtitle: nil
                )
                
                Divider().background(Theme.Colors.borderLight)
                
                inviteCodeRow
                
                Divider().background(Theme.Colors.borderLight)
                
                Button { showSwitchHousehold = true } label: {
                    SettingsRow(icon: "arrow.left.arrow.right", title: "Switch Bank", showChevron: true)
                }
                
                if authViewModel.currentMember?.role == .owner {
                    Divider().background(Theme.Colors.borderLight)
                    Button { showDeleteHouseholdConfirm = true } label: {
                        SettingsRow(icon: "trash.fill", title: "Delete Bank", subtitle: "Permanently delete all data", iconColor: Theme.Colors.error)
                    }
                }
                
                if authViewModel.currentMember?.role != .owner {
                    Divider().background(Theme.Colors.borderLight)
                    Button { showLeaveHouseholdConfirm = true } label: {
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right.fill", title: "Leave Bank", subtitle: "You can rejoin later with an invite code", iconColor: Theme.Colors.warning)
                    }
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    @ViewBuilder
    private var inviteCodeRow: some View {
        HStack(spacing: 0) {
            Button {
                if showInviteCode { showInviteCode = false } else { showInviteCodeWarning = true }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: showInviteCode ? "eye.fill" : "eye.slash.fill")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite Code").font(.body).foregroundStyle(Theme.Colors.textPrimary)
                        if showInviteCode {
                            Text(authViewModel.currentHousehold?.inviteCode ?? "---")
                                .font(.caption).fontWeight(.medium).foregroundStyle(Theme.Colors.accent)
                        } else {
                            Text("Tap to reveal").font(.caption).foregroundStyle(Theme.Colors.textSecondary)
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
                    Image(systemName: "doc.on.doc").font(.body).foregroundStyle(Theme.Colors.accent).frame(width: 44, height: 44)
                }
                .padding(.trailing, Theme.Spacing.sm)
            }
        }
    }
    
    // MARK: - Members Section
    
    @ViewBuilder
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("MEMBERS (\(authViewModel.members.count))")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.textMuted)
                Spacer()
                Button { showMemberManagement = true } label: {
                    Text("Manage").font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                ForEach(authViewModel.members) { member in
                    MemberRow(member: member)
                    if member.id != authViewModel.members.last?.id {
                        Divider().background(Theme.Colors.borderLight)
                    }
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Pending Requests Section
    
    @ViewBuilder
    private var pendingRequestsSection: some View {
        if authViewModel.canApproveJoinRequests, !authViewModel.pendingMembers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("PENDING REQUESTS (\(authViewModel.pendingMembers.count))")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.warning)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.md)
                
                VStack(spacing: 0) {
                    ForEach(authViewModel.pendingMembers) { member in
                        PendingMemberRow(member: member)
                        if member.id != authViewModel.pendingMembers.last?.id {
                            Divider().background(Theme.Colors.borderLight)
                        }
                    }
                }
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // MARK: - Organization Section
    
    @ViewBuilder
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ORGANIZATION")
                .font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                Button { showCategories = true } label: {
                    SettingsRow(icon: "folder.fill", title: "Categories", subtitle: "\(authViewModel.categories.count) categories", showChevron: true)
                }
                Divider().background(Theme.Colors.borderLight)
                Button { showSectors = true } label: {
                    SettingsRow(icon: "rectangle.3.group.fill", title: "Sectors", subtitle: "\(authViewModel.sectors.count) sectors", showChevron: true)
                }
                Divider().background(Theme.Colors.borderLight)
                Button { showThemePalette = true } label: {
                    SettingsRow(icon: "paintpalette.fill", title: "Color Themes", subtitle: AppliedThemeManager.shared.appliedThemeName ?? "No theme applied", showChevron: true)
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Account Section
    
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ACCOUNT")
                .font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                Button { showSignOutConfirm = true } label: {
                    SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", iconColor: Theme.Colors.error)
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Data Export/Import Helpers
    
    private func exportHouseholdData() {
        guard let household = authViewModel.currentHousehold else { return }
        
        isExporting = true
        
        Task {
            do {
                let importExportService = ImportExportService()
                
                // Build sector-category mappings from the sectorCategories dictionary
                var sectorCategoryMappings: [(sectorName: String, categoryName: String)] = []
                let categoryMap = Dictionary(uniqueKeysWithValues: authViewModel.categories.map { ($0.id, $0.name) })
                
                for sector in authViewModel.sectors {
                    // Use authViewModel.sectorCategories instead of sector.categoryIds
                    if let categoryIds = authViewModel.sectorCategories[sector.id] {
                        for categoryId in categoryIds {
                            if let categoryName = categoryMap[categoryId] {
                                sectorCategoryMappings.append((sectorName: sector.name, categoryName: categoryName))
                            }
                        }
                    }
                }
                
                // Fetch all transactions and splits for export
                let dataService = DataService()
                let allTransactions = try await dataService.fetchTransactions(householdId: household.id)
                let allSplits = try await dataService.fetchAllSplitsForHousehold(householdId: household.id)
                
                let url = try importExportService.exportHouseholdData(
                    transactions: allTransactions,
                    transactionSplits: allSplits,
                    categories: authViewModel.categories,
                    sectors: authViewModel.sectors,
                    sectorCategories: sectorCategoryMappings,
                    members: authViewModel.members,
                    householdName: household.name
                )
                
                await MainActor.run {
                    exportURL = url
                    showExportShare = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    // Could show an error alert here
                }
            }
        }
    }
    
    private func downloadTemplate() {
        let importExportService = ImportExportService()
        
        do {
            let fileURL = try importExportService.generateImportTemplate()
            templateURL = fileURL
            showTemplateShare = true
        } catch {
            // Could show an error alert here
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var selectedColor: String = ""
    @State private var isSaving = false
    @State private var showEmojiInput = false
    @FocusState private var isEmojiFieldFocused: Bool
    
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
                                    .fill(Color(hex: selectedColor.isEmpty ? (authViewModel.currentMember?.color ?? "#4ECDC4") : selectedColor))
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
                            
                            Text(displayName.isEmpty ? "Your Name" : displayName)
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
                            
                            TextField("Enter your name", text: $displayName)
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
                            
                            Text("Choose any emoji to represent you, or leave blank to show your initials")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            HStack(spacing: Theme.Spacing.md) {
                                // Emoji display/input button
                                Button {
                                    showEmojiInput = true
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                            .fill(Theme.Colors.backgroundCard)
                                            .frame(width: 80, height: 80)
                                        
                                        if selectedEmoji.isEmpty {
                                            VStack(spacing: 4) {
                                                Image(systemName: "face.smiling")
                                                    .font(.title)
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                                Text("Tap")
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.Colors.textMuted)
                                            }
                                        } else {
                                            Text(selectedEmoji)
                                                .font(.system(size: 50))
                                        }
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedEmoji.isEmpty ? "No emoji selected" : "Emoji selected")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    
                                    Text("Tap to choose from the emoji keyboard")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                
                                Spacer()
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
                // Initialize with current values
                displayName = authViewModel.currentMember?.displayName ?? ""
                selectedEmoji = authViewModel.currentMember?.avatarUrl ?? ""
                selectedColor = authViewModel.currentMember?.color ?? ""
            }
            .sheet(isPresented: $showEmojiInput) {
                EmojiPickerSheet(
                    selectedEmoji: $selectedEmoji,
                    profileColor: selectedColor.isEmpty ? (authViewModel.currentMember?.color ?? "#4ECDC4") : selectedColor
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
            
            let success = await authViewModel.updateMyProfile(
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

// MARK: - Emoji Picker Sheet

struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEmoji: String
    let profileColor: String
    
    @State private var emojiInput: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                    .onTapGesture {
                        isInputFocused = false
                    }
                
                VStack(spacing: Theme.Spacing.xl) {
                    // Preview with profile color
                    ZStack {
                        Circle()
                            .fill(Color(hex: profileColor))
                            .frame(width: 120, height: 120)
                        
                        if emojiInput.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("Type an emoji")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        } else {
                            Text(String(emojiInput.prefix(1)))
                                .font(.system(size: 70))
                        }
                    }
                    .padding(.top, Theme.Spacing.xl)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    
                    // Instructions
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Type or paste any emoji")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Tap the field below and use your emoji keyboard 😊")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .onTapGesture {
                        isInputFocused = false
                    }
                    
                    // Emoji Input Field
                    TextField("", text: $emojiInput)
                        .font(.system(size: 50))
                        .multilineTextAlignment(.center)
                        .frame(height: 80)
                        .background(Theme.Colors.backgroundCard)
                        .cornerRadius(Theme.CornerRadius.lg)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .focused($isInputFocused)
                        .onChange(of: emojiInput) { _, newValue in
                            // Always use the last emoji typed (allows replacing without deleting)
                            if let lastEmoji = newValue.last, lastEmoji.isEmoji {
                                emojiInput = String(lastEmoji)
                            } else if !newValue.isEmpty {
                                // If not an emoji, keep the previous valid emoji or clear
                                let emojis = newValue.filter { $0.isEmoji }
                                emojiInput = emojis.last.map { String($0) } ?? ""
                            }
                        }
                    
                    Spacer()
                    
                    // Select Button
                    Button {
                        if !emojiInput.isEmpty {
                            selectedEmoji = emojiInput
                        }
                        dismiss()
                    } label: {
                        Text(emojiInput.isEmpty ? "Cancel" : "Select \(emojiInput)")
                            .font(.headline)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Choose Emoji")
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
                        if !emojiInput.isEmpty {
                            selectedEmoji = emojiInput
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .onAppear {
                emojiInput = selectedEmoji
                // Auto-focus the input field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isInputFocused = true
                }
            }
        }
    }
}

// MARK: - Data Settings Section

struct DataSettingsSection: View {
    let isExporting: Bool
    let onExport: () -> Void
    let onImport: () -> Void
    let onDownloadTemplate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("DATA")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                Button(action: onExport) {
                    HStack {
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            title: "Export Household Data",
                            subtitle: "Download all data as Excel file",
                            showChevron: false
                        )
                        
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, Theme.Spacing.md)
                        }
                    }
                }
                .disabled(isExporting)
                
                Divider()
                    .background(Theme.Colors.borderLight)
                
                Button(action: onImport) {
                    SettingsRow(
                        icon: "square.and.arrow.down",
                        title: "Import Transactions",
                        subtitle: "Import from Excel file",
                        showChevron: true
                    )
                }
                
                Divider()
                    .background(Theme.Colors.borderLight)
                
                Button(action: onDownloadTemplate) {
                    SettingsRow(
                        icon: "doc.text",
                        title: "Download Import Template",
                        subtitle: "Get an Excel template with examples",
                        showChevron: false
                    )
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}

// MARK: - Export Share Sheet

struct ExportShareSheet: UIViewControllerRepresentable {
    let exportDirectory: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Share the xlsx file directly
        let activityVC = UIActivityViewController(activityItems: [exportDirectory], applicationActivities: nil)
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                    .fill(member.swiftUIColor.opacity(member.isInactive ? 0.5 : 1.0))
                    .frame(width: 36, height: 36)
                
                if let emoji = member.avatarUrl, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 20))
                        .opacity(member.isInactive ? 0.6 : 1.0)
                } else {
                    Text(member.initials)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textInverse)
                        .opacity(member.isInactive ? 0.6 : 1.0)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(member.displayName)
                        .font(.body)
                        .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    
                    if member.isInactive {
                        Text("Inactive")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.textMuted.opacity(0.2))
                            .clipShape(Capsule())
                    } else if member.isManaged {
                        Text("Managed")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accent.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
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
                
                if let emoji = member.avatarUrl, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 20))
                        .opacity(0.7)
                } else {
                    Text(member.initials)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textInverse)
                }
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
            Text("\(member.displayName) will be able to see all bank transaction history and add their own transactions.")
        }
        .alert("Decline Request?", isPresented: $showRejectConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Decline", role: .destructive) {
                Task {
                    await authViewModel.rejectMember(member)
                }
            }
        } message: {
            Text("\(member.displayName) will not be added to the bank. They can request again with a new invite code.")
        }
    }
}

struct SwitchHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var showClaimSheet = false
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
                            // Bank Invitations (awaiting approval)
                            if !authViewModel.pendingHouseholds.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text("BANK INVITATIONS")
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
                            Label("Create New Bank", systemImage: "plus.circle")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        
                        Button {
                            showJoinSheet = true
                        } label: {
                            Label("Join Another Bank", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Button {
                            showClaimSheet = true
                        } label: {
                            Label("Claim Managed Account", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
            .navigationTitle("Switch Bank")
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
        .sheet(isPresented: $showClaimSheet) {
            ClaimAccountView()
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
            Text("Anyone with this code can join your bank and see all transaction history, including amounts and who made each purchase. Only share with people you trust.")
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
                            Text("Delete Bank?")
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
                            
                            TextField("Bank name", text: $confirmationText)
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

// MARK: - Privacy Settings Section

struct PrivacySettingsSection: View {
    @State private var privacyManager = PrivacyManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("PRIVACY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: 0) {
                // Hide Income Toggle
                PrivacyToggleRow(
                    icon: "eye.slash",
                    title: "Hide Income",
                    subtitle: "Hide income, net balance, and income transactions",
                    isOn: Binding(
                        get: { privacyManager.hideIncomeData },
                        set: { privacyManager.hideIncomeData = $0 }
                    )
                )
                
                Divider()
                    .background(Theme.Colors.borderLight)
                
                // Randomize Values Toggle
                PrivacyToggleRow(
                    icon: "shuffle",
                    title: "Randomize Values",
                    subtitle: "Show random amounts instead of real values",
                    isOn: Binding(
                        get: { privacyManager.randomizeValues },
                        set: { privacyManager.randomizeValues = $0 }
                    )
                )
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
            
            // Info text when privacy is active
            if privacyManager.hideIncomeData || privacyManager.randomizeValues {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Privacy mode active - look for lock icons on tabs")
                }
                .font(.caption2)
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
}

struct PrivacyToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
}

