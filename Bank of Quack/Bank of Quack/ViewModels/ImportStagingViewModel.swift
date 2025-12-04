import Foundation
import Observation
import SwiftUI

@Observable
final class ImportStagingViewModel {
    
    // MARK: - State
    
    var importRows: [ImportRow] = []
    var splitRows: [ImportSplitRow] = []  // Split data from xlsx Splits sheet
    var categoryRows: [ImportCategoryRow] = []  // Category data from xlsx Categories sheet
    var sectorRows: [ImportSectorRow] = []  // Sector data from xlsx Sectors sheet
    var sectorCategoryRows: [ImportSectorCategoryRow] = []  // Sector-Category linkages
    var summary = ImportSummary()
    var isLoading = false
    var isImporting = false
    var error: String?
    var importResult: ImportResult?
    var hasSplitData = false  // Whether splits were found in the xlsx file
    var hasCategoryData = false  // Whether categories were found in the xlsx file
    var hasSectorData = false  // Whether sectors were found in the xlsx file
    var hasSectorCategoryData = false  // Whether sector-category links were found
    
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
        existingSectors: [Sector],
        existingSectorCategories: [UUID: [UUID]],
        currentUserId: UUID?
    ) async {
        isLoading = true
        error = nil
        importResult = nil
        hasSplitData = false
        hasCategoryData = false
        hasSectorData = false
        hasSectorCategoryData = false
        
        do {
            // Parse XLSX file - this returns all import data
            let parsedData = try importExportService.parseXLSX(from: fileURL)
            
            if parsedData.transactions.isEmpty {
                error = "No valid data found in the Excel file. Make sure the Transactions sheet has a header row and at least one data row."
                isLoading = false
                return
            }
            
            // Validate transaction rows
            let (validatedRows, importSummary) = importExportService.validateRows(
                parsedData.transactions,
                existingCategories: existingCategories,
                existingMembers: existingMembers,
                currentUserId: currentUserId
            )
            
            importRows = validatedRows
            summary = importSummary
            
            // Validate split rows if present
            if !parsedData.splits.isEmpty {
                let validatedSplitRows = importExportService.validateSplitRows(
                    parsedData.splits,
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
            
            // Validate category rows if present (from Categories sheet)
            // This merges with categories already identified from Transactions sheet
            if !parsedData.categories.isEmpty {
                let (validatedCategoryRows, newCategoriesFromSheet, existingCategoriesFromSheet) = importExportService.validateCategoryRows(
                    parsedData.categories,
                    existingCategories: existingCategories
                )
                
                categoryRows = validatedCategoryRows
                hasCategoryData = true
                
                // Merge categories from Categories sheet with those from Transactions
                // The Categories sheet may contain categories not referenced in any transaction
                for categoryName in newCategoriesFromSheet {
                    summary.newCategoriesToCreate.insert(categoryName)
                }
                for categoryName in existingCategoriesFromSheet {
                    summary.existingCategoriesUsed.insert(categoryName)
                }
            }
            
            // Validate sector rows if present
            if !parsedData.sectors.isEmpty {
                let (validatedSectorRows, newSectors, existingSectorsUsed) = importExportService.validateSectorRows(
                    parsedData.sectors,
                    existingSectors: existingSectors
                )
                
                sectorRows = validatedSectorRows
                hasSectorData = true
                summary.newSectorsToCreate = newSectors
                summary.existingSectorsUsed = existingSectorsUsed
            }
            
            // Validate sector-category linkage rows if present
            if !parsedData.sectorCategories.isEmpty {
                let (validatedSCRows, newLinks, existingLinksCount) = importExportService.validateSectorCategoryRows(
                    parsedData.sectorCategories,
                    existingSectors: existingSectors,
                    existingCategories: existingCategories,
                    existingSectorCategories: existingSectorCategories,
                    newSectorsToCreate: summary.newSectorsToCreate,
                    newCategoriesToCreate: summary.newCategoriesToCreate
                )
                
                sectorCategoryRows = validatedSCRows
                hasSectorCategoryData = true
                summary.newSectorCategoryLinks = newLinks
                summary.existingSectorCategoryLinks = existingLinksCount
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
        existingSectors: [Sector],
        currentMemberId: UUID?,
        currentUserId: UUID?,
        onDataCreated: @escaping () -> Void
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
        var createdSectorNames: [String] = []
        var createdSectorCategoryLinksCount = 0
        var createdManagedMemberNames: [String] = []
        
        // Track CSV row -> created transaction ID for reimbursement linking
        var csvRowToTransactionId: [Int: UUID] = [:]
        
        // STEP 1: Create managed members first (so they can be used in transactions)
        var memberMap = Dictionary(uniqueKeysWithValues: existingMembers.filter { $0.status == .approved }.map { ($0.displayName.lowercased(), $0.id) })
        
        for memberName in summary.newManagedMembersToCreate {
            do {
                let newMemberId = try await dataService.createManagedMember(
                    householdId: householdId,
                    displayName: memberName,
                    color: generateRandomColor()
                )
                memberMap[memberName.lowercased()] = newMemberId
                createdManagedMemberNames.append(memberName)
            } catch {
                errors.append("Failed to create member '\(memberName)': \(error.localizedDescription)")
            }
        }
        
        // STEP 2: Create any new categories
        var categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0.id) })
        
        for categoryName in summary.newCategoriesToCreate {
            do {
                let newCategory = try await dataService.createCategory(CreateCategoryDTO(
                    householdId: householdId,
                    name: categoryName,
                    icon: nil,
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
        
        // STEP 3: Create any new sectors
        var sectorMap = Dictionary(uniqueKeysWithValues: existingSectors.map { ($0.name.lowercased(), $0.id) })
        
        for sectorName in summary.newSectorsToCreate {
            do {
                let sortOrder = sectorRows.first { $0.name.lowercased() == sectorName.lowercased() }?.parsedSortOrder ?? (existingSectors.count + createdSectorNames.count)
                let newSector = try await dataService.createSector(CreateSectorDTO(
                    householdId: householdId,
                    name: sectorName,
                    color: generateRandomColor(),
                    sortOrder: sortOrder
                ))
                sectorMap[sectorName.lowercased()] = newSector.id
                createdSectorNames.append(sectorName)
            } catch {
                errors.append("Failed to create sector '\(sectorName)': \(error.localizedDescription)")
            }
        }
        
        // STEP 4: Create sector-category linkages
        for link in summary.newSectorCategoryLinks {
            let sectorLower = link.sectorName.lowercased()
            let categoryLower = link.categoryName.lowercased()
            
            guard let sectorId = sectorMap[sectorLower],
                  let categoryId = categoryMap[categoryLower] else {
                continue
            }
            
            do {
                try await dataService.addCategoryToSector(sectorId: sectorId, categoryId: categoryId)
                createdSectorCategoryLinksCount += 1
            } catch {
                errors.append("Failed to link '\(link.categoryName)' to '\(link.sectorName)': \(error.localizedDescription)")
            }
        }
        
        // STEP 5: Build updated member ID map for looking up splits
        // Re-fetch members to include newly created managed members
        var memberIdMap: [UUID: HouseholdMember] = [:]
        do {
            let updatedMembers = try await dataService.fetchMembers(householdId: householdId)
            memberIdMap = Dictionary(uniqueKeysWithValues: updatedMembers.map { ($0.id, $0) })
        } catch {
            // Fall back to existing members
            memberIdMap = Dictionary(uniqueKeysWithValues: existingMembers.map { ($0.id, $0) })
        }
        
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
        
        // STEP 6: Import non-reimbursement transactions first
        for row in nonReimbursementRows {
            do {
                // Resolve category ID (might be newly created)
                var categoryId = row.matchedCategoryId
                if categoryId == nil && !row.category.isEmpty {
                    categoryId = categoryMap[row.category.lowercased()]
                }
                
                // Resolve paid by member (might be newly created managed member, or default to current member)
                var paidByMemberId = row.matchedPaidByMemberId
                if paidByMemberId == nil && !row.paidBy.isEmpty {
                    paidByMemberId = memberMap[row.paidBy.lowercased()]
                }
                paidByMemberId = paidByMemberId ?? currentMemberId
                
                // Resolve paid to member
                var paidToMemberId = row.matchedPaidToMemberId
                if paidToMemberId == nil && !row.paidTo.isEmpty {
                    paidToMemberId = memberMap[row.paidTo.lowercased()]
                }
                
                // Resolve split member
                var splitMemberId = row.matchedSplitMemberId
                if splitMemberId == nil && !row.splitMember.isEmpty {
                    splitMemberId = memberMap[row.splitMember.lowercased()]
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
                    transactionType: row.parsedType ?? .expense,
                    paidByMemberId: paidByMemberId,
                    paidToMemberId: paidToMemberId,
                    categoryId: categoryId,
                    splitType: row.parsedSplitType ?? .equal,
                    paidByType: .single,
                    splitMemberId: splitMemberId,
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
        
        // STEP 7: Import reimbursements with correct references
        for row in reimbursementRows {
            do {
                // Resolve category ID (might be newly created)
                var categoryId = row.matchedCategoryId
                if categoryId == nil && !row.category.isEmpty {
                    categoryId = categoryMap[row.category.lowercased()]
                }
                
                // Resolve paid by member
                var paidByMemberId = row.matchedPaidByMemberId
                if paidByMemberId == nil && !row.paidBy.isEmpty {
                    paidByMemberId = memberMap[row.paidBy.lowercased()]
                }
                paidByMemberId = paidByMemberId ?? currentMemberId
                
                // Resolve paid to member
                var paidToMemberId = row.matchedPaidToMemberId
                if paidToMemberId == nil && !row.paidTo.isEmpty {
                    paidToMemberId = memberMap[row.paidTo.lowercased()]
                }
                
                // Resolve split member
                var splitMemberId = row.matchedSplitMemberId
                if splitMemberId == nil && !row.splitMember.isEmpty {
                    splitMemberId = memberMap[row.splitMember.lowercased()]
                }
                
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
                    paidToMemberId: paidToMemberId,
                    categoryId: categoryId,
                    splitType: row.parsedSplitType ?? .equal,
                    paidByType: .single,
                    splitMemberId: splitMemberId,
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
        
        // Notify that data was created so caller can refresh
        onDataCreated()
        
        // Re-apply current theme colors to ensure imported sectors/categories match the theme
        // This needs to happen after onDataCreated refreshes the data
        if !createdSectorNames.isEmpty || !createdCategoryNames.isEmpty {
            do {
                // Fetch updated sectors and categories
                let updatedSectors = try await dataService.fetchSectors(householdId: householdId)
                let updatedCategories = try await dataService.fetchCategories(householdId: householdId)
                
                // Re-apply theme colors
                try await AppliedThemeManager.shared.reapplyCurrentThemeColors(
                    sectors: updatedSectors,
                    categories: updatedCategories,
                    dataService: dataService,
                    onComplete: onDataCreated
                )
            } catch {
                // Non-fatal - just log the error, don't fail the import
                print("Failed to re-apply theme colors: \(error)")
            }
        }
        
        importResult = ImportResult(
            successCount: successCount,
            failedCount: failedCount,
            createdCategories: createdCategoryNames,
            createdSectors: createdSectorNames,
            createdSectorCategoryLinks: createdSectorCategoryLinksCount,
            createdManagedMembers: createdManagedMemberNames,
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
        categoryRows = []
        sectorRows = []
        sectorCategoryRows = []
        summary = ImportSummary()
        isLoading = false
        isImporting = false
        error = nil
        importResult = nil
        filterStatus = .all
        hasSplitData = false
        hasCategoryData = false
        hasSectorData = false
        hasSectorCategoryData = false
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
