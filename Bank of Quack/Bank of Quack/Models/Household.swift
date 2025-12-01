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
}

// MARK: - RPC Request/Response

struct CreateHouseholdRequest: Encodable {
    let pName: String
    let pDisplayName: String
    
    enum CodingKeys: String, CodingKey {
        case pName = "p_name"
        case pDisplayName = "p_display_name"
    }
}

struct JoinHouseholdRequest: Encodable {
    let pInviteCode: String
    let pDisplayName: String
    
    enum CodingKeys: String, CodingKey {
        case pInviteCode = "p_invite_code"
        case pDisplayName = "p_display_name"
    }
}

