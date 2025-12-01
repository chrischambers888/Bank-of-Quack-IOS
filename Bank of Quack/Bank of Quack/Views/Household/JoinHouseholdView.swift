import SwiftUI

struct JoinHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteCode = ""
    @State private var displayName = ""
    @State private var requestSubmitted = false
    
    private var isFormValid: Bool {
        !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if requestSubmitted {
                    // Success State - Awaiting Approval
                    VStack(spacing: Theme.Spacing.xl) {
                        Spacer()
                        
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 80))
                            .foregroundStyle(Theme.Colors.warning)
                        
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Request Submitted!")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Your request to join has been sent. A household member will need to approve your request before you can access the household.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }
                        
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "bell.badge")
                                .font(.title3)
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("You'll be notified when you're approved")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        .padding(.top, Theme.Spacing.lg)
                        
                        Spacer()
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xxl)
                    }
                } else {
                    // Form State
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
                            
                            // Info Box
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                
                                Text("A household member will need to approve your request before you can join.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
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
                                    let success = await authViewModel.joinHousehold(
                                        inviteCode: inviteCode.trimmingCharacters(in: .whitespaces),
                                        displayName: displayName.trimmingCharacters(in: .whitespaces)
                                    )
                                    if success {
                                        withAnimation {
                                            requestSubmitted = true
                                        }
                                    }
                                }
                            } label: {
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .tint(Theme.Colors.textInverse)
                                } else {
                                    Text("Request to Join")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isFormValid || authViewModel.isLoading)
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !requestSubmitted {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
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

