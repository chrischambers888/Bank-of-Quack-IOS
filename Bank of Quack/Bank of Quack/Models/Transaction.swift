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
}

// MARK: - Create/Update DTOs

struct CreateTransactionDTO: Encodable {
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
}

