import SwiftUI

struct SectorsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAddSector = false
    @State private var sectorToEdit: Sector?
    @State private var sectorToDelete: Sector?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
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
            }
            .navigationTitle("Sectors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSector = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Theme.Colors.accent)
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
                ForEach(authViewModel.sectors) { sector in
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
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 100)
        }
    }
    
    private func linkedCategories(for sector: Sector) -> [Category] {
        let categoryIds = authViewModel.sectorCategories[sector.id] ?? []
        return authViewModel.categories.filter { categoryIds.contains($0.id) }
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
                                if let icon = category.icon {
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



