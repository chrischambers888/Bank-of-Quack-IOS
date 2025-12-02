import SwiftUI

struct DashboardFilterSheet: View {
    @Binding var filter: DashboardFilter
    @Environment(\.dismiss) private var dismiss
    
    let members: [HouseholdMember]
    let sectors: [Sector]
    let categories: [Category]
    let sectorCategories: [UUID: [UUID]] // sectorId -> [categoryId]
    
    @State private var expandedSectors: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Date Filter Section
                        dateFilterSection
                        
                        // Transaction Types Section
                        transactionTypesSection
                        
                        // Sector/Category Section
                        categoryFilterSection
                        
                        // Users Section
                        usersFilterSection
                        
                        // Search Section
                        searchSection
                        
                        // Reset Button
                        resetButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter.reset()
                        }
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.backgroundPrimary)
    }
    
    // MARK: - Date Filter Section
    
    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Date Range", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            // Date Preset Pills
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.sm) {
                ForEach(DateFilterPreset.allCases, id: \.self) { preset in
                    DatePresetPill(
                        preset: preset,
                        isSelected: filter.datePreset == preset
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter.datePreset = preset
                        }
                    }
                }
            }
            
            // Custom Date Pickers (shown when custom is selected)
            if filter.datePreset == .custom {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("From")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 50, alignment: .leading)
                        
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { filter.customStartDate ?? Date().startOfMonth },
                                set: { filter.customStartDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                    }
                    
                    HStack {
                        Text("To")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 50, alignment: .leading)
                        
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { filter.customEndDate ?? Date() },
                                set: { filter.customEndDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
    
    // MARK: - Transaction Types Section
    
    private var transactionTypesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Transaction Types", systemImage: "arrow.left.arrow.right")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            VStack(spacing: 0) {
                ForEach(TransactionType.allCases, id: \.self) { type in
                    TransactionTypeRow(
                        type: type,
                        isSelected: filter.isTransactionTypeSelected(type)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filter.toggleTransactionType(type)
                        }
                    }
                    
                    if type != TransactionType.allCases.last {
                        Divider()
                            .background(Theme.Colors.borderLight)
                    }
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
        .cardStyle()
    }
    
    // MARK: - Category Filter Section
    
    private var categoryFilterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Categories", systemImage: "folder")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if !filter.selectedSectorIds.isEmpty || !filter.selectedCategoryIds.isEmpty {
                    Button("Clear") {
                        withAnimation {
                            filter.selectedSectorIds.removeAll()
                            filter.selectedCategoryIds.removeAll()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            if sectors.isEmpty && categories.isEmpty {
                Text("No categories configured")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
            } else {
                VStack(spacing: 0) {
                    // Sectors with nested categories
                    ForEach(sectors) { sector in
                        let sectorCats = categoriesForSector(sector.id)
                        SectorFilterRow(
                            sector: sector,
                            categories: sectorCats,
                            isExpanded: expandedSectors.contains(sector.id),
                            isSectorSelected: filter.selectedSectorIds.contains(sector.id),
                            selectedCategoryIds: filter.selectedCategoryIds,
                            onSectorToggle: {
                                withAnimation {
                                    toggleSectorWithCategories(sector.id, categories: sectorCats)
                                }
                            },
                            onCategoryToggle: { categoryId in
                                // Only allow category toggle if sector is not selected
                                if !filter.selectedSectorIds.contains(sector.id) {
                                    withAnimation {
                                        filter.toggleCategory(categoryId)
                                    }
                                }
                            },
                            onExpandToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSectors.contains(sector.id) {
                                        expandedSectors.remove(sector.id)
                                    } else {
                                        expandedSectors.insert(sector.id)
                                    }
                                }
                            }
                        )
                        
                        if sector.id != sectors.last?.id {
                            Divider()
                                .background(Theme.Colors.borderLight)
                        }
                    }
                    
                    // Uncategorized categories (not in any sector)
                    let uncategorizedCats = uncategorizedCategories
                    if !uncategorizedCats.isEmpty {
                        if !sectors.isEmpty {
                            Divider()
                                .background(Theme.Colors.borderLight)
                        }
                        
                        ForEach(uncategorizedCats) { category in
                            CategoryFilterRow(
                                category: category,
                                isSelected: filter.selectedCategoryIds.contains(category.id)
                            ) {
                                withAnimation {
                                    filter.toggleCategory(category.id)
                                }
                            }
                            
                            if category.id != uncategorizedCats.last?.id {
                                Divider()
                                    .background(Theme.Colors.borderLight)
                                    .padding(.leading, Theme.Spacing.xl)
                            }
                        }
                    }
                }
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            }
        }
        .cardStyle()
    }
    
    // MARK: - Users Filter Section
    
    private var usersFilterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label("Members", systemImage: "person.2")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                if !filter.selectedMemberIds.isEmpty {
                    Button("Clear") {
                        withAnimation {
                            filter.selectedMemberIds.removeAll()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            VStack(spacing: 0) {
                // Shared Only Row (at the top)
                SharedOnlyFilterRow(
                    isSelected: filter.sharedOnly && filter.selectedMemberIds.isEmpty
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if filter.sharedOnly && filter.selectedMemberIds.isEmpty {
                            // Deselect shared only
                            filter.sharedOnly = false
                        } else {
                            // Select shared only and clear any selected members
                            filter.selectedMemberIds.removeAll()
                            filter.sharedOnly = true
                        }
                    }
                }
                
                Divider()
                    .background(Theme.Colors.borderLight)
                
                ForEach(members.filter { $0.isActive }) { member in
                    MemberFilterRow(
                        member: member,
                        isSelected: filter.selectedMemberIds.contains(member.id)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            // Clear sharedOnly when selecting a member
                            if filter.sharedOnly {
                                filter.sharedOnly = false
                            }
                            filter.toggleMember(member.id)
                        }
                    }
                    
                    if member.id != members.filter({ $0.isActive }).last?.id {
                        Divider()
                            .background(Theme.Colors.borderLight)
                    }
                }
            }
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            
            // Include Shared Toggle (only shown when members are selected)
            if !filter.selectedMemberIds.isEmpty {
                Toggle(isOn: $filter.includeShared) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Shared Transactions")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Show transactions split with others")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                .tint(Theme.Colors.accent)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Search", systemImage: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textMuted)
                
                TextField("Search description or notes...", text: $filter.searchText)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .autocorrectionDisabled()
                
                if !filter.searchText.isEmpty {
                    Button {
                        filter.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundInput)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
        }
        .cardStyle()
    }
    
    // MARK: - Reset Button
    
    private var resetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filter.reset()
            }
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset All Filters")
            }
            .font(.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(Theme.Colors.borderDefault, lineWidth: 1)
            )
        }
        .opacity(filter.isFiltered ? 1 : 0.5)
        .disabled(!filter.isFiltered)
    }
    
    // MARK: - Helpers
    
    private func categoriesForSector(_ sectorId: UUID) -> [Category] {
        let categoryIds = sectorCategories[sectorId] ?? []
        return categories.filter { categoryIds.contains($0.id) }
    }
    
    private var uncategorizedCategories: [Category] {
        let allSectorCategoryIds = Set(sectorCategories.values.flatMap { $0 })
        return categories.filter { !allSectorCategoryIds.contains($0.id) }
    }
    
    /// Toggle a sector and automatically select/deselect all its categories
    private func toggleSectorWithCategories(_ sectorId: UUID, categories: [Category]) {
        let categoryIds = Set(categories.map { $0.id })
        
        if filter.selectedSectorIds.contains(sectorId) {
            // Deselecting sector - remove sector and its categories
            filter.selectedSectorIds.remove(sectorId)
            filter.selectedCategoryIds.subtract(categoryIds)
        } else {
            // Selecting sector - add sector and all its categories
            filter.selectedSectorIds.insert(sectorId)
            filter.selectedCategoryIds.formUnion(categoryIds)
        }
    }
}

