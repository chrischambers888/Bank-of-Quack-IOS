import Foundation
import SwiftUI

struct Transaction: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    var date: Date
    var description: String
    var amount: Decimal
    var transactionType: TransactionType
    var paidByMemberId: UUID?
    var paidToMemberId: UUID?
    var categoryId: UUID?
    var splitType: SplitType
    var paidByType: PaidByType
    var splitMemberId: UUID?
    var reimbursesTransactionId: UUID?
    var excludedFromBudget: Bool
    var notes: String?
    let createdAt: Date
    let createdByUserId: UUID?
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case date, description, amount
        case transactionType = "transaction_type"
        case paidByMemberId = "paid_by_member_id"
        case paidToMemberId = "paid_to_member_id"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case reimbursesTransactionId = "reimburses_transaction_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case createdAt = "created_at"
        case createdByUserId = "created_by_user_id"
        case updatedAt = "updated_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        date = try container.decode(Date.self, forKey: .date)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Decimal.self, forKey: .amount)
        transactionType = try container.decode(TransactionType.self, forKey: .transactionType)
        paidByMemberId = try container.decodeIfPresent(UUID.self, forKey: .paidByMemberId)
        paidToMemberId = try container.decodeIfPresent(UUID.self, forKey: .paidToMemberId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        splitType = try container.decode(SplitType.self, forKey: .splitType)
        paidByType = try container.decodeIfPresent(PaidByType.self, forKey: .paidByType) ?? .single
        splitMemberId = try container.decodeIfPresent(UUID.self, forKey: .splitMemberId)
        reimbursesTransactionId = try container.decodeIfPresent(UUID.self, forKey: .reimbursesTransactionId)
        excludedFromBudget = try container.decode(Bool.self, forKey: .excludedFromBudget)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        createdByUserId = try container.decodeIfPresent(UUID.self, forKey: .createdByUserId)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case settlement
    case reimbursement
    
    var displayName: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .settlement: return "Settlement"
        case .reimbursement: return "Reimburse"
        }
    }
    
    var icon: String {
        switch self {
        case .expense: return "cart"
        case .income: return "wallet.pass"
        case .settlement: return "arrow.left.arrow.right"
        case .reimbursement: return "arrow.uturn.backward"
        }
    }
    
    var color: Color {
        switch self {
        case .expense: return Theme.Colors.expense
        case .income: return Theme.Colors.income
        case .settlement: return Theme.Colors.settlement
        case .reimbursement: return Theme.Colors.reimbursement
        }
    }
}

enum SplitType: String, Codable, CaseIterable, Sendable {
    case equal
    case memberOnly = "member_only"
    case custom
    case payerOnly = "payer_only" // Legacy, kept for backwards compatibility
    
    var displayName: String {
        switch self {
        case .equal: return "Split Equally"
        case .memberOnly: return "Member Only"
        case .custom: return "Custom Split"
        case .payerOnly: return "Payer Only"
        }
    }
    
    // Split types shown in the UI picker (excludes legacy payerOnly)
    static var pickerCases: [SplitType] {
        [.equal, .memberOnly, .custom]
    }
}

enum PaidByType: String, Codable, CaseIterable, Sendable {
    case single
    case shared
    case custom
    
    var displayName: String {
        switch self {
        case .single: return "Single Member"
        case .shared: return "Shared Equally"
        case .custom: return "Custom Split"
        }
    }
    
    // Paid by types shown in the UI picker
    static var pickerCases: [PaidByType] {
        [.single, .shared, .custom]
    }
}

// MARK: - Transaction Split

