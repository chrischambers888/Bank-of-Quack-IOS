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
}

// MARK: - Donut Chart View

struct ExpenseDonutChart: View {
    let sectors: [SectorExpense]
    let totalExpenses: Decimal
    
    @State private var selectedSectorId: UUID?
    @State private var hasAnimated = false
    @State private var sliceAnimations: [UUID: Double] = [:]
    
    private let donutWidth: CGFloat = 32
    private let chartSize: CGFloat = 200
    private let sliceGap: Double = 1.5 // Gap between slices in degrees
    
    private var selectedSector: SectorExpense? {
        sectors.first { $0.id == selectedSectorId }
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Donut Chart
            ZStack {
                // Background ring
                Circle()
                    .stroke(Theme.Colors.backgroundCard, lineWidth: donutWidth)
                    .frame(width: chartSize, height: chartSize)
                
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
                    .contentShape(DonutSliceShape(
                        startAngle: startAngle(for: index),
                        endAngle: endAngle(for: index),
                        lineWidth: donutWidth
                    ))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            if selectedSectorId == sector.id {
                                selectedSectorId = nil
                            } else {
                                selectedSectorId = sector.id
                            }
                        }
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
            
            // Legend (always show sector legend when no sector selected)
            if selectedSector == nil {
                SectorLegend(sectors: sectors, selectedId: $selectedSectorId)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Expanded sector detail
            if let selected = selectedSector {
                SectorDetailView(
                    sector: selected,
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedSectorId = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
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

// MARK: - Sector Legend

struct SectorLegend: View {
    let sectors: [SectorExpense]
    @Binding var selectedId: UUID?
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: Theme.Spacing.sm) {
            ForEach(sectors) { sector in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedId = sector.id
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(sector.color)
                            .frame(width: 10, height: 10)
                        
                        Text(sector.name)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text("\(Int(sector.percentage))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .background(Theme.Colors.backgroundCard)
                    .cornerRadius(Theme.CornerRadius.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Sector Detail View

struct SectorDetailView: View {
    let sector: SectorExpense
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack {
                Circle()
                    .fill(sector.color)
                    .frame(width: 14, height: 14)
                
                Text(sector.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Text(sector.amount.doubleValue.formattedAsMoney())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
            }
            
            Divider()
                .background(Theme.Colors.borderLight)
            
            // Member breakdown (always shown when data exists)
            if !sector.memberBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("By Member")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textMuted)
                    
                    ForEach(sector.memberBreakdown) { member in
                        MemberExpenseRow(member: member, sectorTotal: sector.amount, sectorColor: sector.color)
                    }
                }
                
                if !sector.categories.isEmpty {
                    Divider()
                        .background(Theme.Colors.borderLight)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
            
            // Categories
            if sector.categories.isEmpty && sector.memberBreakdown.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "folder")
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.textMuted)
                        Text("No categories")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.md)
            } else if !sector.categories.isEmpty {
                if !sector.memberBreakdown.isEmpty {
                    Text("By Category")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                ForEach(sector.categories) { category in
                    CategoryExpenseRow(category: category, sectorTotal: sector.amount)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCardSolid.opacity(0.5))
        .cornerRadius(Theme.CornerRadius.md)
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
    
    private var percentageOfSector: Double {
        guard sectorTotal > 0 else { return 0 }
        return (category.amount.doubleValue / sectorTotal.doubleValue) * 100
    }
    
    /// Check if a string is a valid SF Symbol name
    private func isSFSymbol(_ name: String) -> Bool {
        UIImage(systemName: name) != nil
    }
    
    var body: some View {
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
                    Text(category.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
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
                            CategoryExpense(id: UUID(), name: "Rent", icon: "house.fill", color: .blue, amount: 1200, percentage: 80),
                            CategoryExpense(id: UUID(), name: "Utilities", icon: "bolt.fill", color: .cyan, amount: 300, percentage: 20)
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
                            CategoryExpense(id: UUID(), name: "Groceries", icon: "🛒", color: .green, amount: 500, percentage: 62.5),
                            CategoryExpense(id: UUID(), name: "Dining Out", icon: "🍔", color: .orange, amount: 300, percentage: 37.5)
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
                            CategoryExpense(id: UUID(), name: "Gas", icon: "fuelpump.fill", color: .orange, amount: 300, percentage: 60),
                            CategoryExpense(id: UUID(), name: "Parking", icon: "parkingsign", color: .red, amount: 200, percentage: 40)
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
                            CategoryExpense(id: UUID(), name: "Streaming", icon: "play.tv", color: .purple, amount: 33, percentage: 6),
                            CategoryExpense(id: UUID(), name: "Games", icon: "gamecontroller.fill", color: .pink, amount: 500, percentage: 94)
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
