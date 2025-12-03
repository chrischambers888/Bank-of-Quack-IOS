import SwiftUI
import UIKit

// MARK: - Data Models

struct MemberExpenseBreakdown: Identifiable {
    let id: UUID // member ID
    let name: String
    let color: Color
    let emoji: String? // Member's logo emoji
    let amount: Decimal
    let percentage: Double // Percentage of parent (sector or total)
    var isInactive: Bool = false // Whether the member is inactive
}

struct SectorExpense: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    let amount: Decimal
    let percentage: Double
    let categories: [CategoryExpense]
    var memberBreakdown: [MemberExpenseBreakdown] = []
}

struct CategoryExpense: Identifiable {
    let id: UUID
    let name: String
    let icon: String?
    let color: Color
    let amount: Decimal
    let percentage: Double // Percentage of sector total
    var memberBreakdown: [MemberExpenseBreakdown] = [] // Member breakdown for this category
}

// MARK: - Donut Chart View

struct ExpenseDonutChart: View {
    let sectors: [SectorExpense]
    let totalExpenses: Decimal
    var filteredTransactions: [TransactionView] = []
    var sectorCategories: [UUID: [UUID]] = [:] // sectorId -> [categoryId]
    
    @State private var selectedSectorId: UUID?
    @State private var selectedCategoryId: UUID?
    @State private var showingCategoryPopup = false
    @State private var showingSectorPopup = false
    @State private var hasAnimated = false
    @State private var sliceAnimations: [UUID: Double] = [:]
    @State private var categorySliceAnimations: [UUID: Double] = [:]
    
    private let donutWidth: CGFloat = 32
    private let categoryDonutWidth: CGFloat = 24 // Thinner inner ring for categories
    private let chartSize: CGFloat = 200
    private let sliceGap: Double = 1.5 // Gap between slices in degrees
    
    private var selectedSector: SectorExpense? {
        sectors.first { $0.id == selectedSectorId }
    }
    
    private var selectedCategory: CategoryExpense? {
        guard let sector = selectedSector else { return nil }
        return sector.categories.first { $0.id == selectedCategoryId }
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Donut Chart
            ZStack {
                // Background ring
                Circle()
                    .stroke(Theme.Colors.backgroundCard, lineWidth: donutWidth)
                    .frame(width: chartSize, height: chartSize)
                
                // Inner background ring for categories (when sector selected)
                if selectedSector != nil {
                    Circle()
                        .stroke(Theme.Colors.backgroundCard.opacity(0.5), lineWidth: categoryDonutWidth)
                        .frame(width: chartSize - donutWidth - 8, height: chartSize - donutWidth - 8)
                }
                
                // Standard sector slices
                ForEach(Array(sectors.enumerated()), id: \.element.id) { index, sector in
                    DonutSliceView(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        animationProgress: sliceAnimations[sector.id] ?? (hasAnimated ? 1.0 : 0),
                        isSelected: sector.id == selectedSectorId,
                        color: sector.color,
                        lineWidth: donutWidth,
                        useGap: true
                    )
                    .frame(width: chartSize, height: chartSize)
                    .opacity(selectedSectorId == nil || sector.id == selectedSectorId ? 1.0 : 0.3)
                    .contentShape(DonutSliceShape(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        lineWidth: donutWidth
                    ))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            if selectedSectorId == sector.id {
                                selectedSectorId = nil
                                selectedCategoryId = nil
                            } else {
                                selectedSectorId = sector.id
                                selectedCategoryId = nil
                            }
                        }
                    }
                }
                
                // Category slices (inner ring) when sector is selected
                if let selected = selectedSector, !selected.categories.isEmpty {
                    ForEach(Array(selected.categories.enumerated()), id: \.element.id) { index, category in
                        DonutSliceView(
                            startAngle: categoryStartAngle(for: index, in: selected),
                            endAngle: categoryEndAngle(for: index, in: selected),
                            animationProgress: categorySliceAnimations[category.id] ?? 0,
                            isSelected: false,
                            color: category.color,
                            lineWidth: categoryDonutWidth,
                            useGap: true
                        )
                        .frame(width: chartSize - donutWidth - 8, height: chartSize - donutWidth - 8)
                        .allowsHitTesting(false)
                    }
                }
                
