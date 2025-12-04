import SwiftUI

struct JoinHouseholdView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var inviteCode = ""
    @State private var displayName = ""
    @State private var requestSubmitted = false
    @State private var rejoined = false
    @State private var showClaimSheet = false
    @State private var isCheckingCode = false
    @State private var inactiveMemberInfo: InactiveMemberInfo?
    @State private var checkTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isProcessing = false
    
    private var isFormValid: Bool {
        let codeValid = !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
        if inactiveMemberInfo != nil {
            // For returning members, just need the code
            return codeValid
        } else {
            // For new members, need code and name
            return codeValid && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                if rejoined {
                    // Success State - Rejoined immediately
                    VStack(spacing: Theme.Spacing.xl) {
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(Theme.Colors.success)
                        
                        VStack(spacing: Theme.Spacing.sm) {
                            Text("Welcome Back!")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            
                            Text("You've rejoined the bank. All your previous transaction history is still here.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }
                        
                        Spacer()
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Continue")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xxl)
                    }
                } else if requestSubmitted {
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
                            
                            Text("Your request to join has been sent. A bank member will need to approve your request before you can access the bank.")
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
                                Image(systemName: inactiveMemberInfo != nil ? "hand.wave.fill" : "person.badge.plus")
                                    .font(.system(size: 60))
                                    .foregroundStyle(Theme.Colors.accent)
                                
                                Text(inactiveMemberInfo != nil ? "Welcome Back!" : "Join Bank")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                
                                if inactiveMemberInfo != nil {
                                    Text("We found your previous account")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("Enter the invite code shared with you")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.top, Theme.Spacing.xl)
                            
                            // Welcome Back Card (for returning members)
                            if let info = inactiveMemberInfo {
                                VStack(spacing: Theme.Spacing.md) {
                                    Text("You'll rejoin as")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textMuted)
                                    
                                    Text(info.displayName)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    
                                    Text("in \(info.householdName)")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    Text("Your previous transaction history will be preserved")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.success)
                                        .padding(.top, Theme.Spacing.xs)
                                }
                                .padding(Theme.Spacing.lg)
                                .frame(maxWidth: .infinity)
                                .background(Theme.Colors.success.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg))
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                            
                            // Form
                            VStack(spacing: Theme.Spacing.md) {
                                // Invite Code
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Invite Code")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    
                                    HStack {
                                        TextField("Enter code", text: $inviteCode)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        
                                        if isCheckingCode {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                    }
                                    .inputFieldStyle()
                                }
                                
                                // Display Name (only for new members)
                                if inactiveMemberInfo == nil {
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
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            // Info Box (only for new members)
                            if inactiveMemberInfo == nil {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(Theme.Colors.accent)
                                    
                                    Text("A bank member will need to approve your request before you can join.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                .padding(Theme.Spacing.md)
                                .background(Theme.Colors.backgroundCard)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                            
                            // Error
                            if let error = errorMessage {
                                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Theme.Colors.error)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.error)
                                }
                                .padding(Theme.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Colors.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.md))
                                .padding(.horizontal, Theme.Spacing.lg)
                            }
                            
                            // Join Button
                            Button {
                                joinHousehold()
                            } label: {
                                if isProcessing {
                                    ProgressView()
                                        .tint(Theme.Colors.textInverse)
                                } else {
                                    Text(inactiveMemberInfo != nil ? "Rejoin Bank" : "Request to Join")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isFormValid || isProcessing)
                            .padding(.horizontal, Theme.Spacing.lg)
                            
                            // Claim Account Option
                            VStack(spacing: Theme.Spacing.xs) {
                                Text("Have a claim code instead?")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textMuted)
                                
                                Button {
                                    showClaimSheet = true
                                } label: {
                                    Text("Claim Managed Account")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .padding(.top, Theme.Spacing.md)
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !requestSubmitted && !rejoined {
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
            .onChange(of: inviteCode) { _, newValue in
                checkInactiveStatus(code: newValue)
            }
            .sheet(isPresented: $showClaimSheet) {
                ClaimAccountView()
            }
        }
    }
    
    private func checkInactiveStatus(code: String) {
        // Cancel any existing check
        checkTask?.cancel()
        inactiveMemberInfo = nil
        
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard trimmedCode.count >= 6 else { return }  // Minimum code length
        
        isCheckingCode = true
        
        checkTask = Task {
            // Small delay to debounce
            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
            
            guard !Task.isCancelled else { return }
            
            do {
                let info = try await DataService().checkInactiveMembership(inviteCode: trimmedCode)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    inactiveMemberInfo = info
                    isCheckingCode = false
                }
            } catch {
                await MainActor.run {
                    isCheckingCode = false
                }
            }
        }
    }
    
    private func joinHousehold() {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let trimmedCode = inviteCode.trimmingCharacters(in: .whitespaces)
                let name = inactiveMemberInfo?.displayName ?? displayName.trimmingCharacters(in: .whitespaces)
                
                _ = try await DataService().joinHousehold(inviteCode: trimmedCode, displayName: name)
                
                // Reload user data
                await authViewModel.loadUserData()
                
                // Check if this was a rejoin (user is now approved) or new join (pending)
                if inactiveMemberInfo != nil {
                    // They were reactivated - select the household
                    if let household = authViewModel.households.first(where: { $0.name == inactiveMemberInfo?.householdName }) {
                        await authViewModel.selectHousehold(household)
                    }
                    
                    isProcessing = false
                    withAnimation {
                        rejoined = true
                    }
                } else {
                    isProcessing = false
                    withAnimation {
                        requestSubmitted = true
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }
}

#Preview {
    JoinHouseholdView()
        .environment(AuthViewModel())
}

