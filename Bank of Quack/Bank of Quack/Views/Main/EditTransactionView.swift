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
                        // Transaction Type Selector
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(TransactionType.allCases, id: \.self) { type in
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
                            if transactionType == .expense || transactionType == .settlement {
                                paidBySection
                            }
                            
                            // Received By (for income and reimbursement)
                            if transactionType == .income || transactionType == .reimbursement {
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
            Button("Delete", role: .destructive) {
                deleteTransaction()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this transaction? This action cannot be undone.")
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
            } else if approvedMembers.count > 1 {
                // Paid By Type Picker (for expenses with multiple members)
                if approvedMembers.count > 5 {
                    // Compact layout for 6+ members
                    VStack(spacing: Theme.Spacing.sm) {
                        // Type selector row
                        HStack(spacing: Theme.Spacing.sm) {
                            PaidByOptionButton(
                                title: "Shared",
                                isSelected: paidByType == .shared,
                                action: {
                                    withAnimation {
                                        paidByType = .shared
                                        showCustomPaidByEditor = false
                                        updateMemberSplitsForPaidByType()
                                    }
                                }
                            )
                            
                            PaidByOptionButton(
                                title: "Custom",
                                isSelected: paidByType == .custom,
                                action: {
                                    withAnimation {
                                        paidByType = .custom
                                        showCustomPaidByEditor = true
                                        clearCustomPaidByAmounts()
                                    }
                                }
                            )
                            
                            Spacer()
                        }
                        
                        // Member picker button (only show when not shared/custom)
                        if paidByType == .single || (paidByType != .shared && paidByType != .custom) {
                            MemberPickerButton(
                                members: approvedMembers,
                                selectedId: paidByMemberId,
                                excludeId: nil
                            ) {
                                showPaidByPicker = true
                            }
                        }
                    }
                } else {
                    // Standard horizontal scroll for 5 or fewer members
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            PaidByOptionButton(
                                title: "Shared",
                                isSelected: paidByType == .shared,
                                action: {
                                    withAnimation {
                                        paidByType = .shared
                                        showCustomPaidByEditor = false
                                        updateMemberSplitsForPaidByType()
                                    }
                                }
                            )
                            
                            ForEach(approvedMembers) { member in
                                PaidByOptionButton(
                                    title: member.displayName,
                                    isSelected: paidByType == .single && paidByMemberId == member.id,
                                    action: {
                                        withAnimation {
                                            paidByType = .single
                                            paidByMemberId = member.id
                                            showCustomPaidByEditor = false
                                            updateMemberSplitsForPaidByType()
                                        }
                                    }
                                )
                            }
                            
                            PaidByOptionButton(
                                title: "Custom",
                                isSelected: paidByType == .custom,
                                action: {
                                    withAnimation {
                                        paidByType = .custom
                                        showCustomPaidByEditor = true
                                        clearCustomPaidByAmounts()
                                    }
                                }
                            )
                        }
                    }
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
    
    // MARK: - Split Section
    
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Expense For")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // Split Type Picker
            if approvedMembers.count > 5 {
                // Compact layout for 6+ members
                VStack(spacing: Theme.Spacing.sm) {
                    // Type selector row
                    HStack(spacing: Theme.Spacing.sm) {
                        SplitOptionButton(
                            title: "Everyone",
                            isSelected: splitType == .equal,
                            action: {
                                withAnimation {
                                    splitType = .equal
                                    splitMemberId = nil
                                    showCustomSplitEditor = false
                                    updateMemberSplitsForSplitType()
                                }
                            }
                        )
                        
                        SplitOptionButton(
                            title: "Custom",
                            isSelected: splitType == .custom,
                            action: {
                                withAnimation {
                                    splitType = .custom
                                    splitMemberId = nil
                                    showCustomSplitEditor = true
                                    clearCustomSplitAmounts()
                                }
                            }
                        )
                        
                        Spacer()
                    }
                    
                    // Member picker button (for single member selection)
                    if splitType == .memberOnly || (splitType != .equal && splitType != .custom) {
                        MemberPickerButton(
                            members: approvedMembers,
                            selectedId: splitMemberId,
                            excludeId: nil
                        ) {
                            showSplitMemberPicker = true
                        }
                    } else if splitType != .equal && splitType != .custom {
                        // Show picker option for selecting a single member
                        Button {
                            showSplitMemberPicker = true
                        } label: {
                            HStack {
                                Text("Select one person")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .inputFieldStyle()
                        }
                    }
                }
            } else {
                // Standard horizontal scroll for 5 or fewer members
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        SplitOptionButton(
                            title: "Everyone",
                            isSelected: splitType == .equal,
                            action: {
                                withAnimation {
                                    splitType = .equal
                                    splitMemberId = nil
                                    showCustomSplitEditor = false
                                    updateMemberSplitsForSplitType()
                                }
                            }
                        )
                        
                        ForEach(approvedMembers) { member in
                            SplitOptionButton(
                                title: member.displayName,
                                isSelected: splitType == .memberOnly && splitMemberId == member.id,
                                action: {
                                    withAnimation {
                                        splitType = .memberOnly
                                        splitMemberId = member.id
                                        showCustomSplitEditor = false
                                        updateMemberSplitsForSplitType()
                                    }
                                }
                            )
                        }
                        
                        SplitOptionButton(
                            title: "Custom",
                            isSelected: splitType == .custom,
                            action: {
                                withAnimation {
                                    splitType = .custom
                                    splitMemberId = nil
                                    showCustomSplitEditor = true
                                    clearCustomSplitAmounts()
                                }
                            }
                        )
                    }
                }
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
        .sheet(isPresented: $showSplitMemberPicker) {
            MemberPickerSheet(
                members: approvedMembers,
                excludeId: nil,
                title: "Expense For",
                selectedId: $splitMemberId
            )
            .presentationDetents([.medium])
            .onDisappear {
                if splitMemberId != nil {
                    splitType = .memberOnly
                    updateMemberSplitsForSplitType()
                }
            }
        }
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
    
    // MARK: - Helper Methods
    
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
        
        // Set up UI state based on transaction
        if splitType == .custom {
            showCustomSplitEditor = true
        }
        if paidByType == .custom {
            showCustomPaidByEditor = true
        }
    }
    
    private func loadExistingSplits() async {
        await transactionViewModel.fetchTransactionSplits(transactionId: transaction.id)
        
        if let existingSplits = transactionViewModel.transactionSplits[transaction.id], !existingSplits.isEmpty {
            // Map existing splits to memberSplits
            for i in memberSplits.indices {
                if let existingSplit = existingSplits.first(where: { $0.memberId == memberSplits[i].memberId }) {
                    memberSplits[i].owedAmount = existingSplit.owedAmount
                    memberSplits[i].owedPercentage = existingSplit.owedPercentage ?? 0
                    memberSplits[i].paidAmount = existingSplit.paidAmount
                    memberSplits[i].paidPercentage = existingSplit.paidPercentage ?? 0
                }
            }
        }
    }
    
    private func updateMemberSplitsForAmount() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        let equalShare = total / Decimal(memberCount)
        let equalPercentage: Decimal = 100 / Decimal(memberCount)
        
        for i in memberSplits.indices {
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
                memberSplits[i].owedAmount = total * memberSplits[i].owedPercentage / 100
            }
            
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
                memberSplits[i].paidAmount = total * memberSplits[i].paidPercentage / 100
            }
        }
        
        validateSplits()
    }
    
    private func updateMemberSplitsForSplitType() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        let equalShare = total / Decimal(memberCount)
        let equalPercentage: Decimal = 100 / Decimal(memberCount)
        
        for i in memberSplits.indices {
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
        
        let equalShare = total / Decimal(memberCount)
        let equalPercentage: Decimal = 100 / Decimal(memberCount)
        
        for i in memberSplits.indices {
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
        
        if splitType == .custom {
            let totalOwed = memberSplits.reduce(Decimal(0)) { $0 + $1.owedAmount }
            if abs(totalOwed - total) > 0.01 {
                splitValidationError = "Split amounts must equal \(total.doubleValue.formattedAsMoney(showSign: false))"
            } else {
                splitValidationError = nil
            }
        } else {
            splitValidationError = nil
        }
        
        if paidByType == .custom {
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
                let splitsToSend: [MemberSplit]? = (transactionType == .expense && (splitType == .custom || paidByType == .custom || paidByType == .shared || splitType == .equal))
                    ? memberSplits
                    : nil
                
                // Determine paid by member ID based on transaction type
                let effectivePaidByMemberId: UUID? = {
                    switch transactionType {
                    case .expense:
                        return paidByType == .single ? paidByMemberId : nil
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
                    splitType: transactionType == .expense ? splitType : .equal,
                    paidByType: transactionType == .expense ? paidByType : .single,
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
            await transactionViewModel.deleteTransaction(
                id: transaction.id,
                householdId: transaction.householdId
            )
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
            "split_type": "equal",
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

