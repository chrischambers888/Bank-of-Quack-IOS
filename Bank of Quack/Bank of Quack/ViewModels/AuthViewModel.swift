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
            // Fetch households
            households = try await dataService.fetchUserHouseholds(userId: userId)
            
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
            // Fetch members
            members = try await dataService.fetchMembers(householdId: household.id)
            
            // Find current member
            currentMember = try await dataService.fetchCurrentMember(
                householdId: household.id,
                userId: userId
            )
            
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
    func joinHousehold(inviteCode: String, displayName: String) async {
        isLoading = true
        error = nil
        
        do {
            let householdId = try await dataService.joinHousehold(
                inviteCode: inviteCode,
                displayName: displayName
            )
            
            // Reload user data
            await loadUserData()
            
            // Select the joined household
            if let joinedHousehold = households.first(where: { $0.id == householdId }) {
                await selectHousehold(joinedHousehold)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
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

