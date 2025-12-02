import Foundation
import Observation
import Supabase

@Observable
final class AuthViewModel {
    // MARK: - State
    
    var isLoading = true
    var isAuthenticated = false
    var awaitingConfirmationEmail: String?
    var currentUser: User?
    var currentHousehold: Household?
    var currentMember: HouseholdMember?
    var households: [Household] = []
    var members: [HouseholdMember] = []
    var pendingMembers: [HouseholdMember] = []
    var pendingHouseholds: [PendingHousehold] = []
    var categories: [Category] = []
    var sectors: [Sector] = []
    var sectorCategories: [UUID: [UUID]] = [:] // sectorId -> [categoryId]
    var error: String?
    
    // MARK: - Services
    
    private let authService = AuthService()
    private let dataService = DataService()
    
    // MARK: - Init
    
    init() {
        Task {
            await checkAuthState()
        }
    }
    
    // MARK: - Auth Methods
    
    @MainActor
    func checkAuthState() async {
        isLoading = true
        
        if let user = await authService.currentUser() {
            currentUser = user
            isAuthenticated = true
            awaitingConfirmationEmail = nil // Clear awaiting state on successful auth
            await loadUserData()
        } else {
            isAuthenticated = false
        }
        
        isLoading = false
    }
    
    @MainActor
    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        
        do {
            let user = try await authService.signIn(email: email, password: password)
            currentUser = user
            isAuthenticated = true
            await loadUserData()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        
        do {
            try await authService.signUp(email: email, password: password)
            // Show awaiting confirmation view
            awaitingConfirmationEmail = email
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func signOut() async {
        isLoading = true
        
        do {
            try await authService.signOut()
            currentUser = nil
            currentHousehold = nil
            currentMember = nil
            households = []
            members = []
            categories = []
            sectors = []
            sectorCategories = [:]
            isAuthenticated = false
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func resetPassword(email: String) async {
        isLoading = true
        error = nil
        
        do {
            try await authService.resetPassword(email: email)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Data Loading
    
    @MainActor
    func loadUserData() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            // Fetch households (only approved memberships)
            households = try await dataService.fetchUserHouseholds(userId: userId)
            
            // Fetch pending household requests
            pendingHouseholds = try await dataService.fetchMyPendingHouseholds()
            
            // Set current household (first one if available)
            if currentHousehold == nil, let first = households.first {
                await selectHousehold(first)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    func selectHousehold(_ household: Household) async {
        guard let userId = currentUser?.id else { return }
        
        currentHousehold = household
        
        do {
            // Fetch members (approved and inactive - we need inactive for historical data)
            let allMembers = try await dataService.fetchMembers(householdId: household.id)
            members = allMembers.filter { $0.isApproved || $0.isInactive }
            
            // Find current member
            currentMember = try await dataService.fetchCurrentMember(
                householdId: household.id,
                userId: userId
            )
            
            // Fetch pending members if admin/owner
            if let role = currentMember?.role, role.canApproveMembers {
                pendingMembers = try await dataService.fetchPendingMembers(householdId: household.id)
            } else {
                pendingMembers = []
            }
            
            // Fetch categories and sectors
            categories = try await dataService.fetchCategories(householdId: household.id)
            sectors = try await dataService.fetchSectors(householdId: household.id)
            
            // Fetch sector-category relationships
            await loadSectorCategories()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    private func loadSectorCategories() async {
        var mapping: [UUID: [UUID]] = [:]
        
        for sector in sectors {
            do {
                let links = try await dataService.fetchSectorCategories(sectorId: sector.id)
                mapping[sector.id] = links.map { $0.categoryId }
            } catch {
                mapping[sector.id] = []
            }
        }
        
        sectorCategories = mapping
    }
    
    @MainActor
    func refreshCategories() async {
        guard let householdId = currentHousehold?.id else { return }
        
        do {
            categories = try await dataService.fetchCategories(householdId: householdId)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    func refreshSectors() async {
        guard let householdId = currentHousehold?.id else { return }
        
        do {
            sectors = try await dataService.fetchSectors(householdId: householdId)
            await loadSectorCategories()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Household Management
    
    @MainActor
    func createHousehold(name: String, displayName: String) async {
        isLoading = true
        error = nil
        
        do {
            let householdId = try await dataService.createHousehold(
                name: name,
                displayName: displayName
            )
            
            // Reload user data
            await loadUserData()
            
            // Select the new household
            if let newHousehold = households.first(where: { $0.id == householdId }) {
                await selectHousehold(newHousehold)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func joinHousehold(inviteCode: String, displayName: String) async -> Bool {
        isLoading = true
        error = nil
        
        do {
            _ = try await dataService.joinHousehold(
                inviteCode: inviteCode,
                displayName: displayName
            )
            
            // Reload user data (will now show in pendingHouseholds)
            await loadUserData()
            
            isLoading = false
            return true // Request submitted successfully
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    // MARK: - Member Approval
    
    @MainActor
    func approveMember(_ member: HouseholdMember) async {
        isLoading = true
        error = nil
        
        do {
            try await dataService.approveMember(memberId: member.id)
            
            // Refresh the household data
            if let household = currentHousehold {
                await selectHousehold(household)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func rejectMember(_ member: HouseholdMember) async {
        isLoading = true
        error = nil
        
        do {
            try await dataService.rejectMember(memberId: member.id)
            
            // Refresh pending members
            if let household = currentHousehold {
                pendingMembers = try await dataService.fetchPendingMembers(householdId: household.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func updateMyProfile(displayName: String?, emoji: String?, color: String?) async -> Bool {
        guard let member = currentMember else { return false }
        
        isLoading = true
        error = nil
        
        do {
            let updatedMember = try await dataService.updateMemberProfile(
                memberId: member.id,
                displayName: displayName,
                avatarEmoji: emoji,
                color: color
            )
            currentMember = updatedMember
            
            // Update in members list too
            if let index = members.firstIndex(where: { $0.id == updatedMember.id }) {
                members[index] = updatedMember
            }
            
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    @MainActor
    func refreshPendingMembers() async {
        guard let household = currentHousehold,
              let role = currentMember?.role,
              role.canApproveMembers else { return }
        
        do {
            pendingMembers = try await dataService.fetchPendingMembers(householdId: household.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    func deleteHousehold(_ household: Household) async -> Bool {
        isLoading = true
        error = nil
        
        do {
            try await dataService.deleteHousehold(householdId: household.id)
            
            // Clear current household if it was the deleted one
            if currentHousehold?.id == household.id {
                currentHousehold = nil
                currentMember = nil
                members = []
                pendingMembers = []
                categories = []
                sectors = []
                sectorCategories = [:]
            }
            
            // Reload user data
            await loadUserData()
            
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    @MainActor
    func leaveHousehold() async -> Bool {
        guard let household = currentHousehold else { return false }
        
        isLoading = true
        error = nil
        
        do {
            try await dataService.leaveHousehold(householdId: household.id)
            
            // Clear current household state
            currentHousehold = nil
            currentMember = nil
            members = []
            pendingMembers = []
            categories = []
            sectors = []
            sectorCategories = [:]
            
            // Reload user data (will select another household if available)
            await loadUserData()
            
            isLoading = false
            return true
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return false
        }
    }
    
    // MARK: - Email Confirmation
    
    @MainActor
    func cancelAwaitingConfirmation() {
        awaitingConfirmationEmail = nil
    }
    
    func resendConfirmation(email: String) async throws {
        try await authService.resendConfirmation(email: email)
    }
    
    // MARK: - Helpers
    
    func clearError() {
        error = nil
    }
}

