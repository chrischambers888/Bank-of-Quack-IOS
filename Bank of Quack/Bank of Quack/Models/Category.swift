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
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decode(String.self, forKey: .color)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        householdId = try container.decode(UUID.self, forKey: .householdId)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(String.self, forKey: .color)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        categoryIds = try container.decodeIfPresent([UUID].self, forKey: .categoryIds)
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
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sectorId = try container.decode(UUID.self, forKey: .sectorId)
        categoryId = try container.decode(UUID.self, forKey: .categoryId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Category DTOs

struct CreateCategoryDTO: Encodable, Sendable {
    let householdId: UUID
    let name: String
    let icon: String?
    let color: String
    let imageUrl: String?
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case name, icon, color
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct UpdateCategoryDTO: Encodable, Sendable {
    let name: String?
    let icon: String?
    let color: String?
    let imageUrl: String?
    let sortOrder: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, icon, color
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
    }
    
    init(name: String? = nil, icon: String? = nil, color: String? = nil, imageUrl: String? = nil, sortOrder: Int? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
        self.imageUrl = imageUrl
        self.sortOrder = sortOrder
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Sector DTOs

struct CreateSectorDTO: Encodable, Sendable {
    let householdId: UUID
    let name: String
    let color: String
    let sortOrder: Int
    
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case name, color
        case sortOrder = "sort_order"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

struct UpdateSectorDTO: Encodable, Sendable {
    let name: String?
    let color: String?
    let sortOrder: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, color
        case sortOrder = "sort_order"
    }
    
    init(name: String? = nil, color: String? = nil, sortOrder: Int? = nil) {
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - SectorCategory DTO

struct CreateSectorCategoryDTO: Encodable, Sendable {
    let sectorId: UUID
    let categoryId: UUID
    
    enum CodingKeys: String, CodingKey {
        case sectorId = "sector_id"
        case categoryId = "category_id"
    }
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sectorId, forKey: .sectorId)
        try container.encode(categoryId, forKey: .categoryId)
    }
}

