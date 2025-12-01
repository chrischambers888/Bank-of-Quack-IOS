import Foundation
import SwiftUI

struct Category: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    var name: String
    var icon: String?
    var color: String
    var imageUrl: String?
    var sortOrder: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name, icon, color
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
    
    var swiftUIColor: Color {
        Color(hex: color.replacingOccurrences(of: "#", with: ""))
    }
}

struct Sector: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let householdId: UUID
    var name: String
    var color: String
    var sortOrder: Int
    let createdAt: Date
    var categoryIds: [UUID]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name, color
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case categoryIds = "category_ids"
    }
    
    var swiftUIColor: Color {
        Color(hex: color.replacingOccurrences(of: "#", with: ""))
    }
}

struct SectorCategory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sectorId: UUID
    let categoryId: UUID
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sectorId = "sector_id"
        case categoryId = "category_id"
        case createdAt = "created_at"
    }
}

