import SwiftUI

struct ClaimAccountView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var claimCode = ""
    @State private var claimSuccess = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    private var isFormValid: Bool {
        !claimCode.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if claimSuccess {
                    // Success State
                    ClaimSuccessView {
                        dismiss()
                    }
                }                 else {
                    // Form State
                    ScrollView {
                        VStack(spacing: Theme.Spacing.xl) {
                            // Error Display (at top for visibility)
                            if let error = errorMessage {
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.Colors.error)
                                    Text(error)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.error)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(Theme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Colors.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.top, Theme.Spacing.md)
                            }
                            
                            // Header
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.system(size: 60))
                                    .foregroundStyle(Theme.Colors.accent)
                                
                                Text("Claim Your Account")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                Text("If someone has been managing your transactions, use the claim code they shared with you")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Theme.Spacing.md)
                            }
                            .padding(.top, errorMessage == nil ? Theme.Spacing.xl : 0)
                            
                            // Form
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Claim Code")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                TextField("Enter 8-character code", text: $claimCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .font(.system(.title3, design: .monospaced))
                                    .inputFieldStyle()
                                    .onChange(of: claimCode) { _, newValue in
                                        // Auto-uppercase and limit to 8 characters
                                        claimCode = String(newValue.uppercased().prefix(8))
                                    }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            // Info Box
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(Theme.Colors.accent)
                                    Text("What happens when you claim?")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                                
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    ClaimInfoRow(icon: "arrow.right.circle.fill", text: "You'll join the bank immediately")
                                    ClaimInfoRow(icon: "clock.arrow.circlepath", text: "Your transaction history will be preserved")
                                    ClaimInfoRow(icon: "person.fill.checkmark", text: "You'll take over from the managed account")
                                }
                            }
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            // Claim Button
                            Button {
                                claimAccount()
                            } label: {
                                if isProcessing {
                                    ProgressView()
                                        .tint(Theme.Colors.textInverse)
                                } else {
                                    Text("Claim Account")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isFormValid || isProcessing)
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            // Alternative Options
                            VStack(spacing: Theme.Spacing.xs) {
                                Text("Don't have a claim code?")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                Text("Ask the person managing your account for the code, or join normally with a bank invite code instead.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.top, Theme.Spacing.md)
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !claimSuccess {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            .onAppear {
                errorMessage = nil
            }
        }
    }
    
    private func claimAccount() {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let householdId = try await DataService().claimManagedMember(
                    claimCode: claimCode.trimmingCharacters(in: .whitespaces)
                )
                
                // Reload user data without using global isLoading
                await authViewModel.loadUserData()
                
                // Select the household they joined
                if let household = authViewModel.households.first(where: { $0.id == householdId }) {
                    await authViewModel.selectHousehold(household)
                }
                
                isProcessing = false
                withAnimation {
                    claimSuccess = true
                }
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}

// MARK: - Claim Info Row

struct ClaimInfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Claim Success View

struct ClaimSuccessView: View {
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.success)
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("Account Claimed!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Text("You now have access to your bank and all your transaction history.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
            
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "party.popper")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.accent)
                
                Text("Welcome to the bank!")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textMuted)
            }
            .padding(.top, Theme.Spacing.lg)
            
            Spacer()
            
            Button {
                onDone()
            } label: {
                Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }
}

#Preview {
    ClaimAccountView()
        .environment(AuthViewModel())
}

