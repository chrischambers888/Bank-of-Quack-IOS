import Foundation
import SwiftUI

// MARK: - Date Filter Preset

enum DateFilterPreset: String, Codable, CaseIterable, Sendable {
    case thisMonth
    case lastMonth
    case thisYear
    case allTime
    case custom
    
    var displayName: String {
        switch self {
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .thisYear: return "This Year"
        case .allTime: return "All Time"
        case .custom: return "Custom"
        }
    }
    
    var icon: String {
        switch self {
        case .thisMonth: return "calendar"
        case .lastMonth: return "calendar.badge.clock"
        case .thisYear: return "calendar.circle"
        case .allTime: return "infinity"
        case .custom: return "calendar.badge.plus"
        }
    }
}

// MARK: - Dashboard Filter

struct DashboardFilter: Codable, Equatable, Sendable {
    var datePreset: DateFilterPreset = .thisMonth
    var customStartDate: Date?
    var customEndDate: Date?
    var selectedSectorIds: Set<UUID> = []
    var selectedCategoryIds: Set<UUID> = []
    var selectedTransactionTypes: Set<String> = ["expense", "income", "settlement", "reimbursement"]
    var selectedMemberIds: Set<UUID> = []
    var includeShared: Bool = true
    var sharedOnly: Bool = false // Show only shared expenses (no members selected)
    var searchText: String = ""
    
    /// Default filter state (current month only)
    static var `default`: DashboardFilter {
        DashboardFilter()
    }
    
    /// Whether any non-default filters are active
    var isFiltered: Bool {
        // Check if anything differs from default
        if datePreset != .thisMonth { return true }
        if !selectedSectorIds.isEmpty { return true }
        if !selectedCategoryIds.isEmpty { return true }
        if selectedTransactionTypes.count != 4 { return true }
        if !selectedMemberIds.isEmpty { return true }
        if !includeShared { return true }
        if sharedOnly { return true }
        if !searchText.isEmpty { return true }
        return false
    }
    
    /// Active filter count for badge display
    var activeFilterCount: Int {
        var count = 0
        if datePreset != .thisMonth { count += 1 }
        if !selectedSectorIds.isEmpty || !selectedCategoryIds.isEmpty { count += 1 }
        if selectedTransactionTypes.count != 4 { count += 1 }
        if !selectedMemberIds.isEmpty || sharedOnly { count += 1 }
        if !selectedMemberIds.isEmpty && !includeShared { count += 1 }
        if !searchText.isEmpty { count += 1 }
        return count
    }
    
    /// Compute date range based on preset
    var dateRange: (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()
        
        switch datePreset {
        case .thisMonth:
            return (now.startOfMonth, now.endOfMonth)
            
        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return (lastMonth.startOfMonth, lastMonth.endOfMonth)
            
        case .thisYear:
            guard let startOfYear = calendar.dateInterval(of: .year, for: now)?.start,
                  let endOfYear = calendar.dateInterval(of: .year, for: now)?.end else { return nil }
            return (startOfYear, endOfYear)
            
        case .allTime:
            return nil // No date restriction
            
        case .custom:
            guard let start = customStartDate, let end = customEndDate else { return nil }
            // Ensure end date includes the entire day
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            return (start.startOfDay, endOfDay)
        }
    }
    
    /// Check if a transaction type is selected
    func isTransactionTypeSelected(_ type: TransactionType) -> Bool {
        selectedTransactionTypes.contains(type.rawValue)
    }
    
    /// Toggle a transaction type
    mutating func toggleTransactionType(_ type: TransactionType) {
        if selectedTransactionTypes.contains(type.rawValue) {
            selectedTransactionTypes.remove(type.rawValue)
        } else {
            selectedTransactionTypes.insert(type.rawValue)
        }
    }
    
    /// Check if a member is selected
    func isMemberSelected(_ memberId: UUID) -> Bool {
        // Empty means all selected (no filter)
        selectedMemberIds.isEmpty || selectedMemberIds.contains(memberId)
    }
    
    /// Toggle a member selection
    mutating func toggleMember(_ memberId: UUID) {
        if selectedMemberIds.contains(memberId) {
            selectedMemberIds.remove(memberId)
        } else {
            selectedMemberIds.insert(memberId)
        }
    }
    
    /// Check if a sector is selected
    func isSectorSelected(_ sectorId: UUID) -> Bool {
        selectedSectorIds.isEmpty || selectedSectorIds.contains(sectorId)
    }
    
    /// Toggle a sector selection
    mutating func toggleSector(_ sectorId: UUID) {
        if selectedSectorIds.contains(sectorId) {
            selectedSectorIds.remove(sectorId)
        } else {
            selectedSectorIds.insert(sectorId)
        }
    }
    
    /// Check if a category is selected
    func isCategorySelected(_ categoryId: UUID) -> Bool {
        selectedCategoryIds.isEmpty || selectedCategoryIds.contains(categoryId)
    }
    
    /// Toggle a category selection
    mutating func toggleCategory(_ categoryId: UUID) {
        if selectedCategoryIds.contains(categoryId) {
            selectedCategoryIds.remove(categoryId)
        } else {
            selectedCategoryIds.insert(categoryId)
        }
    }
    
    /// Reset to default state
    mutating func reset() {
        self = .default
    }
}

// MARK: - Dashboard Filter Manager

