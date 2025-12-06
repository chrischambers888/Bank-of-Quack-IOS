import SwiftUI

// MARK: - Member Avatar View

/// A reusable view for displaying member avatars that handles both photo URLs and emojis
struct MemberAvatarView: View {
    let member: HouseholdMember
    var size: CGFloat = 36
    var fontSize: CGFloat = 20
    
    var body: some View {
        ZStack {
            Circle()
                .fill(member.swiftUIColor)
                .frame(width: size, height: size)
            
            if let avatarUrl = member.avatarUrl, avatarUrl.isPhotoUrl {
                // Photo avatar
                AsyncImage(url: URL(string: avatarUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure:
                        initialsView
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.5)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if let emoji = member.avatarUrl, !emoji.isEmpty {
                // Emoji avatar
                Text(emoji)
                    .font(.system(size: fontSize))
            } else {
                // Initials fallback
                initialsView
            }
        }
    }
    
    private var initialsView: some View {
        Text(member.initials)
            .font(.system(size: fontSize * 0.6))
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textInverse)
    }
}

// MARK: - Category Icon View

/// A reusable view for displaying category icons that handles both photo URLs and emojis
struct CategoryIconView: View {
    let category: Category
    var size: CGFloat = 44
    var fontSize: CGFloat = 20
    
    var body: some View {
        ZStack {
            Circle()
                .fill(category.swiftUIColor.opacity(0.2))
                .frame(width: size, height: size)
            
            if let imageUrl = category.imageUrl, imageUrl.isPhotoUrl {
                // Photo icon
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure:
                        defaultIcon
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.5)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if let icon = category.icon, !icon.isEmpty {
                // Emoji icon
                Text(icon)
                    .font(.system(size: fontSize))
            } else {
                // Default folder icon
                defaultIcon
            }
        }
    }
    
    private var defaultIcon: some View {
        Image(systemName: "folder.fill")
            .font(.system(size: fontSize * 0.8))
            .foregroundStyle(category.swiftUIColor)
    }
}

// MARK: - Inline Member Avatar (for text-like contexts)

/// A compact inline avatar for use in lists or text contexts
/// Displays the first character/emoji if no photo, or the photo if available
struct InlineMemberAvatar: View {
    let member: HouseholdMember
    var size: CGFloat = 32
    
    var body: some View {
        ZStack {
            Circle()
                .fill(member.swiftUIColor)
                .frame(width: size, height: size)
            
            if let avatarUrl = member.avatarUrl, avatarUrl.isPhotoUrl {
                AsyncImage(url: URL(string: avatarUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    default:
                        fallbackContent
                    }
                }
            } else {
                fallbackContent
            }
        }
    }
    
    private var fallbackContent: some View {
        Text(displayText)
            .font(.system(size: size * 0.4))
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textInverse)
    }
    
    private var displayText: String {
        if let emoji = member.avatarUrl, !emoji.isEmpty, !emoji.isPhotoUrl {
            return emoji
        }
        return String(member.displayName.prefix(1)).uppercased()
    }
}

// MARK: - Preview Provider

#Preview("Member Avatars") {
    VStack(spacing: 20) {
        Text("Member Avatar Sizes")
            .font(.headline)
        
        HStack(spacing: 16) {
            // Would need sample data for preview
            Circle()
                .fill(Color.blue)
                .frame(width: 32, height: 32)
                .overlay(Text("JD").font(.caption).foregroundStyle(.white))
            
            Circle()
                .fill(Color.green)
                .frame(width: 44, height: 44)
                .overlay(Text("🦆").font(.title3))
            
            Circle()
                .fill(Color.purple)
                .frame(width: 60, height: 60)
                .overlay(Text("AB").font(.title3).foregroundStyle(.white))
        }
    }
    .padding()
    .background(Theme.Colors.backgroundPrimary)
}
