import SwiftUI

struct SignUpView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }
    
    private var isFormValid: Bool {
        email.isValidEmail && passwordsMatch && password.count >= 6
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Theme.Colors.primary900, Theme.Colors.primary700],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Create Account")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        Text("Join Bank of Quack today")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.top, Theme.Spacing.xl)
                    
                    // Form
                    VStack(spacing: Theme.Spacing.md) {
                        // Email
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Email")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            TextField("", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .inputFieldStyle()
                            
                            if !email.isEmpty && !email.isValidEmail {
                                Text("Please enter a valid email")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Password")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            SecureField("", text: $password)
                                .textContentType(.newPassword)
                                .inputFieldStyle()
                            
                            if !password.isEmpty && password.count < 6 {
                                Text("Password must be at least 6 characters")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.error)
                            }
                        }
                        
                        // Confirm Password
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Confirm Password")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            
                            SecureField("", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .inputFieldStyle()
                            
                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text("Passwords don't match")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.error)
                            }
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
                    
                    // Sign Up Button
                    Button {
                        Task {
                            await authViewModel.signUp(email: email, password: password)
                            // AwaitingConfirmationView will be shown automatically by ContentView
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .tint(Theme.Colors.textInverse)
                        } else {
                            Text("Create Account")
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .onAppear {
            authViewModel.clearError()
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environment(AuthViewModel())
    }
}

