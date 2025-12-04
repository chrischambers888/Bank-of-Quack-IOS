import Foundation
import UniformTypeIdentifiers

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
    
    /// Exports all household data to a folder containing multiple CSVs
    /// Returns the URL to the export directory
    func exportHouseholdData(
        transactions: [TransactionView],
        transactionSplits: [TransactionSplit],
        categories: [Category],
        sectors: [Sector],
        sectorCategories: [(sectorName: String, categoryName: String)],
        members: [HouseholdMember],
        householdName: String
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedName = householdName.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let dateStr = Self.dateFormatter.string(from: Date())
        let exportDir = tempDir.appendingPathComponent("\(sanitizedName)_export_\(dateStr)")
        
        // Remove existing export directory if present
        try? FileManager.default.removeItem(at: exportDir)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        // Generate CSVs - transactions first to get row mappings
        let (transactionsCSV, transactionRowMap) = generateTransactionsCSV(
            transactions: transactions,
            categories: categories,
            members: members
        )
        let transactionSplitsCSV = generateTransactionSplitsCSV(
            transactionSplits: transactionSplits,
            transactionRowMap: transactionRowMap,
            members: members
        )
        let categoriesCSV = generateCategoriesCSV(categories: categories)
        let sectorsCSV = generateSectorsCSV(sectors: sectors)
        let sectorCategoriesCSV = generateSectorCategoriesCSV(sectorCategories: sectorCategories)
        let membersCSV = generateMembersCSV(members: members)
        
        // Write CSV files
        try transactionsCSV.write(to: exportDir.appendingPathComponent("transactions.csv"), atomically: true, encoding: .utf8)
        if !transactionSplits.isEmpty {
            try transactionSplitsCSV.write(to: exportDir.appendingPathComponent("transaction_splits.csv"), atomically: true, encoding: .utf8)
        }
        try categoriesCSV.write(to: exportDir.appendingPathComponent("categories.csv"), atomically: true, encoding: .utf8)
        try sectorsCSV.write(to: exportDir.appendingPathComponent("sectors.csv"), atomically: true, encoding: .utf8)
        try sectorCategoriesCSV.write(to: exportDir.appendingPathComponent("sector_categories.csv"), atomically: true, encoding: .utf8)
        try membersCSV.write(to: exportDir.appendingPathComponent("members.csv"), atomically: true, encoding: .utf8)
        
        // Return the export directory URL - iOS share sheet can handle folders
        return exportDir
    }
    
    /// Generates a template CSV for importing transactions
    func generateImportTemplate() -> String {
        var lines: [String] = []
        
        // Header
        lines.append("Date,Description,Amount,Type,Category,Paid By,Split Type,Notes")
        
        // Example rows with different transaction types
        lines.append("2024-01-15,Grocery shopping at Costco,125.50,expense,Groceries,John,equal,Weekly grocery run")
        lines.append("2024-01-16,Monthly salary,5000.00,income,Salary,Jane,equal,")
        lines.append("2024-01-17,Coffee with friends,15.75,expense,Dining Out,John,member_only,Just for me")
        lines.append("2024-01-18,Utility bill split,200.00,expense,Utilities,Jane,equal,Electric bill")
        lines.append("2024-01-20,John pays Jane back,50.00,settlement,,John,equal,For groceries")
        
        // Instructions as comments (will be ignored by parser)
        lines.append("")
        lines.append("# INSTRUCTIONS:")
        lines.append("# - Date: Use YYYY-MM-DD format (e.g. 2024-01-15)")
        lines.append("# - Description: Required. What the transaction was for.")
        lines.append("# - Amount: Required. Use numbers only (e.g. 125.50)")
        lines.append("# - Type: expense income settlement or reimbursement")
        lines.append("# - Category: Will be created if it doesn't exist")
        lines.append("# - Paid By: Must match an existing member name exactly")
        lines.append("# - Split Type: equal member_only or custom (defaults to equal)")
        lines.append("# - Notes: Optional additional notes")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Import Functions
    
    /// Parses a CSV file and returns raw import rows
    func parseCSV(from url: URL) throws -> [ImportRow] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseCSVContent(content)
    }
    
    /// Parses CSV content string and returns raw import rows
    func parseCSVContent(_ content: String) -> [ImportRow] {
        var rows: [ImportRow] = []
        
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") } // Skip empty lines and comments
        
        guard lines.count > 1 else { return [] }
        
        // Parse headers
        let headers = parseCSVLine(lines[0])
        let columnMapping = ImportColumn.findColumn(in: headers)
        
        // Parse data rows
        for (index, line) in lines.dropFirst().enumerated() {
            let values = parseCSVLine(line)
            
            let row = ImportRow(
                rowNumber: index + 2, // +2 because 1-indexed and skipping header
                csvRow: getValue(from: values, column: .row, mapping: columnMapping),
                date: getValue(from: values, column: .date, mapping: columnMapping),
                description: getValue(from: values, column: .description, mapping: columnMapping),
                amount: getValue(from: values, column: .amount, mapping: columnMapping),
                type: getValue(from: values, column: .type, mapping: columnMapping),
                category: getValue(from: values, column: .category, mapping: columnMapping),
                paidBy: getValue(from: values, column: .paidBy, mapping: columnMapping),
                paidTo: getValue(from: values, column: .paidTo, mapping: columnMapping),
                splitType: getValue(from: values, column: .splitType, mapping: columnMapping),
                splitMember: getValue(from: values, column: .splitMember, mapping: columnMapping),
                reimbursesRow: getValue(from: values, column: .reimbursesRow, mapping: columnMapping),
                excludedFromBudget: getValue(from: values, column: .excludedFromBudget, mapping: columnMapping),
                notes: getValue(from: values, column: .notes, mapping: columnMapping)
            )
            
            rows.append(row)
        }
        
        return rows
    }
    
    /// Parses a splits CSV file and returns raw import split rows
    func parseSplitsCSV(from url: URL) throws -> [ImportSplitRow] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parseSplitsCSVContent(content)
    }
    
    /// Parses splits CSV content string and returns raw import split rows
    func parseSplitsCSVContent(_ content: String) -> [ImportSplitRow] {
        var rows: [ImportSplitRow] = []
        
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        guard lines.count > 1 else { return [] }
        
        // Parse headers
        let headers = parseCSVLine(lines[0])
        let columnMapping = ImportSplitColumn.findColumn(in: headers)
        
        // Parse data rows
        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            
            let row = ImportSplitRow(
                transactionRow: getSplitValue(from: values, column: .transactionRow, mapping: columnMapping),
                memberName: getSplitValue(from: values, column: .memberName, mapping: columnMapping),
                owedAmount: getSplitValue(from: values, column: .owedAmount, mapping: columnMapping),
                owedPercentage: getSplitValue(from: values, column: .owedPercentage, mapping: columnMapping),
                paidAmount: getSplitValue(from: values, column: .paidAmount, mapping: columnMapping),
                paidPercentage: getSplitValue(from: values, column: .paidPercentage, mapping: columnMapping)
            )
            
            rows.append(row)
        }
        
        return rows
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
    
    /// Generates a CSV of failed/invalid rows for the user to fix
    func generateFailedRowsCSV(_ rows: [ImportRow]) -> String {
        var lines: [String] = []
        
        // Header with error column
        lines.append("Row,Date,Description,Amount,Type,Category,Paid By,Split Type,Notes,Errors")
        
        for row in rows where row.hasErrors {
            let errorMessages = row.validationErrors.map { $0.message }.joined(separator: "; ")
            let csvRow = [
                String(row.rowNumber),
                escapeCSV(row.date),
                escapeCSV(row.description),
                escapeCSV(row.amount),
                escapeCSV(row.type),
                escapeCSV(row.category),
                escapeCSV(row.paidBy),
                escapeCSV(row.splitType),
                escapeCSV(row.notes),
                escapeCSV(errorMessages)
            ]
            lines.append(csvRow.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Private Helpers
    
    /// Generates transactions CSV and returns both the CSV content and a mapping of transaction ID to row number
    private func generateTransactionsCSV(
        transactions: [TransactionView],
        categories: [Category],
        members: [HouseholdMember]
    ) -> (csv: String, rowMap: [UUID: Int]) {
        var lines: [String] = []
        var transactionRowMap: [UUID: Int] = [:]  // Maps transaction ID to row number
        
        // Header
        lines.append(ExportTransaction.headers.joined(separator: ","))
        
        // Build lookup maps
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let memberMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        
        // First pass: assign row numbers to all transactions
        for (index, transaction) in transactions.enumerated() {
            let rowNumber = index + 1  // 1-indexed row numbers
            transactionRowMap[transaction.id] = rowNumber
        }
        
        // Second pass: generate CSV rows with reimbursement references
        for (index, transaction) in transactions.enumerated() {
            let rowNumber = index + 1
            
            // Look up the reimbursed transaction's row number
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
            
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return (lines.joined(separator: "\n"), transactionRowMap)
    }
    
    /// Generates transaction splits CSV
    private func generateTransactionSplitsCSV(
        transactionSplits: [TransactionSplit],
        transactionRowMap: [UUID: Int],
        members: [HouseholdMember]
    ) -> String {
        var lines: [String] = []
        
        // Header
        lines.append(ExportTransactionSplit.headers.joined(separator: ","))
        
        // Build lookup maps
        let memberMap = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        
        // Output splits with transaction row reference
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
            
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateCategoriesCSV(categories: [Category]) -> String {
        var lines: [String] = []
        lines.append(ExportCategory.headers.joined(separator: ","))
        
        for category in categories {
            let export = ExportCategory(
                name: category.name,
                sortOrder: String(category.sortOrder)
            )
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateSectorsCSV(sectors: [Sector]) -> String {
        var lines: [String] = []
        lines.append(ExportSector.headers.joined(separator: ","))
        
        for sector in sectors {
            let export = ExportSector(
                name: sector.name,
                sortOrder: String(sector.sortOrder)
            )
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateSectorCategoriesCSV(sectorCategories: [(sectorName: String, categoryName: String)]) -> String {
        var lines: [String] = []
        lines.append(ExportSectorCategory.headers.joined(separator: ","))
        
        for mapping in sectorCategories {
            let export = ExportSectorCategory(
                sectorName: mapping.sectorName,
                categoryName: mapping.categoryName
            )
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateMembersCSV(members: [HouseholdMember]) -> String {
        var lines: [String] = []
        lines.append(ExportMember.headers.joined(separator: ","))
        
        for member in members {
            let export = ExportMember(
                displayName: member.displayName,
                role: member.role.rawValue,
                status: member.status.rawValue
            )
            lines.append(export.csvRow.map { escapeCSV($0) }.joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
    
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
    
    private func escapeCSV(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuotes {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

// MARK: - File Type Identifiers

extension UTType {
    static let csv = UTType(filenameExtension: "csv") ?? .commaSeparatedText
}
