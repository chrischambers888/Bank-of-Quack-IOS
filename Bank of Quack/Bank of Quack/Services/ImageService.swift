import Foundation
import UIKit
import Supabase

// MARK: - Image Processing (Main Actor)

/// Helper class for image processing that must run on main actor
@MainActor
enum ImageProcessor {
    /// Resizes the image to fit within maxDimension while preserving aspect ratio
    /// Target: 512px max dimension, ~50KB file size
    static func processForUpload(_ image: UIImage, maxDimension: CGFloat = 512, compressionQuality: CGFloat = 0.75) -> Data? {
        // Square crop first
        let shortestSide = min(image.size.width, image.size.height)
        let origin = CGPoint(
            x: (image.size.width - shortestSide) / 2,
            y: (image.size.height - shortestSide) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: shortestSide, height: shortestSide))
        
        let croppedImage: UIImage
        if let cgImage = image.cgImage?.cropping(to: cropRect) {
            croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        } else {
            croppedImage = image
        }
        
        // Resize
        let scale = min(maxDimension / croppedImage.size.width, maxDimension / croppedImage.size.height, 1.0)
        let newSize = CGSize(width: croppedImage.size.width * scale, height: croppedImage.size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resizedImage.jpegData(compressionQuality: compressionQuality)
    }
}

// MARK: - Image Service Errors

enum ImageServiceError: LocalizedError {
    case resizingFailed
    case uploadFailed(String)
    case deleteFailed(String)
    case limitReached(current: Int, limit: Int)
    case invalidImage
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .resizingFailed:
            return "Failed to process the image."
        case .uploadFailed(let message):
            return "Failed to upload image: \(message)"
        case .deleteFailed(let message):
            return "Failed to delete image: \(message)"
        case .limitReached(let current, let limit):
            return "You've reached the photo limit (\(current)/\(limit)). Remove some photos to add more."
        case .invalidImage:
            return "The selected image could not be processed."
        case .notAuthenticated:
            return "You must be signed in to upload images."
        }
    }
}

// MARK: - Image Service

actor ImageService {
    private let supabase = SupabaseService.shared
    private let bucketName = "avatars"
    
    static let imageLimit = 50
    
    // MARK: - Upload
    
    /// Uploads an image to Supabase Storage
    /// - Parameters:
    ///   - image: The UIImage to upload
    ///   - ownerUserId: The user ID of the household owner (for path organization)
    ///   - existingUrl: Optional existing URL to delete before uploading new one
    /// - Returns: The public URL of the uploaded image
    func uploadImage(
        _ image: UIImage,
        ownerUserId: UUID,
        existingUrl: String? = nil
    ) async throws -> String {
        // Square crop and resize the image on main actor
        guard let imageData = await ImageProcessor.processForUpload(image) else {
            throw ImageServiceError.resizingFailed
        }
        
        // Delete existing image if present
        if let existingUrl = existingUrl, existingUrl.isPhotoUrlValue {
            try? await deleteImage(at: existingUrl)
        }
        
        // Generate unique filename
        let filename = "\(UUID().uuidString).jpg"
        let path = "\(ownerUserId.uuidString)/\(filename)"
        
        do {
            // Upload to Supabase Storage
            try await supabase.client.storage
                .from(bucketName)
                .upload(
                    path,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
            
            // Get public URL
            let publicUrl = try supabase.client.storage
                .from(bucketName)
                .getPublicURL(path: path)
            
            return publicUrl.absoluteString
        } catch {
            throw ImageServiceError.uploadFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Delete
    
    /// Deletes an image from Supabase Storage
    /// - Parameter url: The public URL of the image to delete
    func deleteImage(at url: String) async throws {
        guard url.isPhotoUrlValue else { return }
        
        // Extract path from URL
        // URL format: https://{project}.supabase.co/storage/v1/object/public/avatars/{owner_id}/{filename}
        guard let path = extractStoragePath(from: url) else { return }
        
        do {
            try await supabase.client.storage
                .from(bucketName)
                .remove(paths: [path])
        } catch {
            // Don't throw if delete fails - the image might already be gone
            print("Failed to delete image: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Count Tracking
    
    /// Counts the total number of photo avatars/icons for households owned by the given user
    /// This counts against the owner, not the uploader
    func countImagesForOwner(userId: UUID) async throws -> Int {
        // Fetch households where user is owner
        let ownedHouseholds: [Household] = try await supabase
            .from(.households)
            .select()
            .execute()
            .value
        
        // Get the household IDs where this user is the owner
        var ownedHouseholdIds: [UUID] = []
        
        for household in ownedHouseholds {
            // Check if user is owner of this household
            let members: [HouseholdMember] = try await supabase
                .from(.householdMembers)
                .select()
                .eq("household_id", value: household.id.uuidString)
                .eq("user_id", value: userId.uuidString)
                .eq("role", value: "owner")
                .limit(1)
                .execute()
                .value
            
            if !members.isEmpty {
                ownedHouseholdIds.append(household.id)
            }
        }
        
        guard !ownedHouseholdIds.isEmpty else { return 0 }
        
        var totalCount = 0
        
        // Count member avatars with photo URLs in owned households
        for householdId in ownedHouseholdIds {
            let members: [HouseholdMember] = try await supabase
                .from(.householdMembers)
                .select()
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
            
            totalCount += members.filter { $0.avatarUrl?.isPhotoUrlValue == true }.count
            
            // Count category icons with photo URLs
            let categories: [Category] = try await supabase
                .from(.categories)
                .select()
                .eq("household_id", value: householdId.uuidString)
                .execute()
                .value
            
            totalCount += categories.filter { $0.imageUrl?.isPhotoUrlValue == true }.count
        }
        
        return totalCount
    }
    
    /// Checks if the owner can add more images
    func canAddImage(ownerUserId: UUID) async throws -> (canAdd: Bool, current: Int, limit: Int) {
        let current = try await countImagesForOwner(userId: ownerUserId)
        return (current < Self.imageLimit, current, Self.imageLimit)
    }
    
    // MARK: - Helpers
    
    private func extractStoragePath(from url: String) -> String? {
        // URL format: https://{project}.supabase.co/storage/v1/object/public/avatars/{path}
        let pattern = "/storage/v1/object/public/\(bucketName)/"
        guard let range = url.range(of: pattern) else { return nil }
        return String(url[range.upperBound...])
    }
}

// MARK: - String Extension for URL Detection

extension String {
    /// Returns true if this string looks like a photo URL (vs an emoji)
    /// Marked nonisolated for use from actors
    nonisolated var isPhotoUrlValue: Bool {
        hasPrefix("https://") || hasPrefix("http://")
    }
    
    /// Convenience alias for non-actor contexts
    var isPhotoUrl: Bool {
        isPhotoUrlValue
    }
}

extension Optional where Wrapped == String {
    /// Returns true if this optional string is a photo URL
    /// Marked nonisolated for use from actors
    nonisolated var isPhotoUrlValue: Bool {
        self?.isPhotoUrlValue ?? false
    }
    
    /// Convenience alias for non-actor contexts
    var isPhotoUrl: Bool {
        isPhotoUrlValue
    }
}
