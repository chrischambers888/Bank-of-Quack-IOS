import SwiftUI
import UniformTypeIdentifiers
import Auth

struct ImportStagingView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel = ImportStagingViewModel()
    @State private var showFilePicker = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.importRows.isEmpty {
                    emptyStateView
                } else {
                    stagingContentView
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.xlsx, .spreadsheet],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ImportShareSheet(activityItems: [url])
            }
        }
            .alert("Import Complete", isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                if let result = viewModel.importResult {
                    Text(importResultMessage(result))
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Theme.Colors.accent)
            
            Text("Processing Excel file...")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accent)
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("Import Data")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Select an Excel file (.xlsx) to import transactions, sectors, and members into your bank.")
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
            
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                    .padding(.horizontal, Theme.Spacing.lg)
            }
            
            Button {
                showFilePicker = true
            } label: {
                Label("Select Excel File", systemImage: "folder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.lg)
            
            Spacer()
        }
    }
    
    // MARK: - Staging Content View
    
    private var stagingContentView: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Summary Card
                summaryCard
                
                // Verification Totals
                verificationTotalsSection
                
                // Split Data Section (auto-detected from xlsx)
                if viewModel.hasSplitData {
                    splitsDataSection
                }
                
                // New Items to Create Section
                if hasNewItemsToCreate {
                    newItemsSection
                }
                
                // Filter Pills
                filterPills
                
                // Transaction Rows
                transactionRowsSection
                
                // Error message
                if let error = viewModel.error {
                    errorBanner(error)
                }
                
                // Action Buttons
                actionButtons
                
                Spacer(minLength: 100)
            }
            .padding(.top, Theme.Spacing.md)
        }
    }
    
    /// Returns true if there are any new items to create
    private var hasNewItemsToCreate: Bool {
        !viewModel.summary.newCategoriesToCreate.isEmpty ||
        !viewModel.summary.newSectorsToCreate.isEmpty ||
        !viewModel.summary.newSectorCategoryLinks.isEmpty ||
        !viewModel.summary.newManagedMembersToCreate.isEmpty
    }
    
    // MARK: - Splits Data Section (auto-detected)
    
    private var splitsDataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("SPLIT DATA FOUND")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textMuted)
                
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Splits sheet detected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("\(viewModel.summary.totalSplitRows) splits for \(viewModel.summary.transactionsWithSplits) transactions")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "tablecells")
                        .foregroundStyle(Theme.Colors.success)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                
                // Show reimbursement references info if present
                if viewModel.summary.reimbursementsWithReferences > 0 {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "link")
                            .foregroundStyle(Theme.Colors.accent)
                        
                        Text("\(viewModel.summary.reimbursementsWithReferences) reimbursement(s) with expense references")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Summary Card
    
    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Import Summary")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            HStack(spacing: Theme.Spacing.lg) {
                SummaryStatView(
                    value: viewModel.summary.totalRows,
                    label: "Total",
                    color: Theme.Colors.textPrimary
                )
                
                SummaryStatView(
                    value: viewModel.summary.validRows,
                    label: "Valid",
                    color: Theme.Colors.success
                )
                
                SummaryStatView(
                    value: viewModel.summary.warningRows,
                    label: "Warnings",
                    color: Theme.Colors.warning
                )
                
                SummaryStatView(
                    value: viewModel.summary.errorRows,
                    label: "Errors",
                    color: Theme.Colors.error
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    // MARK: - Verification Totals Section
    
    @State private var showVerificationTotals = false
    
    private var verificationTotalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showVerificationTotals.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(Theme.Colors.accent)
                    Text("VERIFICATION TOTALS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Spacer()
                    
                    Image(systemName: showVerificationTotals ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showVerificationTotals {
                VStack(spacing: Theme.Spacing.sm) {
                    // Calculate totals from valid rows
                    let validRows = viewModel.validRowsToImport
                    
                    let expenseTotal = validRows
                        .filter { $0.parsedType == .expense || $0.parsedType == nil }
                        .compactMap { $0.parsedAmount }
                        .reduce(Decimal(0), +)
                    
                    let incomeTotal = validRows
                        .filter { $0.parsedType == .income }
                        .compactMap { $0.parsedAmount }
                        .reduce(Decimal(0), +)
                    
                    let settlementTotal = validRows
                        .filter { $0.parsedType == .settlement }
                        .compactMap { $0.parsedAmount }
                        .reduce(Decimal(0), +)
                    
                    let reimbursementTotal = validRows
                        .filter { $0.parsedType == .reimbursement }
                        .compactMap { $0.parsedAmount }
                        .reduce(Decimal(0), +)
                    
                    let expenseCount = validRows.filter { $0.parsedType == .expense || $0.parsedType == nil }.count
                    let incomeCount = validRows.filter { $0.parsedType == .income }.count
                    let settlementCount = validRows.filter { $0.parsedType == .settlement }.count
                    let reimbursementCount = validRows.filter { $0.parsedType == .reimbursement }.count
                    
                    VerificationTotalRow(
                        icon: "cart.fill",
                        label: "Expenses",
                        count: expenseCount,
                        total: expenseTotal,
                        color: Theme.Colors.error
                    )
                    
                    VerificationTotalRow(
                        icon: "arrow.down.circle.fill",
                        label: "Income",
                        count: incomeCount,
                        total: incomeTotal,
                        color: Theme.Colors.success
                    )
                    
                    if settlementCount > 0 {
                        VerificationTotalRow(
                            icon: "arrow.left.arrow.right.circle.fill",
                            label: "Settlements",
                            count: settlementCount,
                            total: settlementTotal,
                            color: Theme.Colors.accent
                        )
                    }
                    
                    if reimbursementCount > 0 {
                        VerificationTotalRow(
                            icon: "arrow.uturn.backward.circle.fill",
                            label: "Reimbursements",
                            count: reimbursementCount,
                            total: reimbursementTotal,
                            color: Theme.Colors.warning
                        )
                    }
                    
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Net total
                    let netTotal = incomeTotal - expenseTotal + reimbursementTotal
                    HStack {
                        Text("Net (Income - Expenses + Reimbursements)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text(formatCurrency(netTotal))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(netTotal >= 0 ? Theme.Colors.balancePositive : Theme.Colors.balanceNegative)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.internationalCurrencySymbol = ""
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
    
    // MARK: - New Items Section (Categories, Sectors, Members, Links)
    
    private var newItemsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.warning)
                Text("NEW ITEMS TO CREATE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.warning)
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // New Managed Members
                ForEach(Array(viewModel.summary.newManagedMembersToCreate).sorted(), id: \.self) { memberName in
                    NewItemRow(
                        icon: "person.badge.plus",
                        label: "Member",
                        name: memberName
                    )
                }
                
                // New Categories
                ForEach(Array(viewModel.summary.newCategoriesToCreate).sorted(), id: \.self) { categoryName in
                    NewItemRow(
                        icon: "folder.badge.plus",
                        label: "Category",
                        name: categoryName
                    )
                }
                
                // New Sectors
                ForEach(Array(viewModel.summary.newSectorsToCreate).sorted(), id: \.self) { sectorName in
                    NewItemRow(
                        icon: "rectangle.3.group.badge.plus",
                        label: "Sector",
                        name: sectorName
                    )
                }
                
                // New Sector-Category Links
                ForEach(viewModel.summary.newSectorCategoryLinks.indices, id: \.self) { index in
                    let link = viewModel.summary.newSectorCategoryLinks[index]
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "link.badge.plus")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.warning)
                        
                        Text("\(link.categoryName)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                        
                        Text("\(link.sectorName)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text("LINK")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.warning.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Filter Pills
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ImportStagingViewModel.ImportFilterStatus.allCases, id: \.self) { status in
                    FilterPill(
                        title: status.rawValue,
                        count: countForStatus(status),
                        isSelected: viewModel.filterStatus == status,
                        color: colorForStatus(status)
                    ) {
                        withAnimation {
                            viewModel.filterStatus = status
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Transaction Rows Section
    
    private var transactionRowsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TRANSACTIONS (\(viewModel.filteredRows.count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textMuted)
                .padding(.horizontal, Theme.Spacing.md)
            
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.filteredRows) { row in
                    // Get splits for this row (using parsedCsvRow or rowNumber)
                    let rowNumber = row.parsedCsvRow ?? row.rowNumber
                    let splits = viewModel.splitsByTransactionRow[rowNumber] ?? []
                    ImportRowCard(row: row, splits: splits)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.error)
            
            Text(error)
                .font(.caption)
                .foregroundStyle(Theme.Colors.error)
            
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Show progress during import
            if viewModel.isImporting {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: viewModel.importProgress) {
                        Text(viewModel.importProgressMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .tint(Theme.Colors.accent)
                    
                    Text("\(Int(viewModel.importProgress * 100))%")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            } else {
                if viewModel.summary.canImportAll {
                    Button {
                        importTransactions()
                    } label: {
                        Label("Import All (\(viewModel.summary.totalRows))", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else if viewModel.summary.canImportValid {
                    Button {
                        importTransactions()
                    } label: {
                        Label("Import Valid Only (\(viewModel.validRowsToImport.count))", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                
                if viewModel.summary.errorRows > 0 {
                    Button {
                        exportFailedRows()
                    } label: {
                        Label("Download Failed Rows", systemImage: "arrow.up.doc")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose Different File", systemImage: "folder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }
    
    // MARK: - Helpers
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard fileURL.startAccessingSecurityScopedResource() else {
                viewModel.error = "Unable to access the selected file"
                return
            }
            
            // Copy file to temporary location while we have access
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
            do {
                // Remove existing temp file if present
                try? FileManager.default.removeItem(at: tempURL)
                try FileManager.default.copyItem(at: fileURL, to: tempURL)
            } catch {
                fileURL.stopAccessingSecurityScopedResource()
                viewModel.error = "Failed to access file: \(error.localizedDescription)"
                return
            }
            
            // Stop accessing the original security-scoped resource
            fileURL.stopAccessingSecurityScopedResource()
            
            // Now parse from the temp copy
            Task {
                await viewModel.parseAndValidate(
                    fileURL: tempURL,
                    existingCategories: authViewModel.categories,
                    existingMembers: authViewModel.members,
                    existingSectors: authViewModel.sectors,
                    existingSectorCategories: authViewModel.sectorCategories,
                    currentUserId: authViewModel.currentUser?.id
                )
                
                // Clean up temp file after parsing
                try? FileManager.default.removeItem(at: tempURL)
            }
            
        case .failure(let error):
            viewModel.error = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func importTransactions() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        Task {
            await viewModel.importValidTransactions(
                householdId: householdId,
                existingCategories: authViewModel.categories,
                existingMembers: authViewModel.members,
                existingSectors: authViewModel.sectors,
                currentMemberId: authViewModel.currentMember?.id,
                currentUserId: authViewModel.currentUser?.id,
                onDataCreated: {
                    // Refresh data in auth view model
                    Task {
                        await authViewModel.refreshCategories()
                        await authViewModel.refreshSectors()
                        // Re-select household to refresh members
                        if let household = authViewModel.currentHousehold {
                            await authViewModel.selectHousehold(household)
                        }
                    }
                }
            )
            
            if viewModel.importResult != nil {
                showSuccessAlert = true
            }
        }
    }
    
    private func exportFailedRows() {
        if let url = viewModel.getFailedRowsFileURL() {
            shareURL = url
            showShareSheet = true
        }
    }
    
    private func countForStatus(_ status: ImportStagingViewModel.ImportFilterStatus) -> Int {
        switch status {
        case .all: return viewModel.summary.totalRows
        case .valid: return viewModel.summary.validRows
        case .warnings: return viewModel.summary.warningRows
        case .errors: return viewModel.summary.errorRows
        }
    }
    
    private func colorForStatus(_ status: ImportStagingViewModel.ImportFilterStatus) -> Color {
        switch status {
        case .all: return Theme.Colors.accent
        case .valid: return Theme.Colors.success
        case .warnings: return Theme.Colors.warning
        case .errors: return Theme.Colors.error
        }
    }
    
    private func importResultMessage(_ result: ImportResult) -> String {
        var message = "\(result.successCount) transactions imported successfully."
        
        if !result.createdManagedMembers.isEmpty {
            message += "\n\nNew members created: \(result.createdManagedMembers.joined(separator: ", "))"
        }
        
        if !result.createdCategories.isEmpty {
            message += "\n\nNew categories created: \(result.createdCategories.joined(separator: ", "))"
        }
        
        if !result.createdSectors.isEmpty {
            message += "\n\nNew sectors created: \(result.createdSectors.joined(separator: ", "))"
        }
        
        if result.createdSectorCategoryLinks > 0 {
            message += "\n\n\(result.createdSectorCategoryLinks) sector-category link(s) created."
        }
        
        if result.failedCount > 0 {
            message += "\n\n\(result.failedCount) transaction(s) failed to import."
            
            // Show actual error messages (limit to first 5 for readability)
            if !result.errors.isEmpty {
                let maxErrorsToShow = 5
                let errorsToShow = Array(result.errors.prefix(maxErrorsToShow))
                message += "\n\nErrors:\n• " + errorsToShow.joined(separator: "\n• ")
                
                if result.errors.count > maxErrorsToShow {
                    message += "\n\n...and \(result.errors.count - maxErrorsToShow) more error(s)."
                }
            }
        }
        
        return message
    }
}

// MARK: - New Item Row

struct NewItemRow: View {
    let icon: String
    let label: String
    let name: String
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.Colors.warning)
            
            Text("\(label): \(name)")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Spacer()
            
            Text("NEW")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Colors.warning.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Summary Stat View

struct SummaryStatView: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? color.opacity(0.3) : Theme.Colors.textMuted.opacity(0.2))
                    .clipShape(Capsule())
            }
            .foregroundStyle(isSelected ? color : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? color.opacity(0.15) : Theme.Colors.backgroundCard)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
    }
}

// MARK: - Import Row Card

struct ImportRowCard: View {
    let row: ImportRow
    let splits: [ImportSplitRow]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    // Status Icon
                    statusIcon
                    
                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(row.description.isEmpty ? "(No description)" : row.description)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            
                            // Split indicator
                            if !splits.isEmpty {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(row.date)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            if !row.category.isEmpty {
                                Text("•")
                                    .foregroundStyle(Theme.Colors.textMuted)
                                Text(row.category)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Amount
                    Text(row.amount.isEmpty ? "--" : "$\(row.amount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(Theme.Spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Divider()
                        .background(Theme.Colors.borderLight)
                    
                    // Row details
                    ImportDetailRow(label: "Row #", value: "\(row.rowNumber)")
                    ImportDetailRow(label: "Type", value: row.type.isEmpty ? "(default: expense)" : row.type)
                    ImportDetailRow(label: "Paid By", value: row.paidBy.isEmpty ? "(will use current user)" : row.paidBy)
                    ImportDetailRow(label: "Expense For", value: row.expenseFor.isEmpty ? "(will split equally)" : row.expenseFor)
                    
                    if !row.notes.isEmpty {
                        ImportDetailRow(label: "Notes", value: row.notes)
                    }
                    
                    // Split breakdowns
                    if !splits.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            // Expense For Split (owed amounts)
                            let expenseForSplits = splits.filter { 
                                ($0.parsedOwedAmount ?? 0) > 0 || ($0.parsedOwedPercentage ?? 0) > 0 
                            }
                            if !expenseForSplits.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack {
                                        Image(systemName: "cart.fill")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.error)
                                        Text("Expense For Split:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.Colors.error)
                                    }
                                    
                                    ForEach(expenseForSplits) { split in
                                        ImportSplitMemberRow(
                                            memberName: split.memberName,
                                            amount: split.parsedOwedAmount,
                                            percentage: split.parsedOwedPercentage
                                        )
                                    }
                                }
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                            }
                            
                            // Paid By Split (paid amounts)
                            let paidBySplits = splits.filter { 
                                ($0.parsedPaidAmount ?? 0) > 0 || ($0.parsedPaidPercentage ?? 0) > 0 
                            }
                            if !paidBySplits.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack {
                                        Image(systemName: "creditcard.fill")
                                            .font(.caption)
                                            .foregroundStyle(Theme.Colors.success)
                                        Text("Paid By Split:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Theme.Colors.success)
                                    }
                                    
                                    ForEach(paidBySplits) { split in
                                        ImportSplitMemberRow(
                                            memberName: split.memberName,
                                            amount: split.parsedPaidAmount,
                                            percentage: split.parsedPaidPercentage
                                        )
                                    }
                                }
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.success.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                    
                    // Errors
                    if !row.validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Errors:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.error)
                            
                            ForEach(row.validationErrors) { error in
                                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.error)
                                    
                                    Text(error.message)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.error)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                    
                    // Warnings
                    if !row.validationWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Warnings:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.warning)
                            
                            ForEach(row.validationWarnings) { warning in
                                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.warning)
                                    
                                    Text(warning.message)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.warning)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            }
        }
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var statusIcon: some View {
        Group {
            switch row.validationStatus {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
            case .validWithWarnings:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Colors.error)
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .font(.title3)
    }
    
    private var borderColor: Color {
        switch row.validationStatus {
        case .valid: return Color.clear
        case .validWithWarnings: return Theme.Colors.warning.opacity(0.3)
        case .invalid: return Theme.Colors.error.opacity(0.3)
        case .pending: return Color.clear
        }
    }
}

// MARK: - Import Detail Row

struct ImportDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textMuted)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            
            Spacer()
        }
    }
}

// MARK: - Import Split Member Row

struct ImportSplitMemberRow: View {
    let memberName: String
    let amount: Decimal?
    let percentage: Decimal?
    
    private var formattedPercentage: String? {
        guard let pct = percentage, pct > 0 else { return nil }
        let doubleValue = NSDecimalNumber(decimal: pct).doubleValue
        // Round to 2 decimal places, but remove trailing zeros
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", doubleValue)
        } else if (doubleValue * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f%%", doubleValue)
        } else {
            return String(format: "%.2f%%", doubleValue)
        }
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Member name
            Text(memberName.isEmpty ? "(Unknown)" : memberName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Spacer()
            
            // Percentage and amount
            HStack(spacing: Theme.Spacing.xs) {
                if let pctStr = formattedPercentage {
                    Text(pctStr)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                if let amt = amount, amt > 0 {
                    Text("$\(amt as NSDecimalNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Verification Total Row

struct VerificationTotalRow: View {
    let icon: String
    let label: String
    let count: Int
    let total: Decimal
    let color: Color
    
    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.internationalCurrencySymbol = ""
        return formatter.string(from: total as NSDecimalNumber) ?? "$0.00"
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textMuted)
            
            Spacer()
            
            Text(formattedTotal)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Import Share Sheet

struct ImportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ImportStagingView()
        .environment(AuthViewModel())
}