struct TransactionSplit: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let transactionId: UUID
    let memberId: UUID
    var owedAmount: Decimal
    var owedPercentage: Decimal?
    var paidAmount: Decimal
    var paidPercentage: Decimal?
    let createdAt: Date
    
    // Legacy field - kept for backwards compatibility
    var amount: Decimal { owedAmount }
    var percentage: Decimal? { owedPercentage }
    
    enum CodingKeys: String, CodingKey {
        case id
        case transactionId = "transaction_id"
        case memberId = "member_id"
        case owedAmount = "owed_amount"
        case owedPercentage = "owed_percentage"
        case paidAmount = "paid_amount"
        case paidPercentage = "paid_percentage"
        case createdAt = "created_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        transactionId = try container.decode(UUID.self, forKey: .transactionId)
        memberId = try container.decode(UUID.self, forKey: .memberId)
        owedAmount = try container.decodeIfPresent(Decimal.self, forKey: .owedAmount) ?? 0
        owedPercentage = try container.decodeIfPresent(Decimal.self, forKey: .owedPercentage)
        paidAmount = try container.decodeIfPresent(Decimal.self, forKey: .paidAmount) ?? 0
        paidPercentage = try container.decodeIfPresent(Decimal.self, forKey: .paidPercentage)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    init(
        id: UUID = UUID(),
        transactionId: UUID,
        memberId: UUID,
        owedAmount: Decimal,
        owedPercentage: Decimal? = nil,
        paidAmount: Decimal = 0,
        paidPercentage: Decimal? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.memberId = memberId
        self.owedAmount = owedAmount
        self.owedPercentage = owedPercentage
        self.paidAmount = paidAmount
        self.paidPercentage = paidPercentage
        self.createdAt = createdAt
    }
}

// MARK: - Member Split (for UI state management)

struct MemberSplit: Identifiable, Hashable {
    let id: UUID // member ID
    var memberId: UUID { id }
    var displayName: String
    var owedAmount: Decimal
    var owedPercentage: Decimal
    var paidAmount: Decimal
    var paidPercentage: Decimal
    
    init(member: HouseholdMember, totalAmount: Decimal, memberCount: Int) {
        self.id = member.id
        self.displayName = member.displayName
        let equalShare = memberCount > 0 ? totalAmount / Decimal(memberCount) : 0
        let equalPercentage: Decimal = memberCount > 0 ? 100 / Decimal(memberCount) : 0
        self.owedAmount = equalShare
        self.owedPercentage = equalPercentage
        self.paidAmount = 0
        self.paidPercentage = 0
    }
    
    init(id: UUID, displayName: String, owedAmount: Decimal, owedPercentage: Decimal, paidAmount: Decimal, paidPercentage: Decimal) {
        self.id = id
        self.displayName = displayName
        self.owedAmount = owedAmount
        self.owedPercentage = owedPercentage
        self.paidAmount = paidAmount
        self.paidPercentage = paidPercentage
    }
}

// MARK: - Transaction View (with joined data)

