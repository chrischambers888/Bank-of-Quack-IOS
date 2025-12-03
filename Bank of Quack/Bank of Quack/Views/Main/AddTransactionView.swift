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
    @State private var showBalancesSheet = false
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
                            // Shared Equally option
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
                            
                            // Individual member options
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
                            
                            // Custom option
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
    
    // MARK: - Split Section (Expense For)
    
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
                        // Split Equally option
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
                        
                        // Individual member only options
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
                        
                        // Custom option
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
    
    // MARK: - Settlement Balances Card
    
    private var settlementBalancesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Current Balances")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                Spacer()
                
                if !memberBalances.isEmpty {
                    Button {
                        showBalancesSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Details")
                                .font(.caption)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            
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
                // Compact balance summary
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(sortedBalances, id: \.memberId) { balance in
                        HStack {
                            Text(balance.displayName)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(balance.balance.doubleValue.formattedAsMoney(showSign: true))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(balanceColor(for: balance.balance))
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            
            // Helper text
            Text("Positive = owed money • Negative = owes money")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textMuted)
        }
        .sheet(isPresented: $showBalancesSheet) {
            SettlementBalancesSheet(
                balances: memberBalances,
                members: authViewModel.members,
                onSelectSettlement: { fromMember, toMember, amount in
                    // Pre-fill the settlement form
                    paidByMemberId = fromMember
                    paidToMemberId = toMember
                    self.amount = String(format: "%.2f", abs(amount))
                    showBalancesSheet = false
                }
            )
            .presentationDetents([.medium, .large])
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
    }
    
    private func updateMemberSplitsForAmount() {
        let total = parsedAmount
        let memberCount = approvedMembers.count
        guard memberCount > 0 else { return }
        
        let equalShare = total / Decimal(memberCount)
        let equalPercentage: Decimal = 100 / Decimal(memberCount)
        
        for i in memberSplits.indices {
            // Update owed amounts based on split type
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
                // Keep percentages, recalculate amounts
                memberSplits[i].owedAmount = total * memberSplits[i].owedPercentage / 100
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
                memberSplits[i].paidAmount = equalShare
                memberSplits[i].paidPercentage = equalPercentage
            case .custom:
                // Keep percentages, recalculate amounts
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
                break // Keep existing values
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
        
        // Validate owed amounts for custom split
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
        
        // Validate paid amounts for custom paid by
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
    
    private func submitTransaction() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Prepare splits for custom types
                let splitsToSend: [MemberSplit]? = (splitType == .custom || paidByType == .custom || paidByType == .shared || splitType == .equal)
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
                
                try await transactionViewModel.createTransaction(
                    householdId: householdId,
                    date: date,
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: parsedAmount,
                    transactionType: transactionType,
                    paidByMemberId: effectivePaidByMemberId,
                    paidToMemberId: paidToMemberId,
                    categoryId: transactionType == .expense ? categoryId : nil,
                    splitType: transactionType == .expense ? splitType : .equal,
                    paidByType: transactionType == .expense ? paidByType : .single,
                    splitMemberId: transactionType == .expense ? splitMemberId : nil,
                    reimbursesTransactionId: transactionType == .reimbursement ? reimbursesTransactionId : nil,
                    excludedFromBudget: excludedFromBudget,
                    notes: notes.isEmpty ? nil : notes,
                    createdByUserId: authViewModel.currentUser?.id,
                    splits: transactionType == .expense ? splitsToSend : nil
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
                    if let icon = category.icon {
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
        filteredCategories.filter { !categoriesInSectors.contains($0.id) }
    }
    
    private func categoriesForSector(_ sector: Sector) -> [Category] {
        guard let categoryIds = sectorCategories[sector.id] else { return [] }
        return filteredCategories.filter { categoryIds.contains($0.id) }
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
                        ForEach(sectors) { sector in
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
                if let icon = category.icon {
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

// MARK: - Settlement Balances Sheet

struct SettlementBalancesSheet: View {
    let balances: [MemberBalance]
    let members: [HouseholdMember]
    let onSelectSettlement: (UUID, UUID, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    
    /// Balances filtered to exclude inactive members with zero balance
    private var filteredBalances: [MemberBalance] {
        balances.filter { balance in
            // Hide inactive members with zero balance
            if let member = members.first(where: { $0.id == balance.memberId }),
               member.isInactive,
               abs(balance.balance.doubleValue) < 0.01 {
                return false
            }
            return true
        }
    }
    
    private var sortedBalances: [MemberBalance] {
        filteredBalances.sorted { $0.balance.doubleValue > $1.balance.doubleValue }
    }
    
    /// Members who are owed money (positive balance)
    private var creditors: [MemberBalance] {
        filteredBalances.filter { $0.balance.doubleValue > 0.01 }
            .sorted { $0.balance.doubleValue > $1.balance.doubleValue }
    }
    
    /// Members who owe money (negative balance)
    private var debtors: [MemberBalance] {
        filteredBalances.filter { $0.balance.doubleValue < -0.01 }
            .sorted { $0.balance.doubleValue < $1.balance.doubleValue }
    }
    
    /// Calculate suggested settlements to balance everyone out
    private var suggestedSettlements: [(from: MemberBalance, to: MemberBalance, amount: Double)] {
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        // Summary section
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("All Balances")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            VStack(spacing: 0) {
                                ForEach(sortedBalances, id: \.memberId) { balance in
                                    BalanceRow(balance: balance, member: memberFor(balance.memberId))
                                    
                                    if balance.memberId != sortedBalances.last?.memberId {
                                        Divider()
                                            .background(Theme.Colors.borderLight)
                                    }
                                }
                            }
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Suggested Settlements
                        if !suggestedSettlements.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Suggested Settlements")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Text("Tap a suggestion to pre-fill the form")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                VStack(spacing: Theme.Spacing.sm) {
                                    ForEach(suggestedSettlements.indices, id: \.self) { index in
                                        let settlement = suggestedSettlements[index]
                                        SuggestedSettlementRow(
                                            from: settlement.from,
                                            to: settlement.to,
                                            amount: settlement.amount,
                                            fromMember: memberFor(settlement.from.memberId),
                                            toMember: memberFor(settlement.to.memberId)
                                        ) {
                                            onSelectSettlement(
                                                settlement.from.memberId,
                                                settlement.to.memberId,
                                                settlement.amount
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                        }
                        
                        // Legend
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Circle()
                                    .fill(Theme.Colors.income)
                                    .frame(width: 8, height: 8)
                                Text("Owed money (paid more than share)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            
                            HStack(spacing: Theme.Spacing.sm) {
                                Circle()
                                    .fill(Theme.Colors.expense)
                                    .frame(width: 8, height: 8)
                                Text("Owes money (paid less than share)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.sm)
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.top, Theme.Spacing.md)
                }
            }
            .navigationTitle("Household Balances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
    
    private func memberFor(_ memberId: UUID) -> HouseholdMember? {
        members.first { $0.id == memberId }
    }
}

struct BalanceRow: View {
    let balance: MemberBalance
    let member: HouseholdMember?
    
    private var balanceColor: Color {
        let value = balance.balance.doubleValue
        if abs(value) < 0.01 {
            return Theme.Colors.textSecondary
        } else if value > 0 {
            return Theme.Colors.income
        } else {
            return Theme.Colors.expense
        }
    }
    
    private var statusText: String {
        let value = balance.balance.doubleValue
        if abs(value) < 0.01 {
            return "Settled"
        } else if value > 0 {
            return "is owed"
        } else {
            return "owes"
        }
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Avatar
            if let member = member {
                Text(member.avatarUrl ?? String(member.displayName.prefix(1)).uppercased())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textInverse)
                    .frame(width: 36, height: 36)
                    .background(member.swiftUIColor)
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(abs(balance.balance.doubleValue).formattedAsMoney(showSign: false))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(balanceColor)
                
                HStack(spacing: 4) {
                    Text("Paid: \(balance.totalPaid.doubleValue.formattedAsMoney(showSign: false))")
                        .font(.caption2)
                    Text("•")
                        .font(.caption2)
                    Text("Share: \(balance.totalShare.doubleValue.formattedAsMoney(showSign: false))")
                        .font(.caption2)
                }
                .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .padding(Theme.Spacing.sm)
    }
}

struct SuggestedSettlementRow: View {
    let from: MemberBalance
    let to: MemberBalance
    let amount: Double
    let fromMember: HouseholdMember?
    let toMember: HouseholdMember?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                // From member
                VStack(spacing: 2) {
                    if let member = fromMember {
                        Text(member.avatarUrl ?? String(member.displayName.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textInverse)
                            .frame(width: 28, height: 28)
                            .background(member.swiftUIColor)
                            .clipShape(Circle())
                    }
                    Text(from.displayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 60)
                
                // Arrow with amount
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(amount.formattedAsMoney(showSign: false))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                
                // To member
                VStack(spacing: 2) {
                    if let member = toMember {
                        Text(member.avatarUrl ?? String(member.displayName.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textInverse)
                            .frame(width: 28, height: 28)
                            .background(member.swiftUIColor)
                            .clipShape(Circle())
                    }
                    Text(to.displayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 60)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .strokeBorder(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddTransactionView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
