import Foundation
import UniformTypeIdentifiers
import CoreXLSX

final class ImportExportService: Sendable {
    
    // MARK: - Date Formatters
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private static let alternateDateFormatters: [DateFormatter] = {
        let formats = ["MM/dd/yyyy", "dd/MM/yyyy", "M/d/yyyy", "d/M/yyyy", "yyyy/MM/dd"]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()
    
    // MARK: - Export Functions
    
    /// Exports all household data to a single XLSX file with multiple sheets
    /// Returns the URL to the export file
    func exportHouseholdData(
        transactions: [TransactionView],
        transactionSplits: [TransactionSplit],
        categories: [Category],
        sectors: [Sector],
        sectorCategories: [(sectorName: String, categoryName: String)],
        members: [HouseholdMember],
        householdName: String
    ) throws -> URL {
        let xlsxWriter = XlsxWriter()
        
        // Build lookup maps
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let memberMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        
        // Build transaction row mapping
        var transactionRowMap: [UUID: Int] = [:]
        for (index, transaction) in transactions.enumerated() {
            transactionRowMap[transaction.id] = index + 1
        }
        
        // Sheet 1: Transactions
        let transactionHeaders = ExportTransaction.headers
        var transactionRows: [[String]] = []
        
        for (index, transaction) in transactions.enumerated() {
            let rowNumber = index + 1
            
            var reimbursesRow = ""
            if let reimbursedTransactionId = transaction.reimbursesTransactionId,
               let reimbursedRowNumber = transactionRowMap[reimbursedTransactionId] {
                reimbursesRow = String(reimbursedRowNumber)
            }
            
            let export = ExportTransaction(
                row: rowNumber,
                date: Self.dateFormatter.string(from: transaction.date),
                description: transaction.description,
                amount: "\(transaction.amount)",
                type: transaction.transactionType.rawValue,
                category: transaction.categoryId.flatMap { categoryMap[$0] } ?? "",
                paidBy: transaction.paidByMemberId.flatMap { memberMap[$0] } ?? "",
                paidTo: transaction.paidToMemberId.flatMap { memberMap[$0] } ?? "",
                splitType: transaction.splitType.rawValue,
                splitMember: transaction.splitMemberId.flatMap { memberMap[$0] } ?? "",
                reimbursesRow: reimbursesRow,
                excludedFromBudget: transaction.excludedFromBudget ? "Yes" : "No",
                notes: transaction.notes ?? ""
            )
            
            transactionRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Transactions", headers: transactionHeaders, rows: transactionRows)
        
        // Sheet 2: Splits
        let splitHeaders = ExportTransactionSplit.headers
        var splitRows: [[String]] = []
        
        for split in transactionSplits {
            guard let rowNumber = transactionRowMap[split.transactionId],
                  let memberName = memberMap[split.memberId] else {
                continue
            }
            
            let export = ExportTransactionSplit(
                transactionRow: rowNumber,
                memberName: memberName,
                owedAmount: "\(split.owedAmount)",
                owedPercentage: split.owedPercentage.map { "\($0)" } ?? "",
                paidAmount: "\(split.paidAmount)",
                paidPercentage: split.paidPercentage.map { "\($0)" } ?? ""
            )
            
            splitRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Splits", headers: splitHeaders, rows: splitRows)
        
        // Sheet 3: Categories
        let categoryHeaders = ExportCategory.headers
        var categoryRows: [[String]] = []
        
        for category in categories {
            let export = ExportCategory(
                name: category.name,
                sortOrder: String(category.sortOrder)
            )
            categoryRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Categories", headers: categoryHeaders, rows: categoryRows)
        
        // Sheet 4: Sectors
        let sectorHeaders = ExportSector.headers
        var sectorRows: [[String]] = []
        
        for sector in sectors {
            let export = ExportSector(
                name: sector.name,
                sortOrder: String(sector.sortOrder)
            )
            sectorRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Sectors", headers: sectorHeaders, rows: sectorRows)
        
        // Sheet 5: Sector Categories
        let sectorCategoryHeaders = ExportSectorCategory.headers
        var sectorCategoryRows: [[String]] = []
        
        for mapping in sectorCategories {
            let export = ExportSectorCategory(
                sectorName: mapping.sectorName,
                categoryName: mapping.categoryName
            )
            sectorCategoryRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Sector Categories", headers: sectorCategoryHeaders, rows: sectorCategoryRows)
        
        // Sheet 6: Members
        let memberHeaders = ExportMember.headers
        var memberRows: [[String]] = []
        
        for member in members {
            let export = ExportMember(
                displayName: member.displayName,
                role: member.role.rawValue,
                status: member.status.rawValue
            )
            memberRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Members", headers: memberHeaders, rows: memberRows)
        
        // Generate the filename
        let sanitizedName = householdName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let dateStr = Self.dateFormatter.string(from: Date())
        let filename = "\(sanitizedName)_export_\(dateStr).xlsx"
        
        return try xlsxWriter.write(to: filename)
    }
    
    /// Generates a template XLSX file for importing transactions
    func generateImportTemplate() throws -> URL {
        let xlsxWriter = XlsxWriter()
        
        // Transactions sheet with examples
        let transactionHeaders = ["Date", "Description", "Amount", "Type", "Category", "Paid By", "Split Type", "Notes"]
        let transactionRows: [[String]] = [
            ["2024-01-15", "Grocery shopping at Costco", "125.50", "expense", "Groceries", "John", "equal", "Weekly grocery run"],
            ["2024-01-16", "Monthly salary", "5000.00", "income", "Salary", "Jane", "equal", ""],
            ["2024-01-17", "Coffee with friends", "15.75", "expense", "Dining Out", "John", "member_only", "Just for me"],
            ["2024-01-18", "Utility bill split", "200.00", "expense", "Utilities", "Jane", "equal", "Electric bill"],
            ["2024-01-20", "John pays Jane back", "50.00", "settlement", "", "John", "equal", "For groceries"]
        ]
        
        xlsxWriter.addSheet(name: "Transactions", headers: transactionHeaders, rows: transactionRows)
        
        // Instructions sheet
        let instructionHeaders = ["Field", "Description", "Required", "Example"]
        let instructionRows: [[String]] = [
            ["Date", "Use YYYY-MM-DD format", "Yes", "2024-01-15"],
            ["Description", "What the transaction was for", "Yes", "Grocery shopping"],
            ["Amount", "Use numbers only (no currency symbols)", "Yes", "125.50"],
            ["Type", "expense, income, settlement, or reimbursement", "No (default: expense)", "expense"],
            ["Category", "Will be created if it doesn't exist", "No", "Groceries"],
            ["Paid By", "Must match an existing member name exactly", "No (default: you)", "John"],
            ["Split Type", "equal, member_only, or custom", "No (default: equal)", "equal"],
            ["Notes", "Optional additional notes", "No", "Weekly shopping"]
        ]
        
        xlsxWriter.addSheet(name: "Instructions", headers: instructionHeaders, rows: instructionRows)
        
        // Empty Splits sheet template
        let splitHeaders = ExportTransactionSplit.headers
        xlsxWriter.addSheet(name: "Splits", headers: splitHeaders, rows: [])
        
        return try xlsxWriter.write(to: "quack_import_template.xlsx")
    }
    
    // MARK: - Import Functions
    
    /// Parses an XLSX file and returns raw import rows and split rows
    func parseXLSX(from url: URL) throws -> (transactions: [ImportRow], splits: [ImportSplitRow]) {
        guard let xlsxFile = XLSXFile(filepath: url.path) else {
            throw ImportError.failedToOpenFile
        }
        
        var importRows: [ImportRow] = []
        var splitRows: [ImportSplitRow] = []
        
        // Get shared strings (may be nil for simple spreadsheets)
        let sharedStrings = try xlsxFile.parseSharedStrings()
        
        // Iterate through workbooks and worksheets
        for workbook in try xlsxFile.parseWorkbooks() {
            let worksheetPaths = try xlsxFile.parseWorksheetPathsAndNames(workbook: workbook)
            
            for (name, path) in worksheetPaths {
                guard let sheetName = name else { continue }
                let worksheet = try xlsxFile.parseWorksheet(at: path)
                
                let sheetNameLower = sheetName.lowercased()
                
                if sheetNameLower == "transactions" {
                    importRows = parseTransactionsSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                } else if sheetNameLower == "splits" {
                    splitRows = parseSplitsSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                }
            }
        }
        
        return (importRows, splitRows)
    }
    
    /// Parses the Transactions sheet
    private func parseTransactionsSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportRow] {
        var rows: [ImportRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Parse header row to find column mapping
        let headerRow = worksheetRows[0]
        let headers = headerRow.cells.map { getCellValue($0, sharedStrings: sharedStrings) }
        let columnMapping = ImportColumn.findColumn(in: headers)
        
        // Parse data rows
        for (index, row) in worksheetRows.dropFirst().enumerated() {
            let values = row.cells.map { getCellValue($0, sharedStrings: sharedStrings) }
            
            // Pad values array to match expected columns
            var paddedValues = values
            while paddedValues.count < headers.count {
                paddedValues.append("")
            }
            
            let importRow = ImportRow(
                rowNumber: index + 2,
                csvRow: getValue(from: paddedValues, column: .row, mapping: columnMapping),
                date: getValue(from: paddedValues, column: .date, mapping: columnMapping),
                description: getValue(from: paddedValues, column: .description, mapping: columnMapping),
                amount: getValue(from: paddedValues, column: .amount, mapping: columnMapping),
                type: getValue(from: paddedValues, column: .type, mapping: columnMapping),
                category: getValue(from: paddedValues, column: .category, mapping: columnMapping),
                paidBy: getValue(from: paddedValues, column: .paidBy, mapping: columnMapping),
                paidTo: getValue(from: paddedValues, column: .paidTo, mapping: columnMapping),
                splitType: getValue(from: paddedValues, column: .splitType, mapping: columnMapping),
                splitMember: getValue(from: paddedValues, column: .splitMember, mapping: columnMapping),
                reimbursesRow: getValue(from: paddedValues, column: .reimbursesRow, mapping: columnMapping),
                excludedFromBudget: getValue(from: paddedValues, column: .excludedFromBudget, mapping: columnMapping),
                notes: getValue(from: paddedValues, column: .notes, mapping: columnMapping)
            )
            
            // Skip completely empty rows
            if !importRow.description.isEmpty || !importRow.amount.isEmpty || !importRow.date.isEmpty {
                rows.append(importRow)
            }
        }
        
        return rows
    }
    
    /// Parses the Splits sheet
    private func parseSplitsSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportSplitRow] {
        var rows: [ImportSplitRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Parse header row
        let headerRow = worksheetRows[0]
        let headers = headerRow.cells.map { getCellValue($0, sharedStrings: sharedStrings) }
        let columnMapping = ImportSplitColumn.findColumn(in: headers)
        
        // Parse data rows
        for row in worksheetRows.dropFirst() {
            let values = row.cells.map { getCellValue($0, sharedStrings: sharedStrings) }
            
            var paddedValues = values
            while paddedValues.count < headers.count {
                paddedValues.append("")
            }
            
            let splitRow = ImportSplitRow(
                transactionRow: getSplitValue(from: paddedValues, column: .transactionRow, mapping: columnMapping),
                memberName: getSplitValue(from: paddedValues, column: .memberName, mapping: columnMapping),
                owedAmount: getSplitValue(from: paddedValues, column: .owedAmount, mapping: columnMapping),
                owedPercentage: getSplitValue(from: paddedValues, column: .owedPercentage, mapping: columnMapping),
                paidAmount: getSplitValue(from: paddedValues, column: .paidAmount, mapping: columnMapping),
                paidPercentage: getSplitValue(from: paddedValues, column: .paidPercentage, mapping: columnMapping)
            )
            
            // Skip empty rows
            if !splitRow.transactionRow.isEmpty || !splitRow.memberName.isEmpty {
                rows.append(splitRow)
            }
        }
        
        return rows
    }
    
    /// Gets the string value from a cell, handling shared strings
    private func getCellValue(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if cell.type == .sharedString {
            if let value = cell.value,
               let index = Int(value),
               let strings = sharedStrings,
               index < strings.items.count {
                return strings.items[index].text ?? ""
            }
            return ""
        } else if let value = cell.value {
            return value
        } else if let inlineString = cell.inlineString?.text {
            return inlineString
        }
        return ""
    }
    
    /// Validates and parses split rows against existing members
    func validateSplitRows(
        _ rows: [ImportSplitRow],
        existingMembers: [HouseholdMember]
    ) -> [ImportSplitRow] {
        let activeMembers = existingMembers.filter { $0.status == .approved }
        let memberMap = Dictionary(uniqueKeysWithValues: activeMembers.map { ($0.displayName.lowercased(), $0.id) })
        
        var validatedRows: [ImportSplitRow] = []
        
        for var row in rows {
            // Parse transaction row number
            if let rowNum = Int(row.transactionRow.trimmingCharacters(in: .whitespaces)) {
                row.parsedTransactionRow = rowNum
            }
            
            // Parse amounts
            row.parsedOwedAmount = parseAmount(row.owedAmount)
            row.parsedPaidAmount = parseAmount(row.paidAmount)
            
            // Parse percentages
            row.parsedOwedPercentage = parsePercentage(row.owedPercentage)
            row.parsedPaidPercentage = parsePercentage(row.paidPercentage)
            
            // Match member
            let memberNameLower = row.memberName.lowercased().trimmingCharacters(in: .whitespaces)
            row.matchedMemberId = memberMap[memberNameLower]
            
            validatedRows.append(row)
        }
        
        return validatedRows
    }
    
    private func parseAmount(_ amountString: String) -> Decimal? {
        let cleaned = amountString
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }
    
    private func parsePercentage(_ percentString: String) -> Decimal? {
        let cleaned = percentString
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Decimal(string: cleaned)
    }
    
    private func getSplitValue(from values: [String], column: ImportSplitColumn, mapping: [ImportSplitColumn: Int]) -> String {
        guard let index = mapping[column], index < values.count else { return "" }
        return values[index]
    }
    
    /// Validates import rows against existing household data
    func validateRows(
        _ rows: [ImportRow],
        existingCategories: [Category],
        existingMembers: [HouseholdMember],
        currentUserId: UUID?
    ) -> ([ImportRow], ImportSummary) {
        var validatedRows: [ImportRow] = []
        var summary = ImportSummary()
        summary.totalRows = rows.count
        
        let categoryNames = Set(existingCategories.map { $0.name.lowercased() })
        let categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0.id) })
        
        // Filter active members for matching
        let activeMembers = existingMembers.filter { $0.status == .approved }
        let memberNames = Set(activeMembers.map { $0.displayName.lowercased() })
        let memberMap = Dictionary(uniqueKeysWithValues: activeMembers.map { ($0.displayName.lowercased(), $0.id) })
        
        for var row in rows {
            row.validationErrors = []
            row.validationWarnings = []
            
            // Parse CSV row number (for round-trip import)
            if !row.csvRow.isEmpty {
                row.parsedCsvRow = Int(row.csvRow.trimmingCharacters(in: .whitespaces))
            }
            
            // Validate required fields
            if row.description.trimmingCharacters(in: .whitespaces).isEmpty {
                row.validationErrors.append(.missingRequiredField(field: "Description"))
            }
            
            if row.amount.trimmingCharacters(in: .whitespaces).isEmpty {
                row.validationErrors.append(.missingRequiredField(field: "Amount"))
            }
            
            if row.date.trimmingCharacters(in: .whitespaces).isEmpty {
                row.validationErrors.append(.missingRequiredField(field: "Date"))
            }
            
            // Validate and parse date
            if !row.date.isEmpty {
                if let parsedDate = parseDate(row.date) {
                    row.parsedDate = parsedDate
                } else {
                    row.validationErrors.append(.invalidDateFormat(value: row.date))
                }
            }
            
            // Validate and parse amount
            if !row.amount.isEmpty {
                let cleanedAmount = row.amount
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                if let amount = Decimal(string: cleanedAmount) {
                    row.parsedAmount = abs(amount) // Always use positive amounts
                } else {
                    row.validationErrors.append(.invalidAmountFormat(value: row.amount))
                }
            }
            
            // Validate and parse transaction type
            let typeStr = row.type.lowercased().trimmingCharacters(in: .whitespaces)
            if typeStr.isEmpty {
                row.parsedType = .expense // Default to expense
            } else {
                switch typeStr {
                case "expense", "exp": row.parsedType = .expense
                case "income", "inc": row.parsedType = .income
                case "settlement", "settle": row.parsedType = .settlement
                case "reimbursement", "reimburse", "reimb": row.parsedType = .reimbursement
                default:
                    row.validationErrors.append(.invalidTransactionType(value: row.type))
                }
            }
            
            // Validate category
            let categoryStr = row.category.trimmingCharacters(in: .whitespaces)
            if categoryStr.isEmpty {
                row.validationWarnings.append(.emptyCategory)
            } else {
                let categoryLower = categoryStr.lowercased()
                if categoryNames.contains(categoryLower) {
                    row.matchedCategoryId = categoryMap[categoryLower]
                    summary.existingCategoriesUsed.insert(categoryStr)
                } else {
                    row.validationWarnings.append(.categoryWillBeCreated(name: categoryStr))
                    summary.newCategoriesToCreate.insert(categoryStr)
                }
            }
            
            // Validate paid by member
            let paidByStr = row.paidBy.trimmingCharacters(in: .whitespaces)
            if paidByStr.isEmpty {
                row.validationWarnings.append(.emptyPaidBy)
                // Will default to current user during import
            } else {
                let paidByLower = paidByStr.lowercased()
                if memberNames.contains(paidByLower) {
                    row.matchedPaidByMemberId = memberMap[paidByLower]
                    summary.membersUsed.insert(paidByStr)
                } else {
                    row.validationErrors.append(.unknownMember(name: paidByStr))
                }
            }
            
            // Validate paid to member (for settlements/reimbursements)
            let paidToStr = row.paidTo.trimmingCharacters(in: .whitespaces)
            if !paidToStr.isEmpty {
                let paidToLower = paidToStr.lowercased()
                if memberNames.contains(paidToLower) {
                    row.matchedPaidToMemberId = memberMap[paidToLower]
                    summary.membersUsed.insert(paidToStr)
                } else {
                    row.validationErrors.append(.unknownMember(name: paidToStr))
                }
            }
            
            // Validate split type
            let splitStr = row.splitType.lowercased().trimmingCharacters(in: .whitespaces)
            if splitStr.isEmpty {
                row.parsedSplitType = .equal
                row.validationWarnings.append(.defaultSplitType)
            } else {
                switch splitStr {
                case "equal", "split", "split equally": row.parsedSplitType = .equal
                case "member_only", "memberonly", "member only", "payer only", "payeronly": row.parsedSplitType = .memberOnly
                case "custom": row.parsedSplitType = .custom
                default:
                    row.validationErrors.append(.invalidSplitType(value: row.splitType))
                }
            }
            
            // Validate split member (for member_only splits)
            let splitMemberStr = row.splitMember.trimmingCharacters(in: .whitespaces)
            if !splitMemberStr.isEmpty {
                let splitMemberLower = splitMemberStr.lowercased()
                if memberNames.contains(splitMemberLower) {
                    row.matchedSplitMemberId = memberMap[splitMemberLower]
                    summary.membersUsed.insert(splitMemberStr)
                } else {
                    row.validationErrors.append(.unknownMember(name: splitMemberStr))
                }
            }
            
            // Parse reimburses row (for reimbursement transactions)
            if !row.reimbursesRow.isEmpty {
                row.parsedReimbursesRow = Int(row.reimbursesRow.trimmingCharacters(in: .whitespaces))
                if row.parsedReimbursesRow != nil {
                    summary.reimbursementsWithReferences += 1
                }
            }
            
            // Parse excluded from budget
            let excludedStr = row.excludedFromBudget.lowercased().trimmingCharacters(in: .whitespaces)
            row.parsedExcludedFromBudget = excludedStr == "yes" || excludedStr == "true" || excludedStr == "1"
            
            // Determine validation status
            if row.validationErrors.isEmpty {
                if row.validationWarnings.isEmpty {
                    row.validationStatus = .valid
                    summary.validRows += 1
                } else {
                    row.validationStatus = .validWithWarnings
                    summary.warningRows += 1
                }
            } else {
                row.validationStatus = .invalid
                summary.errorRows += 1
            }
            
            validatedRows.append(row)
        }
        
        return (validatedRows, summary)
    }
    
    /// Generates an XLSX of failed/invalid rows for the user to fix
    func generateFailedRowsXLSX(_ rows: [ImportRow]) throws -> URL {
        let xlsxWriter = XlsxWriter()
        
        let headers = ["Row", "Date", "Description", "Amount", "Type", "Category", "Paid By", "Split Type", "Notes", "Errors"]
        var failedRows: [[String]] = []
        
        for row in rows where row.hasErrors {
            let errorMessages = row.validationErrors.map { $0.message }.joined(separator: "; ")
            failedRows.append([
                String(row.rowNumber),
                row.date,
                row.description,
                row.amount,
                row.type,
                row.category,
                row.paidBy,
                row.splitType,
                row.notes,
                errorMessages
            ])
        }
        
        xlsxWriter.addSheet(name: "Failed Rows", headers: headers, rows: failedRows)
        
        return try xlsxWriter.write(to: "failed_imports_\(Int(Date().timeIntervalSince1970)).xlsx")
    }
    
    // MARK: - Private Helpers
    
    private func getValue(from values: [String], column: ImportColumn, mapping: [ImportColumn: Int]) -> String {
        guard let index = mapping[column], index < values.count else { return "" }
        return values[index]
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let trimmed = dateString.trimmingCharacters(in: .whitespaces)
        
        // Try primary format first
        if let date = Self.dateFormatter.date(from: trimmed) {
            return date
        }
        
        // Try alternate formats
        for formatter in Self.alternateDateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case failedToOpenFile
    case noTransactionsSheet
    
    var errorDescription: String? {
        switch self {
        case .failedToOpenFile:
            return "Failed to open the Excel file. Please make sure it's a valid .xlsx file."
        case .noTransactionsSheet:
            return "No 'Transactions' sheet found in the Excel file."
        }
    }
}

// MARK: - File Type Identifiers

extension UTType {
    static let xlsx = UTType(filenameExtension: "xlsx") ?? .spreadsheet
}
