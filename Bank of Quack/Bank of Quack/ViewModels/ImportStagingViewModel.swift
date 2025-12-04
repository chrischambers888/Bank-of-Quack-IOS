import Foundation
import Observation
import SwiftUI

@Observable
final class ImportStagingViewModel {
    
    // MARK: - State
    
    var importRows: [ImportRow] = []
    var splitRows: [ImportSplitRow] = []  // Split data from xlsx Splits sheet
    var summary = ImportSummary()
    var isLoading = false
    var isImporting = false
    var error: String?
    var importResult: ImportResult?
    var hasSplitData = false  // Whether splits were found in the xlsx file
    
    // Filter state
    var filterStatus: ImportFilterStatus = .all
    
    enum ImportFilterStatus: String, CaseIterable {
        case all = "All"
        case valid = "Valid"
        case warnings = "Warnings"
        case errors = "Errors"
    }
    
    var filteredRows: [ImportRow] {
        switch filterStatus {
        case .all: return importRows
        case .valid: return importRows.filter { $0.validationStatus == .valid }
        case .warnings: return importRows.filter { $0.validationStatus == .validWithWarnings }
        case .errors: return importRows.filter { $0.validationStatus == .invalid }
        }
    }
    
    var validRowsToImport: [ImportRow] {
        importRows.filter { $0.isValid }
    }
    
    /// Splits grouped by their transaction row number
    var splitsByTransactionRow: [Int: [ImportSplitRow]] {
        Dictionary(grouping: splitRows.filter { $0.parsedTransactionRow != nil }) { $0.parsedTransactionRow! }
    }
    
    // MARK: - Services
    
    private let importExportService = ImportExportService()
    private let dataService = DataService()
    
    // MARK: - Parse and Validate
    
    @MainActor
    func parseAndValidate(
        fileURL: URL,
        existingCategories: [Category],
        existingMembers: [HouseholdMember],
        currentUserId: UUID?
    ) async {
        isLoading = true
        error = nil
        importResult = nil
        hasSplitData = false
        
        do {
            // Parse XLSX file - this returns both transactions and splits
            let (rawRows, rawSplitRows) = try importExportService.parseXLSX(from: fileURL)
            
            if rawRows.isEmpty {
                error = "No valid data found in the Excel file. Make sure the Transactions sheet has a header row and at least one data row."
                isLoading = false
                return
            }
            
            // Validate transaction rows
            let (validatedRows, importSummary) = importExportService.validateRows(
                rawRows,
                existingCategories: existingCategories,
                existingMembers: existingMembers,
                currentUserId: currentUserId
            )
            
            importRows = validatedRows
            summary = importSummary
            
            // Validate split rows if present
            if !rawSplitRows.isEmpty {
                let validatedSplitRows = importExportService.validateSplitRows(
                    rawSplitRows,
                    existingMembers: existingMembers
                )
                
                splitRows = validatedSplitRows
                hasSplitData = true
                
                // Update summary with split info
                summary.totalSplitRows = splitRows.count
                
                // Count how many transactions have splits
                let transactionRowsWithSplits = Set(splitRows.compactMap { $0.parsedTransactionRow })
                summary.transactionsWithSplits = transactionRowsWithSplits.count
            }
            
        } catch {
            self.error = "Failed to read Excel file: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Import Actions
    
    @MainActor
    func importValidTransactions(
        householdId: UUID,
        existingCategories: [Category],
        existingMembers: [HouseholdMember],
        currentMemberId: UUID?,
        currentUserId: UUID?,
        onCategoriesCreated: @escaping ([Category]) -> Void
    ) async {
        isImporting = true
        error = nil
        
        let rowsToImport = validRowsToImport
        guard !rowsToImport.isEmpty else {
            error = "No valid transactions to import"
            isImporting = false
            return
        }
        
        var successCount = 0
        var failedCount = 0
        var errors: [String] = []
        var createdCategoryNames: [String] = []
        
        // Track CSV row -> created transaction ID for reimbursement linking
        var csvRowToTransactionId: [Int: UUID] = [:]
        
        // First, create any new categories
        var categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0.id) })
        
