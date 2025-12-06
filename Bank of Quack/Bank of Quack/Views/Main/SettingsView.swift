import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var showSwitchHousehold = false
    @State private var showCategories = false
    @State private var showSectors = false
    @State private var showTemplates = false
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
    @State private var exportURL: URL?
    @State private var templateURL: URL?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportPhase: String = ""
    @State private var showExportError = false
    @State private var exportErrorMessage: String = ""
    
    // Balance health check state
    @State private var balanceHealthCheck: BalanceHealthCheck?
    @State private var isCheckingBalance = false
    @State private var showProblematicTransactions = false
    @State private var problematicTransactions: [ProblematicTransaction] = []
    @State private var isLoadingProblematicTransactions = false
    @State private var transactionToEdit: TransactionView?
    @State private var isLoadingTransaction = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                settingsContent
            }
            .subtleThemedBackground()
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
        .sheet(isPresented: $showTemplates) {
            TemplatesView()
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
        .sheet(item: $templateURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        .sheet(isPresented: $showProblematicTransactions) {
            ProblematicTransactionsSheet(
                transactions: problematicTransactions,
                isLoading: isLoadingProblematicTransactions,
                totalImbalance: balanceHealthCheck?.totalImbalance ?? 0,
                onTransactionTapped: { transactionId in
                    loadTransactionForEditing(transactionId: transactionId)
                }
            )
        }
        .sheet(item: $transactionToEdit) { transaction in
            EditTransactionView(transaction: transaction)
        }
        .onChange(of: transactionToEdit) { oldValue, newValue in
            // When the edit sheet closes (transaction becomes nil), refresh data
            if oldValue != nil && newValue == nil {
                checkBalanceHealth()
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
        .task {
            // Check balance health when view appears
            if balanceHealthCheck == nil {
                checkBalanceHealth()
            }
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
                isOwner: authViewModel.isOwner,
                isExporting: isExporting,
                exportProgress: exportProgress,
                exportPhase: exportPhase,
                onExport: exportHouseholdData,
                onImport: { showImportView = true },
                onDownloadTemplate: downloadTemplate
            )
            
            PrivacySettingsSection()
            diagnosticsSection
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
            if let member = authViewModel.currentMember {
                MemberAvatarView(member: member, size: 80, fontSize: 40)
                    .onTapGesture {
                        showEditProfile = true
                    }
            } else {
                Circle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text("?")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textInverse)
                    )
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
            .background(.regularMaterial)
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
            .background(.regularMaterial)
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
                Button { showTemplates = true } label: {
                    SettingsRow(icon: "doc.on.doc.fill", title: "Templates", subtitle: "\(authViewModel.templates.count) templates", showChevron: true)
                }
                Divider().background(Theme.Colors.borderLight)
                Button { showThemePalette = true } label: {
                    SettingsRow(icon: "paintpalette.fill", title: "Color Themes", subtitle: AppliedThemeManager.shared.appliedThemeName ?? "No theme applied", showChevron: true)
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Diagnostics Section (only shown when there's an issue)
    
    @ViewBuilder
    private var diagnosticsSection: some View {
        // Only show this section if there's an imbalance detected
        if let health = balanceHealthCheck, health.hasImbalance {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("⚠️ DATA ISSUE DETECTED")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(Theme.Colors.error)
                    .padding(.horizontal, Theme.Spacing.md)
                
                VStack(spacing: 0) {
                    // Warning header
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "ladybug.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.error)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Unexpected Balance Imbalance")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.error)
                            
                            Text("Your household balances are off by \(health.totalImbalance.formatted(as: .standard, applyPrivacy: false)). This indicates a bug in the app.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.error.opacity(0.1))
                    
                    Divider()
                    
                    // View Problem Transactions button
                    Button {
                        loadProblematicTransactions()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 24)
                            
                            Text("View Problem Transactions")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                            
                            if isLoadingProblematicTransactions {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    
                    Divider()
                        .padding(.leading, Theme.Spacing.md + 24 + Theme.Spacing.sm)
                    
                    // Contact support button
                    Button {
                        openSupportEmail()
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 24)
                            
                            Text("Contact Support")
                                .font(.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    
                    Divider()
                        .padding(.leading, Theme.Spacing.md + 24 + Theme.Spacing.sm)
                    
                    // Help text
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("You can also fix this yourself:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("1. View problem transactions above\n2. Tap each one to edit the splits\n3. Adjust amounts so they sum to the total")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.backgroundSecondary.opacity(0.5))
                }
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .stroke(Theme.Colors.error.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    private func checkBalanceHealth() {
        guard let household = authViewModel.currentHousehold else { return }
        
        isCheckingBalance = true
        
        Task {
            do {
                let dataService = DataService()
                let health = try await dataService.fetchBalanceHealthCheck(householdId: household.id)
                await MainActor.run {
                    self.balanceHealthCheck = health
                    isCheckingBalance = false
                }
            } catch {
                await MainActor.run {
                    isCheckingBalance = false
                }
            }
        }
    }
    
    private func loadProblematicTransactions() {
        guard let household = authViewModel.currentHousehold else { return }
        
        isLoadingProblematicTransactions = true
        
        Task {
            do {
                let dataService = DataService()
                let transactions = try await dataService.fetchProblematicTransactions(householdId: household.id)
                await MainActor.run {
                    self.problematicTransactions = transactions
                    self.isLoadingProblematicTransactions = false
                    self.showProblematicTransactions = true
                }
            } catch {
                await MainActor.run {
                    self.isLoadingProblematicTransactions = false
                }
            }
        }
    }
    
    private func loadTransactionForEditing(transactionId: UUID) {
        guard let household = authViewModel.currentHousehold else { return }
        
        isLoadingTransaction = true
        
        Task {
            do {
                let dataService = DataService()
                let transactions = try await dataService.fetchTransactions(householdId: household.id)
                
                await MainActor.run {
                    if let transaction = transactions.first(where: { $0.id == transactionId }) {
                        self.transactionToEdit = transaction
                        self.showProblematicTransactions = false // Close the sheet first
                    }
                    self.isLoadingTransaction = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingTransaction = false
                }
            }
        }
    }
    
    private func openSupportEmail() {
        let imbalance = balanceHealthCheck?.totalImbalance ?? 0
        let transactionCount = problematicTransactions.count
        let transactionIds = problematicTransactions.prefix(5).map { $0.transactionId.uuidString.prefix(8) }.joined(separator: ", ")
        
        let subject = "Bank of Quack - Balance Issue Report"
        let body = """
        Hi,
        
        I'm experiencing a balance discrepancy in my household.
        
        --- Diagnostic Info ---
        Total Imbalance: \(imbalance.formatted(as: .standard, applyPrivacy: false))
        Problem Transactions: \(transactionCount)
        \(transactionCount > 0 ? "Transaction IDs: \(transactionIds)\(transactionCount > 5 ? "..." : "")" : "")
        
        [Please describe any additional context or steps that led to this issue]
        
        Thanks!
        """
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // TODO: Replace with your actual support email
        if let url = URL(string: "mailto:support@bankofquack.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Account Section
    
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
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Data Export/Import Helpers
    
    private func exportHouseholdData() {
        guard let household = authViewModel.currentHousehold else { return }
        
        isExporting = true
        exportProgress = 0.0
        exportPhase = "Starting export..."
        
        Task {
            await performExport(household: household)
        }
    }
    
    @MainActor
    private func performExport(household: Household) async {
        // Capture all data on main actor
        let categories = authViewModel.categories
        let sectors = authViewModel.sectors
        let sectorCategoriesMap = authViewModel.sectorCategories
        let members = authViewModel.members
        let householdId = household.id
        let householdName = household.name
        
        // Build sector-category mappings
        var sectorCategoryMappings: [(sectorName: String, categoryName: String)] = []
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        
        for sector in sectors {
            if let categoryIds = sectorCategoriesMap[sector.id] {
                for categoryId in categoryIds {
                    if let categoryName = categoryMap[categoryId] {
                        sectorCategoryMappings.append((sectorName: sector.name, categoryName: categoryName))
                    }
                }
            }
        }
        
        do {
            // Update progress for data fetching
            exportPhase = "Fetching transactions..."
            exportProgress = 0.05
            
            let dataService = DataService()
            print("[Export] Fetching transactions for household: \(householdId)")
            let allTransactions = try await dataService.fetchTransactions(householdId: householdId)
            print("[Export] Fetched \(allTransactions.count) transactions")
            
            exportPhase = "Fetching transaction splits..."
            exportProgress = 0.08
            
            // Use the optimized method that accepts pre-fetched transactions
            // This avoids fetching transactions twice and batches the query for large datasets
            print("[Export] Fetching splits for \(allTransactions.count) transactions...")
            let allSplits = try await dataService.fetchSplitsForTransactions(allTransactions)
            print("[Export] Fetched \(allSplits.count) splits")
            
            exportPhase = "Building export file..."
            exportProgress = 0.10
            
            // Perform the export (optimized to be fast even with large data)
            print("[Export] Starting XLSX generation...")
            let importExportService = ImportExportService()
            let url = try importExportService.exportHouseholdData(
                transactions: allTransactions,
                transactionSplits: allSplits,
                categories: categories,
                sectors: sectors,
                sectorCategories: sectorCategoryMappings,
                members: members,
                householdName: householdName,
                progressCallback: { [self] phase, progress in
                    // Since we're @MainActor, we can update state directly
                    // but the callback comes from sync code, so dispatch back
                    Task { @MainActor in
                        self.exportPhase = phase
                        self.exportProgress = progress
                    }
                }
            )
            
            print("[Export] Export complete, file at: \(url.path)")
            exportProgress = 1.0
            exportPhase = "Complete!"
            exportURL = url
            showExportShare = true
            isExporting = false
        } catch {
            print("[Export] ERROR: \(error)")
            print("[Export] Error description: \(error.localizedDescription)")
            isExporting = false
            exportProgress = 0.0
            exportPhase = ""
            exportErrorMessage = "Failed to export data: \(error.localizedDescription)"
            showExportError = true
        }
    }
    
    private func downloadTemplate() {
        let importExportService = ImportExportService()
        
        do {
            let fileURL = try importExportService.generateImportTemplate()
            templateURL = fileURL
        } catch {
            // Could show an error alert here
            print("Failed to generate template: \(error)")
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayName: String = ""
    @State private var selectedEmoji: String = ""
    @State private var selectedPhotoUrl: String = ""
    @State private var selectedPhotoImage: UIImage? = nil
    @State private var selectedColor: String = ""
    @State private var isSaving = false
    @State private var showEmojiInput = false
    @State private var showPhotoPicker = false
    @State private var imageUsage: (current: Int, limit: Int) = (0, 50)
    @State private var isLoadingUsage = false
    @State private var showLimitAlert = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isEmojiFieldFocused: Bool
    
    private let imageService = ImageService()
    
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
    
    /// Returns true if user has a photo selected (either new or existing)
    private var hasPhoto: Bool {
        selectedPhotoImage != nil || selectedPhotoUrl.isPhotoUrl
    }
    
    /// Returns the owner user ID for image counting/uploading
    private var ownerUserId: UUID? {
        // Find the owner of the current household
        authViewModel.members.first { $0.role == .owner }?.userId
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
                            avatarPreview
                            
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
                        
                        // Avatar Selection (Photo or Emoji)
                        avatarSelectionSection
                        
                        // Color Selection
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Profile Color")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Used as background when no photo is set")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
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
                let currentAvatar = authViewModel.currentMember?.avatarUrl ?? ""
                if currentAvatar.isPhotoUrl {
                    selectedPhotoUrl = currentAvatar
                    selectedEmoji = ""
                } else {
                    selectedEmoji = currentAvatar
                    selectedPhotoUrl = ""
                }
                selectedColor = authViewModel.currentMember?.color ?? ""
                loadImageUsage()
            }
            .sheet(isPresented: $showEmojiInput) {
                EmojiPickerSheet(
                    selectedEmoji: $selectedEmoji,
                    profileColor: selectedColor.isEmpty ? (authViewModel.currentMember?.color ?? "#4ECDC4") : selectedColor
                )
            }
            .sheet(isPresented: $showPhotoPicker) {
                ImagePickerView(selectedImage: $selectedPhotoImage)
            }
            .onChange(of: selectedEmoji) { _, newValue in
                // Clear photo when emoji is selected
                if !newValue.isEmpty {
                    selectedPhotoImage = nil
                    selectedPhotoUrl = ""
                }
            }
            .onChange(of: selectedPhotoImage) { _, newValue in
                // Clear emoji when photo is selected
                if newValue != nil {
                    selectedEmoji = ""
                    selectedPhotoUrl = ""
                }
            }
            .alert("Photo Limit Reached", isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You've used all \(imageUsage.limit) photo slots. Remove some photos from members or categories to add more.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(Color(hex: selectedColor.isEmpty ? (authViewModel.currentMember?.color ?? "#4ECDC4") : selectedColor))
                .frame(width: 100, height: 100)
            
            if let photoImage = selectedPhotoImage {
                // New photo selected
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
            } else if selectedPhotoUrl.isPhotoUrl {
                // Existing photo URL
                AsyncImage(url: URL(string: selectedPhotoUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    case .failure:
                        Text(previewInitials.isEmpty ? "?" : previewInitials)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if !selectedEmoji.isEmpty {
                Text(selectedEmoji)
                    .font(.system(size: 50))
            } else {
                Text(previewInitials.isEmpty ? "?" : previewInitials)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
    }
    
    @ViewBuilder
    private var avatarSelectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Profile Picture")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if hasPhoto || !selectedEmoji.isEmpty {
                    Button("Clear") {
                        selectedEmoji = ""
                        selectedPhotoImage = nil
                        selectedPhotoUrl = ""
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            // Photo usage indicator
            if isLoadingUsage {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading photo usage...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            } else {
                Text("\(imageUsage.current) of \(imageUsage.limit) photos used")
                    .font(.caption)
                    .foregroundStyle(imageUsage.current >= imageUsage.limit ? Theme.Colors.warning : Theme.Colors.textMuted)
            }
            
            HStack(spacing: Theme.Spacing.md) {
                // Photo picker button
                Button {
                    checkLimitAndShowPicker()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(hasPhoto ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.backgroundCard)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(hasPhoto ? Theme.Colors.accent : Color.clear, lineWidth: 2)
                            )
                        
                        if let photoImage = selectedPhotoImage {
                            Image(uiImage: photoImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md - 2))
                        } else if selectedPhotoUrl.isPhotoUrl {
                            AsyncImage(url: URL(string: selectedPhotoUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md - 2))
                                default:
                                    Image(systemName: "photo")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                            }
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.title)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("Photo")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
                
                // Emoji picker button
                Button {
                    showEmojiInput = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(!selectedEmoji.isEmpty ? Theme.Colors.accent.opacity(0.1) : Theme.Colors.backgroundCard)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(!selectedEmoji.isEmpty ? Theme.Colors.accent : Color.clear, lineWidth: 2)
                            )
                        
                        if selectedEmoji.isEmpty {
                            VStack(spacing: 4) {
                                Image(systemName: "face.smiling")
                                    .font(.title)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("Emoji")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        } else {
                            Text(selectedEmoji)
                                .font(.system(size: 40))
                        }
                    }
                }
                
                Spacer()
            }
            
            Text("Choose a photo or emoji, or leave blank to show your initials")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    private func loadImageUsage() {
        guard let ownerId = ownerUserId else { return }
        
        isLoadingUsage = true
        Task {
            do {
                let (_, current, limit) = try await imageService.canAddImage(ownerUserId: ownerId)
                await MainActor.run {
                    imageUsage = (current, limit)
                    isLoadingUsage = false
                }
            } catch {
                await MainActor.run {
                    isLoadingUsage = false
                }
            }
        }
    }
    
    private func checkLimitAndShowPicker() {
        // If user already has a photo, they can replace it (doesn't count as new)
        if hasPhoto {
            showPhotoPicker = true
            return
        }
        
        // Check if at limit
        if imageUsage.current >= imageUsage.limit {
            showLimitAlert = true
            return
        }
        
        showPhotoPicker = true
    }
    
    private func saveProfile() {
        isSaving = true
        
        Task {
            do {
            let nameToSave = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                var avatarToSave: String? = nil
                
                // Handle photo upload if new photo selected
                if let photoImage = selectedPhotoImage, let ownerId = ownerUserId {
                    // Get existing URL for potential deletion
                    let existingUrl = authViewModel.currentMember?.avatarUrl
                    
                    // Upload new photo
                    let uploadedUrl = try await imageService.uploadImage(
                        photoImage,
                        ownerUserId: ownerId,
                        existingUrl: existingUrl?.isPhotoUrl == true ? existingUrl : nil
                    )
                    avatarToSave = uploadedUrl
                } else if selectedPhotoUrl.isPhotoUrl {
                    // Keep existing photo URL
                    avatarToSave = selectedPhotoUrl
                } else if !selectedEmoji.isEmpty {
                    // Use emoji
                    avatarToSave = selectedEmoji
                } else {
                    // Clear avatar - check if we need to delete an old photo
                    let existingUrl = authViewModel.currentMember?.avatarUrl
                    if existingUrl?.isPhotoUrl == true {
                        try? await imageService.deleteImage(at: existingUrl!)
                    }
                    avatarToSave = nil
                }
                
            let colorToSave = selectedColor.isEmpty ? nil : selectedColor
            
            let success = await authViewModel.updateMyProfile(
                displayName: nameToSave,
                    emoji: avatarToSave,
                color: colorToSave
            )
            
                await MainActor.run {
            if success {
                dismiss()
            }
            isSaving = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Image Picker View

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
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
    let isOwner: Bool
    let isExporting: Bool
    let exportProgress: Double
    let exportPhase: String
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
                // Export - Owner only
                if isOwner {
                    if isExporting {
                        // Show progress view when exporting
                        ExportProgressView(progress: exportProgress, phase: exportPhase)
                    } else {
                        Button(action: onExport) {
                            SettingsRow(
                                icon: "square.and.arrow.up",
                                title: "Export Bank Data",
                                subtitle: "Download all data as Excel file",
                                showChevron: false
                            )
                        }
                    }
                    
                    Divider()
                        .background(Theme.Colors.borderLight)
                }
                
                // Import - Owner only
                if isOwner {
                    Button(action: onImport) {
                        SettingsRow(
                            icon: "square.and.arrow.down",
                            title: "Import Data",
                            subtitle: "Import from Excel file",
                            showChevron: true
                        )
                    }
                    
                    Divider()
                        .background(Theme.Colors.borderLight)
                }
                
                // Template download - Available to all
                Button(action: onDownloadTemplate) {
                    SettingsRow(
                        icon: "doc.text",
                        title: "Download Import Template",
                        subtitle: "Get an Excel template with examples",
                        showChevron: false
                    )
                }
            }
            .background(.regularMaterial)
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
            MemberAvatarView(member: member, size: 36, fontSize: 20)
                        .opacity(member.isInactive ? 0.6 : 1.0)
            
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
            MemberAvatarView(member: member, size: 36, fontSize: 20)
                        .opacity(0.7)
            
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
            .background(.regularMaterial)
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

// MARK: - Problematic Transactions Sheet

struct ProblematicTransactionsSheet: View {
    let transactions: [ProblematicTransaction]
    let isLoading: Bool
    let totalImbalance: Decimal
    let onTransactionTapped: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading...")
                } else if transactions.isEmpty {
                    emptyState
                } else {
                    transactionsList
                }
            }
            .navigationTitle("Problem Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.income)
            
            Text("No Problem Transactions Found")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("All transactions have valid split totals. The imbalance may be due to other factors.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            
            contactSupportButton
                .padding(.top, Theme.Spacing.lg)
        }
    }
    
    private var transactionsList: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                // Header info
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Found \(transactions.count) transaction\(transactions.count == 1 ? "" : "s") with split issues")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    Text("Tap a transaction to edit and fix the splits.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                
                // Transaction cards
                ForEach(transactions) { transaction in
                    Button {
                        onTransactionTapped(transaction.transactionId)
                    } label: {
                        ProblematicTransactionCard(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
                
                // Contact support section
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Need help?")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    contactSupportButton
                }
                .padding(.top, Theme.Spacing.lg)
                
                Spacer(minLength: 50)
            }
        }
    }
    
    private var contactSupportButton: some View {
        Button {
            openSupportEmail()
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                Text("Contact Support")
            }
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
    }
    
    private func openSupportEmail() {
        let subject = "Bank of Quack - Balance Issue Report"
        let body = """
        Hi,
        
        I'm experiencing a balance discrepancy in my household.
        
        --- Diagnostic Info ---
        Total Imbalance: \(totalImbalance.formatted(as: .standard, applyPrivacy: false))
        Problem Transactions: \(transactions.count)
        Transaction IDs: \(transactions.map { $0.transactionId.uuidString.prefix(8) }.joined(separator: ", "))
        
        [Please describe any additional context or steps to reproduce]
        
        Thanks!
        """
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // TODO: Replace with your actual support email
        if let url = URL(string: "mailto:support@bankofquack.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

struct ProblematicTransactionCard: View {
    let transaction: ProblematicTransaction
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.description)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(transaction.expectedAmount.formatted(as: .standard, applyPrivacy: false))
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    // Tap to edit hint
                    HStack(spacing: 2) {
                        Text("Tap to fix")
                            .font(.caption2)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            Divider()
            
            // Issue details
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Issue Details")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textMuted)
                
                HStack {
                    Text("Expected:")
                    Spacer()
                    Text(transaction.expectedAmount.formatted(as: .standard, applyPrivacy: false))
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                
                if abs(transaction.owedDifference) > 0.01 {
                    HStack {
                        Text("Owed sum:")
                        Spacer()
                        Text(transaction.actualOwedSum.formatted(as: .standard, applyPrivacy: false))
                        Text("(\(transaction.owedDifference > 0 ? "-" : "+")\(abs(transaction.owedDifference).formatted(as: .standard, applyPrivacy: false)))")
                            .foregroundStyle(Theme.Colors.error)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                if abs(transaction.paidDifference) > 0.01 {
                    HStack {
                        Text("Paid sum:")
                        Spacer()
                        Text(transaction.actualPaidSum.formatted(as: .standard, applyPrivacy: false))
                        Text("(\(transaction.paidDifference > 0 ? "-" : "+")\(abs(transaction.paidDifference).formatted(as: .standard, applyPrivacy: false)))")
                            .foregroundStyle(Theme.Colors.error)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            
            // Transaction ID for support
            HStack {
                Text("ID:")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textMuted)
                Text(transaction.transactionId.uuidString.prefix(8) + "...")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(Theme.Colors.error.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Export Progress View

struct ExportProgressView: View {
    let progress: Double
    let phase: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Exporting Bank Data...")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text(phase.isEmpty ? "Starting export..." : phase)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.accent)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.backgroundTertiary)
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.accent)
                        .frame(width: max(0, geometry.size.width * progress), height: 8)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
        }
        .background(Theme.Colors.backgroundSecondary)
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
}
