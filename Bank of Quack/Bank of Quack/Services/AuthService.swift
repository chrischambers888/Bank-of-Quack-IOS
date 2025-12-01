import Foundation
import Supabase

enum AuthError: LocalizedError {
    case notAuthenticated
    case invalidCredentials
    case emailNotConfirmed
    case networkError
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You are not signed in."
        case .invalidCredentials:
            return "Invalid email or password."
        case .emailNotConfirmed:
            return "Please confirm your email address."
        case .networkError:
            return "Network error. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}

actor AuthService {
    private let supabase = SupabaseService.shared
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String) async throws {
        do {
            try await supabase.auth.signUp(
                email: email,
                password: password
            )
        } catch {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async throws -> User {
        do {
            let response = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            return response.user
        } catch {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() async throws {
        do {
            try await supabase.auth.signOut()
        } catch {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Password Reset
    
    func resetPassword(email: String) async throws {
        do {
            try await supabase.auth.resetPasswordForEmail(email)
        } catch {
            throw mapAuthError(error)
        }
    }
    
    // MARK: - Current User
    
    func currentUser() async -> User? {
        try? await supabase.auth.session.user
    }
    
    func currentSession() async -> Session? {
        try? await supabase.auth.session
    }
    
    // MARK: - Auth State
    
    func authStateChanges() -> AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in supabase.auth.authStateChanges {
                    continuation.yield((event, session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAuthError(_ error: Error) -> AuthError {
        let message = error.localizedDescription.lowercased()
        
        if message.contains("invalid") || message.contains("credentials") {
            return .invalidCredentials
        } else if message.contains("confirm") || message.contains("verified") {
            return .emailNotConfirmed
        } else if message.contains("network") || message.contains("connection") {
            return .networkError
        } else {
            return .unknown(error.localizedDescription)
        }
    }
}