@Observable
final class DashboardFilterManager {
    private static let storageKey = "dashboard_filter_state"
    
    var filter: DashboardFilter {
        didSet {
            saveFilter()
        }
    }
    
    init() {
        // Try to load persisted filter, otherwise use default
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(DashboardFilter.self, from: data) {
            self.filter = decoded
        } else {
            self.filter = .default
        }
    }
    
    /// Save filter state to UserDefaults
    private func saveFilter() {
        if let encoded = try? JSONEncoder().encode(filter) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }
    
    /// Reset filter to default and clear persisted state
    func resetToDefault() {
        filter = .default
    }
    
    /// Clear persisted filter (called on force quit detection if needed)
    static func clearPersistedFilter() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Filter Summary

extension DashboardFilter {
    /// Formatted date description showing actual month/year names
    var dateDescription: String {
        dateDescription(firstTransactionDate: nil, lastTransactionDate: nil)
    }
    
    /// Formatted date description with transaction date range for "All Time"
    func dateDescription(firstTransactionDate: Date?, lastTransactionDate: Date?) -> String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        
        switch datePreset {
        case .thisMonth:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: now)
            
        case .lastMonth:
            formatter.dateFormat = "MMMM yyyy"
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else {
                return "Last Month"
            }
            return formatter.string(from: lastMonth)
            
        case .thisYear:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: now)
            
        case .allTime:
            // Show actual date range if transaction dates are available
            guard let firstDate = firstTransactionDate else {
                return "All Time"
            }
            
            formatter.dateFormat = "MMM yyyy"
            let firstFormatted = formatter.string(from: firstDate)
            
            // Determine the end date to display
            let currentMonthStart = now.startOfMonth
            let lastDate = lastTransactionDate ?? now
            
            // Check if last transaction is in current month or earlier
            if lastDate < currentMonthStart {
                // Last transaction is before current month - show actual end date
                let lastFormatted = formatter.string(from: lastDate)
                return "\(firstFormatted) – \(lastFormatted)"
            } else {
                // Last transaction is in current month or later
                // Check if it's in the future (past current month)
                let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now
                if lastDate >= nextMonthStart {
                    // Future transaction data exists
                    let lastFormatted = formatter.string(from: lastDate)
                    return "\(firstFormatted) – \(lastFormatted)"
                } else {
                    // Last transaction is in current month
                    return "\(firstFormatted) – Present"
                }
            }
            
        case .custom:
            guard let start = customStartDate, let end = customEndDate else {
                return "Custom"
            }
            formatter.dateStyle = .medium
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
    }
    
    /// Human-readable summary of active filters
    var summary: String {
        summary(firstTransactionDate: nil, lastTransactionDate: nil)
    }
    
    /// Human-readable summary with transaction date range for "All Time"
    func summary(firstTransactionDate: Date?, lastTransactionDate: Date?) -> String {
        var parts: [String] = []
        
        // Date - always show with actual month/year
        parts.append(dateDescription(firstTransactionDate: firstTransactionDate, lastTransactionDate: lastTransactionDate))
        
        // Categories/Sectors
        if !selectedSectorIds.isEmpty && !selectedCategoryIds.isEmpty {
            parts.append("\(selectedSectorIds.count) sector\(selectedSectorIds.count == 1 ? "" : "s"), \(selectedCategoryIds.count) categor\(selectedCategoryIds.count == 1 ? "y" : "ies")")
        } else if !selectedSectorIds.isEmpty {
            parts.append("\(selectedSectorIds.count) sector\(selectedSectorIds.count == 1 ? "" : "s")")
        } else if !selectedCategoryIds.isEmpty {
            parts.append("\(selectedCategoryIds.count) categor\(selectedCategoryIds.count == 1 ? "y" : "ies")")
        }
        
        // Transaction types
        if selectedTransactionTypes.count < 4 {
            let typeNames = selectedTransactionTypes.sorted().map { type -> String in
                switch type {
                case "expense": return "Expenses"
                case "income": return "Income"
                case "settlement": return "Settlements"
                case "reimbursement": return "Reimbursements"
                default: return type.capitalized
                }
            }
            if typeNames.count <= 2 {
                parts.append(typeNames.joined(separator: " & "))
            } else {
                parts.append("\(selectedTransactionTypes.count) types")
            }
        }
        
        // Members
        if sharedOnly && selectedMemberIds.isEmpty {
            parts.append("Shared only")
        } else if !selectedMemberIds.isEmpty {
            let memberText = selectedMemberIds.count == 1 ? "1 member" : "\(selectedMemberIds.count) members"
            if !includeShared {
                parts.append("\(memberText) only")
            } else {
                parts.append(memberText)
            }
        }
        
        // Search
        if !searchText.isEmpty {
            parts.append("Search: \"\(searchText)\"")
        }
        
        return parts.joined(separator: " • ")
    }
    
    /// Detailed description for display
    var detailedDescription: String {
        var lines: [String] = []
        
        // Date range
        switch datePreset {
        case .thisMonth:
            lines.append("Showing this month's transactions")
        case .lastMonth:
            lines.append("Showing last month's transactions")
        case .thisYear:
            lines.append("Showing this year's transactions")
        case .allTime:
            lines.append("Showing all transactions")
        case .custom:
            if let start = customStartDate, let end = customEndDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                lines.append("From \(formatter.string(from: start)) to \(formatter.string(from: end))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}