        for categoryName in summary.newCategoriesToCreate {
            do {
                let newCategory = try await dataService.createCategory(CreateCategoryDTO(
                    householdId: householdId,
                    name: categoryName,
                    icon: "folder",
                    color: generateRandomColor(),
                    imageUrl: nil,
                    sortOrder: existingCategories.count + createdCategoryNames.count
                ))
                categoryMap[categoryName.lowercased()] = newCategory.id
                createdCategoryNames.append(categoryName)
            } catch {
                errors.append("Failed to create category '\(categoryName)': \(error.localizedDescription)")
            }
        }
        
        // Fetch newly created categories to pass back
        if !createdCategoryNames.isEmpty {
            do {
                let allCategories = try await dataService.fetchCategories(householdId: householdId)
                onCategoriesCreated(allCategories)
            } catch {
                // Non-fatal, continue with import
            }
        }
        
        // Build member ID map for looking up splits
        let memberIdMap = Dictionary(uniqueKeysWithValues: existingMembers.map { ($0.id, $0) })
        
        // Get splits grouped by transaction row
        let splitsMap = splitsByTransactionRow
        
        // Separate reimbursements (that reference another row) from other transactions
        let (reimbursementRows, nonReimbursementRows) = rowsToImport.reduce(into: ([ImportRow](), [ImportRow]())) { result, row in
            if row.isReimbursementWithReference {
                result.0.append(row)
            } else {
                result.1.append(row)
            }
        }
        
        // PASS 1: Import non-reimbursement transactions first
        for row in nonReimbursementRows {
            do {
                // Resolve category ID (might be newly created)
                var categoryId = row.matchedCategoryId
                if categoryId == nil && !row.category.isEmpty {
                    categoryId = categoryMap[row.category.lowercased()]
                }
                
                // Resolve paid by member (default to current member if not specified)
                let paidByMemberId = row.matchedPaidByMemberId ?? currentMemberId
                
                // Get splits for this transaction if available
                let rowNumber = row.parsedCsvRow ?? row.rowNumber
                let memberSplits = buildMemberSplits(
                    from: splitsMap[rowNumber] ?? [],
                    memberIdMap: memberIdMap,
                    totalAmount: row.parsedAmount ?? 0
                )
                
                let transactionId = try await dataService.createTransactionWithSplits(
                    householdId: householdId,
                    date: row.parsedDate ?? Date(),
                    description: row.description,
                    amount: row.parsedAmount ?? 0,
                    transactionType: row.parsedType ?? .expense,
                    paidByMemberId: paidByMemberId,
                    paidToMemberId: row.matchedPaidToMemberId,
                    categoryId: categoryId,
                    splitType: row.parsedSplitType ?? .equal,
                    paidByType: .single,
                    splitMemberId: row.matchedSplitMemberId,
                    reimbursesTransactionId: nil,
                    excludedFromBudget: row.parsedExcludedFromBudget,
                    notes: row.notes.isEmpty ? nil : row.notes,
                    createdByUserId: currentUserId,
                    splits: memberSplits
                )
                
                // Track the mapping for reimbursement linking
                if let csvRow = row.parsedCsvRow {
                    csvRowToTransactionId[csvRow] = transactionId
                }
                
                successCount += 1
            } catch {
                failedCount += 1
                errors.append("Row \(row.rowNumber): \(error.localizedDescription)")
            }
        }
        
