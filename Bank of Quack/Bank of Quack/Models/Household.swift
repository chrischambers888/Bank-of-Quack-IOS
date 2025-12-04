import Foundation

struct Household: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let inviteCode: String
    let createdAt: Date
    var updatedAt: Date
    var pendingOwnerMemberId: UUID?
    var pendingOwnerInitiatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pendingOwnerMemberId = "pending_owner_member_id"
        case pendingOwnerInitiatedAt = "pending_owner_initiated_at"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pendingOwnerMemberId = try container.decodeIfPresent(UUID.self, forKey: .pendingOwnerMemberId)
        pendingOwnerInitiatedAt = try container.decodeIfPresent(Date.self, forKey: .pendingOwnerInitiatedAt)
    }
    
    /// Returns true if there's a pending ownership transfer
    var hasPendingOwnershipTransfer: Bool {
        pendingOwnerMemberId != nil
    }
}

struct HouseholdMember: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    let userId: UUID?  // Optional for managed members
    var displayName: String
    var avatarUrl: String?
    var role: MemberRole
    var color: String
    var status: MemberStatus
    let createdAt: Date
    var updatedAt: Date
    var managedByUserId: UUID?  // Who manages this member (if managed)
    var claimCode: String?  // Code for claiming this managed member
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case role, color, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case managedByUserId = "managed_by_user_id"
        case claimCode = "claim_code"
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = try container.decode(MemberRole.self, forKey: .role)
        color = try container.decode(String.self, forKey: .color)
        status = try container.decodeIfPresent(MemberStatus.self, forKey: .status) ?? .approved
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        managedByUserId = try container.decodeIfPresent(UUID.self, forKey: .managedByUserId)
        claimCode = try container.decodeIfPresent(String.self, forKey: .claimCode)
    }
    
    var isPending: Bool {
        status == .pending
    }
    
    var isApproved: Bool {
        status == .approved
    }
    
    var isInactive: Bool {
        status == .inactive
    }
    
    /// Returns true if member is active (approved) and can be used for new transactions
    var isActive: Bool {
        status == .approved
    }
    
    /// Returns true if this is a managed member (no linked user account)
    var isManaged: Bool {
        userId == nil && managedByUserId != nil
    }
    
    /// Returns true if the given user manages this member
    func isManagedBy(userId: UUID) -> Bool {
        managedByUserId == userId
    }
}

enum MemberRole: String, Codable, CaseIterable, Sendable {
    case owner
    case member
    
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .member: return "Member"
        }
    }
    
    var isOwner: Bool {
        self == .owner
    }
}

enum MemberStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case inactive
    
    var displayName: String {
        switch self {
        case .pending: return "Pending Approval"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .inactive: return "Inactive"
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
    
    init(householdId: UUID, memberId: UUID, displayName: String, totalPaid: Decimal, totalShare: Decimal, balance: Decimal) {
        self.householdId = householdId
        self.memberId = memberId
        self.displayName = displayName
        self.totalPaid = totalPaid
        self.totalShare = totalShare
        self.balance = balance
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

// MARK: - Member Profile Update

struct UpdateMemberProfileDTO: Encodable, Sendable {
    let displayName: String?
    let avatarUrl: String?
    let color: String?
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case color
    }
    
    nonisolated init(displayName: String? = nil, avatarUrl: String? = nil, color: String? = nil) {
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.color = color
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(color, forKey: .color)
    }
}

struct UpdateMyProfileRequest: Encodable, Sendable {
    let pMemberId: UUID
    let pDisplayName: String?
    let pAvatarUrl: String?
    let pColor: String?
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
        case pDisplayName = "p_display_name"
        case pAvatarUrl = "p_avatar_url"
        case pColor = "p_color"
    }
    
    nonisolated init(memberId: UUID, displayName: String? = nil, avatarUrl: String? = nil, color: String? = nil) {
        self.pMemberId = memberId
        self.pDisplayName = displayName
        self.pAvatarUrl = avatarUrl
        self.pColor = color
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
        try container.encodeIfPresent(pDisplayName, forKey: .pDisplayName)
        try container.encodeIfPresent(pAvatarUrl, forKey: .pAvatarUrl)
        try container.encodeIfPresent(pColor, forKey: .pColor)
    }
}

// MARK: - Member Approval

struct ApproveMemberRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct RejectMemberRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct GetPendingMembersRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

struct PendingHousehold: Codable, Identifiable, Sendable {
    let householdId: UUID
    let householdName: String
    let memberId: UUID
    let displayName: String
    let status: String
    let requestedAt: Date
    
    var id: UUID { memberId }
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case householdName = "household_name"
        case memberId = "member_id"
        case displayName = "display_name"
        case status
        case requestedAt = "requested_at"
    }
}

