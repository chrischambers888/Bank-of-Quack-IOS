import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @ObservedObject private var themeProvider = ThemeProvider.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var showForgotPassword = false
    
    // Yellow-100 color matching web version
    private let titleColor = Color(red: 254/255, green: 249/255, blue: 195/255)
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    // Background gradient
                    LinearGradient(
                        colors: [Theme.Colors.primary900, Theme.Colors.primary700],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: Theme.Spacing.xl) {
                            // Hero Image with Cursive Title - extends to top edge
                            ZStack {
                                Image(themeProvider.currentPalette.specialEffect == .snowfall ? "QuackMascotChristmas" : "QuackMascot")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: 380 + geometry.safeAreaInsets.top)
                                    .clipped()
                                    .overlay(
                                        LinearGradient(
                                            colors: [
                                                Color.black.opacity(0.35),
                                                Color.clear,
                                                Color.black.opacity(0.45)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                
                                // Cursive Title - Snell Roundhand Bold with Zapfino Q
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("Bank of ")
                                        .font(.custom("Snell Roundhand Bold", size: 58))
                                    Text("Q")
                                        .font(.custom("Zapfino", size: 42))
                                        .fontWeight(.bold)
                                    Text("uack")
                                        .font(.custom("Snell Roundhand Bold", size: 58))
                                }
                                .foregroundStyle(titleColor)
                                .shadow(color: .black.opacity(0.7), radius: 4, x: 2, y: 2)
                                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, geometry.safeAreaInsets.top / 2)
                            }
                            .frame(height: 380 + geometry.safeAreaInsets.top)
                            
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
                    .ignoresSafeArea(edges: .top)
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
