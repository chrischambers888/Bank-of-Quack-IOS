# Bank of Quack - iOS

Native iOS app for household expense tracking, built with SwiftUI and Supabase.

## Requirements

- Xcode 15+
- iOS 17+

## Setup

### 1. Add Files to Xcode

The Swift files are in `Bank of Quack/Bank of Quack/` but Xcode doesn't know about them yet:

1. Open `Bank of Quack/Bank of Quack.xcodeproj` in Xcode
2. In the Project Navigator (left sidebar), right-click on `Bank of Quack` folder
3. Select "Add Files to 'Bank of Quack'..."
4. Select all folders: `App`, `Models`, `Services`, `ViewModels`, `Views`, `Utils`
5. Make sure "Copy items if needed" is **unchecked**
6. Click Add

### 2. Add Supabase Package

1. File → Add Package Dependencies
2. Enter: `https://github.com/supabase/supabase-swift`
3. Select version `2.0.0` or later
4. Add to target `Bank of Quack`

### 3. Configure Supabase

Edit `Services/SupabaseService.swift`:

```swift
enum SupabaseConfig {
    static let url = URL(string: "YOUR_SUPABASE_URL")!
    static let anonKey = "YOUR_SUPABASE_ANON_KEY"
}
```

### 4. Build & Run

Select an iPhone simulator and press ⌘R

## Project Structure

```
Bank of Quack/
├── App/           → App entry point (@main)
├── Models/        → Data models
├── Services/      → Supabase connectivity
├── ViewModels/    → State management
├── Views/         → SwiftUI views
└── Utils/         → Theme & extensions
```

## Features

- Email/password authentication
- Create & join households via invite code
- Track expenses, income, settlements, reimbursements
- Dashboard with monthly totals
- Member balance calculations
