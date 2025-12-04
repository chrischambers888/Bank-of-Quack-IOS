import Foundation

// MARK: - Import Row (Raw parsed data from CSV)

struct ImportRow: Identifiable, Sendable {
    let id = UUID()
    let rowNumber: Int  // Auto-generated row number during parsing (1-indexed, after header)
    
    // Raw string values from CSV
    var csvRow: String  // Row number from CSV (for round-trip import)
    var date: String
    var description: String
    var amount: String
    var type: String
    var category: String
    var paidBy: String
    var paidTo: String
    var splitType: String
    var splitMember: String
    var reimbursesRow: String  // Row number of the expense this reimburses
    var excludedFromBudget: String
    var notes: String
    
    // Parsed/validated values
    var parsedDate: Date?
    var parsedAmount: Decimal?
    var parsedType: TransactionType?
    var matchedCategoryId: UUID?
    var matchedPaidByMemberId: UUID?
    var matchedPaidToMemberId: UUID?
    var matchedSplitMemberId: UUID?
    var parsedSplitType: SplitType?
    var parsedCsvRow: Int?  // Parsed row number from CSV
    var parsedReimbursesRow: Int?  // Parsed reimburses row number
    var parsedExcludedFromBudget: Bool = false
    
    // Validation state
    var validationStatus: ImportValidationStatus = .pending
    var validationErrors: [ImportValidationError] = []
    var validationWarnings: [ImportValidationWarning] = []
    
    var isValid: Bool {
        validationStatus == .valid || validationStatus == .validWithWarnings
    }
    
    var hasErrors: Bool {
        validationStatus == .invalid
    }
    
    var hasWarnings: Bool {
        !validationWarnings.isEmpty
    }
    
    /// Whether this is a reimbursement that references another transaction
    var isReimbursementWithReference: Bool {
        parsedType == .reimbursement && parsedReimbursesRow != nil
    }
}

// MARK: - Validation Status

enum ImportValidationStatus: String, Sendable {
    case pending
    case valid
    case validWithWarnings
    case invalid
}

// MARK: - Validation Errors

enum ImportValidationError: Identifiable, Equatable, Sendable {
    case missingRequiredField(field: String)
    case invalidDateFormat(value: String)
    case invalidAmountFormat(value: String)
    case invalidTransactionType(value: String)
    case unknownMember(name: String)
    case invalidSplitType(value: String)
    
    var id: String {
        switch self {
        case .missingRequiredField(let field): return "missing_\(field)"
        case .invalidDateFormat(let value): return "date_\(value)"
        case .invalidAmountFormat(let value): return "amount_\(value)"
        case .invalidTransactionType(let value): return "type_\(value)"
        case .unknownMember(let name): return "member_\(name)"
        case .invalidSplitType(let value): return "split_\(value)"
        }
    }
    
    var message: String {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidDateFormat(let value):
            return "Invalid date format: \"\(value)\". Use YYYY-MM-DD format."
        case .invalidAmountFormat(let value):
            return "Invalid amount: \"\(value)\". Use a number like 123.45"
        case .invalidTransactionType(let value):
            return "Unknown transaction type: \"\(value)\". Use expense, income, settlement, or reimbursement."
        case .unknownMember(let name):
            return "Unknown member: \"\(name)\". Member must exist in household."
        case .invalidSplitType(let value):
            return "Invalid split type: \"\(value)\". Use equal, member_only, or custom."
        }
    }
}

// MARK: - Validation Warnings

enum ImportValidationWarning: Identifiable, Equatable, Sendable {
    case categoryWillBeCreated(name: String)
    case categoryWillBeIgnored(transactionType: String)
    case emptyCategory
    case emptyPaidBy
    case defaultSplitType
    case memberWillBeCreated(name: String)
    
    var id: String {
        switch self {
        case .categoryWillBeCreated(let name): return "create_cat_\(name)"
        case .categoryWillBeIgnored(let type): return "ignore_cat_\(type)"
        case .emptyCategory: return "empty_category"
        case .emptyPaidBy: return "empty_paid_by"
        case .defaultSplitType: return "default_split"
        case .memberWillBeCreated(let name): return "create_member_\(name)"
        }
    }
    
    var message: String {
        switch self {
        case .categoryWillBeCreated(let name):
            return "Category \"\(name)\" will be created"
        case .categoryWillBeIgnored(let transactionType):
            return "Category will be ignored for \(transactionType) transactions"
        case .emptyCategory:
            return "No category specified - transaction will be uncategorized"
        case .emptyPaidBy:
            return "No 'Paid By' specified - will be assigned to you"
        case .defaultSplitType:
            return "No split type specified - will use 'Split Equally'"
        case .memberWillBeCreated(let name):
            return "Member \"\(name)\" will be created as managed member"
        }
    }
}

// MARK: - Import Summary

struct ImportSummary: Sendable {
    var totalRows: Int = 0
    var validRows: Int = 0
    var warningRows: Int = 0
    var errorRows: Int = 0
    
    var newCategoriesToCreate: Set<String> = []
    var existingCategoriesUsed: Set<String> = []
    var membersUsed: Set<String> = []
    
