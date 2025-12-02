import SwiftUI
import Auth

struct AddTransactionView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(TransactionViewModel.self) private var transactionViewModel
    
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
    
    @State private var showDatePicker = false
    @State private var showNotes = false
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
    
    private var approvedMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isApproved }
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
                    .onTapGesture {
                        focusedField = nil
                    }
                
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
                            
                            // Date
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
                            
                            if showDatePicker {
                                DatePicker(
                                    "",
                                    selection: $date,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.graphical)
                                .tint(Theme.Colors.accent)
                                .colorScheme(.dark)
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
                                    MemberSelector(
                                        members: approvedMembers,
                                        selectedId: $paidByMemberId,
                                        excludeId: nil
                                    )
                                }
                            }
                            
                            // Link to Expense (for reimbursement - optional)
                            if transactionType == .reimbursement {
                                reimbursementLinkSection
                            }
                            
                            // Paid To (for settlement)
                            if transactionType == .settlement {
                                FormField(label: "Paid To") {
                                    MemberSelector(
                                        members: approvedMembers,
                                        selectedId: $paidToMemberId,
                                        excludeId: paidByMemberId
                                    )
                                }
                            }
                            
                            // Category and Split (for expense only)
                            if transactionType == .expense {
                                FormField(label: "Category") {
                                    CategorySelector(
                                        categories: authViewModel.categories,
                                        selectedId: $categoryId
                                    )
                                }
                                
                                // Split Type Section
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
        .onAppear {
            initializeMemberSplits()
            // Set default paid by to current member
            if paidByMemberId == nil {
                paidByMemberId = authViewModel.currentMember?.id
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
    }
    
    // MARK: - Paid By Section
    
    private var paidBySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Paid By")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // For settlements and reimbursements, only allow single member selection
            if transactionType == .settlement || transactionType == .reimbursement {
                MemberSelector(
                    members: approvedMembers,
                    selectedId: $paidByMemberId,
                    excludeId: transactionType == .settlement ? paidToMemberId : nil
                )
            } else if approvedMembers.count > 1 {
                // Paid By Type Picker (for expenses with multiple members)
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
    }
    
    // MARK: - Split Section (Expense For)
    
    private var splitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Expense For")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            // Split Type Picker
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
    
    // MARK: - Reimbursement Link Section
    
    private var reimbursementLinkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Link to Expense (Optional)")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            ExpensePicker(
                expenses: linkableExpenses,
                selectedId: $reimbursesTransactionId
            )
            
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
                splitValidationError = "Split amounts must equal $\(total.doubleValue.formattedAsMoney(showSign: false))"
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
                paidByValidationError = "Paid amounts must equal $\(total.doubleValue.formattedAsMoney(showSign: false))"
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
                        Text(member.displayName)
                            .font(.subheadline)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(selectedId == member.id ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                            .foregroundStyle(selectedId == member.id ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct CategorySelector: View {
    let categories: [Category]
    @Binding var selectedId: UUID?
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(categories) { category in
                    Button {
                        selectedId = category.id
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            if let icon = category.icon {
                                Text(icon)
                            }
                            Text(category.name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(selectedId == category.id ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                        .foregroundStyle(selectedId == category.id ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                        .clipShape(Capsule())
                    }
                }
            }
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
            validationError = "Amounts must equal $\(totalAmount.doubleValue.formattedAsMoney(showSign: false))"
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
                        if let value = Decimal(string: newValue), value > 0 {
                            if editingPaidAmount {
                                split.paidAmount = value
                                if totalAmount > 0 {
                                    split.paidPercentage = (value / totalAmount) * 100
                                    percentageText = String(format: "%.1f", (split.paidPercentage as NSDecimalNumber).doubleValue)
                                }
                            } else {
                                split.owedAmount = value
                                if totalAmount > 0 {
                                    split.owedPercentage = (value / totalAmount) * 100
                                    percentageText = String(format: "%.1f", (split.owedPercentage as NSDecimalNumber).doubleValue)
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
                            percentageText = ""
                            onAmountChanged()
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
                        if let value = Decimal(string: newValue), value > 0 {
                            let newAmount = (value / 100) * totalAmount
                            if editingPaidAmount {
                                split.paidPercentage = value
                                split.paidAmount = newAmount
                                amountText = String(format: "%.2f", (newAmount as NSDecimalNumber).doubleValue)
                            } else {
                                split.owedPercentage = value
                                split.owedAmount = newAmount
                                amountText = String(format: "%.2f", (newAmount as NSDecimalNumber).doubleValue)
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
                            amountText = ""
                            onAmountChanged()
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
            // Start empty if amount is 0, otherwise show current value
            if currentAmount > 0 {
                amountText = String(format: "%.2f", (currentAmount as NSDecimalNumber).doubleValue)
                percentageText = String(format: "%.1f", (currentPercentage as NSDecimalNumber).doubleValue)
            }
        }
        .onChange(of: currentAmount) { _, newValue in
            // Update text when the model changes externally
            if newValue > 0 {
                amountText = String(format: "%.2f", (newValue as NSDecimalNumber).doubleValue)
                percentageText = String(format: "%.1f", (currentPercentage as NSDecimalNumber).doubleValue)
            } else if !isAmountFocused && !isPercentageFocused {
                amountText = ""
                percentageText = ""
            }
        }
    }
}

struct ExpensePicker: View {
    let expenses: [TransactionView]
    @Binding var selectedId: UUID?
    
    private var sortedExpenses: [TransactionView] {
        expenses.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // "None" option
            Button {
                selectedId = nil
            } label: {
                HStack {
                    Text("None (counts as income)")
                        .font(.subheadline)
                        .foregroundStyle(selectedId == nil ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                    Spacer()
                    if selectedId == nil {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textInverse)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(selectedId == nil ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
            
            if !sortedExpenses.isEmpty {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(sortedExpenses.prefix(20)) { expense in
                            Button {
                                selectedId = expense.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(expense.description)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(selectedId == expense.id ? Theme.Colors.textInverse : Theme.Colors.textPrimary)
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
                                            }
                                        }
                                        .foregroundStyle(selectedId == expense.id ? Theme.Colors.textInverse.opacity(0.8) : Theme.Colors.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedId == expense.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.textInverse)
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(selectedId == expense.id ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

#Preview {
    AddTransactionView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}
