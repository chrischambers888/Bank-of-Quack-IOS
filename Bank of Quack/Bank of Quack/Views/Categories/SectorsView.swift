import SwiftUI

struct SectorsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddSector = false
    @State private var sectorToEdit: Sector?
    @State private var sectorToDelete: Sector?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
    // Multi-select state
    @State private var isSelectionMode = false
    @State private var selectedSectorIds: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    
    private let dataService = DataService()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if authViewModel.sectors.isEmpty {
                    emptyStateView
                } else {
                    sectorList
                }
                
                // Bulk delete button
                if isSelectionMode && !selectedSectorIds.isEmpty {
                    VStack {
                        Spacer()
                        
                        Button {
                            showBulkDeleteConfirm = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "trash")
                                Text("Delete \(selectedSectorIds.count) Sector\(selectedSectorIds.count == 1 ? "" : "s")")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.md)
                            .background(Theme.Colors.error)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                }
            }
            .navigationTitle("Sectors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(Theme.Colors.isLightMode ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isSelectionMode ? "Cancel" : "Done") {
                        if isSelectionMode {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = false
                                selectedSectorIds.removeAll()
                            }
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Theme.Spacing.md) {
                        if !authViewModel.sectors.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedSectorIds.removeAll()
                                    }
                                }
                            } label: {
                                Text(isSelectionMode ? "Done" : "Select")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        
                        if !isSelectionMode {
                            Button {
                                showAddSector = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSector) {
            SectorFormView(mode: .create)
        }
        .sheet(item: $sectorToEdit) { sector in
            SectorFormView(mode: .edit(sector))
        }
        .alert("Delete Sector?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {
                sectorToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let sector = sectorToDelete {
                    deleteSector(sector)
                }
            }
        } message: {
            Text("This will remove the sector and unlink all associated categories.")
        }
        .alert("Delete \(selectedSectorIds.count) Sector\(selectedSectorIds.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                bulkDeleteSectors()
            }
        } message: {
            Text("This will remove the selected sectors and unlink all associated categories.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.textMuted)
            
            Text("No Sectors Yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            Text("Sectors group related categories together\nfor better budget organization.")
                .font(.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                showAddSector = true
            } label: {
                Label("Add Sector", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.lg)
    }
    
    private var sectorList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                // Select all row when in selection mode
                if isSelectionMode {
                    Button {
                        let allIds = Set(authViewModel.sectors.map { $0.id })
                        if allIds == selectedSectorIds {
                            selectedSectorIds.removeAll()
                        } else {
                            selectedSectorIds = allIds
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: Set(authViewModel.sectors.map { $0.id }) == selectedSectorIds ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24))
                                .foregroundStyle(Set(authViewModel.sectors.map { $0.id }) == selectedSectorIds ? Theme.Colors.accent : Theme.Colors.textMuted)
                            
                            Text("Select All")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Spacer()
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.backgroundCard.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                    }
                }
                
                ForEach(authViewModel.sectors) { sector in
                    if isSelectionMode {
                        SectorRowSelectable(
                            sector: sector,
                            linkedCategories: linkedCategories(for: sector),
                            isSelected: selectedSectorIds.contains(sector.id),
                            onTap: {
                                toggleSelection(sector.id)
                            }
                        )
                    } else {
                        SectorRow(
                            sector: sector,
                            linkedCategories: linkedCategories(for: sector),
                            onEdit: {
                                sectorToEdit = sector
                            },
                            onDelete: {
                                sectorToDelete = sector
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, isSelectionMode && !selectedSectorIds.isEmpty ? 150 : 100)
        }
    }
    
    private func linkedCategories(for sector: Sector) -> [Category] {
        let categoryIds = authViewModel.sectorCategories[sector.id] ?? []
        return authViewModel.categories.filter { categoryIds.contains($0.id) }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedSectorIds.contains(id) {
            selectedSectorIds.remove(id)
        } else {
            selectedSectorIds.insert(id)
        }
    }
    
    private func deleteSector(_ sector: Sector) {
        isDeleting = true
        
        Task {
            do {
                try await dataService.deleteSector(id: sector.id)
                await authViewModel.refreshSectors()
            } catch {
                await MainActor.run {
                    authViewModel.error = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isDeleting = false
                sectorToDelete = nil
            }
        }
    }
    
    private func bulkDeleteSectors() {
        guard !selectedSectorIds.isEmpty else { return }
        isDeleting = true
        
        Task {
            do {
                for id in selectedSectorIds {
                    try await dataService.deleteSector(id: id)
                }
                await authViewModel.refreshSectors()
            } catch {
                await MainActor.run {
                    authViewModel.error = error.localizedDescription
                }
            }
            
            await MainActor.run {
                isDeleting = false
                selectedSectorIds.removeAll()
                isSelectionMode = false
            }
        }
    }
}

// MARK: - Selectable Sector Row

struct SectorRowSelectable: View {
    let sector: Sector
    let linkedCategories: [Category]
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textMuted)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        // Color bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(sector.swiftUIColor)
                            .frame(width: 4, height: 40)
                        
                        // Name
                        Text(sector.name)
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Spacer()
                    }
                    
                    // Linked categories
                    if !linkedCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.xs) {
                                ForEach(linkedCategories) { category in
                                    HStack(spacing: 4) {
                                        if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                                            Text(icon)
                                                .font(.caption)
                                        }
                                        Text(category.name)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(category.swiftUIColor.opacity(0.3))
                                    .clipShape(Capsule())
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                }
                            }
                        }
                    } else {
                        Text("No categories linked")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textMuted)
                            .italic()
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SectorRow: View {
    let sector: Sector
    let linkedCategories: [Category]
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                // Color bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(sector.swiftUIColor)
                    .frame(width: 4, height: 40)
                
                // Name
                Text(sector.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                // Actions
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
            }
            
            // Linked categories
            if !linkedCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(linkedCategories) { category in
                            HStack(spacing: 4) {
                                if let icon = category.icon, !icon.isEmpty, icon != "folder" {
                                    Text(icon)
                                        .font(.caption)
                                }
                                Text(category.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(category.swiftUIColor.opacity(0.3))
                            .clipShape(Capsule())
                            .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            } else {
                Text("No categories linked")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
                    .italic()
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
    }
}

#Preview {
    SectorsView()
        .environment(AuthViewModel())
}




