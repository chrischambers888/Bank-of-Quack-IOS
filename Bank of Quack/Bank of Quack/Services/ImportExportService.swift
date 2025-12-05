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
        
        // Get active member IDs for equal split comparison
        let activeMembers = members.filter { $0.status == .approved }
        let activeMemberIds = Set(activeMembers.map { $0.id })
        let activeMemberCount = activeMembers.count
        
        // Build splits map by transaction ID
        let splitsByTransaction = Dictionary(grouping: transactionSplits) { $0.transactionId }
        
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
            
            // Get splits for this transaction
            let splits = splitsByTransaction[transaction.id] ?? []
            
            // For income/reimbursement: recipient goes in "Paid To", leave "Paid By" and "Expense For" empty
            // For expense/settlement: use normal logic
            let paidByValue: String
            let paidToValue: String
            let expenseForValue: String
            
            switch transaction.transactionType {
            case .income, .reimbursement:
                // Income/Reimbursement: money flows TO the member (stored in paidByMemberId)
                paidByValue = ""
                paidToValue = transaction.paidByMemberId.flatMap { memberMap[$0] } ?? ""
                expenseForValue = ""
                
            case .settlement:
                // Settlement: paidBy pays TO paidTo
                paidByValue = transaction.paidByMemberId.flatMap { memberMap[$0] } ?? ""
                paidToValue = transaction.paidToMemberId.flatMap { memberMap[$0] } ?? ""
                expenseForValue = ""
                
            case .expense:
                // Expense: use full split analysis
                paidByValue = determinePaidByValue(
                    transaction: transaction,
                    splits: splits,
                    activeMemberIds: activeMemberIds,
                    activeMemberCount: activeMemberCount,
                    memberMap: memberMap
                )
                paidToValue = ""
                expenseForValue = determineExpenseForValue(
                    transaction: transaction,
                    splits: splits,
                    activeMemberIds: activeMemberIds,
                    activeMemberCount: activeMemberCount,
                    memberMap: memberMap
                )
            }
            
            let export = ExportTransaction(
                row: rowNumber,
                date: Self.dateFormatter.string(from: transaction.date),
                description: transaction.description,
                amount: "\(transaction.amount)",
                type: transaction.transactionType.rawValue,
                category: transaction.categoryId.flatMap { categoryMap[$0] } ?? "",
                paidBy: paidByValue,
                paidTo: paidToValue,
                expenseFor: expenseForValue,
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
                name: category.name
            )
            categoryRows.append(export.csvRow)
        }
        
        xlsxWriter.addSheet(name: "Categories", headers: categoryHeaders, rows: categoryRows)
        
        // Sheet 4: Sectors
        let sectorHeaders = ExportSector.headers
        var sectorRows: [[String]] = []
        
        for sector in sectors {
            let export = ExportSector(
                name: sector.name
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
    
    /// Determines the "Paid By" export value by examining actual splits
    /// - Returns member name if single payer, "Shared" if equal among active members, "Custom" otherwise
    private func determinePaidByValue(
        transaction: TransactionView,
        splits: [TransactionSplit],
        activeMemberIds: Set<UUID>,
        activeMemberCount: Int,
        memberMap: [UUID: String]
    ) -> String {
        // If explicitly marked as custom, use Custom
        if transaction.paidByType == .custom {
            return "Custom"
        }
        
        // If no splits data, fall back to transaction's recorded type
        if splits.isEmpty {
            switch transaction.paidByType {
            case .single:
                return transaction.paidByMemberId.flatMap { memberMap[$0] } ?? ""
            case .shared:
                return "Equal"
            case .custom:
                return "Custom"
            }
        }
        
        // Analyze actual paid amounts from splits
        let paidSplits = splits.filter { $0.paidAmount > 0 }
        
        // If only one person paid, it's a single payer
        if paidSplits.count == 1 {
            if let payerName = memberMap[paidSplits[0].memberId] {
                return payerName
            }
        }
        
        // Check if it's an equal split among current active members
        if paidSplits.count == activeMemberCount && activeMemberCount > 0 {
            let paidMemberIds = Set(paidSplits.map { $0.memberId })
            
            // All active members must have paid
            if paidMemberIds == activeMemberIds {
                // Check if all paid amounts are equal
                let paidAmounts = paidSplits.map { $0.paidAmount }
                let firstAmount = paidAmounts.first ?? 0
                let allEqual = paidAmounts.allSatisfy { abs($0 - firstAmount) < 0.01 }
                
                if allEqual {
                    return "Equal"
                }
            }
        }
        
        // Otherwise it's a custom split
        return "Custom"
    }
    
    /// Determines the "Expense For" export value by examining actual splits
    /// - Returns "Equal" if equal among active members, member name if member_only, "Custom" otherwise
    private func determineExpenseForValue(
        transaction: TransactionView,
        splits: [TransactionSplit],
        activeMemberIds: Set<UUID>,
        activeMemberCount: Int,
        memberMap: [UUID: String]
    ) -> String {
        // If explicitly marked as custom, use Custom
        if transaction.splitType == .custom {
            return "Custom"
        }
        
        // If no splits data, fall back to transaction's recorded type
        if splits.isEmpty {
            switch transaction.splitType {
            case .equal:
                return "Equal"
            case .memberOnly, .payerOnly:
                return transaction.splitMemberId.flatMap { memberMap[$0] } ?? ""
            case .custom:
                return "Custom"
            }
        }
        
        // Analyze actual owed amounts from splits
        let owedSplits = splits.filter { $0.owedAmount > 0 }
        
        // If only one person owes, it's member_only
        if owedSplits.count == 1 {
            if let memberName = memberMap[owedSplits[0].memberId] {
                return memberName
            }
        }
        
        // Check if it's an equal split among current active members
        if owedSplits.count == activeMemberCount && activeMemberCount > 0 {
            let owedMemberIds = Set(owedSplits.map { $0.memberId })
            
            // All active members must owe
            if owedMemberIds == activeMemberIds {
                // Check if all owed amounts are equal
                let owedAmounts = owedSplits.map { $0.owedAmount }
                let firstAmount = owedAmounts.first ?? 0
                let allEqual = owedAmounts.allSatisfy { abs($0 - firstAmount) < 0.01 }
                
                if allEqual {
                    return "Equal"
                }
            }
        }
        
        // Otherwise it's a custom split
        return "Custom"
    }
    
    /// Generates a template XLSX file for importing transactions
    func generateImportTemplate() throws -> URL {
        let xlsxWriter = XlsxWriter()
        
        // Transactions sheet with examples - using new simplified format
        let transactionHeaders = ExportTransaction.headers
        let transactionRows: [[String]] = [
            // Row, Date, Description, Amount, Type, Category, Paid By, Paid To, Expense For, Reimburses Row, Excluded From Budget, Notes
            ["1", "2024-01-15", "Grocery shopping at Costco", "125.50", "expense", "Groceries", "John", "", "Equal", "", "No", "John paid, split equally among all"],
            ["2", "2024-01-16", "Monthly salary deposit", "5000.00", "income", "", "", "Jane", "", "", "No", "Income: money received by Jane"],
            ["3", "2024-01-17", "Coffee for John only", "5.75", "expense", "Dining Out", "John", "", "John", "", "No", "John paid, expense only for John"],
            ["4", "2024-01-18", "Dinner - everyone chipped in", "80.00", "expense", "Dining Out", "Equal", "", "Equal", "", "No", "Everyone paid equally, split equally"],
            ["5", "2024-01-19", "Work expense (reimbursable)", "45.00", "expense", "Work", "John", "", "John", "", "Yes", "Will be reimbursed by employer"],
            ["6", "2024-01-20", "John settles up with Jane", "50.00", "settlement", "", "John", "Jane", "", "", "No", "John pays Jane (settling up)"],
            ["7", "2024-01-21", "Expense reimbursement from work", "45.00", "reimbursement", "", "", "John", "", "5", "No", "Reimbursement: money received by John"],
            ["8", "2024-01-22", "Complex dinner split", "150.00", "expense", "Dining Out", "Custom", "", "Custom", "", "No", "See Splits sheet for details"]
        ]
        
        xlsxWriter.addSheet(name: "Transactions", headers: transactionHeaders, rows: transactionRows)
        
        // Splits sheet with examples for custom splits
        let splitHeaders = ExportTransactionSplit.headers
        let splitRows: [[String]] = [
            // Transaction Row, Member Name, Owed Amount, Owed %, Paid Amount, Paid %
            // Example for row 8: John paid $100, Jane paid $50, but John owes $90 (more food), Jane owes $60
            ["8", "John", "90.00", "60", "100.00", "66.67"],
            ["8", "Jane", "60.00", "40", "50.00", "33.33"]
        ]
        xlsxWriter.addSheet(name: "Splits", headers: splitHeaders, rows: splitRows)
        
        // Sectors sheet with examples
        let sectorHeaders = ExportSector.headers
        let sectorRows: [[String]] = [
            ["Essential"],
            ["Lifestyle"],
            ["Savings"]
        ]
        xlsxWriter.addSheet(name: "Sectors", headers: sectorHeaders, rows: sectorRows)
        
        // Sector Categories sheet with examples
        let sectorCategoryHeaders = ExportSectorCategory.headers
        let sectorCategoryRows: [[String]] = [
            ["Essential", "Groceries"],
            ["Essential", "Utilities"],
            ["Lifestyle", "Dining Out"],
            ["Lifestyle", "Entertainment"]
        ]
        xlsxWriter.addSheet(name: "Sector Categories", headers: sectorCategoryHeaders, rows: sectorCategoryRows)
        
        // Comprehensive Instructions sheet
        let instructionRows: [[String]] = [
            // Section: Getting Started
            ["📋 GETTING STARTED", "", ""],
            ["This template helps you import transactions into Bank of Quack.", "", ""],
            ["Delete the example rows and add your own data.", "", ""],
            ["Only the Transactions sheet is required - other sheets are optional.", "", ""],
            ["", "", ""],
            
            // Section: Transactions Sheet
            ["📝 TRANSACTIONS SHEET", "", ""],
            ["Column", "Required?", "Description"],
            ["Row", "Optional", "Row number for reference (used by Splits and Reimburses Row)"],
            ["Date", "Yes", "Use YYYY-MM-DD format (e.g., 2024-01-15)"],
            ["Description", "Yes", "What the transaction was for"],
            ["Amount", "Yes", "Positive number only, no currency symbols (e.g., 125.50)"],
            ["Type", "No", "expense (default), income, settlement, or reimbursement"],
            ["Category", "No", "Category name for expenses - auto-created if doesn't exist"],
            ["Paid By", "No", "WHO PAID - see 'Paid By Values' section below"],
            ["Paid To", "For settlements", "Member receiving payment (for settlement/reimbursement types)"],
            ["Expense For", "No", "WHO OWES - see 'Expense For Values' section below"],
            ["Reimburses Row", "For reimbursements", "Row number of the expense being reimbursed"],
            ["Excluded From Budget", "No", "Yes or No - exclude from budget calculations"],
            ["Notes", "No", "Additional notes about the transaction"],
            ["", "", ""],
            
            // Section: Paid By Values
            ["💳 PAID BY VALUES (Who paid for this?)", "", ""],
            ["Value", "Meaning", "Example"],
            ["(empty)", "Current user paid - warning shown", "You'll be assigned as payer"],
            ["Member name", "That member paid 100%", "John paid the full $100"],
            ["Equal", "All ACTIVE members paid equally", "Everyone chipped in $25 each"],
            ["Custom", "Use Splits sheet for who paid", "Complex payment split"],
            ["", "", ""],
            
            // Section: Expense For Values
            ["📊 EXPENSE FOR VALUES (Who owes for this?)", "", ""],
            ["Value", "Meaning", "Example"],
            ["(empty) or Equal", "Split equally among all ACTIVE members", "Groceries split 50/50"],
            ["Member name", "Only that member owes", "John's personal coffee"],
            ["Custom", "Use Splits sheet for who owes", "Complex expense split"],
            ["", "", ""],
            
            // Section: Important Note about Equal splits
            ["⚠️ IMPORTANT: EQUAL SPLITS", "", ""],
            ["'Equal' splits among ACTIVE bank members at import time.", "", ""],
            ["If your bank membership has changed, use 'Custom' with the Splits sheet.", "", ""],
            ["When exporting, transactions with non-equal splits are marked 'Custom'.", "", ""],
            ["", "", ""],
            
            // Section: Common Scenarios
            ["🎯 COMMON SCENARIOS", "", ""],
            ["Scenario", "Paid By", "Expense For"],
            ["John paid for shared groceries", "John", "Equal"],
            ["Everyone chipped in for dinner", "Equal", "Equal"],
            ["John bought his own coffee", "John", "John"],
            ["Jane paid for John's gift", "Jane", "John"],
            ["Complex custom split", "Custom", "Custom"],
            ["", "", ""],
            
            // Section: Transaction Types
            ["💰 TRANSACTION TYPES", "", ""],
            ["Type", "When to Use", "Fields Used"],
            ["expense", "Regular spending (groceries, bills)", "Paid By, Expense For"],
            ["income", "Money received (salary, gifts)", "Paid To only"],
            ["settlement", "Paying someone back", "Paid By, Paid To"],
            ["reimbursement", "Getting refunded for an expense", "Paid To only (+ Reimburses Row)"],
            ["", "", ""],
            
            // Section: Income/Reimbursement Note
            ["📥 INCOME & REIMBURSEMENT", "", ""],
            ["For income and reimbursement, use 'Paid To' (who receives the money).", "", ""],
            ["Leave 'Paid By' and 'Expense For' empty - they don't apply.", "", ""],
            ["", "", ""],
            
            // Section: Splits Sheet
            ["📊 SPLITS SHEET (For Custom splits only)", "", ""],
            ["Use this sheet when Paid By or Expense For is 'Custom'.", "", ""],
            ["Column", "Required?", "Description"],
            ["Transaction Row", "Yes", "Must match a Row number from Transactions sheet"],
            ["Member Name", "Yes", "Must match member name (case-insensitive)"],
            ["Owed Amount", "Yes", "How much this member owes (their share)"],
            ["Owed %", "Optional", "Percentage this member owes"],
            ["Paid Amount", "Yes", "How much this member actually paid"],
            ["Paid %", "Optional", "Percentage this member paid"],
            ["", "", ""],
            
            // Splits Example
            ["Example: $150 dinner - John paid $100, Jane paid $50, but John owes $90, Jane owes $60:", "", ""],
            ["• John: Owed Amount = 90 (he ate more), Paid Amount = 100 (he paid more)", "", ""],
            ["• Jane: Owed Amount = 60 (she ate less), Paid Amount = 50 (she paid less)", "", ""],
            ["Result: Jane owes John $10 (she owes $60 but only paid $50).", "", ""],
            ["", "", ""],
            
            // Section: Sectors Sheet
            ["🏷️ SECTORS SHEET (Optional)", "", ""],
            ["Create budget sectors to group categories.", "", ""],
            ["Column", "Required?", "Description"],
            ["Name", "Yes", "Sector name (e.g., Essential, Lifestyle)"],
            ["", "", ""],
            
            // Section: Sector Categories Sheet
            ["🔗 SECTOR CATEGORIES SHEET (Optional)", "", ""],
            ["Link categories to sectors for budget tracking.", "", ""],
            ["Column", "Required?", "Description"],
            ["Sector Name", "Yes", "Must match a sector name (case-insensitive)"],
            ["Category Name", "Yes", "Must match a category name (case-insensitive)"],
            ["", "", ""],
            
            // Section: Tips
            ["💡 TIPS", "", ""],
            ["• All name matching is case-insensitive (members, categories, sectors)", "", ""],
            ["• Unknown members will be created as 'managed' members you control", "", ""],
            ["• Categories are auto-created if they don't exist", "", ""],
            ["• Expenses without a category will be imported as uncategorized", "", ""],
            ["• Leave optional fields blank if not needed", "", ""],
            ["• Dates can also use MM/DD/YYYY or DD/MM/YYYY format", "", ""],
            ["• For reimbursements, the Reimburses Row links to the original expense", "", ""]
        ]
        
        xlsxWriter.addSheet(name: "Instructions", headers: ["Topic", "Details", "Notes"], rows: instructionRows)
        
        return try xlsxWriter.write(to: "quack_import_template.xlsx")
    }
    
    // MARK: - Import Functions
    
    /// Result type for parsing XLSX files
    struct ParsedXLSXData: Sendable {
        var transactions: [ImportRow] = []
        var splits: [ImportSplitRow] = []
        var categories: [ImportCategoryRow] = []
        var sectors: [ImportSectorRow] = []
        var sectorCategories: [ImportSectorCategoryRow] = []
    }
    
    /// Parses an XLSX file and returns all import data (transactions, splits, sectors, sector-categories)
    func parseXLSX(from url: URL) throws -> ParsedXLSXData {
        guard let xlsxFile = XLSXFile(filepath: url.path) else {
            throw ImportError.failedToOpenFile
        }
        
        var result = ParsedXLSXData()
        
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
                    result.transactions = parseTransactionsSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                } else if sheetNameLower == "splits" {
                    result.splits = parseSplitsSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                } else if sheetNameLower == "categories" {
                    result.categories = parseCategoriesSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                } else if sheetNameLower == "sectors" {
                    result.sectors = parseSectorsSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                } else if sheetNameLower == "sector categories" {
                    result.sectorCategories = parseSectorCategoriesSheet(worksheet: worksheet, sharedStrings: sharedStrings)
                }
            }
        }
        
        return result
    }
    
    /// Parses the Transactions sheet
    private func parseTransactionsSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportRow] {
        var rows: [ImportRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Determine the maximum column count from the header row
        let headerRow = worksheetRows[0]
        let maxColumn = getMaxColumnIndex(from: headerRow)
        
        // Parse header row using proper column positioning
        let headers = getRowValues(from: headerRow, columnCount: maxColumn, sharedStrings: sharedStrings)
        let columnMapping = ImportColumn.findColumn(in: headers)
        
        // Parse data rows
        for (index, row) in worksheetRows.dropFirst().enumerated() {
            // Use proper column positioning to handle sparse cells
            let values = getRowValues(from: row, columnCount: maxColumn, sharedStrings: sharedStrings)
            
            let importRow = ImportRow(
                rowNumber: index + 2,
                csvRow: getValue(from: values, column: .row, mapping: columnMapping),
                date: getValue(from: values, column: .date, mapping: columnMapping),
                description: getValue(from: values, column: .description, mapping: columnMapping),
                amount: getValue(from: values, column: .amount, mapping: columnMapping),
                type: getValue(from: values, column: .type, mapping: columnMapping),
                category: getValue(from: values, column: .category, mapping: columnMapping),
                paidBy: getValue(from: values, column: .paidBy, mapping: columnMapping),
                paidTo: getValue(from: values, column: .paidTo, mapping: columnMapping),
                expenseFor: getValue(from: values, column: .expenseFor, mapping: columnMapping),
                reimbursesRow: getValue(from: values, column: .reimbursesRow, mapping: columnMapping),
                excludedFromBudget: getValue(from: values, column: .excludedFromBudget, mapping: columnMapping),
                notes: getValue(from: values, column: .notes, mapping: columnMapping)
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
        
        // Determine the maximum column count from the header row
        let headerRow = worksheetRows[0]
        let maxColumn = getMaxColumnIndex(from: headerRow)
        
        // Parse header row using proper column positioning
        let headers = getRowValues(from: headerRow, columnCount: maxColumn, sharedStrings: sharedStrings)
        let columnMapping = ImportSplitColumn.findColumn(in: headers)
        
        // Parse data rows
        for row in worksheetRows.dropFirst() {
            // Use proper column positioning to handle sparse cells
            let values = getRowValues(from: row, columnCount: maxColumn, sharedStrings: sharedStrings)
            
            let splitRow = ImportSplitRow(
                transactionRow: getSplitValue(from: values, column: .transactionRow, mapping: columnMapping),
                memberName: getSplitValue(from: values, column: .memberName, mapping: columnMapping),
                owedAmount: getSplitValue(from: values, column: .owedAmount, mapping: columnMapping),
                owedPercentage: getSplitValue(from: values, column: .owedPercentage, mapping: columnMapping),
                paidAmount: getSplitValue(from: values, column: .paidAmount, mapping: columnMapping),
                paidPercentage: getSplitValue(from: values, column: .paidPercentage, mapping: columnMapping)
            )
            
            // Skip empty rows
            if !splitRow.transactionRow.isEmpty || !splitRow.memberName.isEmpty {
                rows.append(splitRow)
            }
        }
        
        return rows
    }
    
    /// Parses the Sectors sheet
    private func parseSectorsSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportSectorRow] {
        var rows: [ImportSectorRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Determine the maximum column count from the header row
        let headerRow = worksheetRows[0]
        let maxColumn = getMaxColumnIndex(from: headerRow)
        
        // Parse header row using proper column positioning
        let headers = getRowValues(from: headerRow, columnCount: maxColumn, sharedStrings: sharedStrings)
        let columnMapping = ImportSectorColumn.findColumn(in: headers)
        
        // Parse data rows
        for row in worksheetRows.dropFirst() {
            // Use proper column positioning to handle sparse cells
            let values = getRowValues(from: row, columnCount: maxColumn, sharedStrings: sharedStrings)
            
            let sectorRow = ImportSectorRow(
                name: getSectorValue(from: values, column: .name, mapping: columnMapping)
            )
            
            // Skip empty rows
            if !sectorRow.name.trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(sectorRow)
            }
        }
        
        return rows
    }
    
    /// Parses the Sector Categories sheet
    private func parseSectorCategoriesSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportSectorCategoryRow] {
        var rows: [ImportSectorCategoryRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Determine the maximum column count from the header row
        let headerRow = worksheetRows[0]
        let maxColumn = getMaxColumnIndex(from: headerRow)
        
        // Parse header row using proper column positioning
        let headers = getRowValues(from: headerRow, columnCount: maxColumn, sharedStrings: sharedStrings)
        let columnMapping = ImportSectorCategoryColumn.findColumn(in: headers)
        
        // Parse data rows
        for row in worksheetRows.dropFirst() {
            // Use proper column positioning to handle sparse cells
            let values = getRowValues(from: row, columnCount: maxColumn, sharedStrings: sharedStrings)
            
            let scRow = ImportSectorCategoryRow(
                sectorName: getSectorCategoryValue(from: values, column: .sectorName, mapping: columnMapping),
                categoryName: getSectorCategoryValue(from: values, column: .categoryName, mapping: columnMapping)
            )
            
            // Skip empty rows
            if !scRow.sectorName.trimmingCharacters(in: .whitespaces).isEmpty &&
               !scRow.categoryName.trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(scRow)
            }
        }
        
        return rows
    }
    
    /// Parses the Categories sheet
    private func parseCategoriesSheet(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [ImportCategoryRow] {
        var rows: [ImportCategoryRow] = []
        
        guard let sheetData = worksheet.data else { return rows }
        let worksheetRows = sheetData.rows
        
        guard worksheetRows.count > 1 else { return rows }
        
        // Determine the maximum column count from the header row
        let headerRow = worksheetRows[0]
        let maxColumn = getMaxColumnIndex(from: headerRow)
        
        // Parse header row using proper column positioning
        let headers = getRowValues(from: headerRow, columnCount: maxColumn, sharedStrings: sharedStrings)
        let columnMapping = ImportCategoryColumn.findColumn(in: headers)
        
        // Parse data rows
        for row in worksheetRows.dropFirst() {
            // Use proper column positioning to handle sparse cells
            let values = getRowValues(from: row, columnCount: maxColumn, sharedStrings: sharedStrings)
            
            let categoryRow = ImportCategoryRow(
                name: getCategoryValue(from: values, column: .name, mapping: columnMapping)
            )
            
            // Skip empty rows
            if !categoryRow.name.trimmingCharacters(in: .whitespaces).isEmpty {
                rows.append(categoryRow)
            }
        }
        
        return rows
    }
    
    private func getCategoryValue(from values: [String], column: ImportCategoryColumn, mapping: [ImportCategoryColumn: Int]) -> String {
        guard let index = mapping[column], index < values.count else { return "" }
        return values[index]
    }
    
    private func getSectorValue(from values: [String], column: ImportSectorColumn, mapping: [ImportSectorColumn: Int]) -> String {
        guard let index = mapping[column], index < values.count else { return "" }
        return values[index]
    }
    
    private func getSectorCategoryValue(from values: [String], column: ImportSectorCategoryColumn, mapping: [ImportSectorCategoryColumn: Int]) -> String {
        guard let index = mapping[column], index < values.count else { return "" }
        return values[index]
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
    
    /// Extracts cell values into a properly positioned array based on column references.
    /// This handles sparse rows where empty cells are not included in the cells array.
    private func getRowValues(from row: CoreXLSX.Row, columnCount: Int, sharedStrings: SharedStrings?) -> [String] {
        var values = Array(repeating: "", count: columnCount)
        
        for cell in row.cells {
            // Get the column index from the cell reference (e.g., "A1" -> 0, "B1" -> 1)
            let columnIndex = columnLetterToIndex(cell.reference.column.value)
            if columnIndex >= 0 && columnIndex < columnCount {
                values[columnIndex] = getCellValue(cell, sharedStrings: sharedStrings)
            }
        }
        
        return values
    }
    
    /// Converts a column letter (e.g., "A", "B", "AA") to a 0-based index
    private func columnLetterToIndex(_ column: String) -> Int {
        var index = 0
        for char in column.uppercased() {
            if let asciiValue = char.asciiValue {
                index = index * 26 + Int(asciiValue - Character("A").asciiValue!) + 1
            }
        }
        return index - 1  // Convert to 0-based
    }
    
    /// Gets the maximum column index from a row's cells
    private func getMaxColumnIndex(from row: CoreXLSX.Row) -> Int {
        var maxIndex = 0
        for cell in row.cells {
            let index = columnLetterToIndex(cell.reference.column.value)
            maxIndex = max(maxIndex, index + 1)  // +1 because we need count, not max index
        }
        return maxIndex
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
    /// Note: splitRowsByTransaction should be pre-built from validated split rows, keyed by parsedTransactionRow (csvRow number)
    func validateRows(
        _ rows: [ImportRow],
        existingCategories: [Category],
        existingMembers: [HouseholdMember],
        currentUserId: UUID?,
        splitRowsByTransaction: [Int: [ImportSplitRow]] = [:]
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
        
        // Special values for Paid By and Expense For
        let sharedValues = Set(["shared", "equal", "split", "split equally", "all"])
        let customValues = Set(["custom"])
        
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
            // Note: Categories only apply to expenses - income/settlement/reimbursement don't use categories
            let categoryStr = row.category.trimmingCharacters(in: .whitespaces)
            let transactionTypeForCategory = row.parsedType ?? .expense
            
            if transactionTypeForCategory == .expense {
                // Expenses can have categories - if empty, they'll be uncategorized (warning, not error)
                if categoryStr.isEmpty {
                    row.validationWarnings.append(.emptyCategory)
                    // matchedCategoryId remains nil - expense will be uncategorized
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
            } else {
                // Income, settlement, and reimbursement don't use categories
                if !categoryStr.isEmpty {
                    // Warn that category will be ignored
                    row.validationWarnings.append(.categoryWillBeIgnored(transactionType: transactionTypeForCategory.rawValue))
                }
                // Don't set matchedCategoryId - it will remain nil
            }
            
            // Get transaction type for field validation
            let transactionType = row.parsedType ?? .expense
            
            // For income/reimbursement: recipient comes from "Paid To", ignore "Paid By" and "Expense For"
            // For settlement: "Paid By" pays TO "Paid To"
            // For expense: normal validation
            
            if transactionType == .income || transactionType == .reimbursement {
                // Income/Reimbursement: Recipient in "Paid To" maps to paidByMemberId in DB
                let paidToStr = row.paidTo.trimmingCharacters(in: .whitespaces)
                
                if paidToStr.isEmpty {
                    row.validationWarnings.append(.emptyPaidBy) // Reuse warning - will be assigned to current user
                    row.parsedPaidByType = .single
                } else {
                    let paidToLower = paidToStr.lowercased()
                    if memberNames.contains(paidToLower) {
                        row.matchedPaidByMemberId = memberMap[paidToLower]
                        summary.membersUsed.insert(paidToStr)
                    } else {
                        row.validationWarnings.append(.memberWillBeCreated(name: paidToStr))
                        summary.newManagedMembersToCreate.insert(paidToStr)
                    }
                    row.parsedPaidByType = .single
                }
                
                // Set defaults for income/reimbursement
                row.parsedSplitType = .memberOnly
                // matchedExpenseForMemberId will be set to same as paidBy during import
                
            } else if transactionType == .settlement {
                // Settlement: "Paid By" pays TO "Paid To"
                let paidByStr = row.paidBy.trimmingCharacters(in: .whitespaces)
                let paidByLower = paidByStr.lowercased()
                
                if paidByStr.isEmpty {
                    row.validationWarnings.append(.emptyPaidBy)
                    row.parsedPaidByType = .single
                } else {
                    if memberNames.contains(paidByLower) {
                        row.matchedPaidByMemberId = memberMap[paidByLower]
                        summary.membersUsed.insert(paidByStr)
                    } else {
                        row.validationWarnings.append(.memberWillBeCreated(name: paidByStr))
                        summary.newManagedMembersToCreate.insert(paidByStr)
                    }
                    row.parsedPaidByType = .single
                }
                
                // Validate paid to for settlement
                let paidToStr = row.paidTo.trimmingCharacters(in: .whitespaces)
                if !paidToStr.isEmpty {
                    let paidToLower = paidToStr.lowercased()
                    if memberNames.contains(paidToLower) {
                        row.matchedPaidToMemberId = memberMap[paidToLower]
                        summary.membersUsed.insert(paidToStr)
                    } else {
                        row.validationWarnings.append(.memberWillBeCreated(name: paidToStr))
                        summary.newManagedMembersToCreate.insert(paidToStr)
                    }
                }
                
                row.parsedSplitType = .equal
                
            } else {
                // Expense: Full validation of "Paid By" and "Expense For"
                
            // Validate "Paid By" - NEW SIMPLIFIED LOGIC
            // Accepts: empty (current user), member name (single), "Equal" (shared), "Custom" (custom)
            let paidByStr = row.paidBy.trimmingCharacters(in: .whitespaces)
            let paidByLower = paidByStr.lowercased()
            
            if paidByStr.isEmpty {
                // Empty = current user with warning
                row.validationWarnings.append(.emptyPaidBy)
                row.parsedPaidByType = .single
                // matchedPaidByMemberId will be set to current user during actual import
            } else if sharedValues.contains(paidByLower) {
                // "Shared", "Equal", etc. = all members paid equally
                row.parsedPaidByType = .shared
            } else if customValues.contains(paidByLower) {
                // "Custom" = use splits sheet
                row.parsedPaidByType = .custom
                // Check if splits exist for this row
                if let csvRow = row.parsedCsvRow, splitRowsByTransaction[csvRow] == nil {
                    row.validationErrors.append(.customWithoutSplits(field: "Paid By"))
                }
            } else {
                // Assume it's a member name
                row.parsedPaidByType = .single
                if memberNames.contains(paidByLower) {
                    row.matchedPaidByMemberId = memberMap[paidByLower]
                    summary.membersUsed.insert(paidByStr)
                } else {
                    // Unknown member - will be created as managed member
                    row.validationWarnings.append(.memberWillBeCreated(name: paidByStr))
                    summary.newManagedMembersToCreate.insert(paidByStr)
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
                    // Unknown member - will be created as managed member
                    row.validationWarnings.append(.memberWillBeCreated(name: paidToStr))
                    summary.newManagedMembersToCreate.insert(paidToStr)
                }
            }
            
            // Validate "Expense For" - NEW SIMPLIFIED LOGIC
            // Accepts: empty or "Equal" (equal split), member name (member_only), "Custom" (custom)
            let expenseForStr = row.expenseFor.trimmingCharacters(in: .whitespaces)
            let expenseForLower = expenseForStr.lowercased()
            
            if expenseForStr.isEmpty {
                // Empty = split equally among all members with warning
                row.parsedSplitType = .equal
                row.validationWarnings.append(.emptyExpenseFor)
            } else if sharedValues.contains(expenseForLower) {
                // "Equal"/"Shared" = split equally among all members (no warning - explicit choice)
                row.parsedSplitType = .equal
            } else if customValues.contains(expenseForLower) {
                // "Custom" = use splits sheet
                row.parsedSplitType = .custom
                // Check if splits exist for this row
                if let csvRow = row.parsedCsvRow, splitRowsByTransaction[csvRow] == nil {
                    row.validationErrors.append(.customWithoutSplits(field: "Expense For"))
                }
            } else {
                // Assume it's a member name = member_only
                row.parsedSplitType = .memberOnly
                if memberNames.contains(expenseForLower) {
                    row.matchedExpenseForMemberId = memberMap[expenseForLower]
                    summary.membersUsed.insert(expenseForStr)
                } else {
                    // Unknown member - will be created as managed member
                    row.validationWarnings.append(.memberWillBeCreated(name: expenseForStr))
                    summary.newManagedMembersToCreate.insert(expenseForStr)
                }
            }
            
            } // End of expense transaction type validation
            
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
    
    /// Validates sector rows against existing sectors
    func validateSectorRows(
        _ rows: [ImportSectorRow],
        existingSectors: [Sector]
    ) -> ([ImportSectorRow], Set<String>, Set<String>) {
        let sectorNames = Set(existingSectors.map { $0.name.lowercased() })
        let sectorMap = Dictionary(uniqueKeysWithValues: existingSectors.map { ($0.name.lowercased(), $0.id) })
        
        var validatedRows: [ImportSectorRow] = []
        var newSectorsToCreate: Set<String> = []
        var existingSectorsUsed: Set<String> = []
        
        for var row in rows {
            let nameStr = row.name.trimmingCharacters(in: .whitespaces)
            let nameLower = nameStr.lowercased()
            
            // Check if sector exists
            if sectorNames.contains(nameLower) {
                row.matchedSectorId = sectorMap[nameLower]
                existingSectorsUsed.insert(nameStr)
            } else {
                newSectorsToCreate.insert(nameStr)
            }
            
            validatedRows.append(row)
        }
        
        return (validatedRows, newSectorsToCreate, existingSectorsUsed)
    }
    
    /// Validates category rows against existing categories
    func validateCategoryRows(
        _ rows: [ImportCategoryRow],
        existingCategories: [Category]
    ) -> ([ImportCategoryRow], Set<String>, Set<String>) {
        let categoryNames = Set(existingCategories.map { $0.name.lowercased() })
        let categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0.id) })
        
        var validatedRows: [ImportCategoryRow] = []
        var newCategoriesToCreate: Set<String> = []
        var existingCategoriesUsed: Set<String> = []
        
        for var row in rows {
            let nameStr = row.name.trimmingCharacters(in: .whitespaces)
            let nameLower = nameStr.lowercased()
            
            // Check if category exists
            if categoryNames.contains(nameLower) {
                row.matchedCategoryId = categoryMap[nameLower]
                existingCategoriesUsed.insert(nameStr)
            } else {
                newCategoriesToCreate.insert(nameStr)
            }
            
            validatedRows.append(row)
        }
        
        return (validatedRows, newCategoriesToCreate, existingCategoriesUsed)
    }
    
    /// Validates sector-category linkage rows
    func validateSectorCategoryRows(
        _ rows: [ImportSectorCategoryRow],
        existingSectors: [Sector],
        existingCategories: [Category],
        existingSectorCategories: [UUID: [UUID]],
        newSectorsToCreate: Set<String>,
        newCategoriesToCreate: Set<String>
    ) -> ([ImportSectorCategoryRow], [(sectorName: String, categoryName: String)], Int) {
        let sectorMap = Dictionary(uniqueKeysWithValues: existingSectors.map { ($0.name.lowercased(), $0.id) })
        let categoryMap = Dictionary(uniqueKeysWithValues: existingCategories.map { ($0.name.lowercased(), $0.id) })
        
        var validatedRows: [ImportSectorCategoryRow] = []
        var newLinks: [(sectorName: String, categoryName: String)] = []
        var existingLinksCount = 0
        
        for var row in rows {
            let sectorNameStr = row.sectorName.trimmingCharacters(in: .whitespaces)
            let categoryNameStr = row.categoryName.trimmingCharacters(in: .whitespaces)
            let sectorLower = sectorNameStr.lowercased()
            let categoryLower = categoryNameStr.lowercased()
            
            // Match sector
            row.matchedSectorId = sectorMap[sectorLower]
            
            // Match category
            row.matchedCategoryId = categoryMap[categoryLower]
            
            // Check if this is a new link
            if let sectorId = row.matchedSectorId, let categoryId = row.matchedCategoryId {
                // Both exist - check if link already exists
                let existingCategoryIds = existingSectorCategories[sectorId] ?? []
                if existingCategoryIds.contains(categoryId) {
                    row.isNewLink = false
                    existingLinksCount += 1
                } else {
                    row.isNewLink = true
                    newLinks.append((sectorName: sectorNameStr, categoryName: categoryNameStr))
                }
            } else {
                // Either sector or category is new, so link will be new
                row.isNewLink = true
                newLinks.append((sectorName: sectorNameStr, categoryName: categoryNameStr))
            }
            
            validatedRows.append(row)
        }
        
        return (validatedRows, newLinks, existingLinksCount)
    }
    
    /// Generates an XLSX of failed/invalid rows for the user to fix
    func generateFailedRowsXLSX(_ rows: [ImportRow]) throws -> URL {
        let xlsxWriter = XlsxWriter()
        
        let headers = ["Row", "Date", "Description", "Amount", "Type", "Category", "Paid By", "Expense For", "Notes", "Errors"]
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
                row.expenseFor,
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
