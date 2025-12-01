import Foundation
import SwiftUI

// Re-export from Household.swift for convenience
// The actual HouseholdMember is defined in Household.swift

extension HouseholdMember {
    var swiftUIColor: Color {
        Color(hex: color.replacingOccurrences(of: "#", with: ""))
    }
    
    var initials: String {
        displayName.initials(count: 2)
    }
}

// MARK: - App State

struct AppUser: Codable, Sendable {
    let id: UUID
    let email: String
}