    // Split import tracking
    var totalSplitRows: Int = 0
    var transactionsWithSplits: Int = 0  // Number of transactions that have split data
    var reimbursementsWithReferences: Int = 0  // Number of reimbursements that reference an expense
    
    // Sector import tracking
    var newSectorsToCreate: Set<String> = []
    var existingSectorsUsed: Set<String> = []
    var newSectorCategoryLinks: [(sectorName: String, categoryName: String)] = []
    var existingSectorCategoryLinks: Int = 0
    
    // Managed member import tracking
    var newManagedMembersToCreate: Set<String> = []
    
    var canImportAll: Bool {
        errorRows == 0
    }
    
    var canImportValid: Bool {
        validRows > 0 || warningRows > 0
    }
    
    var hasSplitData: Bool {
        totalSplitRows > 0
    }
    
    var hasSectorData: Bool {
        !newSectorsToCreate.isEmpty || !existingSectorsUsed.isEmpty
    }
    
    var hasSectorCategoryLinks: Bool {
        !newSectorCategoryLinks.isEmpty || existingSectorCategoryLinks > 0
    }
    
    var hasNewManagedMembers: Bool {
        !newManagedMembersToCreate.isEmpty
    }
}

// MARK: - Export Data Containers

struct ExportTransaction: Sendable {
    let row: Int  // Row number for reference (used by reimbursements and splits)
    let date: String
    let description: String
    let amount: String
    let type: String
    let category: String
    let paidBy: String
    let paidTo: String
    let splitType: String
    let splitMember: String
    let reimbursesRow: String  // Row number of the expense this reimburses (empty if not a reimbursement)
    let excludedFromBudget: String
    let notes: String
    
    static let headers = [
        "Row",
        "Date",
        "Description", 
        "Amount",
        "Type",
        "Category",
        "Paid By",
        "Paid To",
        "Split Type",
        "Split Member",
        "Reimburses Row",
        "Excluded From Budget",
        "Notes"
    ]
    
    var csvRow: [String] {
        [String(row), date, description, amount, type, category, paidBy, paidTo, splitType, splitMember, reimbursesRow, excludedFromBudget, notes]
    }
}

struct ExportTransactionSplit: Sendable {
    let transactionRow: Int  // References the transaction row number
    let memberName: String
    let owedAmount: String
    let owedPercentage: String
    let paidAmount: String
    let paidPercentage: String
    
    static let headers = [
        "Transaction Row",
        "Member Name",
        "Owed Amount",
        "Owed %",
        "Paid Amount",
        "Paid %"
    ]
    
    var csvRow: [String] {
        [String(transactionRow), memberName, owedAmount, owedPercentage, paidAmount, paidPercentage]
    }
}

struct ExportCategory: Sendable {
    let name: String
    let sortOrder: String
    
    // Note: Icon and color removed - emojis don't export well to CSV, colors managed by theme
    static let headers = ["Name", "Sort Order"]
    
    var csvRow: [String] {
        [name, sortOrder]
    }
}

struct ExportSector: Sendable {
    let name: String
    let sortOrder: String
    
    // Note: Color removed - colors are managed by the theme
    static let headers = ["Name", "Sort Order"]
    
    var csvRow: [String] {
        [name, sortOrder]
    }
}

struct ExportSectorCategory: Sendable {
    let sectorName: String
    let categoryName: String
    
    static let headers = ["Sector Name", "Category Name"]
    
    var csvRow: [String] {
        [sectorName, categoryName]
    }
}

struct ExportMember: Sendable {
    let displayName: String
    let role: String
    let status: String
    
    // Note: Color removed - users can set colors in the app
    static let headers = ["Display Name", "Role", "Status"]
    
    var csvRow: [String] {
        [displayName, role, status]
    }
}

// MARK: - CSV Column Mapping

enum ImportColumn: String, CaseIterable, Sendable {
    case row = "row"
    case date = "date"
    case description = "description"
    case amount = "amount"
    case type = "type"
    case category = "category"
    case paidBy = "paid by"
    case paidTo = "paid to"
    case splitType = "split type"
    case splitMember = "split member"
    case reimbursesRow = "reimburses row"
    case excludedFromBudget = "excluded from budget"
    case notes = "notes"
    
    var alternateNames: [String] {
        switch self {
        case .row: return ["row", "row number", "row #", "row_number"]
        case .date: return ["date", "transaction date", "trans date"]
        case .description: return ["description", "desc", "memo", "name"]
        case .amount: return ["amount", "value", "sum", "total"]
        case .type: return ["type", "transaction type", "trans type"]
        case .category: return ["category", "cat", "category name"]
        case .paidBy: return ["paid by", "paidby", "paid_by", "member", "who paid"]
        case .paidTo: return ["paid to", "paidto", "paid_to", "recipient"]
        case .splitType: return ["split type", "split_type", "splittype", "split"]
        case .splitMember: return ["split member", "split_member", "splitmember"]
        case .reimbursesRow: return ["reimburses row", "reimburses_row", "reimbursesrow", "reimburses"]
        case .excludedFromBudget: return ["excluded from budget", "excluded_from_budget", "excludedfrombudget", "excluded"]
        case .notes: return ["notes", "note", "comments", "comment"]
        }
    }
    
