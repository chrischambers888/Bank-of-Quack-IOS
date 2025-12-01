import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Theme.Colors.accent)
                        
                        Text("Reset Password")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Enter your email and we'll send you a link to reset your password")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.xl)
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Email")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        
                        TextField("", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .inputFieldStyle()
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
                    
                    // Reset Button
                    Button {
                        Task {
                            await authViewModel.resetPassword(email: email)
                            if authViewModel.error == nil {
                                showSuccess = true
                            }
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .tint(Theme.Colors.textInverse)
                        } else {
                            Text("Send Reset Link")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!email.isValidEmail || authViewModel.isLoading)
                    .padding(.horizontal, Theme.Spacing.lg)
                    
                    Spacer()
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
            .alert("Email Sent", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Check your email for a password reset link.")
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
        .environment(AuthViewModel())
}

