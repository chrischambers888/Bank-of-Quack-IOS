import SwiftUI

struct CreateHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var householdName = ""
    @State private var displayName = ""
    
    private var isFormValid: Bool {
        !householdName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Header
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "house.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("Create Household")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Start tracking expenses with your family or roommates")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.xl)
                        
                        // Form
                        VStack(spacing: Theme.Spacing.md) {
                            // Household Name
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Household Name")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("e.g., The Smiths", text: $householdName)
                                    .inputFieldStyle()
                            }
                            
                            // Display Name
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Your Display Name")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("e.g., John", text: $displayName)
                                    .inputFieldStyle()
                                
                                Text("This is how other members will see you")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Error
                        if let error = authViewModel.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.error)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Create Button
                        Button {
                            Task {
                                await authViewModel.createHousehold(
                                    name: householdName.trimmingCharacters(in: .whitespaces),
                                    displayName: displayName.trimmingCharacters(in: .whitespaces)
                                )
                                if authViewModel.error == nil && authViewModel.currentHousehold != nil {
                                    dismiss()
                                }
                            }
                        } label: {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(Theme.Colors.textInverse)
                            } else {
                                Text("Create Household")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isFormValid || authViewModel.isLoading)
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .onAppear {
                authViewModel.clearError()
            }
        }
    }
}

#Preview {
    CreateHouseholdView()
        .environment(AuthViewModel())
}

