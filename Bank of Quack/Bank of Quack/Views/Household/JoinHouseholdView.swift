import SwiftUI

struct JoinHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteCode = ""
    @State private var displayName = ""
    
    private var isFormValid: Bool {
        !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty &&
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
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 60))
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("Join Household")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Enter the invite code shared with you")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, Theme.Spacing.xl)
                        
                        // Form
                        VStack(spacing: Theme.Spacing.md) {
                            // Invite Code
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Invite Code")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("Enter code", text: $inviteCode)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
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
                        
                        // Join Button
                        Button {
                            Task {
                                await authViewModel.joinHousehold(
                                    inviteCode: inviteCode.trimmingCharacters(in: .whitespaces),
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
                                Text("Join Household")
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
    JoinHouseholdView()
        .environment(AuthViewModel())
}

