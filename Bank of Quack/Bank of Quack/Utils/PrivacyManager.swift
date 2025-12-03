import Foundation
import SwiftUI

/// Manages privacy settings for hiding sensitive financial information.
/// Settings persist between sessions.
@Observable
final class PrivacyManager {
    static let shared = PrivacyManager()
    
    /// When true, hides income transactions, total income card, and net balance card
    var hideIncomeData: Bool {
        didSet { UserDefaults.standard.set(hideIncomeData, forKey: "privacy_hideIncomeData") }
    }
    
    /// When true, randomizes all monetary values displayed in the app (client-side only)
    var randomizeValues: Bool {
        didSet { UserDefaults.standard.set(randomizeValues, forKey: "privacy_randomizeValues") }
    }
    
    /// Returns true if any privacy setting is currently active
    var isPrivacyActive: Bool {
        hideIncomeData || randomizeValues
    }
    
    /// Seed for randomization - stays consistent during a session so values don't jump around
    private let randomSeed: UInt64
    
    private init() {
        // Load persisted settings
        self.hideIncomeData = UserDefaults.standard.bool(forKey: "privacy_hideIncomeData")
        self.randomizeValues = UserDefaults.standard.bool(forKey: "privacy_randomizeValues")
        
        // Generate a random seed for this session
        randomSeed = UInt64.random(in: 0..<UInt64.max)
    }
    
    /// Cache of multipliers by amount to ensure consistency
    private var multiplierCache: [UInt64: Double] = [:]
    
    /// Returns the randomization multiplier for a given amount (cached for consistency)
    private func multiplier(for amount: Double) -> Double {
        let key = amount.bitPattern
        
        if let cached = multiplierCache[key] {
            return cached
        }
        
        // Use a hash of the amount combined with the seed to get consistent randomization
        let hashInput = key ^ randomSeed
        let hash = hashInput.hashValue
        
        // Convert hash to a multiplier between 0.3 and 2.5 (aggressive randomization)
        let normalized = Double(abs(hash) % 1000) / 1000.0 // 0.0 to 0.999
        let mult = 0.3 + (normalized * 2.2) // 0.3 to 2.5
        
        multiplierCache[key] = mult
        return mult
    }
    
    /// Returns a randomized amount based on the original value.
    /// Uses a seeded approach so the same input always produces the same output during a session.
    /// - Parameter amount: The original monetary amount
    /// - Returns: A randomized amount (multiplied by 0.3-2.5) if randomizeValues is true, otherwise the original
    func randomizedAmount(_ amount: Double) -> Double {
        guard randomizeValues else { return amount }
        
        let mult = multiplier(for: amount)
        
        // Ensure result is never negative (handles edge cases)
        return max(amount * mult, 0)
    }
    
    /// Returns a randomized Decimal amount
    func randomizedAmount(_ amount: Decimal) -> Decimal {
        Decimal(randomizedAmount(amount.doubleValue))
    }
    
    /// Returns a randomized amount for a reimbursement, ensuring it doesn't exceed the expense.
    /// Uses the same multiplier as the expense to maintain proportional relationships.
    /// - Parameters:
    ///   - reimbursementAmount: The reimbursement amount
    ///   - expenseAmount: The original expense amount
    ///   - totalReimbursements: Total of all reimbursements for this expense
    /// - Returns: A randomized amount that maintains the proportion relative to the expense
    func randomizedReimbursement(_ reimbursementAmount: Double, expenseAmount: Double, totalReimbursements: Double) -> Double {
        guard randomizeValues else { return reimbursementAmount }
        
        // Use the expense's multiplier to maintain consistency
        let expenseMultiplier = multiplier(for: expenseAmount)
        
        // Calculate this reimbursement's proportion of total reimbursements
        let proportion = totalReimbursements > 0 ? reimbursementAmount / totalReimbursements : 1.0
        
        // If total reimbursements exceed expense, cap them at the expense amount
        let effectiveTotalReimbursed = min(totalReimbursements, expenseAmount)
        let randomizedTotalReimbursed = effectiveTotalReimbursed * expenseMultiplier
        
        // This reimbursement gets its proportional share
        return max(randomizedTotalReimbursed * proportion, 0)
    }
    
    /// Returns a randomized Decimal reimbursement amount
    func randomizedReimbursement(_ reimbursementAmount: Decimal, expenseAmount: Decimal, totalReimbursements: Decimal) -> Decimal {
        Decimal(randomizedReimbursement(reimbursementAmount.doubleValue, expenseAmount: expenseAmount.doubleValue, totalReimbursements: totalReimbursements.doubleValue))
    }
    
    /// Resets all privacy settings to their defaults
    func reset() {
        hideIncomeData = false
        randomizeValues = false
    }
}