                // Selection ring
                if let selected = selectedSector, let index = sectors.firstIndex(where: { $0.id == selected.id }) {
                    DonutSliceView(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        animationProgress: 1.0,
                        isSelected: true,
                        color: Theme.Colors.accent,
                        lineWidth: 4,
                        useGap: false
                    )
                    .frame(width: chartSize + donutWidth + 8, height: chartSize + donutWidth + 8)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Center content
                VStack(spacing: 2) {
                    if let selected = selectedSector {
                        Text(selected.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                        
                        Text(selected.amount.doubleValue.formattedAsMoney())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("\(Int(selected.percentage))%")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    } else {
                        Text("Total")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        Text(totalExpenses.doubleValue.formattedAsMoney())
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Expenses")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                .frame(width: chartSize - donutWidth * 2 - 16)
                .animation(.easeInOut(duration: 0.2), value: selectedSectorId)
            }
            .padding(.vertical, Theme.Spacing.sm)
            
            // Accordion list showing all sectors (expandable)
            SectorAccordionList(
                sectors: sectors,
                selectedId: $selectedSectorId,
                onCategoryTapped: { category in
                    selectedCategoryId = category.id
                    showingCategoryPopup = true
                },
                onSectorDetailsTapped: { sector in
                    selectedSectorId = sector.id
                    showingSectorPopup = true
                }
            )
        }
        .cardStyle()
        .task {
            // Small delay to ensure view is laid out before animating
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await animateSlicesIn()
        }
        .onChange(of: sectors.map { $0.id }) { _, _ in
            // Re-animate when sectors change
            Task {
                await animateSlicesIn()
            }
        }
        .onChange(of: selectedSectorId) { _, newId in
            // Animate category slices when sector is selected (from accordion or donut)
            if let sectorId = newId, let sector = sectors.first(where: { $0.id == sectorId }) {
                Task {
                    await animateCategorySlicesIn(for: sector)
                }
            }
        }
        .sheet(isPresented: $showingCategoryPopup) {
            if let category = selectedCategory, let sector = selectedSector {
                let categoryTransactions = filteredTransactions.filter { $0.categoryId == category.id && $0.transactionType == .expense }
                CategoryMemberPopup(
                    category: category,
                    sectorColor: sector.color,
                    transactions: categoryTransactions,
                    onDismiss: {
                        showingCategoryPopup = false
                        selectedCategoryId = nil
                    }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingSectorPopup) {
            if let sector = selectedSector {
                let sectorCategoryIds = sectorCategories[sector.id] ?? sector.categories.map { $0.id }
                let sectorTransactions = filteredTransactions.filter { transaction in
                    guard transaction.transactionType == .expense else { return false }
                    guard let categoryId = transaction.categoryId else {
                        // Include uncategorized if this is the "Other" sector
                        return sector.name == "Other"
                    }
                    return sectorCategoryIds.contains(categoryId)
                }
                SectorDetailPopup(
                    sector: sector,
                    transactions: sectorTransactions,
                    onDismiss: {
                        showingSectorPopup = false
                    }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - Angle Calculations
    
    private func startAngle(for index: Int) -> Angle {
        let precedingPercentage = sectors.prefix(index).reduce(0.0) { $0 + $1.percentage }
        // Add half gap at start
        let gapOffset = index > 0 ? sliceGap / 2 : 0
        return Angle(degrees: precedingPercentage * 3.6 - 90 + gapOffset)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let totalPercentage = sectors.prefix(index + 1).reduce(0.0) { $0 + $1.percentage }
        // Subtract half gap at end
        let gapOffset = index < sectors.count - 1 ? sliceGap / 2 : 0
        return Angle(degrees: totalPercentage * 3.6 - 90 - gapOffset)
    }
    
    // MARK: - Category Angle Calculations
    
    private func categoryStartAngle(for index: Int, in sector: SectorExpense) -> Angle {
        let precedingPercentage = sector.categories.prefix(index).reduce(0.0) { $0 + $1.percentage }
        // Add half gap at start
        let gapOffset = index > 0 ? sliceGap / 2 : 0
        return Angle(degrees: precedingPercentage * 3.6 - 90 + gapOffset)
    }
    
    private func categoryEndAngle(for index: Int, in sector: SectorExpense) -> Angle {
        let totalPercentage = sector.categories.prefix(index + 1).reduce(0.0) { $0 + $1.percentage }
        // Subtract half gap at end
        let gapOffset = index < sector.categories.count - 1 ? sliceGap / 2 : 0
        return Angle(degrees: totalPercentage * 3.6 - 90 - gapOffset)
    }
    
    // MARK: - Animation
    
    @MainActor
    private func animateSlicesIn() async {
        // Initialize all slices to 0
        for sector in sectors {
            sliceAnimations[sector.id] = 0
        }
        
        // Staggered animation for each slice
        for (index, sector) in sectors.enumerated() {
            let delay = Double(index) * 0.08
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(delay)) {
                sliceAnimations[sector.id] = 1.0
            }
        }
        
        hasAnimated = true
    }
    
    @MainActor
    private func animateCategorySlicesIn(for sector: SectorExpense) async {
        // Initialize all category slices to 0
        for category in sector.categories {
            categorySliceAnimations[category.id] = 0
        }
        
        // Small delay before starting category animations
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Staggered animation for each category slice
        for (index, category) in sector.categories.enumerated() {
            let delay = Double(index) * 0.06
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(delay)) {
                categorySliceAnimations[category.id] = 1.0
            }
        }
    }
}

// MARK: - Donut Slice Shape (for hit testing)

struct DonutSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let lineWidth: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius - lineWidth
        
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Donut Slice View

struct DonutSliceView: View {
    let startAngle: Angle
    let endAngle: Angle
    let animationProgress: Double
    let isSelected: Bool
    let color: Color
    let lineWidth: CGFloat
    var useGap: Bool = true
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2
            
            // Calculate animated end angle
            let animatedEndAngle = Angle(degrees: startAngle.degrees + (endAngle.degrees - startAngle.degrees) * animationProgress)
            
            Path { path in
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: animatedEndAngle,
                    clockwise: false
                )
            }
            .stroke(
                LinearGradient(
                    colors: [color, color.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: useGap ? .butt : .round
                )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
    }
}

// MARK: - Sector Accordion List

struct SectorAccordionList: View {
    let sectors: [SectorExpense]
    @Binding var selectedId: UUID?
    var onCategoryTapped: ((CategoryExpense) -> Void)?
    var onSectorDetailsTapped: ((SectorExpense) -> Void)?
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(sectors) { sector in
                SectorAccordionRow(
                    sector: sector,
                    isExpanded: sector.id == selectedId,
                    onToggle: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            if selectedId == sector.id {
                                selectedId = nil
                            } else {
                                selectedId = sector.id
                            }
                        }
                    },
                    onCategoryTapped: onCategoryTapped,
                    onDetailsTapped: { onSectorDetailsTapped?(sector) }
                )
            }
        }
    }
}

// MARK: - Sector Accordion Row

struct SectorAccordionRow: View {
    let sector: SectorExpense
    let isExpanded: Bool
    let onToggle: () -> Void
    var onCategoryTapped: ((CategoryExpense) -> Void)?
    var onDetailsTapped: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (always visible) - split into left (details) and right (expand/collapse) zones
            HStack(spacing: 0) {
                // LEFT SIDE - Opens sector popup
                Button(action: { onDetailsTapped?() }) {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Sector color indicator
                        Circle()
                            .fill(sector.color)
                            .frame(width: 12, height: 12)
                        
                        // Sector name
                        Text(sector.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Amount and percentage
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(sector.amount.doubleValue.formattedAsMoney())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("\(Int(sector.percentage))%")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // RIGHT SIDE - Expands/collapses accordion
                Button(action: onToggle) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Divider()
                            .frame(height: 24)
                            .background(Theme.Colors.borderLight)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(.leading, Theme.Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.leading, Theme.Spacing.md)
            .padding(.trailing, Theme.Spacing.md)
            .background(isExpanded ? Theme.Colors.backgroundCardSolid.opacity(0.5) : Theme.Colors.backgroundCard)
            .cornerRadius(isExpanded ? Theme.CornerRadius.md : Theme.CornerRadius.sm)
            
            // Expanded content - Categories only
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Categories as circles
                    if !sector.categories.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Categories")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textMuted)
                            
                            CategoryCircleGrid(
                                categories: sector.categories,
                                onCategoryTapped: onCategoryTapped
                            )
                        }
                    } else {
                        Text("No categories in this sector")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundCardSolid.opacity(0.3))
                .cornerRadius(Theme.CornerRadius.md)
                .padding(.top, Theme.Spacing.xs)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
    }
}

// MARK: - Category Circle Grid

struct CategoryCircleGrid: View {
    let categories: [CategoryExpense]
    var onCategoryTapped: ((CategoryExpense) -> Void)?
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: Theme.Spacing.sm)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(categories) { category in
                CategoryCircleButton(
                    category: category,
                    onTap: { onCategoryTapped?(category) }
                )
            }
        }
    }
}

