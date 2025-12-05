import SwiftUI

struct EditTransactionView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    let transaction: TransactionView
    
    @State private var transactionType: TransactionType
    @State private var amount: String
    @State private var description: String
    @State private var date: Date
    @State private var paidByMemberId: UUID?
    @State private var paidToMemberId: UUID?
    @State private var categoryId: UUID?
    @State private var splitType: SplitType
    @State private var paidByType: PaidByType
    @State private var splitMemberId: UUID?
    @State private var reimbursesTransactionId: UUID?
    @State private var notes: String
    @State private var excludedFromBudget: Bool
    
    // Custom split state
    @State private var memberSplits: [MemberSplit] = []
    @State private var showCustomSplitEditor = false
    @State private var showCustomPaidByEditor = false
    @State private var splitValidationError: String?
    @State private var paidByValidationError: String?
    
    // Multi-select member state (for equal split between subset of members)
    @State private var selectedSplitMemberIds: Set<UUID> = []
    @State private var selectedPaidByMemberIds: Set<UUID> = []
    
    @State private var showDatePicker = false
    @State private var showCategoryPicker = false
    @State private var showPaidByPicker = false
    @State private var showReceivedByPicker = false
    @State private var showPaidToPicker = false
    @State private var showSplitMemberPicker = false
    @State private var showNotes: Bool
    @State private var showExpensePicker = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false
    
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
    
    init(transaction: TransactionView) {
        self.transaction = transaction
        _transactionType = State(initialValue: transaction.transactionType)
        _amount = State(initialValue: String(format: "%.2f", (transaction.amount as NSDecimalNumber).doubleValue))
        _description = State(initialValue: transaction.description)
        _date = State(initialValue: transaction.date)
        _paidByMemberId = State(initialValue: transaction.paidByMemberId)
        _paidToMemberId = State(initialValue: transaction.paidToMemberId)
        _categoryId = State(initialValue: transaction.categoryId)
        _splitType = State(initialValue: transaction.splitType)
        _paidByType = State(initialValue: transaction.paidByType)
        _splitMemberId = State(initialValue: transaction.splitMemberId)
        _reimbursesTransactionId = State(initialValue: transaction.reimbursesTransactionId)
        _notes = State(initialValue: transaction.notes ?? "")
        _excludedFromBudget = State(initialValue: transaction.excludedFromBudget)
        _showNotes = State(initialValue: transaction.notes != nil && !transaction.notes!.isEmpty)
    }
    
    private var parsedAmount: Decimal {
        Decimal(string: amount) ?? 0
    }
    
    /// Reimbursements linked to this expense (if it's an expense)
    private var linkedReimbursements: [TransactionView] {
        guard transaction.transactionType == .expense else { return [] }
        return transactionViewModel.reimbursementsForExpense(transaction.id)
    }
    
    /// Total amount reimbursed for this expense
    private var totalReimbursed: Decimal {
        linkedReimbursements.reduce(Decimal(0)) { $0 + $1.amount }
    }
    
    /// Whether this expense has any reimbursements
    private var hasReimbursements: Bool {
        !linkedReimbursements.isEmpty
    }
    
    /// Active members only (for new expenses, income, reimbursements)
    private var activeMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isActive }
    }
    
    /// Members eligible for settlements (includes inactive members for settling balances)
    private var settlementEligibleMembers: [HouseholdMember] {
        authViewModel.members // All members including inactive
    }
    
    /// Alias for backward compatibility - used for most transaction types
    private var approvedMembers: [HouseholdMember] {
        activeMembers
    }
    
    /// Members to use for the paid by section based on transaction type
    private var paidByMemberList: [HouseholdMember] {
        transactionType == .settlement ? settlementEligibleMembers : approvedMembers
    }
    
    /// Members to show in the multi-select UI for split (expense for)
    /// Includes active members plus any inactive members who are part of this transaction's existing splits
    private var membersForSplitSelector: [HouseholdMember] {
        let activeMemberIds = Set(approvedMembers.map { $0.id })
        
        // Get inactive members who have splits in this transaction
        let inactiveMembersInSplits = authViewModel.members.filter { member in
            !activeMemberIds.contains(member.id) &&
            (selectedSplitMemberIds.contains(member.id) ||
             memberSplits.contains { $0.memberId == member.id && $0.owedAmount > 0 })
        }
        
        return approvedMembers + inactiveMembersInSplits
    }
    
    /// Members to show in the multi-select UI for paid by
    /// Includes active members plus any inactive members who paid in this transaction
    private var membersForPaidBySelector: [HouseholdMember] {
        let activeMemberIds = Set(approvedMembers.map { $0.id })
        
        // Get inactive members who paid in this transaction
        let inactiveMembersWhoPaid = authViewModel.members.filter { member in
            !activeMemberIds.contains(member.id) &&
            (selectedPaidByMemberIds.contains(member.id) ||
             memberSplits.contains { $0.memberId == member.id && $0.paidAmount > 0 })
        }
        
        return approvedMembers + inactiveMembersWhoPaid
    }
    
    private var isFormValid: Bool {
        guard parsedAmount > 0 else { return false }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        switch transactionType {
        case .expense:
            if paidByType == .single && paidByMemberId == nil { return false }
            if paidByType == .custom && paidByValidationError != nil { return false }
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
                        // Transaction Type Display (non-editable)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: transactionType.icon)
                                .font(.body)
                            Text(transactionType.displayName)
                                .font(.headline)
                        }
                        .foregroundStyle(transactionType.color)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(transactionType.color.opacity(0.15))
                        .clipShape(Capsule())
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
                            }
                            
                            // Split Type Section (for expense only, moved category to date row)
                            if transactionType == .expense {
                                if approvedMembers.count > 1 {
                                    splitSection
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Notes (expandable)
                        if showNotes {
                            FormField(label: "Notes") {
                                TextField("Add any notes...", text: $notes, axis: .vertical)
                                    .lineLimit(3...5)
                                    .inputFieldStyle()
                                    .focused($focusedField, equals: .notes)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Action Buttons
                        VStack(spacing: Theme.Spacing.sm) {
                            // Save Button
                            HStack(spacing: Theme.Spacing.sm) {
                                Button {
                                    saveTransaction()
                                } label: {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(Theme.Colors.textInverse)
                                    } else {
                                        Text("Save Changes")
                                    }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(!isFormValid || isSubmitting)
                                .frame(maxWidth: .infinity)
                                .id("saveChanges-\(themeProvider.currentPalette.id)")
                                
                                // Notes Icon Button
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
                            
                            // Delete Button
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Delete Transaction")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.md)
                                .background(Theme.Colors.error.opacity(0.1))
                                .foregroundStyle(Theme.Colors.error)
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
            .navigationTitle("Edit Transaction")
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
        .onAppear {
            initializeMemberSplits()
        }
        .task {
            // Load existing splits if available
            await loadExistingSplits()
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
        .confirmationDialog(
            "Delete Transaction",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete\(hasReimbursements ? " All" : "")", role: .destructive) {
                deleteTransaction()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if hasReimbursements {
                Text("This expense has \(linkedReimbursements.count) linked reimbursement\(linkedReimbursements.count == 1 ? "" : "s") totaling \(totalReimbursed.doubleValue.formattedAsMoney()). Deleting this expense will also delete all linked reimbursements. This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete this transaction? This action cannot be undone.")
            }
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
    }
    
    // MARK: - Paid By Section
    
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
            } else if membersForPaidBySelector.count > 1 {
                // Multi-select member selector for expenses
                MultiSelectMemberSelector(
                    members: membersForPaidBySelector,
                    selectedMemberIds: $selectedPaidByMemberIds,
                    isCustomSelected: showCustomPaidByEditor,
                    onSelectAll: {
                        withAnimation {
                            // Select all members shown in the selector (includes inactive members who are part of this transaction)
                            selectedPaidByMemberIds = Set(membersForPaidBySelector.map { $0.id })
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
        let selectedNames = membersForPaidBySelector
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
    
    // MARK: - Split Section
    
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Expense For")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // Multi-select member selector
            MultiSelectMemberSelector(
                members: membersForSplitSelector,
                selectedMemberIds: $selectedSplitMemberIds,
                isCustomSelected: showCustomSplitEditor,
                onSelectAll: {
                    withAnimation {
                        // Select all members shown in the selector (includes inactive members who are part of this transaction)
                        selectedSplitMemberIds = Set(membersForSplitSelector.map { $0.id })
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
        let selectedNames = membersForSplitSelector
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
    
    /// Calculate total reimbursements already applied to a specific expense (excluding this transaction if editing a reimbursement)
    private func existingReimbursements(for expenseId: UUID) -> Decimal {
        transactionViewModel.transactions
            .filter { 
                $0.transactionType == .reimbursement && 
                $0.reimbursesTransactionId == expenseId &&
                $0.id != transaction.id // Exclude current transaction when editing
            }
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
    
    // MARK: - Helper Methods
    
    private func initializeMemberSplits() {
        memberSplits = approvedMembers.map { member in
            MemberSplit(member: member, totalAmount: parsedAmount, memberCount: approvedMembers.count)
        }
        
        // Set up initial selection state based on transaction type
        // For memberOnly, pre-select that member
        if splitType == .memberOnly, let memberId = splitMemberId {
            selectedSplitMemberIds = [memberId]
        }
        
        // For single payer, pre-select that member
        if paidByType == .single, let memberId = paidByMemberId {
            selectedPaidByMemberIds = [memberId]
        }
        
        // Don't automatically open custom editors - let detectMultiSelectFromSplits determine this
        // after loading existing splits
    }
    
    private func loadExistingSplits() async {
        await transactionViewModel.fetchTransactionSplits(transactionId: transaction.id)
        
        if let existingSplits = transactionViewModel.transactionSplits[transaction.id], !existingSplits.isEmpty {
            // Get the set of member IDs already in memberSplits (active members)
            let activeMemberIds = Set(memberSplits.map { $0.memberId })
            
            // Map existing splits to memberSplits for active members
            for i in memberSplits.indices {
                if let existingSplit = existingSplits.first(where: { $0.memberId == memberSplits[i].memberId }) {
                    memberSplits[i].owedAmount = existingSplit.owedAmount
                    memberSplits[i].owedPercentage = existingSplit.owedPercentage ?? 0
                    memberSplits[i].paidAmount = existingSplit.paidAmount
                    memberSplits[i].paidPercentage = existingSplit.paidPercentage ?? 0
                }
            }
            
            // Add inactive members who have existing splits (to preserve their data)
            for existingSplit in existingSplits {
                // Skip if this member is already in memberSplits (active member)
                if activeMemberIds.contains(existingSplit.memberId) {
                    continue
                }
                
                // Look up the member (including inactive ones) in authViewModel.members
                if let member = authViewModel.members.first(where: { $0.id == existingSplit.memberId }) {
                    // Add inactive member with their existing split data
                    let inactiveSplit = MemberSplit(
                        id: member.id,
                        displayName: member.displayName + " (inactive)",
                        owedAmount: existingSplit.owedAmount,
                        owedPercentage: existingSplit.owedPercentage ?? 0,
                        paidAmount: existingSplit.paidAmount,
                        paidPercentage: existingSplit.paidPercentage ?? 0
                    )
                    memberSplits.append(inactiveSplit)
                }
            }
            
            // Detect and set up multi-select UI state based on existing splits
            detectMultiSelectFromSplits()
        }
    }
    
    /// Detect if existing splits represent an equal split between a subset of members
    /// and set up the multi-select UI state accordingly
    private func detectMultiSelectFromSplits() {
        let total = parsedAmount
        guard total > 0 else { return }
        
        // ===== SPLIT (OWED) DETECTION =====
        let membersWithOwed = memberSplits.filter { $0.owedAmount > 0 }
        
        if membersWithOwed.count >= 1 {
            // Check if all amounts are approximately equal
            let expectedShare = total / Decimal(membersWithOwed.count)
            let allEqual = membersWithOwed.allSatisfy { abs($0.owedAmount - expectedShare) < 0.02 }
            
            if allEqual {
                // Equal split - select all members who owe
                selectedSplitMemberIds = Set(membersWithOwed.map { $0.memberId })
                if membersWithOwed.count == 1 {
                    splitType = .memberOnly
                    splitMemberId = membersWithOwed.first?.memberId
                } else {
                    splitType = .custom
                    splitMemberId = nil
                }
                showCustomSplitEditor = false
            } else {
                // Unequal custom split - show custom editor
                splitType = .custom
                selectedSplitMemberIds.removeAll()
                showCustomSplitEditor = true
            }
        }
        
        // ===== PAID BY DETECTION =====
        let membersWhoPaid = memberSplits.filter { $0.paidAmount > 0 }
        
        if membersWhoPaid.count >= 1 {
            // Check if all paid amounts are approximately equal
            let expectedShare = total / Decimal(membersWhoPaid.count)
            let allEqual = membersWhoPaid.allSatisfy { abs($0.paidAmount - expectedShare) < 0.02 }
            
            if allEqual {
                // Equal paid split - select all members who paid
                selectedPaidByMemberIds = Set(membersWhoPaid.map { $0.memberId })
                if membersWhoPaid.count == 1 {
                    paidByType = .single
                    paidByMemberId = membersWhoPaid.first?.memberId
                } else {
                    paidByType = .custom
                    paidByMemberId = nil
                }
                showCustomPaidByEditor = false
            } else {
                // Unequal custom paid - show custom editor
                paidByType = .custom
                selectedPaidByMemberIds.removeAll()
                showCustomPaidByEditor = true
            }
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
                break
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
                break
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
    
    private func saveTransaction() {
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
                
                try await transactionViewModel.updateTransaction(
                    transactionId: transaction.id,
                    householdId: transaction.householdId,
                    date: date,
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: parsedAmount,
                    transactionType: transactionType,
                    paidByMemberId: effectivePaidByMemberId,
                    paidToMemberId: transactionType == .settlement ? paidToMemberId : nil,
                    categoryId: transactionType == .expense ? categoryId : nil,
                    splitType: transactionType == .expense ? effectiveSplitType : .custom,
                    paidByType: transactionType == .expense ? effectivePaidByType : .single,
                    splitMemberId: transactionType == .expense ? splitMemberId : nil,
                    reimbursesTransactionId: transactionType == .reimbursement ? reimbursesTransactionId : nil,
                    excludedFromBudget: excludedFromBudget,
                    notes: notes.isEmpty ? nil : notes,
                    splits: splitsToSend
                )
                
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
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
    
    private func deleteTransaction() {
        Task {
            // If this is an expense with reimbursements, delete them too
            if transaction.transactionType == .expense && hasReimbursements {
                await transactionViewModel.deleteExpenseWithReimbursements(
                    id: transaction.id,
                    householdId: transaction.householdId
                )
            } else {
                await transactionViewModel.deleteTransaction(
                    id: transaction.id,
                    householdId: transaction.householdId
                )
            }
            await MainActor.run {
                dismiss()
            }
        }
    }
}

#Preview {
    // Create a sample transaction for preview
    let sampleTransaction = try! JSONDecoder().decode(
        TransactionView.self,
        from: """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "household_id": "00000000-0000-0000-0000-000000000002",
            "date": "2025-12-01",
            "description": "Groceries",
            "amount": 150.00,
            "transaction_type": "expense",
            "split_type": "custom",
            "paid_by_type": "single",
            "excluded_from_budget": false,
            "created_at": "2025-12-01T12:00:00Z",
            "updated_at": "2025-12-01T12:00:00Z"
        }
        """.data(using: .utf8)!
    )
    
    return EditTransactionView(transaction: sampleTransaction)
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}