// MARK: - Household Management

struct DeleteHouseholdRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

struct LeaveHouseholdRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

// MARK: - Managed Members

struct CreateManagedMemberRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    let pDisplayName: String
    let pColor: String
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pDisplayName = "p_display_name"
        case pColor = "p_color"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
        try container.encode(pDisplayName, forKey: .pDisplayName)
        try container.encode(pColor, forKey: .pColor)
    }
}

struct ClaimManagedMemberRequest: Encodable, Sendable {
    let pClaimCode: String
    
    enum CodingKeys: String, CodingKey {
        case pClaimCode = "p_claim_code"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pClaimCode, forKey: .pClaimCode)
    }
}

struct RegenerateClaimCodeRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct DeleteManagedMemberRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct CheckInactiveMembershipRequest: Encodable, Sendable {
    let pInviteCode: String
    
    enum CodingKeys: String, CodingKey {
        case pInviteCode = "p_invite_code"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pInviteCode, forKey: .pInviteCode)
    }
}

struct InactiveMemberInfo: Codable, Sendable {
    let memberId: UUID
    let displayName: String
    let householdName: String
    
    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case displayName = "display_name"
        case householdName = "household_name"
    }
}

// MARK: - Owner Member Management

struct RemoveMemberRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct ReactivateMemberRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

// MARK: - Ownership Transfer

struct InitiateOwnershipTransferRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    let pTargetMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
        case pTargetMemberId = "p_target_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
        try container.encode(pTargetMemberId, forKey: .pTargetMemberId)
    }
}

struct RevokeOwnershipTransferRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

struct AcceptOwnershipTransferRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

struct DeclineOwnershipTransferRequest: Encodable, Sendable {
    let pHouseholdId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pHouseholdId = "p_household_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pHouseholdId, forKey: .pHouseholdId)
    }
}

// MARK: - Member Permissions

/// Represents the permissions granted to a member by the household owner
struct MemberPermissions: Codable, Sendable, Equatable {
    let memberId: UUID
    var canCreateManagedMembers: Bool
    var canRemoveMembers: Bool
    var canReactivateMembers: Bool
    var canApproveJoinRequests: Bool
    
    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case canCreateManagedMembers = "can_create_managed_members"
        case canRemoveMembers = "can_remove_members"
        case canReactivateMembers = "can_reactivate_members"
        case canApproveJoinRequests = "can_approve_join_requests"
    }
    
    /// Creates a default permissions object with no permissions granted
    nonisolated static func defaultPermissions(for memberId: UUID) -> MemberPermissions {
        MemberPermissions(
            memberId: memberId,
            canCreateManagedMembers: false,
            canRemoveMembers: false,
            canReactivateMembers: false,
            canApproveJoinRequests: false
        )
    }
    
    /// Returns true if all permissions are false (default state)
    var hasNoPermissions: Bool {
        !canCreateManagedMembers && !canRemoveMembers && !canReactivateMembers && !canApproveJoinRequests
    }
    
    /// Returns true if any permission is granted
    var hasAnyPermission: Bool {
        canCreateManagedMembers || canRemoveMembers || canReactivateMembers || canApproveJoinRequests
    }
}

struct GetMemberPermissionsRequest: Encodable, Sendable {
    let pMemberId: UUID
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
    }
}

struct UpdateMemberPermissionsRequest: Encodable, Sendable {
    let pMemberId: UUID
    let pCanCreateManagedMembers: Bool?
    let pCanRemoveMembers: Bool?
    let pCanReactivateMembers: Bool?
    let pCanApproveJoinRequests: Bool?
    
    enum CodingKeys: String, CodingKey {
        case pMemberId = "p_member_id"
        case pCanCreateManagedMembers = "p_can_create_managed_members"
        case pCanRemoveMembers = "p_can_remove_members"
        case pCanReactivateMembers = "p_can_reactivate_members"
        case pCanApproveJoinRequests = "p_can_approve_join_requests"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pMemberId, forKey: .pMemberId)
        try container.encodeIfPresent(pCanCreateManagedMembers, forKey: .pCanCreateManagedMembers)
        try container.encodeIfPresent(pCanRemoveMembers, forKey: .pCanRemoveMembers)
        try container.encodeIfPresent(pCanReactivateMembers, forKey: .pCanReactivateMembers)
        try container.encodeIfPresent(pCanApproveJoinRequests, forKey: .pCanApproveJoinRequests)
    }
}

