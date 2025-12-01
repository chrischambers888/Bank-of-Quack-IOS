import Foundation

struct Household: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let inviteCode: String
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct HouseholdMember: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    let userId: UUID
    var displayName: String
    var avatarUrl: String?
    var role: MemberRole
    var color: String
    let createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case role, color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        userId = try container.decode(UUID.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = try container.decode(MemberRole.self, forKey: .role)
        color = try container.decode(String.self, forKey: .color)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner
    case admin
    case member
    
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .member: return "Member"
        }
    }
}

// MARK: - Member Balance (from view)

struct MemberBalance: Codable, Sendable {
    let householdId: UUID
    let memberId: UUID
    let displayName: String
    let totalPaid: Decimal
    let totalShare: Decimal
    let balance: Decimal
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case memberId = "member_id"
        case displayName = "display_name"
        case totalPaid = "total_paid"
        case totalShare = "total_share"
        case balance
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        memberId = try container.decode(UUID.self, forKey: .memberId)
        displayName = try container.decode(String.self, forKey: .displayName)
        totalPaid = try container.decode(Decimal.self, forKey: .totalPaid)
        totalShare = try container.decode(Decimal.self, forKey: .totalShare)
        balance = try container.decode(Decimal.self, forKey: .balance)
    }
}

// MARK: - RPC Request/Response

struct CreateHouseholdRequest: Encodable, Sendable {
    let pName: String
    let pDisplayName: String
    
    enum CodingKeys: String, CodingKey {
        case pName = "p_name"
        case pDisplayName = "p_display_name"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pName, forKey: .pName)
        try container.encode(pDisplayName, forKey: .pDisplayName)
    }
}

struct JoinHouseholdRequest: Encodable, Sendable {
    let pInviteCode: String
    let pDisplayName: String
    
    enum CodingKeys: String, CodingKey {
        case pInviteCode = "p_invite_code"
        case pDisplayName = "p_display_name"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pInviteCode, forKey: .pInviteCode)
        try container.encode(pDisplayName, forKey: .pDisplayName)
    }
}

