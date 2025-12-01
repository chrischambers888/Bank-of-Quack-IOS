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
    @State private var notes = ""
    @State private var excludedFromBudget = false
    
    @State private var showDatePicker = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    private var isFormValid: Bool {
        guard let amountValue = Decimal(string: amount), amountValue > 0 else { return false }
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        switch transactionType {
        case .expense:
            return paidByMemberId != nil && categoryId != nil
        case .income:
            return true
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
                                        transactionType = type
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
                            
                            HStack(alignment: .center, spacing: 4) {
                                Text("$")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("0.00", text: $amount)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                        
                        // Form Fields
                        VStack(spacing: Theme.Spacing.md) {
                            // Description
                            FormField(label: "Description") {
                                TextField("What was this for?", text: $description)
                                    .inputFieldStyle()
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
                            }
                            
                            // Paid By (for expense, settlement, reimbursement)
                            if transactionType != .income {
                                FormField(label: "Paid By") {
                                    MemberSelector(
                                        members: authViewModel.members,
                                        selectedId: $paidByMemberId,
                                        excludeId: transactionType == .settlement ? paidToMemberId : nil
                                    )
                                }
                            }
                            
                            // Paid To (for settlement)
                            if transactionType == .settlement {
                                FormField(label: "Paid To") {
                                    MemberSelector(
                                        members: authViewModel.members,
                                        selectedId: $paidToMemberId,
                                        excludeId: paidByMemberId
                                    )
                                }
                            }
                            
                            // Category (for expense)
                            if transactionType == .expense {
                                FormField(label: "Category") {
                                    CategorySelector(
                                        categories: authViewModel.categories,
                                        selectedId: $categoryId
                                    )
                                }
                                
                                // Split Type
                                if authViewModel.members.count > 1 {
                                    FormField(label: "Split") {
                                        SplitTypeSelector(
                                            selectedType: $splitType,
                                            payerName: authViewModel.members.first { $0.id == paidByMemberId }?.displayName
                                        )
                                    }
                                }
                            }
                            
                            // Notes
                            FormField(label: "Notes (Optional)") {
                                TextField("Add any notes...", text: $notes, axis: .vertical)
                                    .lineLimit(3...5)
                                    .inputFieldStyle()
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        
                        // Submit Button
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
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.md)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationTitle("Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
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
    
    private func submitTransaction() {
        guard let householdId = authViewModel.currentHousehold?.id,
              let amountValue = Decimal(string: amount) else { return }
        
        isSubmitting = true
        
        Task {
            do {
                try await transactionViewModel.createTransaction(
                    householdId: householdId,
                    date: date,
                    description: description.trimmingCharacters(in: .whitespaces),
                    amount: amountValue,
                    transactionType: transactionType,
                    paidByMemberId: paidByMemberId,
                    paidToMemberId: paidToMemberId,
                    categoryId: categoryId,
                    splitType: splitType,
                    excludedFromBudget: excludedFromBudget,
                    notes: notes.isEmpty ? nil : notes,
                    createdByUserId: authViewModel.currentUser?.id
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
        notes = ""
        excludedFromBudget = false
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
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.full)
                                .stroke(category.swiftUIColor, lineWidth: selectedId == category.id ? 0 : 2)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct SplitTypeSelector: View {
    @Binding var selectedType: SplitType
    var payerName: String?
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(SplitType.allCases, id: \.self) { type in
                Button {
                    selectedType = type
                } label: {
                    Text(type == .payerOnly ? "\(payerName ?? "Payer") Only" : type.displayName)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(selectedType == type ? Theme.Colors.accent : Theme.Colors.backgroundCard)
                        .foregroundStyle(selectedType == type ? Theme.Colors.textInverse : Theme.Colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                }
            }
        }
    }
}

#Preview {
    AddTransactionView()
        .environment(AuthViewModel())
        .environment(TransactionViewModel())
}