struct TransactionView: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    var date: Date
    var description: String
    var amount: Decimal
    var transactionType: TransactionType
    var paidByMemberId: UUID?
    var paidToMemberId: UUID?
    var categoryId: UUID?
    var splitType: SplitType
    var paidByType: PaidByType
    var splitMemberId: UUID?
    var reimbursesTransactionId: UUID?
    var excludedFromBudget: Bool
    var notes: String?
    let createdAt: Date
    let createdByUserId: UUID?
    var updatedAt: Date
    
    // Joined fields
    var categoryName: String?
    var categoryIcon: String?
    var categoryColor: String?
    var paidByName: String?
    var paidByAvatar: String?
    var paidToName: String?
    var paidToAvatar: String?
    var splitMemberName: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case date, description, amount
        case transactionType = "transaction_type"
        case paidByMemberId = "paid_by_member_id"
        case paidToMemberId = "paid_to_member_id"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case reimbursesTransactionId = "reimburses_transaction_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case createdAt = "created_at"
        case createdByUserId = "created_by_user_id"
        case updatedAt = "updated_at"
        case categoryName = "category_name"
        case categoryIcon = "category_icon"
        case categoryColor = "category_color"
        case paidByName = "paid_by_name"
        case paidByAvatar = "paid_by_avatar"
        case paidToName = "paid_to_name"
        case paidToAvatar = "paid_to_avatar"
        case splitMemberName = "split_member_name"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        
        // Parse date from string (PostgreSQL DATE format: "2025-12-01")
        // Create date in LOCAL timezone to avoid off-by-one-day issues
        let dateString = try container.decode(String.self, forKey: .date)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current // Use local timezone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let parsedDate = dateFormatter.date(from: dateString) {
            date = parsedDate
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [CodingKeys.date], debugDescription: "Invalid date format: \(dateString)"))
        }
        
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Decimal.self, forKey: .amount)
        transactionType = try container.decode(TransactionType.self, forKey: .transactionType)
        paidByMemberId = try container.decodeIfPresent(UUID.self, forKey: .paidByMemberId)
        paidToMemberId = try container.decodeIfPresent(UUID.self, forKey: .paidToMemberId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        splitType = try container.decode(SplitType.self, forKey: .splitType)
        paidByType = try container.decodeIfPresent(PaidByType.self, forKey: .paidByType) ?? .single
        splitMemberId = try container.decodeIfPresent(UUID.self, forKey: .splitMemberId)
        reimbursesTransactionId = try container.decodeIfPresent(UUID.self, forKey: .reimbursesTransactionId)
        excludedFromBudget = try container.decode(Bool.self, forKey: .excludedFromBudget)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        
        // Parse timestamps from ISO8601 strings (PostgreSQL TIMESTAMPTZ format)
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        if let parsed = timestampFormatter.date(from: createdAtString) {
            createdAt = parsed
        } else {
            // Try without fractional seconds
            timestampFormatter.formatOptions = [.withInternetDateTime]
            createdAt = timestampFormatter.date(from: createdAtString) ?? Date()
        }
        
        createdByUserId = try container.decodeIfPresent(UUID.self, forKey: .createdByUserId)
        
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        if let parsed = timestampFormatter.date(from: updatedAtString) {
            updatedAt = parsed
        } else {
            timestampFormatter.formatOptions = [.withInternetDateTime]
            updatedAt = timestampFormatter.date(from: updatedAtString) ?? Date()
        }
        
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        categoryIcon = try container.decodeIfPresent(String.self, forKey: .categoryIcon)
        categoryColor = try container.decodeIfPresent(String.self, forKey: .categoryColor)
        paidByName = try container.decodeIfPresent(String.self, forKey: .paidByName)
        paidByAvatar = try container.decodeIfPresent(String.self, forKey: .paidByAvatar)
        paidToName = try container.decodeIfPresent(String.self, forKey: .paidToName)
        paidToAvatar = try container.decodeIfPresent(String.self, forKey: .paidToAvatar)
        splitMemberName = try container.decodeIfPresent(String.self, forKey: .splitMemberName)
    }
}

// MARK: - Create/Update DTOs

struct CreateTransactionDTO: Encodable, Sendable {
    let householdId: UUID
    let date: Date
    let description: String
    let amount: Decimal
    let transactionType: TransactionType
    let paidByMemberId: UUID?
    let paidToMemberId: UUID?
    let categoryId: UUID?
    let splitType: SplitType
    let paidByType: PaidByType
    let splitMemberId: UUID?
    let reimbursesTransactionId: UUID?
    let excludedFromBudget: Bool
    let notes: String?
    let createdByUserId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case date, description, amount
        case transactionType = "transaction_type"
        case paidByMemberId = "paid_by_member_id"
        case paidToMemberId = "paid_to_member_id"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case reimbursesTransactionId = "reimburses_transaction_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case createdByUserId = "created_by_user_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        
        // Format date as yyyy-MM-dd string for PostgreSQL DATE column
        // Use local calendar to get the correct date components
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dateString = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        try container.encode(dateString, forKey: .date)
        
        try container.encode(description, forKey: .description)
        try container.encode(amount, forKey: .amount)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encodeIfPresent(paidByMemberId, forKey: .paidByMemberId)
        try container.encodeIfPresent(paidToMemberId, forKey: .paidToMemberId)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encode(splitType, forKey: .splitType)
        try container.encode(paidByType, forKey: .paidByType)
        try container.encodeIfPresent(splitMemberId, forKey: .splitMemberId)
        try container.encodeIfPresent(reimbursesTransactionId, forKey: .reimbursesTransactionId)
        try container.encode(excludedFromBudget, forKey: .excludedFromBudget)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(createdByUserId, forKey: .createdByUserId)
    }
}