// MARK: - Category Circle Button

struct CategoryCircleButton: View {
    let category: CategoryExpense
    var onTap: (() -> Void)?
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                // Circle with category color outline
                ZStack {
                    // Category color outline ring
                    Circle()
                        .stroke(category.color, lineWidth: 2.5)
                        .frame(width: 52, height: 52)
                    
                    // Inner colored circle
                    Circle()
                        .fill(category.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    // Icon or emoji
                    if let icon = category.icon, !icon.isEmpty {
                        if isSFSymbol(icon) {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .foregroundStyle(category.color)
                        } else {
                            Text(icon)
                                .font(.system(size: 20))
                        }
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(category.color)
                    }
                }
                
                // Category name
                Text(category.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Amount + percentage
                VStack(spacing: 1) {
                    Text(category.amount.doubleValue.formattedAsMoney())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("\(Int(category.percentage))%")
                        .font(.caption2)
                        .foregroundStyle(category.color)
                }
            }
            .frame(minWidth: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(CategoryCircleButtonStyle())
    }
}

// MARK: - Category Circle Button Style

struct CategoryCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Member Expense Row

struct MemberExpenseRow: View {
    let member: MemberExpenseBreakdown
    let sectorTotal: Decimal
    let sectorColor: Color
    
    private var percentageOfSector: Double {
        guard sectorTotal > 0 else { return 0 }
        return (member.amount.doubleValue / sectorTotal.doubleValue) * 100
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                // Member emoji or color
                if let emoji = member.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(width: 28, height: 28)
                        .opacity(member.isInactive ? 0.6 : 1.0)
                } else {
                    ZStack {
                        Circle()
                            .fill(member.color.opacity(member.isInactive ? 0.5 : 1.0))
                            .frame(width: 28, height: 28)
                        
                        Text(String(member.name.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .opacity(member.isInactive ? 0.7 : 1.0)
                    }
                }
                
                HStack(spacing: Theme.Spacing.xs) {
                    Text(member.name)
                        .font(.subheadline)
                        .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                    
                    if member.isInactive {
                        Text("Inactive")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.textMuted.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                Text(member.amount.doubleValue.formattedAsMoney())
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                
                Text("\(Int(percentageOfSector))%")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(width: 36, alignment: .trailing)
            }
            
            // Progress bar using sector color
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.backgroundCard)
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(sectorColor.opacity(member.isInactive ? 0.5 : 1.0))
                        .frame(width: geometry.size.width * CGFloat(percentageOfSector / 100), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - Category Expense Row

struct CategoryExpenseRow: View {
    let category: CategoryExpense
    let sectorTotal: Decimal
    var onTap: (() -> Void)? = nil
    
    private var percentageOfSector: Double {
        guard sectorTotal > 0 else { return 0 }
        return (category.amount.doubleValue / sectorTotal.doubleValue) * 100
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    // Category icon
                    ZStack {
                        Circle()
                            .fill(category.color.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        if let icon = category.icon, !icon.isEmpty {
                            if isSFSymbol(icon) {
                                // It's an SF Symbol
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(category.color)
                            } else {
                                // It's an emoji or other text
                                Text(icon)
                                    .font(.system(size: 16))
                            }
                        } else {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(category.color)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(category.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            if onTap != nil && !category.memberBreakdown.isEmpty {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                        
                        Text("\(Int(percentageOfSector))% of sector")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Spacer()
                    
                    Text(category.amount.doubleValue.formattedAsMoney())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.backgroundCard)
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(category.color)
                            .frame(width: geometry.size.width * CGFloat(percentageOfSector / 100), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - Sector Detail Popup

struct SectorDetailPopup: View {
    let sector: SectorExpense
    let transactions: [TransactionView]
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Sector header
                        VStack(spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(sector.color)
                                .frame(width: 60, height: 60)
                            
                            Text(sector.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text(sector.amount.doubleValue.formattedAsMoney())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(sector.color)
                            
                            Text("\(Int(sector.percentage))% of total expenses")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.top, Theme.Spacing.md)
                        
                        // Member breakdown
                        if !sector.memberBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Expense By Member")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(sector.memberBreakdown) { member in
                                        CategoryMemberRow(
                                            member: member,
                                            categoryTotal: sector.amount,
                                            categoryColor: sector.color
                                        )
                                        
                                        if member.id != sector.memberBreakdown.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.horizontal, Theme.Spacing.md)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Transactions
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("Transactions")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\(transactions.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if transactions.isEmpty {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "tray")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No transactions in this sector")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(transactions) { transaction in
                                        CompactTransactionRow(transaction: transaction)
                                        
                                        if transaction.id != transactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Sector Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Category Member Popup

struct CategoryMemberPopup: View {
    let category: CategoryExpense
    let sectorColor: Color
    var transactions: [TransactionView] = []
    let onDismiss: () -> Void
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Category header
                        VStack(spacing: Theme.Spacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(category.color.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                
                                if let icon = category.icon, !icon.isEmpty {
                                    if isSFSymbol(icon) {
                                        Image(systemName: icon)
                                            .font(.system(size: 28))
                                            .foregroundStyle(category.color)
                                    } else {
                                        Text(icon)
                                            .font(.system(size: 32))
                                    }
                                } else {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(category.color)
                                }
                            }
                            
                            Text(category.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text(category.amount.doubleValue.formattedAsMoney())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(category.color)
                        }
                        .padding(.top, Theme.Spacing.md)
                        
                        // Member breakdown
                        if !category.memberBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Expense By Member")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                
                                VStack(spacing: 0) {
                                    ForEach(category.memberBreakdown) { member in
                                        CategoryMemberRow(
                                            member: member,
                                            categoryTotal: category.amount,
                                            categoryColor: category.color
                                        )
                                        
                                        if member.id != category.memberBreakdown.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.horizontal, Theme.Spacing.md)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        // Transactions
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack {
                                Text("Transactions")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\(transactions.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.Colors.backgroundCard)
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            
                            if transactions.isEmpty {
                                VStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "tray")
                                        .font(.title)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text("No transactions in this category")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(transactions) { transaction in
                                        CompactTransactionRow(transaction: transaction)
                                        
                                        if transaction.id != transactions.last?.id {
                                            Divider()
                                                .background(Theme.Colors.borderLight)
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .background(Theme.Colors.backgroundCard)
                                .cornerRadius(Theme.CornerRadius.md)
                                .padding(.horizontal, Theme.Spacing.md)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Category Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Category Member Row

struct CategoryMemberRow: View {
    let member: MemberExpenseBreakdown
    let categoryTotal: Decimal
    let categoryColor: Color
    
    private var percentageOfCategory: Double {
        guard categoryTotal > 0 else { return 0 }
        return (member.amount.doubleValue / categoryTotal.doubleValue) * 100
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                // Member emoji or color
                if let emoji = member.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 36, height: 36)
                        .opacity(member.isInactive ? 0.6 : 1.0)
                } else {
                    ZStack {
                        Circle()
                            .fill(member.color.opacity(member.isInactive ? 0.5 : 1.0))
                            .frame(width: 36, height: 36)
                        
                        Text(String(member.name.prefix(1)).uppercased())
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .opacity(member.isInactive ? 0.7 : 1.0)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(member.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
                        
                        if member.isInactive {
                            Text("Inactive")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.Colors.textMuted.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text("\(Int(percentageOfCategory))% of category")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                Spacer()
                
                Text(member.amount.doubleValue.formattedAsMoney())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(member.isInactive ? Theme.Colors.textMuted : Theme.Colors.textPrimary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.backgroundPrimary)
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(categoryColor.opacity(member.isInactive ? 0.5 : 1.0))
                        .frame(width: geometry.size.width * CGFloat(percentageOfCategory / 100), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(Theme.Spacing.md)
    }
}

// MARK: - Compact Transaction Row

struct CompactTransactionRow: View {
    let transaction: TransactionView
    
    private var categoryColor: Color {
        if let colorHex = transaction.categoryColor {
            return Color(hex: colorHex.replacingOccurrences(of: "#", with: ""))
        }
        return transaction.transactionType.color
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                if let icon = transaction.categoryIcon, !icon.isEmpty {
                    if isSFSymbol(icon) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(categoryColor)
                    } else {
                        Text(icon)
                            .font(.system(size: 16))
                    }
                } else {
                    Image(systemName: transaction.transactionType.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(categoryColor)
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: Theme.Spacing.xs) {
                    if let paidByName = transaction.paidByName {
                        Text(paidByName)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Spacer()
            
            // Amount
            Text("-\(transaction.amount.doubleValue.formattedAsMoney())")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.expense)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Empty State

struct ExpenseDonutEmptyState: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.backgroundCard, lineWidth: 24)
                    .frame(width: 140, height: 140)
                
                VStack(spacing: 4) {
                    Image(systemName: "chart.pie")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    Text("No expenses")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Text("Start tracking your expenses to see a beautiful breakdown by sector")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .cardStyle()
    }
}

// MARK: - Preview

#Preview {
    let member1Id = UUID()
    let member2Id = UUID()
    
    ZStack {
        Theme.Colors.backgroundPrimary
            .ignoresSafeArea()
        
        ScrollView {
            ExpenseDonutChart(
                sectors: [
                    SectorExpense(
                        id: UUID(),
                        name: "Housing",
                        color: .blue,
                        amount: 1500,
                        percentage: 45,
                        categories: [
                            CategoryExpense(
                                id: UUID(),
                                name: "Rent",
                                icon: "house.fill",
                                color: .blue,
                                amount: 1200,
                                percentage: 80,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 720, percentage: 60),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 480, percentage: 40)
                                ]
                            ),
                            CategoryExpense(
                                id: UUID(),
                                name: "Utilities",
                                icon: "bolt.fill",
                                color: .cyan,
                                amount: 300,
                                percentage: 20,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 180, percentage: 60),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 120, percentage: 40)
                                ]
                            )
                        ],
                        memberBreakdown: [
                            MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 900, percentage: 60),
                            MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 600, percentage: 40)
                        ]
                    ),
                    SectorExpense(
                        id: UUID(),
                        name: "Food",
                        color: .green,
                        amount: 800,
                        percentage: 24,
                        categories: [
                            CategoryExpense(
                                id: UUID(),
                                name: "Groceries",
                                icon: "🛒",
                                color: .green,
                                amount: 500,
                                percentage: 62.5,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 300, percentage: 60),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 200, percentage: 40)
                                ]
                            ),
                            CategoryExpense(
                                id: UUID(),
                                name: "Dining Out",
                                icon: "🍔",
                                color: .orange,
                                amount: 300,
                                percentage: 37.5,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 150, percentage: 50),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 150, percentage: 50)
                                ]
                            )
                        ],
                        memberBreakdown: [
                            MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 450, percentage: 56),
                            MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 350, percentage: 44)
                        ]
                    ),
                    SectorExpense(
                        id: UUID(),
                        name: "Transport",
                        color: .orange,
                        amount: 500,
                        percentage: 15,
                        categories: [
                            CategoryExpense(
                                id: UUID(),
                                name: "Gas",
                                icon: "fuelpump.fill",
                                color: .orange,
                                amount: 300,
                                percentage: 60,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 120, percentage: 40),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 180, percentage: 60)
                                ]
                            ),
                            CategoryExpense(
                                id: UUID(),
                                name: "Parking",
                                icon: "parkingsign",
                                color: .red,
                                amount: 200,
                                percentage: 40,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 80, percentage: 40),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 120, percentage: 60)
                                ]
                            )
                        ],
                        memberBreakdown: [
                            MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 200, percentage: 40),
                            MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 300, percentage: 60)
                        ]
                    ),
                    SectorExpense(
                        id: UUID(),
                        name: "Entertainment",
                        color: .purple,
                        amount: 533,
                        percentage: 16,
                        categories: [
                            CategoryExpense(
                                id: UUID(),
                                name: "Streaming",
                                icon: "play.tv",
                                color: .purple,
                                amount: 33,
                                percentage: 6,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 16.50, percentage: 50),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 16.50, percentage: 50)
                                ]
                            ),
                            CategoryExpense(
                                id: UUID(),
                                name: "Games",
                                icon: "gamecontroller.fill",
                                color: .pink,
                                amount: 500,
                                percentage: 94,
                                memberBreakdown: [
                                    MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 283.50, percentage: 56.7),
                                    MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 216.50, percentage: 43.3)
                                ]
                            )
                        ],
                        memberBreakdown: [
                            MemberExpenseBreakdown(id: member1Id, name: "Alex", color: .pink, emoji: "🦊", amount: 300, percentage: 56),
                            MemberExpenseBreakdown(id: member2Id, name: "Jordan", color: .mint, emoji: "🐸", amount: 233, percentage: 44)
                        ]
                    )
                ],
                totalExpenses: 3333
            )
            .padding()
        }
    }
}
