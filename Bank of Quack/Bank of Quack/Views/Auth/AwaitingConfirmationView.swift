import SwiftUI

struct AwaitingConfirmationView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    let email: String
    
    @State private var isResending = false
    @State private var showResendSuccess = false
    @State private var showResendError = false
    @State private var resendErrorMessage = ""
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Theme.Colors.primary900, Theme.Colors.primary700],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: Theme.Spacing.xl) {
                Spacer()
                
                // Email icon with animation
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 50))
                        .foregroundStyle(Theme.Colors.accent)
                        .symbolEffect(.pulse, options: .repeating)
                }
                
                // Header
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Check Your Email")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    
                    Text("We sent a confirmation link to")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    Text(email)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.accent)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    InstructionRow(
                        number: 1,
                        text: "Open the email on your iPhone",
                        icon: "iphone"
                    )
                    InstructionRow(number: 2, text: "Tap the confirmation link")
                    InstructionRow(number: 3, text: "You'll be signed in automatically")
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
                .background(Theme.Colors.backgroundCard.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                .padding(.horizontal, Theme.Spacing.lg)
                
                // Warning about desktop
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.warning)
                    
                    Text("The link won't work if opened on a computer")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.sm)
                
                Spacer()
                
                // Actions
                VStack(spacing: Theme.Spacing.md) {
                    // Resend button
                    Button {
                        resendConfirmation()
                    } label: {
                        if isResending {
                            ProgressView()
                                .tint(Theme.Colors.accent)
                        } else {
                            Text("Resend Confirmation Email")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isResending)
                    .padding(.horizontal, Theme.Spacing.lg)
                    
                    // Back to login
                    Button {
                        authViewModel.cancelAwaitingConfirmation()
                    } label: {
                        Text("Back to Sign In")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .alert("Email Sent!", isPresented: $showResendSuccess) {
            Button("OK") { }
        } message: {
            Text("We've sent another confirmation email to \(email)")
        }
        .alert("Error", isPresented: $showResendError) {
            Button("OK") { }
        } message: {
            Text(resendErrorMessage)
        }
    }
    
    private func resendConfirmation() {
        isResending = true
        
        Task {
            do {
                try await authViewModel.resendConfirmation(email: email)
                await MainActor.run {
                    isResending = false
                    showResendSuccess = true
                }
            } catch {
                await MainActor.run {
                    isResending = false
                    resendErrorMessage = error.localizedDescription
                    showResendError = true
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textInverse)
            }
            
            HStack(spacing: Theme.Spacing.xs) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    AwaitingConfirmationView(email: "test@example.com")
        .environment(AuthViewModel())
}

