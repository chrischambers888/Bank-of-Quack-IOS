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
    case custom
    case payerOnly = "payer_only"
    
    var displayName: String {
        switch self {
        case .equal: return "Split Equally"
        case .custom: return "Custom Split"
        case .payerOnly: return "Payer Only"
        }
    }
}

struct TransactionSplit: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let transactionId: UUID
    let memberId: UUID
    var amount: Decimal
    var percentage: Decimal?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case transactionId = "transaction_id"
        case memberId = "member_id"
        case amount, percentage
        case createdAt = "created_at"
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
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case date, description, amount
        case transactionType = "transaction_type"
        case paidByMemberId = "paid_by_member_id"
        case paidToMemberId = "paid_to_member_id"
        case categoryId = "category_id"
        case splitType = "split_type"
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
        try container.encodeIfPresent(reimbursesTransactionId, forKey: .reimbursesTransactionId)
        try container.encode(excludedFromBudget, forKey: .excludedFromBudget)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(createdByUserId, forKey: .createdByUserId)
    }
}