    static func findColumn(in headers: [String]) -> [ImportColumn: Int] {
        var mapping: [ImportColumn: Int] = [:]
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        for column in ImportColumn.allCases {
            for (index, header) in normalizedHeaders.enumerated() {
                if column.alternateNames.contains(header) {
                    mapping[column] = index
                    break
                }
            }
        }
        
        return mapping
    }
}

// MARK: - Import Split Row (for parsing transaction_splits.csv)

struct ImportSplitRow: Identifiable, Sendable {
    let id = UUID()
    
    // Raw string values from CSV
    var transactionRow: String
    var memberName: String
    var owedAmount: String
    var owedPercentage: String
    var paidAmount: String
    var paidPercentage: String
    
    // Parsed values
    var parsedTransactionRow: Int?
    var parsedOwedAmount: Decimal?
    var parsedOwedPercentage: Decimal?
    var parsedPaidAmount: Decimal?
    var parsedPaidPercentage: Decimal?
    var matchedMemberId: UUID?
}

enum ImportSplitColumn: String, CaseIterable, Sendable {
    case transactionRow = "transaction row"
    case memberName = "member name"
    case owedAmount = "owed amount"
    case owedPercentage = "owed %"
    case paidAmount = "paid amount"
    case paidPercentage = "paid %"
    
    var alternateNames: [String] {
        switch self {
        case .transactionRow: return ["transaction row", "transaction_row", "transactionrow", "row"]
        case .memberName: return ["member name", "member_name", "membername", "member"]
        case .owedAmount: return ["owed amount", "owed_amount", "owedamount", "owed"]
        case .owedPercentage: return ["owed %", "owed_percentage", "owedpercentage", "owed percent"]
        case .paidAmount: return ["paid amount", "paid_amount", "paidamount", "paid"]
        case .paidPercentage: return ["paid %", "paid_percentage", "paidpercentage", "paid percent"]
        }
    }
    
    static func findColumn(in headers: [String]) -> [ImportSplitColumn: Int] {
        var mapping: [ImportSplitColumn: Int] = [:]
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        for column in ImportSplitColumn.allCases {
            for (index, header) in normalizedHeaders.enumerated() {
                if column.alternateNames.contains(header) {
                    mapping[column] = index
                    break
                }
            }
        }
        
        return mapping
    }
}

// MARK: - Import Sector Row

struct ImportSectorRow: Identifiable, Sendable {
    let id = UUID()
    
    // Raw string values from XLSX
    var name: String
    var sortOrder: String
    
    // Parsed values
    var parsedSortOrder: Int?
    var matchedSectorId: UUID?  // If sector already exists
}

enum ImportSectorColumn: String, CaseIterable, Sendable {
    case name = "name"
    case sortOrder = "sort order"
    
    var alternateNames: [String] {
        switch self {
        case .name: return ["name", "sector name", "sector_name", "sectorname"]
        case .sortOrder: return ["sort order", "sort_order", "sortorder", "order"]
        }
    }
    
    static func findColumn(in headers: [String]) -> [ImportSectorColumn: Int] {
        var mapping: [ImportSectorColumn: Int] = [:]
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        for column in ImportSectorColumn.allCases {
            for (index, header) in normalizedHeaders.enumerated() {
                if column.alternateNames.contains(header) {
                    mapping[column] = index
                    break
                }
            }
        }
        
        return mapping
    }
}

// MARK: - Import Sector Category Row

struct ImportSectorCategoryRow: Identifiable, Sendable {
    let id = UUID()
    
    // Raw string values from XLSX
    var sectorName: String
    var categoryName: String
    
    // Parsed values
    var matchedSectorId: UUID?
    var matchedCategoryId: UUID?
    var isNewLink: Bool = false  // True if this link doesn't already exist
}

enum ImportSectorCategoryColumn: String, CaseIterable, Sendable {
    case sectorName = "sector name"
    case categoryName = "category name"
    
    var alternateNames: [String] {
        switch self {
        case .sectorName: return ["sector name", "sector_name", "sectorname", "sector"]
        case .categoryName: return ["category name", "category_name", "categoryname", "category"]
        }
    }
    
    static func findColumn(in headers: [String]) -> [ImportSectorCategoryColumn: Int] {
        var mapping: [ImportSectorCategoryColumn: Int] = [:]
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        for column in ImportSectorCategoryColumn.allCases {
            for (index, header) in normalizedHeaders.enumerated() {
                if column.alternateNames.contains(header) {
                    mapping[column] = index
                    break
                }
            }
        }
        
        return mapping
    }
}

// MARK: - Import Result

struct ImportResult: Sendable {
    let successCount: Int
    let failedCount: Int
    let createdCategories: [String]
    let createdSectors: [String]
    let createdSectorCategoryLinks: Int
    let createdManagedMembers: [String]
    let errors: [String]
    
    var isFullySuccessful: Bool {
        failedCount == 0
    }
}
