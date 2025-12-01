import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    
    var body: some View {
        NavigationStack {
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
                        // Logo
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(Theme.Colors.accent)
                            
                            Text("Bank of Quack")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("Household expense tracking made simple")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.top, Theme.Spacing.xxl)
                        
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
                            }
                            
                            // Password
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text("Password")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                
                                SecureField("", text: $password)
                                    .textContentType(.password)
                                    .inputFieldStyle()
                            }
                            
                            // Forgot Password
                            HStack {
                                Spacer()
                                Button("Forgot Password?") {
                                    showForgotPassword = true
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.accent)
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
                        
                        // Sign In Button
                        Button {
                            Task {
                                await authViewModel.signIn(email: email, password: password)
                            }
                        } label: {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(Theme.Colors.textInverse)
                            } else {
                                Text("Sign In")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(email.isEmpty || password.isEmpty || authViewModel.isLoading)
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Theme.Colors.borderLight)
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textMuted)
                            Rectangle()
                                .fill(Theme.Colors.borderLight)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        // Sign Up Link
                        Button {
                            showSignUp = true
                        } label: {
                            Text("Create an Account")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, Theme.Spacing.lg)
                        
                        Spacer()
                    }
                }
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}

