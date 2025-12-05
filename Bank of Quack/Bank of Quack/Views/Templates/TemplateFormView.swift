import SwiftUI

enum TemplateFormMode: Identifiable {
    case create
    case edit(TransactionTemplate)
    
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let template): return template.id.uuidString
        }
    }
    
    var title: String {
        switch self {
        case .create: return "New Template"
        case .edit: return "Edit Template"
        }
    }
    
    var buttonTitle: String {
        switch self {
        case .create: return "Create Template"
        case .edit: return "Save Changes"
        }
    }
}

struct TemplateFormView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    let mode: TemplateFormMode
    
    // Form State
    @State private var name = ""
    @State private var description = ""
    @State private var amount = ""
    @State private var transactionType: TransactionType = .expense
    @State private var categoryId: UUID?
    @State private var splitType: SplitType = .equal
    @State private var paidByMemberId: UUID?
    @State private var paidByType: PaidByType = .single
    @State private var splitMemberId: UUID?
    @State private var excludedFromBudget = false
    @State private var notes = ""
    
    // UI State
    @State private var showCategoryPicker = false
    @State private var showPaidByPicker = false
    @State private var showSplitMemberPicker = false
    @State private var showNotes = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var nameManuallyEdited = false
    
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case name
        case description
        case amount
        case notes
    }
    
    private let dataService = DataService()
    
    private var parsedAmount: Decimal {
        Decimal(string: amount) ?? 0
    }
    
    private var activeMembers: [HouseholdMember] {
        authViewModel.members.filter { $0.isActive }
    }
    
    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard parsedAmount > 0 else { return false }
        
        switch transactionType {
        case .expense:
            if paidByType == .single && activeMembers.count > 1 && paidByMemberId == nil { return false }
            if splitType == .memberOnly && splitMemberId == nil { return false }
            return categoryId != nil
        case .income:
            return activeMembers.count <= 1 || paidByMemberId != nil
        case .settlement:
            return true
        case .reimbursement:
            return activeMembers.count <= 1 || paidByMemberId != nil
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    formContent
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .onAppear {
                loadExistingData()
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
            .sheet(isPresented: $showPaidByPicker) {
                MemberPickerSheet(
                    members: activeMembers,
                    excludeId: nil,
                    title: transactionType == .expense ? "Paid By" : "Received By",
                    selectedId: $paidByMemberId
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSplitMemberPicker) {
                MemberPickerSheet(
                    members: activeMembers,
                    excludeId: nil,
                    title: "Split To",
                    selectedId: $splitMemberId
                )
                .presentationDetents([.medium])
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Form Content
    
    private var formContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            nameField
            transactionTypeSelector
            amountField
            descriptionField
            
            if transactionType == .expense {
                categoryField
            }
            
            paidBySection
            receivedBySection
            splitTypeSection
            budgetExclusionToggle
            notesSection
            submitSection
            
            Spacer(minLength: 50)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
    }
    
    // MARK: - Form Fields
    
    private var nameField: some View {
        FormField(label: "Template Name") {
            TextField("e.g., Weekly Groceries", text: $name)
                .inputFieldStyle()
                .focused($focusedField, equals: .name)
                .onChange(of: name) { oldValue, newValue in
                    // Mark as manually edited if user types while focused on name field
                    if focusedField == .name && oldValue != newValue {
                        nameManuallyEdited = true
                    }
                }
        }
    }
    
    private var transactionTypeSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Transaction Type")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([TransactionType.expense, .income], id: \.self) { type in
                    TransactionTypeButton(
                        type: type,
                        isSelected: transactionType == type
                    ) {
                        withAnimation {
                            transactionType = type
                            resetTypeSpecificFields()
                        }
                    }
                }
            }
        }
    }
    
    private var amountField: some View {
        FormField(label: "Default Amount") {
            HStack {
                Text("$")
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
            }
            .inputFieldStyle()
        }
    }
    
    private var descriptionField: some View {
        FormField(label: "Description") {
            TextField("What is this for?", text: $description)
                .inputFieldStyle()
                .focused($focusedField, equals: .description)
                .onChange(of: description) { _, newValue in
                    // Auto-sync name from description if user hasn't manually edited the name
                    if !nameManuallyEdited {
                        name = newValue
                    }
                }
        }
    }
    
    private var categoryField: some View {
        FormField(label: "Category") {
            CategoryPickerButton(
                categories: authViewModel.categories,
                selectedId: categoryId
            ) {
                showCategoryPicker = true
            }
        }
    }
    
    @ViewBuilder
    private var paidBySection: some View {
        if transactionType == .expense && activeMembers.count > 1 {
            FormField(label: "Default Paid By") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Picker("", selection: $paidByType) {
                        ForEach(PaidByType.pickerCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if paidByType == .single {
                        paidByMemberSelector
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var paidByMemberSelector: some View {
        if activeMembers.count <= 5 {
            MemberSelector(
                members: activeMembers,
                selectedId: $paidByMemberId,
                excludeId: nil
            )
        } else {
            MemberPickerButton(
                members: activeMembers,
                selectedId: paidByMemberId,
                excludeId: nil
            ) {
                showPaidByPicker = true
            }
        }
    }
    
    @ViewBuilder
    private var receivedBySection: some View {
        if (transactionType == .income || transactionType == .reimbursement) && activeMembers.count > 1 {
            FormField(label: "Received By") {
                if activeMembers.count <= 5 {
                    MemberSelector(
                        members: activeMembers,
                        selectedId: $paidByMemberId,
                        excludeId: nil
                    )
                } else {
                    MemberPickerButton(
                        members: activeMembers,
                        selectedId: paidByMemberId,
                        excludeId: nil
                    ) {
                        showPaidByPicker = true
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var splitTypeSection: some View {
        if transactionType == .expense && activeMembers.count > 1 {
            FormField(label: "Expense For") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Picker("", selection: $splitType) {
                        Text("Split Equally").tag(SplitType.equal)
                        Text("Single Member").tag(SplitType.memberOnly)
                        Text("Custom Split").tag(SplitType.custom)
                    }
                    .pickerStyle(.segmented)
                    
                    if splitType == .memberOnly {
                        splitMemberSelector
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var splitMemberSelector: some View {
        if activeMembers.count <= 5 {
            MemberSelector(
                members: activeMembers,
                selectedId: $splitMemberId,
                excludeId: nil
            )
        } else {
            MemberPickerButton(
                members: activeMembers,
                selectedId: splitMemberId,
                excludeId: nil
            ) {
                showSplitMemberPicker = true
            }
        }
    }
    
    @ViewBuilder
    private var budgetExclusionToggle: some View {
        if transactionType == .expense {
            Toggle(isOn: $excludedFromBudget) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exclude from Budget")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Won't count towards budget totals")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .tint(Theme.Colors.accent)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
    }
    
    @ViewBuilder
    private var notesSection: some View {
        if showNotes {
            FormField(label: "Notes") {
                TextField("Add any notes...", text: $notes, axis: .vertical)
                    .lineLimit(3...5)
                    .inputFieldStyle()
                    .focused($focusedField, equals: .notes)
            }
        }
    }
    
    private var submitSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                Task {
                    await submitTemplate()
                }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .tint(Theme.Colors.textInverse)
                } else {
                    Text(mode.buttonTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isFormValid || isSubmitting)
            .frame(maxWidth: .infinity)
            
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
    }
    
    // MARK: - Actions
    
    private func loadExistingData() {
        switch mode {
        case .create:
            if activeMembers.count == 1 {
                paidByMemberId = authViewModel.currentMember?.id
            }
        case .edit(let template):
            name = template.name
            description = template.description
            amount = "\(template.amount)"
            transactionType = template.transactionType
            categoryId = template.categoryId
            splitType = template.splitType
            paidByMemberId = template.paidByMemberId
            // Map 'custom' back to 'shared' for UI display in templates
            paidByType = template.paidByType == .custom ? .shared : template.paidByType
            splitMemberId = template.splitMemberId
            excludedFromBudget = template.excludedFromBudget
            notes = template.notes ?? ""
            showNotes = !notes.isEmpty
            // Mark name as manually edited since we're loading existing data
            nameManuallyEdited = true
        }
    }
    
    private func resetTypeSpecificFields() {
        categoryId = nil
        splitType = .equal
        splitMemberId = nil
        excludedFromBudget = false
    }
    
    private func submitTemplate() async {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        isSubmitting = true
        
        // Convert 'equal' to 'custom' since DB no longer supports 'equal'
        let effectiveSplitType: SplitType = splitType == .equal ? .custom : splitType
        
        // Convert 'shared' to 'custom' since DB no longer supports 'shared'
        let effectivePaidByType: PaidByType = paidByType == .shared ? .custom : paidByType
        
        do {
            switch mode {
            case .create:
                let dto = CreateTemplateDTO(
                    householdId: householdId,
                    createdByMemberId: authViewModel.currentMember?.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: parsedAmount,
                    transactionType: transactionType,
                    categoryId: transactionType == .expense ? categoryId : nil,
                    splitType: transactionType == .expense ? effectiveSplitType : .custom,
                    paidByMemberId: paidByMemberId,
                    paidByType: transactionType == .expense ? effectivePaidByType : .single,
                    splitMemberId: splitType == .memberOnly ? splitMemberId : nil,
                    excludedFromBudget: transactionType == .expense ? excludedFromBudget : false,
                    notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces),
                    sortOrder: authViewModel.templates.count
                )
                
                _ = try await dataService.createTemplate(dto)
                
            case .edit(let template):
                let dto = UpdateTemplateDTO(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: parsedAmount,
                    transactionType: transactionType,
                    categoryId: transactionType == .expense ? categoryId : nil,
                    splitType: transactionType == .expense ? effectiveSplitType : .custom,
                    paidByMemberId: paidByMemberId,
                    paidByType: transactionType == .expense ? effectivePaidByType : .single,
                    splitMemberId: splitType == .memberOnly ? splitMemberId : nil,
                    excludedFromBudget: transactionType == .expense ? excludedFromBudget : false,
                    notes: notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
                )
                
                _ = try await dataService.updateTemplate(id: template.id, dto: dto)
            }
            
            await authViewModel.refreshTemplates()
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isSubmitting = false
    }
}

#Preview {
    TemplateFormView(mode: .create)
        .environment(AuthViewModel())
}