// MARK: - RPC Request for creating transaction with splits

struct CreateTransactionWithSplitsRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    let pDate: String
    let pDescription: String
    let pAmount: Decimal
    let pTransactionType: String
    let pPaidByMemberId: UUID?
    let pPaidToMemberId: UUID?
    let pCategoryId: UUID?
    let pSplitType: String
    let pPaidByType: String
    let pSplitMemberId: UUID?
    let pExcludedFromBudget: Bool
    let pNotes: String?
    let pCreatedByUserId: UUID?
    let pSplits: [SplitInput]?
    
    struct SplitInput: Encodable, Sendable {
        let memberId: UUID
        let owedAmount: Decimal
        let owedPercentage: Decimal?
        let paidAmount: Decimal
        let paidPercentage: Decimal?
        
        enum CodingKeys: String, CodingKey {
            case memberId = "member_id"
            case owedAmount = "owed_amount"
            case owedPercentage = "owed_percentage"
            case paidAmount = "paid_amount"
            case paidPercentage = "paid_percentage"
        }
        
        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(memberId, forKey: .memberId)
            try container.encode(owedAmount, forKey: .owedAmount)
            try container.encodeIfPresent(owedPercentage, forKey: .owedPercentage)
            try container.encode(paidAmount, forKey: .paidAmount)
            try container.encodeIfPresent(paidPercentage, forKey: .paidPercentage)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pDate = "p_date"
        case pDescription = "p_description"
        case pAmount = "p_amount"
        case pTransactionType = "p_transaction_type"
        case pPaidByMemberId = "p_paid_by_member_id"
        case pPaidToMemberId = "p_paid_to_member_id"
        case pCategoryId = "p_category_id"
        case pSplitType = "p_split_type"
        case pPaidByType = "p_paid_by_type"
        case pSplitMemberId = "p_split_member_id"
        case pExcludedFromBudget = "p_excluded_from_budget"
        case pNotes = "p_notes"
        case pCreatedByUserId = "p_created_by_user_id"
        case pSplits = "p_splits"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
        try container.encode(pDate, forKey: .pDate)
        try container.encode(pDescription, forKey: .pDescription)
        try container.encode(pAmount, forKey: .pAmount)
        try container.encode(pTransactionType, forKey: .pTransactionType)
        // Must encode all parameters (even nil) for PostgreSQL function matching
        try container.encode(pPaidByMemberId, forKey: .pPaidByMemberId)
        try container.encode(pPaidToMemberId, forKey: .pPaidToMemberId)
        try container.encode(pCategoryId, forKey: .pCategoryId)
        try container.encode(pSplitType, forKey: .pSplitType)
        try container.encode(pPaidByType, forKey: .pPaidByType)
        try container.encode(pSplitMemberId, forKey: .pSplitMemberId)
        try container.encode(pExcludedFromBudget, forKey: .pExcludedFromBudget)
        try container.encode(pNotes, forKey: .pNotes)
        try container.encode(pCreatedByUserId, forKey: .pCreatedByUserId)
        try container.encode(pSplits, forKey: .pSplits)
    }
    
    nonisolated init(
        householdId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID?,
        categoryId: UUID?,
        splitType: SplitType,
        paidByType: PaidByType,
        splitMemberId: UUID?,
        excludedFromBudget: Bool,
        notes: String?,
        createdByUserId: UUID?,
        splits: [MemberSplit]?
    ) {
        self.pHouseholdId = householdId
        
        // Format date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.pDate = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        
        self.pDescription = description
        self.pAmount = amount
        self.pTransactionType = transactionType.rawValue
        self.pPaidByMemberId = paidByMemberId
        self.pPaidToMemberId = paidToMemberId
        self.pCategoryId = categoryId
        self.pSplitType = splitType.rawValue
        self.pPaidByType = paidByType.rawValue
        self.pSplitMemberId = splitMemberId
        self.pExcludedFromBudget = excludedFromBudget
        self.pNotes = notes
        self.pCreatedByUserId = createdByUserId
        
        // Convert MemberSplit to SplitInput
        if let splits = splits {
            self.pSplits = splits.map { split in
                SplitInput(
                    memberId: split.id,
                    owedAmount: split.owedAmount,
                    owedPercentage: split.owedPercentage,
                    paidAmount: split.paidAmount,
                    paidPercentage: split.paidPercentage
                )
            }
        } else {
            self.pSplits = nil
        }
    }
}

