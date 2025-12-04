import SwiftUI
import UniformTypeIdentifiers
import Auth

struct ImportStagingView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel = ImportStagingViewModel()
    @State private var showFilePicker = false
    @State private var showSplitsFilePicker = false
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
            .navigationTitle("Import Transactions")
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
                allowedContentTypes: [.commaSeparatedText, UTType.csv],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .fileImporter(
                isPresented: $showSplitsFilePicker,
                allowedContentTypes: [.commaSeparatedText, UTType.csv],
                allowsMultipleSelection: false
            ) { result in
                handleSplitsFileSelection(result)
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
            
            Text("Processing CSV file...")
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
                Text("Import Transactions")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("Select a CSV file to import transactions into your household.")
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
                Label("Select CSV File", systemImage: "folder")
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
                
                // Split Data Section (optional file picker)
                splitsDataSection
                
                // New Items Section (Categories to be created)
                if !viewModel.summary.newCategoriesToCreate.isEmpty {
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
    
    // MARK: - Splits Data Section
    
    private var splitsDataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: viewModel.splitsFileLoaded ? "checkmark.circle.fill" : "doc.badge.plus")
                    .foregroundStyle(viewModel.splitsFileLoaded ? Theme.Colors.success : Theme.Colors.accent)
                Text("SPLIT DATA (OPTIONAL)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textMuted)
                
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            
            VStack(spacing: Theme.Spacing.sm) {
                if viewModel.splitsFileLoaded {
                    // Show loaded splits info
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Splits file loaded")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("\(viewModel.summary.totalSplitRows) splits for \(viewModel.summary.transactionsWithSplits) transactions")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            viewModel.clearSplits()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.success.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                } else {
                    // Show button to add splits file
                    Button {
                        showSplitsFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Add Splits File")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text("Optional")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                .stroke(Theme.Colors.borderLight, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.accent)
                    
                    Text("If you exported with split data, add the transaction_splits.csv file here to preserve custom split allocations.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
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
    
    // MARK: - New Items Section
    
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
                ForEach(Array(viewModel.summary.newCategoriesToCreate).sorted(), id: \.self) { categoryName in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "folder.badge.plus")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.warning)
                        
                        Text("Category: \(categoryName)")
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
                    ImportRowCard(row: row)
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
            if viewModel.summary.canImportAll {
                Button {
                    importTransactions()
                } label: {
                    if viewModel.isImporting {
                        ProgressView()
                            .tint(Theme.Colors.textInverse)
                    } else {
                        Label("Import All (\(viewModel.summary.totalRows))", systemImage: "arrow.down.doc")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isImporting)
            } else if viewModel.summary.canImportValid {
                Button {
                    importTransactions()
                } label: {
                    if viewModel.isImporting {
                        ProgressView()
                            .tint(Theme.Colors.textInverse)
                    } else {
                        Label("Import Valid Only (\(viewModel.validRowsToImport.count))", systemImage: "arrow.down.doc")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isImporting)
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
            
            defer { fileURL.stopAccessingSecurityScopedResource() }
            
            Task {
                await viewModel.parseAndValidate(
                    fileURL: fileURL,
                    existingCategories: authViewModel.categories,
                    existingMembers: authViewModel.members,
                    currentUserId: authViewModel.currentUser?.id
                )
            }
            
        case .failure(let error):
            viewModel.error = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func handleSplitsFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard fileURL.startAccessingSecurityScopedResource() else {
                viewModel.error = "Unable to access the splits file"
                return
            }
            
            defer { fileURL.stopAccessingSecurityScopedResource() }
            
            Task {
                await viewModel.parseAndValidateSplits(
                    fileURL: fileURL,
                    existingMembers: authViewModel.members
                )
            }
            
        case .failure(let error):
            viewModel.error = "Failed to select splits file: \(error.localizedDescription)"
        }
    }
    
    private func importTransactions() {
        guard let householdId = authViewModel.currentHousehold?.id else { return }
        
        Task {
            await viewModel.importValidTransactions(
                householdId: householdId,
                existingCategories: authViewModel.categories,
                existingMembers: authViewModel.members,
                currentMemberId: authViewModel.currentMember?.id,
                currentUserId: authViewModel.currentUser?.id,
                onCategoriesCreated: { _ in
                    // Refresh categories in auth view model
                    Task {
                        await authViewModel.refreshCategories()
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
        
        if !result.createdCategories.isEmpty {
            message += "\n\nNew categories created: \(result.createdCategories.joined(separator: ", "))"
        }
        
        if result.failedCount > 0 {
            message += "\n\n\(result.failedCount) transactions failed to import."
        }
        
        return message
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
                        Text(row.description.isEmpty ? "(No description)" : row.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        
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
                    ImportDetailRow(label: "Split Type", value: row.splitType.isEmpty ? "(default: equal)" : row.splitType)
                    
                    if !row.notes.isEmpty {
                        ImportDetailRow(label: "Notes", value: row.notes)
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