        // PASS 2: Import reimbursements with correct references
        for row in reimbursementRows {
            do {
                // Resolve category ID (might be newly created)
                var categoryId = row.matchedCategoryId
                if categoryId == nil && !row.category.isEmpty {
                    categoryId = categoryMap[row.category.lowercased()]
                }
                
                // Resolve paid by member (default to current member if not specified)
                let paidByMemberId = row.matchedPaidByMemberId ?? currentMemberId
                
                // Look up the reimbursed transaction ID
                var reimbursesTransactionId: UUID? = nil
                if let reimbursesRow = row.parsedReimbursesRow {
                    reimbursesTransactionId = csvRowToTransactionId[reimbursesRow]
                    if reimbursesTransactionId == nil {
                        errors.append("Row \(row.rowNumber): Referenced expense row \(reimbursesRow) was not imported or not found")
                    }
                }
                
                // Get splits for this transaction if available
                let rowNumber = row.parsedCsvRow ?? row.rowNumber
                let memberSplits = buildMemberSplits(
                    from: splitsMap[rowNumber] ?? [],
                    memberIdMap: memberIdMap,
                    totalAmount: row.parsedAmount ?? 0
                )
                
                let transactionId = try await dataService.createTransactionWithSplits(
                    householdId: householdId,
                    date: row.parsedDate ?? Date(),
                    description: row.description,
                    amount: row.parsedAmount ?? 0,
                    transactionType: row.parsedType ?? .reimbursement,
                    paidByMemberId: paidByMemberId,
                    paidToMemberId: row.matchedPaidToMemberId,
                    categoryId: categoryId,
                    splitType: row.parsedSplitType ?? .equal,
                    paidByType: .single,
                    splitMemberId: row.matchedSplitMemberId,
                    reimbursesTransactionId: reimbursesTransactionId,
                    excludedFromBudget: row.parsedExcludedFromBudget,
                    notes: row.notes.isEmpty ? nil : row.notes,
                    createdByUserId: currentUserId,
                    splits: memberSplits
                )
                
                // Track the mapping in case there are chained reimbursements
                if let csvRow = row.parsedCsvRow {
                    csvRowToTransactionId[csvRow] = transactionId
                }
                
                successCount += 1
            } catch {
                failedCount += 1
                errors.append("Row \(row.rowNumber): \(error.localizedDescription)")
            }
        }
        
        importResult = ImportResult(
            successCount: successCount,
            failedCount: failedCount,
            createdCategories: createdCategoryNames,
            errors: errors
        )
        
        isImporting = false
    }
    
    /// Builds MemberSplit array from ImportSplitRow data
    private func buildMemberSplits(
        from splitRows: [ImportSplitRow],
        memberIdMap: [UUID: HouseholdMember],
        totalAmount: Decimal
    ) -> [MemberSplit]? {
        guard !splitRows.isEmpty else { return nil }
        
        var memberSplits: [MemberSplit] = []
        
        for splitRow in splitRows {
            guard let memberId = splitRow.matchedMemberId,
                  let member = memberIdMap[memberId] else {
                continue
            }
            
            let memberSplit = MemberSplit(
                id: memberId,
                displayName: member.displayName,
                owedAmount: splitRow.parsedOwedAmount ?? 0,
                owedPercentage: splitRow.parsedOwedPercentage ?? 0,
                paidAmount: splitRow.parsedPaidAmount ?? 0,
                paidPercentage: splitRow.parsedPaidPercentage ?? 0
            )
            memberSplits.append(memberSplit)
        }
        
        return memberSplits.isEmpty ? nil : memberSplits
    }
    
    // MARK: - Export Failed Rows
    
    func getFailedRowsFileURL() -> URL? {
        do {
            return try importExportService.generateFailedRowsXLSX(importRows)
        } catch {
            return nil
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        importRows = []
        splitRows = []
        summary = ImportSummary()
        isLoading = false
        isImporting = false
        error = nil
        importResult = nil
        filterStatus = .all
        hasSplitData = false
    }
    
    // MARK: - Helpers
    
    private func generateRandomColor() -> String {
        let colors = [
            "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
            "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F",
            "#BB8FCE", "#85C1E9", "#F8B500", "#FF8C00",
            "#00CED1", "#FF69B4", "#32CD32", "#FFD700"
        ]
        return colors.randomElement() ?? "#4ECDC4"
    }
}
