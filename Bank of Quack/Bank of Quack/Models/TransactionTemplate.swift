import Foundation

// MARK: - Transaction Template

struct TransactionTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    let createdByMemberId: UUID?
    
    var name: String
    var description: String
    var amount: Decimal
    var transactionType: TransactionType
    var categoryId: UUID?
    var splitType: SplitType
    var paidByMemberId: UUID?
    var paidByType: PaidByType
    var splitMemberId: UUID?
    var excludedFromBudget: Bool
    var notes: String?
    var sortOrder: Int
    
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case createdByMemberId = "created_by_member_id"
        case name, description, amount
        case transactionType = "transaction_type"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByMemberId = "paid_by_member_id"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        createdByMemberId = try container.decodeIfPresent(UUID.self, forKey: .createdByMemberId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Decimal.self, forKey: .amount)
        transactionType = try container.decodeIfPresent(TransactionType.self, forKey: .transactionType) ?? .expense
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        splitType = try container.decodeIfPresent(SplitType.self, forKey: .splitType) ?? .equal
        paidByMemberId = try container.decodeIfPresent(UUID.self, forKey: .paidByMemberId)
        paidByType = try container.decodeIfPresent(PaidByType.self, forKey: .paidByType) ?? .single
        splitMemberId = try container.decodeIfPresent(UUID.self, forKey: .splitMemberId)
        excludedFromBudget = try container.decodeIfPresent(Bool.self, forKey: .excludedFromBudget) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Create Template DTO

struct CreateTemplateDTO: Encodable, Sendable {
    let householdId: UUID
    let createdByMemberId: UUID?
    let name: String
    let description: String
    let amount: Decimal
    let transactionType: TransactionType
    let categoryId: UUID?
    let splitType: SplitType
    let paidByMemberId: UUID?
    let paidByType: PaidByType
    let splitMemberId: UUID?
    let excludedFromBudget: Bool
    let notes: String?
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case createdByMemberId = "created_by_member_id"
        case name, description, amount
        case transactionType = "transaction_type"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByMemberId = "paid_by_member_id"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case sortOrder = "sort_order"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        try container.encodeIfPresent(createdByMemberId, forKey: .createdByMemberId)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(amount, forKey: .amount)
        try container.encode(transactionType, forKey: .transactionType)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encode(splitType, forKey: .splitType)
        try container.encodeIfPresent(paidByMemberId, forKey: .paidByMemberId)
        try container.encode(paidByType, forKey: .paidByType)
        try container.encodeIfPresent(splitMemberId, forKey: .splitMemberId)
        try container.encode(excludedFromBudget, forKey: .excludedFromBudget)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Update Template DTO

struct UpdateTemplateDTO: Encodable, Sendable {
    let name: String?
    let description: String?
    let amount: Decimal?
    let transactionType: TransactionType?
    let categoryId: UUID?
    let splitType: SplitType?
    let paidByMemberId: UUID?
    let paidByType: PaidByType?
    let splitMemberId: UUID?
    let excludedFromBudget: Bool?
    let notes: String?
    let sortOrder: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, description, amount
        case transactionType = "transaction_type"
        case categoryId = "category_id"
        case splitType = "split_type"
        case paidByMemberId = "paid_by_member_id"
        case paidByType = "paid_by_type"
        case splitMemberId = "split_member_id"
        case excludedFromBudget = "excluded_from_budget"
        case notes
        case sortOrder = "sort_order"
    }
    
    init(
        name: String? = nil,
        description: String? = nil,
        amount: Decimal? = nil,
        transactionType: TransactionType? = nil,
        categoryId: UUID? = nil,
        splitType: SplitType? = nil,
        paidByMemberId: UUID? = nil,
        paidByType: PaidByType? = nil,
        splitMemberId: UUID? = nil,
        excludedFromBudget: Bool? = nil,
        notes: String? = nil,
        sortOrder: Int? = nil
    ) {
        self.name = name
        self.description = description
        self.amount = amount
        self.transactionType = transactionType
        self.categoryId = categoryId
        self.splitType = splitType
        self.paidByMemberId = paidByMemberId
        self.paidByType = paidByType
        self.splitMemberId = splitMemberId
        self.excludedFromBudget = excludedFromBudget
        self.notes = notes
        self.sortOrder = sortOrder
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(transactionType, forKey: .transactionType)
        try container.encodeIfPresent(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(splitType, forKey: .splitType)
        try container.encodeIfPresent(paidByMemberId, forKey: .paidByMemberId)
        try container.encodeIfPresent(paidByType, forKey: .paidByType)
        try container.encodeIfPresent(splitMemberId, forKey: .splitMemberId)
        try container.encodeIfPresent(excludedFromBudget, forKey: .excludedFromBudget)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }
}

