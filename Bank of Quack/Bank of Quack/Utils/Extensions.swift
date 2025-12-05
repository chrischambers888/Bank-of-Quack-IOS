import Foundation

// MARK: - Date Extensions

extension Date {
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }
    
    var endOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.end ?? self
    }
    
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    func formatted(as style: DateFormatStyle) -> String {
        let formatter = DateFormatter()
        switch style {
        case .short:
            formatter.dateStyle = .short
        case .medium:
            formatter.dateStyle = .medium
        case .long:
            formatter.dateStyle = .long
        case .monthYear:
            formatter.dateFormat = "MMMM yyyy"
        case .dayMonth:
            formatter.dateFormat = "d MMM"
        case .weekdayDayMonth:
            formatter.dateFormat = "EEE, d MMM"
        }
        return formatter.string(from: self)
    }
    
    enum DateFormatStyle {
        case short, medium, long, monthYear, dayMonth, weekdayDayMonth
    }
}

// MARK: - Decimal Extensions

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
    
    /// Rounds to specified decimal places using banker's rounding
    func rounded(_ decimalPlaces: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, decimalPlaces, .bankers)
        return result
    }
    
    /// Calculates equal shares with remainder allocation to prevent rounding drift
    /// - Parameters:
    ///   - total: The total amount to split
    ///   - memberCount: Number of members to split among
    ///   - memberIndex: Index of the current member (0-based)
    /// - Returns: The share for this member, with any remainder allocated to the first member
    static func calculateEqualShare(total: Decimal, memberCount: Int, memberIndex: Int) -> Decimal {
        guard memberCount > 0 else { return 0 }
        
        // Round each share to 2 decimal places
        let equalShare = (total / Decimal(memberCount)).rounded(2)
        
        // Calculate what the sum would be
        let totalAllocated = equalShare * Decimal(memberCount)
        
        // Calculate remainder (could be positive or negative due to rounding)
        let remainder = total - totalAllocated
        
        // Assign remainder to first member to ensure exact sum
        if memberIndex == 0 {
            return equalShare + remainder
        }
        return equalShare
    }
    
    func formatted(as style: MoneyFormatStyle = .standard, applyPrivacy: Bool = true) -> String {
        let displayValue: Decimal
        if applyPrivacy && PrivacyManager.shared.randomizeValues {
            displayValue = PrivacyManager.shared.randomizedAmount(self)
        } else {
            displayValue = self
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.currencySymbol = "$"
        
        switch style {
        case .standard:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        case .compact:
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        
        guard let formatted = formatter.string(from: displayValue as NSDecimalNumber) else {
            return "$0.00"
        }
        return "$\(formatted)"
    }
    
    enum MoneyFormatStyle {
        case standard, compact
    }
}

extension Double {
    func formattedAsMoney(showSign: Bool = false, applyPrivacy: Bool = true) -> String {
        let displayValue: Double
        if applyPrivacy && PrivacyManager.shared.randomizeValues {
            displayValue = PrivacyManager.shared.randomizedAmount(self)
        } else {
            displayValue = self
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        guard let formatted = formatter.string(from: NSNumber(value: abs(displayValue))) else {
            return "$0.00"
        }
        
        if displayValue < 0 {
            return "-$\(formatted)"
        } else if showSign && displayValue > 0 {
            return "+$\(formatted)"
        }
        return "$\(formatted)"
    }
}

// MARK: - String Extensions

extension String {
    var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return self.range(of: emailRegex, options: .regularExpression) != nil
    }
    
    func initials(count: Int = 2) -> String {
        let words = self.split(separator: " ")
        let initials = words.prefix(count).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
}

// MARK: - Array Extensions

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }
    
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

// MARK: - URL Extensions

extension URL: @retroactive Identifiable {
    public var id: String {
        self.absoluteString
    }
}

