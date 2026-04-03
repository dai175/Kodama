# Kodama

Voxel bonsai tree iOS app. Tree grows autonomously over real-world time with user interactions.

## Tech Stack

- iOS 26+ / iPhone only
- Swift 6.1+ / Xcode 26
- SwiftUI (UI) + SceneKit (3D rendering)
- SwiftData (local-first, no server)
- MVVM architecture

## Build & Test

```bash
# Build
xcodebuild -scheme Kodama -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test
xcodebuild -scheme Kodama -destination 'platform=iOS Simulator,name=iPhone 16' test

# Lint
swiftlint

# Format
swiftformat .
```

## Project Structure

- `Kodama/KodamaApp.swift` - App entry point
- `Kodama/App/` - AppState (`@Observable`)
- `Kodama/Models/` - SwiftData models (BonsaiTree, VoxelBlock, Interaction, Season, BlockType, GrowthSource)
- `Kodama/Views/` - SwiftUI views (RootView, TreeView, InteractionOverlay, Onboarding, Settings, ColorPalette, WordInput)
- `Kodama/ViewModels/` - TreeViewModel, GrowthEngine
- `Kodama/Scene/` - SceneKit (BonsaiScene, BonsaiRenderer, TreeBuilder, SeasonalEngine, GrowthAnimator, InteractionHandler)

## Key Specs

- Full spec: `docs/kodama-mvp-spec.md`, concept: `docs/kodama-concept.md`
- Performance: 60fps on iPhone 12+, up to 2000 voxel blocks, render <300ms
- Growth engine runs on app open only (no background processing)
- Seasons from real-world date affect growth rate and leaf colors
- No sound, no haptics, no network — purely local, quiet experience

## Code Style

- Observation: use `@Observable` class (not `ObservableObject`)
- Environment: `.environment(obj)` + `@Environment(Type.self)` pattern
- SwiftData: `@Model` macro, `@Relationship(deleteRule: .cascade)`
- Auto-formatted with SwiftFormat (`.swiftformat`) and SwiftLint (`.swiftlint.yml`)

## Gotchas

- SceneKit uses `UIViewRepresentable` bridge — not native SwiftUI
- Shared `SCNGeometry` instances per color for performance
- Use `flattenedClone()` for static tree parts
- Growth is calculated, not real-time — catch-up on app open
- Dark theme only, no pure white/black colors
- SwiftFormat uses `--swiftversion 6.1` (separate from pbxproj `SWIFT_VERSION = 5.0` — to be unified later)
