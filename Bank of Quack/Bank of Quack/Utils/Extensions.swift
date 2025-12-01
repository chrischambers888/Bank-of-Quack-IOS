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
    
    func formatted(as style: MoneyFormatStyle = .standard) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        switch style {
        case .standard:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        case .compact:
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }
    
    enum MoneyFormatStyle {
        case standard, compact
    }
}

extension Double {
    func formattedAsMoney(showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        
        if showSign && self > 0 {
            return "+" + (formatter.string(from: NSNumber(value: self)) ?? "$0.00")
        }
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
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

