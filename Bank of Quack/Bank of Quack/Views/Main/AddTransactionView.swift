import SwiftUI
import Auth

struct AddTransactionView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var transactionType: TransactionType = .expense
    @State private var amount = ""
    @State private var description = ""
    @State private var date = Date()
    @State private var paidByMemberId: UUID?
    @State private var paidToMemberId: UUID?
    @State private var categoryId: UUID?
    @State private var splitType: SplitType = .equal
    @State private var paidByType: PaidByType = .single
    @State private var splitMemberId: UUID?
    @State private var reimbursesTransactionId: UUID?
    @State private var notes = ""
    @State private var excludedFromBudget = false
    
    // Custom split state
    @State private var memberSplits: [MemberSplit] = []
    @State private var showCustomSplitEditor = false
    @State private var showCustomPaidByEditor = false
    @State private var splitValidationError: String?
    @State private var paidByValidationError: String?
    
    // Multi-select member state (for equal split between subset of members)
    @State private var selectedSplitMemberIds: Set<UUID> = []
    @State private var selectedPaidByMemberIds: Set<UUID> = []
    
    // Member balances (for filtering inactive members in settlements)
    @State private var memberBalances: [MemberBalance] = []
    private let dataService = DataService()
    
    @State private var showDatePicker = false
    @State private var showCategoryPicker = false
    @State private var showPaidByPicker = false
    @State private var showReceivedByPicker = false
    @State private var showPaidToPicker = false
    @State private var showSplitMemberPicker = false
    @State private var showNotes = false
    @State private var showExpensePicker = false
    @State private var showSuggestedSettlements = false
    @State private var showTemplatePicker = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case amount
        case description
        case notes
        case splitAmount(UUID)
        case splitPercentage(UUID)
        case paidAmount(UUID)
        case paidPercentage(UUID)
    }
    
    private var parsedAmount: Decimal {
        Decimal(string: amount) ?? 0
    }
    
    /// Active members only (for new expenses, income, reimbursements)
    private var activeMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isActive }
    }
    
    /// Members eligible for settlements (includes inactive members only if they have non-zero balance)
    private var settlementEligibleMembers: [HouseholdMember] {
        authViewModel.members.filter { member in
            // Active members are always eligible
            if member.isActive { return true }
            
            // Inactive members are only eligible if they have a non-zero balance
            if let balance = memberBalances.first(where: { $0.memberId == member.id }) {
                return abs(balance.balance.doubleValue) >= 0.01
            }
            
            // If no balance data yet, exclude inactive members
            return false
        }
    }
    
    /// Alias for backward compatibility - used for most transaction types
    private var approvedMembers: [HouseholdMember] {
        activeMembers
    }
    
    /// Check if settlements should be available as a transaction type
    /// Hide settlements when: only one active member AND no inactive members with non-zero balance
    private var shouldShowSettlementOption: Bool {
        // If there are multiple active members, settlements make sense
        if activeMembers.count > 1 {
            return true
        }
        
        // Single active member: check if any inactive member has a non-zero balance
        // (meaning there could still be settling to do with departed members)
        let inactiveMembersWithBalance = authViewModel.members.filter { member in
            guard member.isInactive else { return false }
            if let balance = memberBalances.first(where: { $0.memberId == member.id }) {
                return abs(balance.balance.doubleValue) >= 0.01
            }
            return false
        }
        
        return !inactiveMembersWithBalance.isEmpty
    }
    
    /// Transaction types available for selection (may exclude settlement for single-member households)
    private var availableTransactionTypes: [TransactionType] {
        if shouldShowSettlementOption {
            return TransactionType.allCases
        } else {
            return TransactionType.allCases.filter { $0 != .settlement }
        }
    }
    
    private var isFormValid: Bool {
        guard parsedAmount > 0 else { return false }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        switch transactionType {
        case .expense:
            // Validate paid by
            if paidByType == .single && paidByMemberId == nil { return false }
            if paidByType == .custom && paidByValidationError != nil { return false }
            
            // Validate split
            if splitType == .memberOnly && splitMemberId == nil { return false }
            if splitType == .custom && splitValidationError != nil { return false }
            
            return categoryId != nil
        case .income:
            // Income requires someone to have received it
            return paidByMemberId != nil
        case .settlement:
            return paidByMemberId != nil && paidToMemberId != nil && paidByMemberId != paidToMemberId
        case .reimbursement:
            // Check that reimbursement amount doesn't exceed remaining expense amount
            if reimbursementExceedsExpense { return false }
            return paidByMemberId != nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Transaction Type Selector + Template Button
                        HStack(spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(availableTransactionTypes, id: \.self) { type in
                                    TransactionTypeButton(
                                        type: type,
                                        isSelected: transactionType == type
                                    ) {
                                        withAnimation {
                                            switchTransactionType(to: type)
                                        }
                                    }
                                }
                            }
                            
                            // Template Button
                            if !authViewModel.templates.isEmpty {
                                Button {
                                    showTemplatePicker = true
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Theme.Colors.accent)
                                        .frame(width: 44, height: 44)
                                        .background(Theme.Colors.accent.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        // Amount Input
                        VStack(spacing: Theme.Spacing.xs) {
                            Text("Amount")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("$")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("0", text: $amount)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .focused($focusedField, equals: .amount)
                                    .onChange(of: amount) { _, _ in
                                        updateMemberSplitsForAmount()
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = .amount
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        
                        // Form Fields
                        VStack(spacing: Theme.Spacing.md) {
                            // Description
                            FormField(label: "Description") {
                                TextField("What was this for?", text: $description)
                                    .inputFieldStyle()
                                    .focused($focusedField, equals: .description)
                            }
                            
                            // Date + Category Row (side by side for expenses)
                            if transactionType == .expense {
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    // Date (left side)
                                    FormField(label: "Date") {
                                        Button {
                                            showDatePicker.toggle()
                                        } label: {
                                            HStack {
                                                Text(date.formatted(as: .dayMonth))
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                Spacer()
                                                Image(systemName: "calendar")
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                            }
                                            .inputFieldStyle()
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    
                                    // Category (right side)
                                    FormField(label: "Category") {
                                        CategoryPickerButton(
                                            categories: authViewModel.categories,
                                            selectedId: categoryId
                                        ) {
                                            showCategoryPicker = true
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            } else {
                                // Date only for non-expense types
                                FormField(label: "Date") {
                                    Button {
                                        showDatePicker.toggle()
                                    } label: {
                                        HStack {
                                            Text(date.formatted(as: .weekdayDayMonth))
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                            Spacer()
                                            Image(systemName: "calendar")
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        .inputFieldStyle()
                                    }
                                }
                            }
                            
                            if showDatePicker {
                                DatePicker(
                                    "",
                                    selection: $date,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .tint(Theme.Colors.accent)
                                .colorScheme(Theme.Colors.isLightMode ? .light : .dark)
                                .onChange(of: date) { _, _ in
                                    withAnimation {
                                        showDatePicker = false
                                    }
                                }
                            }
                            
                            // Paid By Section (for expense, settlement only)
                            // Hide for single-member households on expenses (always current user)
                            if transactionType == .settlement || (transactionType == .expense && activeMembers.count > 1) {
                                paidBySection
                            }
                            
                            // Received By (for income and reimbursement)
                            // Hide for single-member households (always current user)
                            if (transactionType == .income || transactionType == .reimbursement) && activeMembers.count > 1 {
                                FormField(label: "Received By") {
                                    if approvedMembers.count > 5 {
                                        MemberPickerButton(
                                            members: approvedMembers,
                                            selectedId: paidByMemberId,
                                            excludeId: nil
                                        ) {
                                            showReceivedByPicker = true
                                        }
                                    } else {
                                        MemberSelector(
                                            members: approvedMembers,
                                            selectedId: $paidByMemberId,
                                            excludeId: nil
                                        )
                                    }
                                }
                                .sheet(isPresented: $showReceivedByPicker) {
                                    MemberPickerSheet(
                                        members: approvedMembers,
                                        excludeId: nil,
                                        title: "Received By",
                                        selectedId: $paidByMemberId
                                    )
                                    .presentationDetents([.medium])
                                }
                            }
                            
                            // Link to Expense (for reimbursement - optional)
                            if transactionType == .reimbursement {
                                reimbursementLinkSection
                            }
                            
                            // Paid To (for settlement - includes inactive members for settling balances)
                            if transactionType == .settlement {
                                FormField(label: "Paid To") {
                                    if settlementEligibleMembers.count > 5 {
                                        MemberPickerButton(
                                            members: settlementEligibleMembers,
                                            selectedId: paidToMemberId,
                                            excludeId: paidByMemberId
                                        ) {
                                            showPaidToPicker = true
                                        }
                                    } else {
                                        MemberSelector(
                                            members: settlementEligibleMembers,
                                            selectedId: $paidToMemberId,
                                            excludeId: paidByMemberId
                                        )
                                    }
                                }
                                .sheet(isPresented: $showPaidToPicker) {
                                    MemberPickerSheet(
                                        members: settlementEligibleMembers,
                                        excludeId: paidByMemberId,
                                        title: "Paid To",
                                        selectedId: $paidToMemberId
                                    )
                                    .presentationDetents([.medium])
                                }
                                
                                // Current Balances Card
                                settlementBalancesCard
                            }
                            
                            // Split Type Section (for expense only, moved category to date row)
                            if transactionType == .expense {
                                if approvedMembers.count > 1 {
                                    splitSection
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Notes (expandable, shown above buttons)
                        if showNotes {
                            FormField(label: "Notes") {
                                TextField("Add any notes...", text: $notes, axis: .vertical)
                                    .lineLimit(3...5)
                                    .inputFieldStyle()
                                    .focused($focusedField, equals: .notes)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Submit Button + Notes Icon
                        HStack(spacing: Theme.Spacing.sm) {
                            // Add Transaction Button (80%)
                            Button {
                                submitTransaction()
                            } label: {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(Theme.Colors.textInverse)
                                } else {
                                    Text("Add Transaction")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isFormValid || isSubmitting)
                            .frame(maxWidth: .infinity)
                            .id("addTransaction-\(themeProvider.currentPalette.id)")
                            
                            // Notes Icon Button (20%)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showNotes.toggle()
                                }
                            } label: {
                                Image(systemName: showNotes ? "note.text" : "note.text.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(showNotes ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                    .frame(width: 56, height: 56)
                                    .background(showNotes ? Theme.Colors.accent.opacity(0.2) : Theme.Colors.backgroundCard)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
        }
        .onAppear {
            initializeMemberSplits()
            // Set default paid by to current member
            if paidByMemberId == nil {
                paidByMemberId = authViewModel.currentMember?.id
            }
        }
        .task {
            // Fetch member balances for filtering inactive members in settlements
            await fetchMemberBalances()
        }
        .onChange(of: approvedMembers.map { $0.id }) { _, newMemberIds in
            // Re-initialize splits when active members change (e.g., member becomes inactive)
            let currentMemberIds = Set(memberSplits.map { $0.memberId })
            let newMemberIdSet = Set(newMemberIds)
            if currentMemberIds != newMemberIdSet {
                initializeMemberSplits()
                updateMemberSplitsForAmount()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                resetForm()
            }
        } message: {
            Text("Transaction added successfully!")
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(
                categories: authViewModel.categories,
                sectors: authViewModel.sectors,
                sectorCategories: authViewModel.sectorCategories,
                selectedId: $categoryId
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerSheet(
                templates: authViewModel.templates,
                categories: authViewModel.categories,
                onSelect: { template in
                    applyTemplate(template)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Template Application
    
    private func applyTemplate(_ template: TransactionTemplate) {
        withAnimation {
            transactionType = template.transactionType
            amount = "\(template.amount)"
            description = template.description
            categoryId = template.categoryId
            // Map 'custom' back to 'equal' for UI display
            // (templates that were 'equal' are now stored as 'custom' after migration)
            splitType = template.splitType == .custom ? .equal : template.splitType
            // Map 'custom' back to 'shared' for UI display
            paidByType = template.paidByType == .custom ? .shared : template.paidByType
            splitMemberId = template.splitMemberId
            excludedFromBudget = template.excludedFromBudget
            notes = template.notes ?? ""
            showNotes = !notes.isEmpty
            
            // Set paid by member if specified in template, otherwise use current member
            if let templatePaidBy = template.paidByMemberId {
                paidByMemberId = templatePaidBy
            } else if activeMembers.count == 1 {
                paidByMemberId = authViewModel.currentMember?.id
            }
            
            // Re-initialize member splits for equal/shared types
            if splitType == .equal || paidByType == .shared {
                initializeMemberSplits()
            }
        }
    }
    
    // MARK: - Paid By Section
    
    /// Members to use for the paid by section based on transaction type
    private var paidByMemberList: [HouseholdMember] {
        transactionType == .settlement ? settlementEligibleMembers : approvedMembers
    }
    
    private var paidBySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Paid By")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // For settlements and reimbursements, only allow single member selection
            if transactionType == .settlement || transactionType == .reimbursement {
                if paidByMemberList.count > 5 {
                    // Use sheet picker for 6+ members
                    MemberPickerButton(
                        members: paidByMemberList,
                        selectedId: paidByMemberId,
                        excludeId: transactionType == .settlement ? paidToMemberId : nil
                    ) {
                        showPaidByPicker = true
                    }
                } else {
                    MemberSelector(
                        members: paidByMemberList,
                        selectedId: $paidByMemberId,
                        excludeId: transactionType == .settlement ? paidToMemberId : nil
                    )
                }
            } else if approvedMembers.count > 1 {
                // Multi-select member selector for expenses
                MultiSelectMemberSelector(
                    members: approvedMembers,
                    selectedMemberIds: $selectedPaidByMemberIds,
                    isCustomSelected: showCustomPaidByEditor,
                    onSelectAll: {
                        withAnimation {
                            // Select all members
                            selectedPaidByMemberIds = Set(approvedMembers.map { $0.id })
                            paidByType = .custom
                            paidByMemberId = nil
                            showCustomPaidByEditor = false
                            updateMemberSplitsForSelectedPaidByMembers()
                        }
                    },
                    onSelectCustom: {
                        withAnimation {
                            paidByType = .custom
                            paidByMemberId = nil
                            selectedPaidByMemberIds.removeAll()
                            showCustomPaidByEditor = true
                            clearCustomPaidByAmounts()
                        }
                    },
                    onToggleMember: { memberId in
                        withAnimation {
                            togglePaidByMember(memberId)
                        }
                    }
                )
                
                // Show summary when multiple members are selected (not useful for single member)
                if selectedPaidByMemberIds.count > 1 && !showCustomPaidByEditor {
                    paidBySummaryView
                }
                
                // Custom Paid By Editor
                if showCustomPaidByEditor && paidByType == .custom {
                    CustomSplitEditor(
                        title: "Who paid how much?",
                        memberSplits: $memberSplits,
                        totalAmount: parsedAmount,
                        editingPaidAmount: true,
                        validationError: $paidByValidationError
                    )
                }
            } else {
                // Single member household - just show who paid
                MemberSelector(
                    members: approvedMembers,
                    selectedId: $paidByMemberId,
                    excludeId: nil
                )
            }
        }
        .sheet(isPresented: $showPaidByPicker) {
            MemberPickerSheet(
                members: paidByMemberList,
                excludeId: transactionType == .settlement ? paidToMemberId : nil,
                title: "Who Paid?",
                selectedId: $paidByMemberId
            )
            .presentationDetents([.medium])
            .onDisappear {
                if paidByMemberId != nil && paidByType != .shared && paidByType != .custom {
                    paidByType = .single
                    updateMemberSplitsForPaidByType()
                }
            }
        }
    }
    
    /// Summary view showing equal paid split between selected members
    private var paidBySummaryView: some View {
        let selectedCount = selectedPaidByMemberIds.count
        let shareAmount = selectedCount > 0 ? parsedAmount / Decimal(selectedCount) : 0
        let selectedNames = approvedMembers
            .filter { selectedPaidByMemberIds.contains($0.id) }
            .map { $0.displayName }
        
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("Paid equally by \(selectedCount) members")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Text(selectedNames.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            
            if parsedAmount > 0 {
                Text("\(shareAmount.doubleValue.formattedAsMoney()) each")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
    }
    
    /// Toggle a member's selection for paid by
    private func togglePaidByMember(_ memberId: UUID) {
        // Exit "All" or "Custom" mode when toggling individual members
        showCustomPaidByEditor = false
        
        if selectedPaidByMemberIds.contains(memberId) {
            selectedPaidByMemberIds.remove(memberId)
        } else {
            selectedPaidByMemberIds.insert(memberId)
        }
        
        // Update paid by type based on selection
        if selectedPaidByMemberIds.isEmpty {
            // No members selected - revert to shared
            paidByType = .shared
            paidByMemberId = nil
        } else if selectedPaidByMemberIds.count == 1 {
            // Single member selected
            paidByType = .single
            paidByMemberId = selectedPaidByMemberIds.first
        } else {
            // Multiple members selected - use custom with equal amounts
            paidByType = .custom
            paidByMemberId = nil
        }
        
        updateMemberSplitsForSelectedPaidByMembers()
    }
    
    /// Update member splits based on selected paid by members (equal split among selected)
    private func updateMemberSplitsForSelectedPaidByMembers() {
        let total = parsedAmount
        let selectedCount = selectedPaidByMemberIds.isEmpty ? approvedMembers.count : selectedPaidByMemberIds.count
        guard selectedCount > 0 else { return }
        
        for i in memberSplits.indices {
            let isSelected = selectedPaidByMemberIds.isEmpty || selectedPaidByMemberIds.contains(memberSplits[i].memberId)
            
            if isSelected {
                // Calculate equal share for selected members
                let shareIndex = selectedPaidByMemberIds.isEmpty ? i :
                    Array(selectedPaidByMemberIds.sorted()).firstIndex(of: memberSplits[i].memberId) ?? 0
                let equalShare = Decimal.calculateEqualShare(total: total, memberCount: selectedCount, memberIndex: shareIndex)
                let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: selectedCount, memberIndex: shareIndex)
                memberSplits[i].paidAmount = equalShare
                memberSplits[i].paidPercentage = equalPercentage
            } else {
                // Not selected - zero out
                memberSplits[i].paidAmount = 0
                memberSplits[i].paidPercentage = 0
            }
        }
        
        paidByValidationError = nil
    }
    
    // MARK: - Split Section (Expense For)
    
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Expense For")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // Multi-select member selector
            MultiSelectMemberSelector(
                members: approvedMembers,
                selectedMemberIds: $selectedSplitMemberIds,
                isCustomSelected: showCustomSplitEditor,
                onSelectAll: {
                    withAnimation {
                        // Select all members
                        selectedSplitMemberIds = Set(approvedMembers.map { $0.id })
                        splitType = .custom
                        splitMemberId = nil
                        showCustomSplitEditor = false
                        updateMemberSplitsForSelectedMembers()
                    }
                },
                onSelectCustom: {
                    withAnimation {
                        splitType = .custom
                        splitMemberId = nil
                        selectedSplitMemberIds.removeAll()
                        showCustomSplitEditor = true
                        clearCustomSplitAmounts()
                    }
                },
                onToggleMember: { memberId in
                    withAnimation {
                        toggleSplitMember(memberId)
                    }
                }
            )
            
            // Show summary when multiple members are selected (not useful for single member)
            if selectedSplitMemberIds.count > 1 && !showCustomSplitEditor {
                splitSummaryView
            }
            
            // Custom Split Editor
            if showCustomSplitEditor && splitType == .custom {
                CustomSplitEditor(
                    title: "Who owes how much?",
                    memberSplits: $memberSplits,
                    totalAmount: parsedAmount,
                    editingPaidAmount: false,
                    validationError: $splitValidationError
                )
            }
        }
    }
    
    /// Summary view showing equal split between selected members
    private var splitSummaryView: some View {
        let selectedCount = selectedSplitMemberIds.count
        let shareAmount = selectedCount > 0 ? parsedAmount / Decimal(selectedCount) : 0
        let selectedNames = approvedMembers
            .filter { selectedSplitMemberIds.contains($0.id) }
            .map { $0.displayName }
        
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("Split equally between \(selectedCount) members")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Text(selectedNames.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
            
            if parsedAmount > 0 {
                Text("\(shareAmount.doubleValue.formattedAsMoney()) each")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
    }
    
    /// Toggle a member's selection for split
    private func toggleSplitMember(_ memberId: UUID) {
        // Exit "All" or "Custom" mode when toggling individual members
        showCustomSplitEditor = false
        
        if selectedSplitMemberIds.contains(memberId) {
            selectedSplitMemberIds.remove(memberId)
        } else {
            selectedSplitMemberIds.insert(memberId)
        }
        
        // Update split type based on selection
        if selectedSplitMemberIds.isEmpty {
            // No members selected - revert to all
            splitType = .equal
        } else if selectedSplitMemberIds.count == 1 {
            // Single member selected
            splitType = .memberOnly
            splitMemberId = selectedSplitMemberIds.first
        } else {
            // Multiple members selected - use custom with equal amounts
            splitType = .custom
            splitMemberId = nil
        }
        
        updateMemberSplitsForSelectedMembers()
    }
    
    /// Update member splits based on selected members (equal split among selected)
    private func updateMemberSplitsForSelectedMembers() {
        let total = parsedAmount
        let selectedCount = selectedSplitMemberIds.isEmpty ? approvedMembers.count : selectedSplitMemberIds.count
        guard selectedCount > 0 else { return }
        
        for i in memberSplits.indices {
            let isSelected = selectedSplitMemberIds.isEmpty || selectedSplitMemberIds.contains(memberSplits[i].memberId)
            
            if isSelected {
                // Calculate equal share for selected members
                let shareIndex = selectedSplitMemberIds.isEmpty ? i : 
                    Array(selectedSplitMemberIds.sorted()).firstIndex(of: memberSplits[i].memberId) ?? 0
                let equalShare = Decimal.calculateEqualShare(total: total, memberCount: selectedCount, memberIndex: shareIndex)
                let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: selectedCount, memberIndex: shareIndex)
                memberSplits[i].owedAmount = equalShare
                memberSplits[i].owedPercentage = equalPercentage
            } else {
                // Not selected - zero out
                memberSplits[i].owedAmount = 0
                memberSplits[i].owedPercentage = 0
            }
        }
        
        splitValidationError = nil
    }
    
    // MARK: - Reimbursement Link Section
    
    private var reimbursementLinkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Link to Expense (Optional)")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            ExpensePickerButton(
                expenses: linkableExpenses,
                selectedId: reimbursesTransactionId
            ) {
                showExpensePicker = true
            }
            
            if reimbursesTransactionId == nil {
                Text("Unlinked reimbursements will count as income")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textMuted)
            } else if let remaining = remainingReimbursableAmount {
                if reimbursementExceedsExpense {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Amount exceeds remaining \(remaining.doubleValue.formattedAsMoney(applyPrivacy: false))")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.error)
                } else {
                    Text("Remaining: \(remaining.doubleValue.formattedAsMoney(applyPrivacy: false)) of \(selectedExpense?.amount.doubleValue.formattedAsMoney(applyPrivacy: false) ?? "$0.00")")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            } else {
                Text("Linked reimbursements reduce the original expense value")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .sheet(isPresented: $showExpensePicker) {
            ExpensePickerSheet(
                expenses: linkableExpenses,
                selectedId: $reimbursesTransactionId
            )
            .presentationDetents([.medium, .large])
        }
    }
    
    /// Expenses that can be linked to for reimbursement
    private var linkableExpenses: [TransactionView] {
        transactionViewModel.transactions.filter { $0.transactionType == .expense }
    }
    
    /// Calculate total reimbursements already applied to a specific expense
    private func existingReimbursements(for expenseId: UUID) -> Decimal {
        transactionViewModel.transactions
            .filter { $0.transactionType == .reimbursement && $0.reimbursesTransactionId == expenseId }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// The selected expense for reimbursement (if any)
    private var selectedExpense: TransactionView? {
        guard let id = reimbursesTransactionId else { return nil }
        return transactionViewModel.transactions.first { $0.id == id }
    }
    
    /// Remaining amount that can be reimbursed for the selected expense
    private var remainingReimbursableAmount: Decimal? {
        guard let expense = selectedExpense else { return nil }
        let existing = existingReimbursements(for: expense.id)
        return max(expense.amount - existing, 0)
    }
    
    /// Whether the current reimbursement amount exceeds the remaining reimbursable amount
    private var reimbursementExceedsExpense: Bool {
        guard transactionType == .reimbursement,
              let remaining = remainingReimbursableAmount else { return false }
        return parsedAmount > remaining
    }
    
    // MARK: - Settlement Balances Card
    
    /// Projected balance changes based on current form state
    private var projectedBalanceChanges: [(member: HouseholdMember, currentBalance: Decimal, change: Decimal, newBalance: Decimal)] {
        guard parsedAmount > 0 else { return [] }
        
        var changes: [(HouseholdMember, Decimal, Decimal, Decimal)] = []
        
        switch transactionType {
        case .expense:
            // For expenses, calculate from splits
            for split in memberSplits {
                guard let member = authViewModel.members.first(where: { $0.id == split.memberId }) else { continue }
                let currentBalance = memberBalances.first { $0.memberId == member.id }?.balance ?? 0
                let change = split.paidAmount - split.owedAmount
                
                // Only include if there's a meaningful change
                if abs(change) > 0.001 {
                    changes.append((member, currentBalance, change, currentBalance + change))
                }
            }
            
        case .settlement:
            // Settlement: payer pays to settle up (balance increases), recipient receives (balance decreases)
            if let payerId = paidByMemberId,
               let payer = authViewModel.members.first(where: { $0.id == payerId }) {
                let currentBalance = memberBalances.first { $0.memberId == payer.id }?.balance ?? 0
                changes.append((payer, currentBalance, parsedAmount, currentBalance + parsedAmount))
            }
            if let recipientId = paidToMemberId,
               let recipient = authViewModel.members.first(where: { $0.id == recipientId }) {
                let currentBalance = memberBalances.first { $0.memberId == recipient.id }?.balance ?? 0
                changes.append((recipient, currentBalance, -parsedAmount, currentBalance - parsedAmount))
            }
            
        case .reimbursement:
            // Reimbursements are more complex - simplified view for preview
            if let recipientId = paidByMemberId,
               let recipient = authViewModel.members.first(where: { $0.id == recipientId }) {
                let currentBalance = memberBalances.first { $0.memberId == recipient.id }?.balance ?? 0
                // Simplified: recipient's balance typically decreases (they received money)
                changes.append((recipient, currentBalance, -parsedAmount, currentBalance - parsedAmount))
            }
            
        case .income:
            // Income doesn't affect balances
            break
        }
        
        return changes.sorted { abs($0.2) > abs($1.2) }
    }
    
    /// Whether to show the balance preview (valid form state with meaningful changes)
    private var shouldShowBalancePreview: Bool {
        !projectedBalanceChanges.isEmpty && parsedAmount > 0
    }
    
    /// Suggested settlements for the inline expandable section
    private var inlineSuggestedSettlements: [(from: MemberBalance, to: MemberBalance, amount: Double)] {
        let filteredBalances = memberBalances.filter { balance in
            if let member = authViewModel.members.first(where: { $0.id == balance.memberId }),
               member.isInactive,
               abs(balance.balance.doubleValue) < 0.01 {
                return false
            }
            return true
        }
        
        let creditors = filteredBalances.filter { $0.balance.doubleValue > 0.01 }
            .sorted { $0.balance.doubleValue > $1.balance.doubleValue }
        let debtors = filteredBalances.filter { $0.balance.doubleValue < -0.01 }
            .sorted { $0.balance.doubleValue < $1.balance.doubleValue }
        
        var settlements: [(from: MemberBalance, to: MemberBalance, amount: Double)] = []
        var debtorsCopy = debtors.map { ($0, abs($0.balance.doubleValue)) }
        var creditorsCopy = creditors.map { ($0, $0.balance.doubleValue) }
        
        var i = 0, j = 0
        while i < debtorsCopy.count && j < creditorsCopy.count {
            let (debtor, debtAmount) = debtorsCopy[i]
            let (creditor, creditAmount) = creditorsCopy[j]
            
            let settlementAmount = min(debtAmount, creditAmount)
            if settlementAmount >= 0.01 {
                settlements.append((from: debtor, to: creditor, amount: settlementAmount))
            }
            
            debtorsCopy[i].1 -= settlementAmount
            creditorsCopy[j].1 -= settlementAmount
            
            if debtorsCopy[i].1 < 0.01 { i += 1 }
            if creditorsCopy[j].1 < 0.01 { j += 1 }
        }
        
        return settlements
    }
    
    private var settlementBalancesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Current Balances")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            if memberBalances.isEmpty {
                // Loading or empty state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading balances...")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(.vertical, Theme.Spacing.sm)
            } else {
                // Member balances with avatars
                VStack(spacing: 0) {
                    ForEach(sortedBalances, id: \.memberId) { balance in
                        let member = authViewModel.members.first { $0.id == balance.memberId }
                        
                        HStack(spacing: Theme.Spacing.sm) {
                            // Avatar/Emoji
                            if let member = member {
                                InlineMemberAvatar(member: member, size: 32)
                            } else {
                                Circle()
                                    .fill(Theme.Colors.textMuted)
                                    .frame(width: 32, height: 32)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(balance.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                
                                Text(balanceStatusText(for: balance.balance))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Text(abs(balance.balance.doubleValue).formattedAsMoney(showSign: false))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(balanceColor(for: balance.balance))
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                        .padding(.horizontal, Theme.Spacing.sm)
                        
                        if balance.memberId != sortedBalances.last?.memberId {
                            Divider()
                                .background(Theme.Colors.borderLight)
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                
                // Expandable Suggested Settlements
                if !inlineSuggestedSettlements.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSuggestedSettlements.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: showSuggestedSettlements ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .frame(width: 16)
                                
                                Text("Suggested Settlements")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                Text("(\(inlineSuggestedSettlements.count))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        if showSuggestedSettlements {
                            VStack(spacing: Theme.Spacing.sm) {
                                ForEach(inlineSuggestedSettlements.indices, id: \.self) { index in
                                    let settlement = inlineSuggestedSettlements[index]
                                    let fromMember = authViewModel.members.first { $0.id == settlement.from.memberId }
                                    let toMember = authViewModel.members.first { $0.id == settlement.to.memberId }
                                    
                                    Button {
                                        // Pre-fill the settlement form
                                        paidByMemberId = settlement.from.memberId
                                        paidToMemberId = settlement.to.memberId
                                        self.amount = String(format: "%.2f", abs(settlement.amount))
                                    } label: {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            // From member avatar
                                            if let member = fromMember {
                                                InlineMemberAvatar(member: member, size: 24)
                                            }
                                            
                                            Text(settlement.from.displayName)
                                                .font(.caption)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                                .lineLimit(1)
                                            
                                            Image(systemName: "arrow.right")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.Colors.accent)
                                            
                                            // To member avatar
                                            if let member = toMember {
                                                InlineMemberAvatar(member: member, size: 24)
                                            }
                                            
                                            Text(settlement.to.displayName)
                                                .font(.caption)
                                                .foregroundStyle(Theme.Colors.textPrimary)
                                                .lineLimit(1)
                                            
                                            Spacer()
                                            
                                            Text(settlement.amount.formattedAsMoney(showSign: false))
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(Theme.Colors.accent)
                                        }
                                        .padding(Theme.Spacing.sm)
                                        .background(Theme.Colors.backgroundCard)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                                .strokeBorder(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                
                // Balance Preview (when form has valid data)
                if shouldShowBalancePreview {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("Preview: After this transaction")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        
                        VStack(spacing: Theme.Spacing.xs) {
                            ForEach(projectedBalanceChanges, id: \.member.id) { item in
                                HStack(spacing: Theme.Spacing.sm) {
                                    // Member avatar
                                    InlineMemberAvatar(member: item.member, size: 24)
                                    
                                    Text(item.member.displayName)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    // Current → New balance
                                    HStack(spacing: 4) {
                                        Text(formatBalanceCompact(item.currentBalance))
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textMuted)
                                        
                                        Image(systemName: "arrow.right")
                                            .font(.caption2)
                                            .foregroundStyle(Theme.Colors.textMuted)
                                        
                                        Text(formatBalanceCompact(item.newBalance))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(item.newBalance >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                    }
                                    
                                    // Change indicator
                                    Text("(\(item.change >= 0 ? "+" : "")\(formatBalanceCompact(item.change)))")
                                        .font(.caption2)
                                        .foregroundStyle(item.change >= 0 ? Theme.Colors.success : Theme.Colors.error)
                                }
                            }
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                                .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
            }
            
            // Helper text (legend)
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.Colors.income)
                        .frame(width: 6, height: 6)
                    Text("owed")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.Colors.expense)
                        .frame(width: 6, height: 6)
                    Text("owes")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }
    
    private func formatBalanceCompact(_ balance: Decimal) -> String {
        let value = abs(balance.doubleValue)
        let sign = balance >= 0 ? "" : "-"
        return "\(sign)\(value.formattedAsMoney(showSign: false))"
    }
    
    private func balanceStatusText(for balance: Decimal) -> String {
        let value = balance.doubleValue
        if abs(value) < 0.01 {
            return "Settled"
        } else if value > 0 {
            return "is owed"
        } else {
            return "owes"
        }
    }
    
    private var sortedBalances: [MemberBalance] {
        memberBalances
            .filter { balance in
                // Hide inactive members with zero balance
                if let member = authViewModel.members.first(where: { $0.id == balance.memberId }),
                   member.isInactive,
                   abs(balance.balance.doubleValue) < 0.01 {
                    return false
                }
                return true
            }
            .sorted { abs($0.balance.doubleValue) > abs($1.balance.doubleValue) }
    }
    
    private func balanceColor(for balance: Decimal) -> Color {
        let value = balance.doubleValue
        if abs(value) < 0.01 {
            return Theme.Colors.textSecondary
        } else if value > 0 {
            return Theme.Colors.income // Owed money (positive)
        } else {
            return Theme.Colors.expense // Owes money (negative)
        }
    }
    
    // MARK: - Helper Methods
    
    private func fetchMemberBalances() async {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        do {
            let balances = try await dataService.fetchMemberBalances(householdId: householdId)
            await MainActor.run {
                memberBalances = balances
            }
        } catch {
            // Silently fail - we'll just show all members if balance fetch fails
            print("Failed to fetch member balances: \(error)")
        }
    }
    
    private func switchTransactionType(to newType: TransactionType) {
        let oldType = transactionType
        transactionType = newType
        
        // Clear type-specific fields when switching types
        if oldType != newType {
            // Clear expense-specific fields
            if oldType == .expense {
                categoryId = nil
                splitType = .equal
                splitMemberId = nil
                showCustomSplitEditor = false
                paidByType = .single
                showCustomPaidByEditor = false
            }
            
            // Clear settlement-specific fields
            if oldType == .settlement {
                paidToMemberId = nil
            }
            
            // Clear reimbursement-specific fields
            if oldType == .reimbursement {
                reimbursesTransactionId = nil
            }
            
            // Reset paid by to current user when switching to a type that uses it
            if newType == .expense || newType == .settlement || newType == .reimbursement || newType == .income {
                paidByMemberId = authViewModel.currentMember?.id
                paidByType = .single
            }
            
            // Re-initialize member splits for expenses
            if newType == .expense {
                initializeMemberSplits()
                updateMemberSplitsForAmount()
            }
        }
    }
    
    private func initializeMemberSplits() {
        memberSplits = approvedMembers.map { member in
            MemberSplit(member: member, totalAmount: parsedAmount, memberCount: approvedMembers.count)
        }
        
        // By default, select just the current user for both split and paid by
        if let currentMemberId = paidByMemberId ?? authViewModel.currentMember?.id {
            selectedSplitMemberIds = [currentMemberId]
            selectedPaidByMemberIds = [currentMemberId]
        }
    }
    
    private func updateMemberSplitsForAmount() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        // Calculate counts for selected subsets (if any)
        let splitSelectedCount = selectedSplitMemberIds.isEmpty ? memberCount : selectedSplitMemberIds.count
        let paidBySelectedCount = selectedPaidByMemberIds.isEmpty ? memberCount : selectedPaidByMemberIds.count
        
        for i in memberSplits.indices {
            let memberId = memberSplits[i].memberId
            
            // Determine if this member is in the split selection
            let isInSplitSelection = selectedSplitMemberIds.isEmpty || selectedSplitMemberIds.contains(memberId)
            let splitShareIndex = selectedSplitMemberIds.isEmpty ? i :
                Array(selectedSplitMemberIds.sorted()).firstIndex(of: memberId) ?? 0
            
            // Determine if this member is in the paid by selection
            let isInPaidBySelection = selectedPaidByMemberIds.isEmpty || selectedPaidByMemberIds.contains(memberId)
            let paidByShareIndex = selectedPaidByMemberIds.isEmpty ? i :
                Array(selectedPaidByMemberIds.sorted()).firstIndex(of: memberId) ?? 0
            
            // Update owed amounts based on split type
            switch splitType {
            case .equal:
                // Equal split among all members
                let equalShare = Decimal.calculateEqualShare(total: total, memberCount: memberCount, memberIndex: i)
                let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: memberCount, memberIndex: i)
                memberSplits[i].owedAmount = equalShare
                memberSplits[i].owedPercentage = equalPercentage
            case .memberOnly:
                if memberSplits[i].memberId == splitMemberId {
                    memberSplits[i].owedAmount = total
                    memberSplits[i].owedPercentage = 100
                } else {
                    memberSplits[i].owedAmount = 0
                    memberSplits[i].owedPercentage = 0
                }
            case .custom:
                // If we have a subset selected (not custom editor), recalculate equal among selected
                if !selectedSplitMemberIds.isEmpty && !showCustomSplitEditor {
                    if isInSplitSelection {
                        let equalShare = Decimal.calculateEqualShare(total: total, memberCount: splitSelectedCount, memberIndex: splitShareIndex)
                        let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: splitSelectedCount, memberIndex: splitShareIndex)
                        memberSplits[i].owedAmount = equalShare
                        memberSplits[i].owedPercentage = equalPercentage
                    } else {
                        memberSplits[i].owedAmount = 0
                        memberSplits[i].owedPercentage = 0
                    }
                } else {
                    // Keep percentages, recalculate amounts (round to prevent drift)
                    memberSplits[i].owedAmount = (total * memberSplits[i].owedPercentage / 100).rounded(2)
                }
            case .payerOnly:
                memberSplits[i].owedAmount = (total * memberSplits[i].owedPercentage / 100).rounded(2)
            }
            
            // Update paid amounts based on paid by type
            switch paidByType {
            case .single:
                if memberSplits[i].memberId == paidByMemberId {
                    memberSplits[i].paidAmount = total
                    memberSplits[i].paidPercentage = 100
                } else {
                    memberSplits[i].paidAmount = 0
                    memberSplits[i].paidPercentage = 0
                }
            case .shared:
                // Shared equally among all members
                let equalShare = Decimal.calculateEqualShare(total: total, memberCount: memberCount, memberIndex: i)
                let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: memberCount, memberIndex: i)
                memberSplits[i].paidAmount = equalShare
                memberSplits[i].paidPercentage = equalPercentage
            case .custom:
                // If we have a subset selected (not custom editor), recalculate equal among selected
                if !selectedPaidByMemberIds.isEmpty && !showCustomPaidByEditor {
                    if isInPaidBySelection {
                        let equalShare = Decimal.calculateEqualShare(total: total, memberCount: paidBySelectedCount, memberIndex: paidByShareIndex)
                        let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: paidBySelectedCount, memberIndex: paidByShareIndex)
                        memberSplits[i].paidAmount = equalShare
                        memberSplits[i].paidPercentage = equalPercentage
                    } else {
                        memberSplits[i].paidAmount = 0
                        memberSplits[i].paidPercentage = 0
                    }
                } else {
                    // Keep percentages, recalculate amounts (round to prevent drift)
                    memberSplits[i].paidAmount = (total * memberSplits[i].paidPercentage / 100).rounded(2)
                }
            }
        }
        
        validateSplits()
    }
    
    private func updateMemberSplitsForSplitType() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        for i in memberSplits.indices {
            // Calculate equal share with remainder allocation to prevent rounding drift
            let equalShare = Decimal.calculateEqualShare(total: total, memberCount: memberCount, memberIndex: i)
            let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: memberCount, memberIndex: i)
            
            switch splitType {
            case .equal:
                memberSplits[i].owedAmount = equalShare
                memberSplits[i].owedPercentage = equalPercentage
            case .memberOnly:
                if memberSplits[i].memberId == splitMemberId {
                    memberSplits[i].owedAmount = total
                    memberSplits[i].owedPercentage = 100
                } else {
                    memberSplits[i].owedAmount = 0
                    memberSplits[i].owedPercentage = 0
                }
            case .custom, .payerOnly:
                break // Keep existing values
            }
        }
        
        validateSplits()
    }
    
    private func updateMemberSplitsForPaidByType() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        for i in memberSplits.indices {
            // Calculate equal share with remainder allocation to prevent rounding drift
            let equalShare = Decimal.calculateEqualShare(total: total, memberCount: memberCount, memberIndex: i)
            let equalPercentage = Decimal.calculateEqualShare(total: 100, memberCount: memberCount, memberIndex: i)
            
            switch paidByType {
            case .single:
                if memberSplits[i].memberId == paidByMemberId {
                    memberSplits[i].paidAmount = total
                    memberSplits[i].paidPercentage = 100
                } else {
                    memberSplits[i].paidAmount = 0
                    memberSplits[i].paidPercentage = 0
                }
            case .shared:
                memberSplits[i].paidAmount = equalShare
                memberSplits[i].paidPercentage = equalPercentage
            case .custom:
                break // Keep existing values
            }
        }
        
        validateSplits()
    }
    
    private func clearCustomSplitAmounts() {
        for i in memberSplits.indices {
            memberSplits[i].owedAmount = 0
            memberSplits[i].owedPercentage = 0
        }
        validateSplits()
    }
    
    private func clearCustomPaidByAmounts() {
        for i in memberSplits.indices {
            memberSplits[i].paidAmount = 0
            memberSplits[i].paidPercentage = 0
        }
        validateSplits()
    }
    
    private func validateSplits() {
        let total = parsedAmount
        
        // Validate owed amounts for custom split (only when using custom editor, not multi-select)
        if splitType == .custom && showCustomSplitEditor {
            let totalOwed = memberSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
            if abs(totalOwed - total) > 0.01 {
                splitValidationError = "Split amounts must equal \(total.doubleValue.formattedAsMoney(showSign: false))"
            } else {
                splitValidationError = nil
            }
        } else {
            splitValidationError = nil
        }
        
        // Validate paid amounts for custom paid by (only when using custom editor, not multi-select)
        if paidByType == .custom && showCustomPaidByEditor {
            let totalPaid = memberSplits.reduce(Decimal(0)) { $0 + $1.paidAmount }
            if abs(totalPaid - total) > 0.01 {
                paidByValidationError = "Paid amounts must equal \(total.doubleValue.formattedAsMoney(showSign: false))"
            } else {
                paidByValidationError = nil
            }
        } else {
            paidByValidationError = nil
        }
    }
    
    private func submitTransaction() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Always send splits for expenses - convert 'equal' and 'shared' to 'custom' with explicit splits
                let splitsToSend: [MemberSplit]? = transactionType == .expense ? memberSplits : nil
                
                // Convert 'equal' to 'custom' since we're storing explicit splits
                // Keep 'member_only' as-is since it indicates single-member expense
                let effectiveSplitType: SplitType = {
                    switch splitType {
                    case .equal:
                        return .custom  // Store as custom with explicit equal splits
                    default:
                        return splitType
                    }
                }()
                
                // Convert 'shared' to 'custom' since we're storing explicit paid amounts
                let effectivePaidByType: PaidByType = {
                    switch paidByType {
                    case .shared:
                        return .custom  // Store as custom with explicit equal paid amounts
                    default:
                        return paidByType
                    }
                }()
                
                // Determine paid by member ID based on transaction type
                let effectivePaidByMemberId: UUID? = {
                    switch transactionType {
                    case .expense:
                        return effectivePaidByType == .single ? paidByMemberId : nil
                    case .income:
                        return paidByMemberId // Always include for income (received by)
                    case .settlement, .reimbursement:
                        return paidByMemberId
                    }
                }()
                
                try await transactionViewModel.createTransaction(
                    householdId: householdId,
                    date: date,
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: parsedAmount,
                    transactionType: transactionType,
                    paidByMemberId: effectivePaidByMemberId,
                    paidToMemberId: paidToMemberId,
                    categoryId: transactionType == .expense ? categoryId : nil,
                    splitType: transactionType == .expense ? effectiveSplitType : .custom,
                    paidByType: transactionType == .expense ? effectivePaidByType : .single,
                    splitMemberId: transactionType == .expense ? splitMemberId : nil,
                    reimbursesTransactionId: transactionType == .reimbursement ? reimbursesTransactionId : nil,
                    excludedFromBudget: excludedFromBudget,
                    notes: notes.isEmpty ? nil : notes,
                    createdByUserId: authViewModel.currentUser?.id,
                    splits: splitsToSend
                )
                
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func resetForm() {
        amount = ""
        description = ""
        date = Date()
        paidByMemberId = authViewModel.currentMember?.id
        paidToMemberId = nil
        categoryId = nil
        splitType = .equal
        paidByType = .single
        splitMemberId = nil
        reimbursesTransactionId = nil
        notes = ""
        showNotes = false
        excludedFromBudget = false
        showCustomSplitEditor = false
        showCustomPaidByEditor = false
        selectedSplitMemberIds.removeAll()
        selectedPaidByMemberIds.removeAll()
        initializeMemberSplits()
    }
}

// MARK: - Supporting Views

struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            content
        }
    }
}

struct TransactionTypeButton: View {
    let type: TransactionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: type.icon)
                    .font(.title3)
                
                Text(type.displayName)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accent : Theme.Colors.backgroundCard)
            .foregroundStyle(isSelected ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
    }
}

struct MemberSelector: View {
    let members: [HouseholdMember]
    @Binding var selectedId: UUID?
    var excludeId: UUID? = nil
    
    private var availableMembers: [HouseholdMember] {
        members.filter { $0.id != excludeId }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(availableMembers) { member in
                    Button {
                        selectedId = member.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(member.displayName)
                                .font(.subheadline)
                            if member.isInactive {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(selectedId == member.id ? Theme.Colors.textInverse.opacity(0.6) : Theme.Colors.textMuted)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(selectedId == member.id ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                        .foregroundStyle(selectedId == member.id ? Theme.Colors.textInverse : (member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textSecondary))
                        .clipShape(Capsule())
                        .opacity(member.isInactive ? 0.8 : 1.0)
                    }
                }
            }
        }
    }
}

struct MemberPickerButton: View {
    let members: [HouseholdMember]
    let selectedId: UUID?
    let excludeId: UUID?
    let action: () -> Void
    
    private var selectedMember: HouseholdMember? {
        members.first { $0.id == selectedId }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if let member = selectedMember {
                    Text(member.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("Select")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .inputFieldStyle()
        }
    }
}

struct MemberPickerSheet: View {
    let members: [HouseholdMember]
    let excludeId: UUID?
    let title: String
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    
    private var availableMembers: [HouseholdMember] {
        members.filter { $0.id != excludeId }
    }
    
    private var filteredMembers: [HouseholdMember] {
        if searchText.isEmpty {
            return availableMembers
        }
        return availableMembers.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Search bar (only show if many members)
                        if availableMembers.count > 6 {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                TextField("Search members...", text: $searchText)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            .padding(Theme.Spacing.sm)
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.sm)
                        }
                        
                        // Member list
                        VStack(spacing: 0) {
                            ForEach(filteredMembers) { member in
                                MemberPickerRow(
                                    member: member,
                                    isSelected: selectedId == member.id
                                ) {
                                    selectedId = member.id
                                    dismiss()
                                }
                                
                                if member.id != filteredMembers.last?.id {
                                    Divider()
                                        .background(Theme.Colors.borderLight)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        
                        // Empty state
                        if filteredMembers.isEmpty {
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "person.slash")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("No members found")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

struct MemberPickerRow: View {
    let member: HouseholdMember
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                // Avatar circle with initial
                Text(String(member.displayName.prefix(1)).uppercased())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textInverse)
                    .frame(width: 32, height: 32)
                    .background(Theme.Colors.accent.opacity(member.isInactive ? 0.5 : 1.0))
                    .clipShape(Circle())
                
                HStack(spacing: Theme.Spacing.xs) {
                    Text(member.displayName)
                        .font(.subheadline)
                        .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    
                    if member.isInactive {
                        Text("Inactive")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.textMuted.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accent.opacity(0.15) : Color.clear)
        }
    }
}

struct CategoryPickerButton: View {
    let categories: [Category]
    let selectedId: UUID?
    let action: () -> Void
    
    private var selectedCategory: Category? {
        categories.first { $0.id == selectedId }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if let category = selectedCategory {
                    if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                        Text(icon)
                    }
                    Text(category.name)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("Select")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .inputFieldStyle()
        }
    }
}

struct CategoryPickerSheet: View {
    let categories: [Category]
    let sectors: [Sector]
    let sectorCategories: [UUID: [UUID]]
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    
    private var filteredCategories: [Category] {
        if searchText.isEmpty {
            return categories
        }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var categoriesInSectors: Set<UUID> {
        var ids = Set<UUID>()
        for categoryIds in sectorCategories.values {
            ids.formUnion(categoryIds)
        }
        return ids
    }
    
    private var uncategorizedCategories: [Category] {
        filteredCategories
            .filter { !categoriesInSectors.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private func categoriesForSector(_ sector: Sector) -> [Category] {
        guard let categoryIds = sectorCategories[sector.id] else { return [] }
        return filteredCategories
            .filter { categoryIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("Search categories...", text: $searchText)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        
                        // Sectors with their categories
                        ForEach(sectors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { sector in
                            let sectorCats = categoriesForSector(sector)
                            if !sectorCats.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(sector.name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(sector.swiftUIColor)
                                        .padding(.horizontal, Theme.Spacing.md)
                                        .padding(.top, Theme.Spacing.sm)
                                    
                                    ForEach(sectorCats) { category in
                                        CategoryPickerRow(
                                            category: category,
                                            isSelected: selectedId == category.id
                                        ) {
                                            selectedId = category.id
                                            dismiss()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Uncategorized categories
                        if !uncategorizedCategories.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Other")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.top, Theme.Spacing.sm)
                                
                                ForEach(uncategorizedCategories) { category in
                                    CategoryPickerRow(
                                        category: category,
                                        isSelected: selectedId == category.id
                                    ) {
                                        selectedId = category.id
                                        dismiss()
                                    }
                                }
                            }
                        }
                        
                        // Empty state
                        if filteredCategories.isEmpty {
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("No categories found")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

struct CategoryPickerRow: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                    Text(icon)
                        .font(.title3)
                }
                
                Text(category.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accent.opacity(0.15) : Color.clear)
        }
    }
}

struct SplitOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                .foregroundStyle(isSelected ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                .clipShape(Capsule())
        }
    }
}

struct PaidByOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                .foregroundStyle(isSelected ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Multi-Select Member Selector
/// Allows selecting multiple members for equal split, or "All" for everyone, or "Custom" for manual amounts
struct MultiSelectMemberSelector: View {
    let members: [HouseholdMember]
    @Binding var selectedMemberIds: Set<UUID>
    let isCustomSelected: Bool
    let onSelectAll: () -> Void
    let onSelectCustom: () -> Void
    let onToggleMember: (UUID) -> Void
    
    /// Check if all members are currently selected
    private var allMembersSelected: Bool {
        !isCustomSelected && selectedMemberIds.count == members.count && 
        members.allSatisfy { selectedMemberIds.contains($0.id) }
    }
    
    /// Check if a specific member is selected
    private func isMemberSelected(_ memberId: UUID) -> Bool {
        !isCustomSelected && selectedMemberIds.contains(memberId)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                // "All" option - only show when not all members are selected
                if !allMembersSelected && !isCustomSelected {
                    Button(action: onSelectAll) {
                        Text("All")
                            .font(.subheadline)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.backgroundCard)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .clipShape(Capsule())
                    }
                }
                
                // Individual members (multi-select)
                ForEach(members) { member in
                    Button {
                        onToggleMember(member.id)
                    } label: {
                        HStack(spacing: 4) {
                            // Show checkmark inside the pill when selected
                            if isMemberSelected(member.id) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(member.displayName)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(isMemberSelected(member.id) ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                        .foregroundStyle(isMemberSelected(member.id) ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                        .clipShape(Capsule())
                    }
                }
                
                // "Custom" option
                Button(action: onSelectCustom) {
                    Text("Custom")
                        .font(.subheadline)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(isCustomSelected ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                        .foregroundStyle(isCustomSelected ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct CustomSplitEditor: View {
    let title: String
    @Binding var memberSplits: [MemberSplit]
    let totalAmount: Decimal
    let editingPaidAmount: Bool // true = editing paid amounts, false = editing owed amounts
    @Binding var validationError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            // Warning if total amount is 0
            if totalAmount == 0 {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.warning)
                    Text("Enter an amount above first")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            
            ForEach($memberSplits) { $split in
                MemberSplitRow(
                    split: $split,
                    totalAmount: totalAmount,
                    editingPaidAmount: editingPaidAmount,
                    onAmountChanged: { validateTotals() }
                )
            }
            
            // Total and validation
            HStack {
                Text("Total")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                let currentTotal = editingPaidAmount
                    ? memberSplits.reduce(Decimal(0)) { $0 + $1.paidAmount }
                    : memberSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
                
                Text(currentTotal.doubleValue.formattedAsMoney())
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(abs(currentTotal - totalAmount) > 0.01 ? Theme.Colors.error : Theme.Colors.success)
                
                Text("/ \(totalAmount.doubleValue.formattedAsMoney())")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.top, Theme.Spacing.xs)
            
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.error)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }
    
    private func validateTotals() {
        let total = editingPaidAmount
            ? memberSplits.reduce(Decimal(0)) { $0 + $1.paidAmount }
            : memberSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
        
        if abs(total - totalAmount) > 0.01 {
            validationError = "Amounts must equal \(totalAmount.doubleValue.formattedAsMoney(showSign: false))"
        } else {
            validationError = nil
        }
    }
}

struct MemberSplitRow: View {
    @Binding var split: MemberSplit
    let totalAmount: Decimal
    let editingPaidAmount: Bool
    let onAmountChanged: () -> Void
    
    @State private var amountText: String = ""
    @State private var percentageText: String = ""
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isPercentageFocused: Bool
    
    private var currentAmount: Decimal {
        editingPaidAmount ? split.paidAmount : split.owedAmount
    }
    
    private var currentPercentage: Decimal {
        editingPaidAmount ? split.paidPercentage : split.owedPercentage
    }
    
    private var isEditing: Bool {
        isAmountFocused || isPercentageFocused
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Member name
            Text(split.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(minWidth: 60, alignment: .leading)
            
            Spacer()
            
            // Amount field
            HStack(spacing: 2) {
                Text("$")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                TextField("0.00", text: $amountText)
                    .font(.subheadline)
                    .keyboardType(.decimalPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .focused($isAmountFocused)
                    .onChange(of: amountText) { _, newValue in
                        // Only process if this field is focused (user is typing)
                        guard isAmountFocused else { return }
                        
                        if let value = Decimal(string: newValue), value > 0 {
                            if editingPaidAmount {
                                split.paidAmount = value
                                if totalAmount > 0 {
                                    split.paidPercentage = (value / totalAmount) * 100
                                }
                            } else {
                                split.owedAmount = value
                                if totalAmount > 0 {
                                    split.owedPercentage = (value / totalAmount) * 100
                                }
                            }
                            onAmountChanged()
                        } else if newValue.isEmpty {
                            if editingPaidAmount {
                                split.paidAmount = 0
                                split.paidPercentage = 0
                            } else {
                                split.owedAmount = 0
                                split.owedPercentage = 0
                            }
                            onAmountChanged()
                        }
                    }
                    .onChange(of: isAmountFocused) { _, focused in
                        if !focused {
                            // User finished editing - sync display
                            syncDisplayFromModel()
                        }
                    }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
            
            // Percentage field
            HStack(spacing: 2) {
                TextField("0", text: $percentageText)
                    .font(.subheadline)
                    .keyboardType(.decimalPad)
                    .frame(width: 40)
                    .multilineTextAlignment(.trailing)
                    .focused($isPercentageFocused)
                    .onChange(of: percentageText) { _, newValue in
                        // Only process if this field is focused (user is typing)
                        guard isPercentageFocused else { return }
                        
                        if let value = Decimal(string: newValue), value > 0 {
                            let newAmount = (value / 100) * totalAmount
                            if editingPaidAmount {
                                split.paidPercentage = value
                                split.paidAmount = newAmount
                            } else {
                                split.owedPercentage = value
                                split.owedAmount = newAmount
                            }
                            onAmountChanged()
                        } else if newValue.isEmpty {
                            if editingPaidAmount {
                                split.paidAmount = 0
                                split.paidPercentage = 0
                            } else {
                                split.owedAmount = 0
                                split.owedPercentage = 0
                            }
                            onAmountChanged()
                        }
                    }
                    .onChange(of: isPercentageFocused) { _, focused in
                        if !focused {
                            // User finished editing - sync display
                            syncDisplayFromModel()
                        }
                    }
                
                Text("%")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
        }
        .onAppear {
            syncDisplayFromModel()
        }
        .onChange(of: currentAmount) { _, _ in
            // Only update text when NOT actively editing
            if !isEditing {
                syncDisplayFromModel()
            }
        }
    }
    
    private func syncDisplayFromModel() {
        if currentAmount > 0 {
            amountText = String(format: "%.2f", (currentAmount as NSDecimalNumber).doubleValue)
            percentageText = String(format: "%.1f", (currentPercentage as NSDecimalNumber).doubleValue)
        } else {
            amountText = ""
            percentageText = ""
        }
    }
}

struct ExpensePickerButton: View {
    let expenses: [TransactionView]
    let selectedId: UUID?
    let action: () -> Void
    
    private var selectedExpense: TransactionView? {
        expenses.first { $0.id == selectedId }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                if let expense = selectedExpense {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expense.description)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(expense.amount.doubleValue.formattedAsMoney())
                                .font(.caption)
                            Text("•")
                                .font(.caption)
                            Text(expense.date.formatted(as: .dayMonth))
                                .font(.caption)
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                } else {
                    Text("None (counts as income)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .inputFieldStyle()
        }
    }
}

struct ExpensePickerSheet: View {
    let expenses: [TransactionView]
    @Binding var selectedId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    
    private var sortedExpenses: [TransactionView] {
        expenses.sorted { $0.date > $1.date }
    }
    
    private var filteredExpenses: [TransactionView] {
        if searchText.isEmpty {
            return sortedExpenses
        }
        return sortedExpenses.filter { expense in
            expense.description.localizedCaseInsensitiveContains(searchText) ||
            (expense.categoryName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.Colors.textSecondary)
                            TextField("Search expenses...", text: $searchText)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                            }
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        
                        // "None" option
                        Button {
                            selectedId = nil
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("None")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Counts as income")
                                        .font(.caption)
                                        .foregroundStyle(selectedId == nil ? Theme.Colors.textInverse.opacity(0.8) : Theme.Colors.textSecondary)
                                }
                                
                                Spacer()
                                
                                if selectedId == nil {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(selectedId == nil ? Theme.Colors.textInverse : Theme.Colors.accent)
                                }
                            }
                            .foregroundStyle(selectedId == nil ? Theme.Colors.textInverse : Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(selectedId == nil ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Expense list
                        if !filteredExpenses.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(filteredExpenses) { expense in
                                    ExpensePickerRow(
                                        expense: expense,
                                        isSelected: selectedId == expense.id
                                    ) {
                                        selectedId = expense.id
                                        dismiss()
                                    }
                                    
                                    if expense.id != filteredExpenses.last?.id {
                                        Divider()
                                            .background(Theme.Colors.borderLight)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Empty state
                        if filteredExpenses.isEmpty && !searchText.isEmpty {
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("No expenses found")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("Try a different search term")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                        } else if expenses.isEmpty {
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "doc.text")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text("No expenses yet")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("Add some expenses first")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                        }
                        
                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle("Link to Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

struct ExpensePickerRow: View {
    let expense: TransactionView
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(expense.amount.doubleValue.formattedAsMoney())
                            .font(.caption)
                        Text("•")
                            .font(.caption)
                        Text(expense.date.formatted(as: .dayMonth))
                            .font(.caption)
                        if let categoryName = expense.categoryName {
                            Text("•")
                                .font(.caption)
                            Text(categoryName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.Colors.accent.opacity(0.15) : Color.clear)
        }
    }
}

#Preview {
    AddTransactionView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