// MARK: - Date Preset Pill

struct DatePresetPill: View {
    let preset: DateFilterPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: preset.icon)
                    .font(.caption)
                Text(preset.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Theme.Colors.accent : Theme.Colors.backgroundCard)
            .foregroundStyle(isSelected ? Theme.Colors.textInverse : Theme.Colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(isSelected ? Theme.Colors.accent : Theme.Colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transaction Type Row

struct TransactionTypeRow: View {
    let type: TransactionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle()
                        .fill(type.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(type.color)
                }
                
                Text(type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sector Filter Row

struct SectorFilterRow: View {
    let sector: Sector
    let categories: [Category]
    let isExpanded: Bool
    let isSectorSelected: Bool
    let selectedCategoryIds: Set<UUID>
    let onSectorToggle: () -> Void
    let onCategoryToggle: (UUID) -> Void
    let onExpandToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Sector Header
            HStack {
                Button(action: onExpandToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textMuted)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                
                Circle()
                    .fill(sector.swiftUIColor)
                    .frame(width: 12, height: 12)
                
                Text(sector.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("(\(categories.count))")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                
                Spacer()
                
                Button(action: onSectorToggle) {
                    Image(systemName: isSectorSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSectorSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
            .onTapGesture {
                onExpandToggle()
            }
            
            // Expanded Categories
            if isExpanded && !categories.isEmpty {
                VStack(spacing: 0) {
                    // Show info when sector is selected
                    if isSectorSelected {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                            Text("All categories included")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.leading, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    ForEach(categories) { category in
                        let isSelected = selectedCategoryIds.contains(category.id)
                        HStack {
                            if let icon = category.icon {
                                Image(systemName: icon)
                                    .font(.caption)
                                    .foregroundStyle(isSectorSelected ? category.swiftUIColor.opacity(0.6) : category.swiftUIColor)
                                    .frame(width: 20)
                            } else {
                                Circle()
                                    .fill(isSectorSelected ? category.swiftUIColor.opacity(0.6) : category.swiftUIColor)
                                    .frame(width: 8, height: 8)
                                    .frame(width: 20)
                            }
                            
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(isSectorSelected ? Theme.Colors.textMuted : Theme.Colors.textSecondary)
                            
                            Spacer()
                            
                            // When sector is selected, show locked checkmark
                            if isSectorSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
                            } else {
                                Button {
                                    onCategoryToggle(category.id)
                                } label: {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.subheadline)
                                        .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.leading, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.xs)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isSectorSelected {
                                onCategoryToggle(category.id)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Category Filter Row

struct CategoryFilterRow: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                if let icon = category.icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(category.swiftUIColor)
                        .frame(width: 24)
                } else {
                    Circle()
                        .fill(category.swiftUIColor)
                        .frame(width: 10, height: 10)
                        .frame(width: 24)
                }
                
                Text(category.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Only Filter Row

struct SharedOnlyFilterRow: View {
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Only")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("Expenses split between multiple people")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textMuted)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Member Filter Row

struct MemberFilterRow: View {
    let member: HouseholdMember
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle()
                        .fill(member.swiftUIColor)
                        .frame(width: 32, height: 32)
                    
                    if let emoji = member.avatarUrl, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 16))
                    } else {
                        Text(member.initials)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.textInverse)
                    }
                }
                
                Text(member.displayName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    DashboardFilterSheet(
        filter: .constant(.default),
        members: [],
        sectors: [],
        categories: [],
        sectorCategories: [:]
    )
}