// MARK: - RPC Request for updating transaction with splits

struct UpdateTransactionWithSplitsRequest: Encodable, Sendable {
    let pTransactionId: UUID
    let pDate: String
    let pDescription: String
    let pAmount: Decimal
    let pTransactionType: String
    let pPaidByMemberId: UUID?
    let pPaidToMemberId: UUID?
    let pCategoryId: UUID?
    let pSplitType: String
    let pPaidByType: String
    let pSplitMemberId: UUID?
    let pExcludedFromBudget: Bool
    let pNotes: String?
    let pSplits: [CreateTransactionWithSplitsRequest.SplitInput]?
    
    enum CodingKeys: String, CodingKey {
        case pTransactionId = "p_transaction_id"
        case pDate = "p_date"
        case pDescription = "p_description"
        case pAmount = "p_amount"
        case pTransactionType = "p_transaction_type"
        case pPaidByMemberId = "p_paid_by_member_id"
        case pPaidToMemberId = "p_paid_to_member_id"
        case pCategoryId = "p_category_id"
        case pSplitType = "p_split_type"
        case pPaidByType = "p_paid_by_type"
        case pSplitMemberId = "p_split_member_id"
        case pExcludedFromBudget = "p_excluded_from_budget"
        case pNotes = "p_notes"
        case pSplits = "p_splits"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pTransactionId, forKey: .pTransactionId)
        try container.encode(pDate, forKey: .pDate)
        try container.encode(pDescription, forKey: .pDescription)
        try container.encode(pAmount, forKey: .pAmount)
        try container.encode(pTransactionType, forKey: .pTransactionType)
        // Must encode all parameters (even nil) for PostgreSQL function matching
        try container.encode(pPaidByMemberId, forKey: .pPaidByMemberId)
        try container.encode(pPaidToMemberId, forKey: .pPaidToMemberId)
        try container.encode(pCategoryId, forKey: .pCategoryId)
        try container.encode(pSplitType, forKey: .pSplitType)
        try container.encode(pPaidByType, forKey: .pPaidByType)
        try container.encode(pSplitMemberId, forKey: .pSplitMemberId)
        try container.encode(pExcludedFromBudget, forKey: .pExcludedFromBudget)
        try container.encode(pNotes, forKey: .pNotes)
        try container.encode(pSplits, forKey: .pSplits)
    }
    
    nonisolated init(
        transactionId: UUID,
        date: Date,
        description: String,
        amount: Decimal,
        transactionType: TransactionType,
        paidByMemberId: UUID?,
        paidToMemberId: UUID?,
        categoryId: UUID?,
        splitType: SplitType,
        paidByType: PaidByType,
        splitMemberId: UUID?,
        excludedFromBudget: Bool,
        notes: String?,
        splits: [MemberSplit]?
    ) {
        self.pTransactionId = transactionId
        
        // Format date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.pDate = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
        
        self.pDescription = description
        self.pAmount = amount
        self.pTransactionType = transactionType.rawValue
        self.pPaidByMemberId = paidByMemberId
        self.pPaidToMemberId = paidToMemberId
        self.pCategoryId = categoryId
        self.pSplitType = splitType.rawValue
        self.pPaidByType = paidByType.rawValue
        self.pSplitMemberId = splitMemberId
        self.pExcludedFromBudget = excludedFromBudget
        self.pNotes = notes
        
        // Convert MemberSplit to SplitInput
        if let splits = splits {
            self.pSplits = splits.map { split in
                CreateTransactionWithSplitsRequest.SplitInput(
                    memberId: split.id,
                    owedAmount: split.owedAmount,
                    owedPercentage: split.owedPercentage,
                    paidAmount: split.paidAmount,
                    paidPercentage: split.paidPercentage
                )
            }
        } else {
            self.pSplits = nil
        }
    }
}
