# Kodama Agent Notes

## Response

- Respond in Japanese.

## Project Summary

- Kodama is an iPhone-only iOS app for a voxel bonsai tree that grows over real-world time.
- Tech stack: SwiftUI, SceneKit, SwiftData, Swift 6.1+, Xcode 26.
- Architecture: MVVM.

## Project Structure

- `Kodama/KodamaApp.swift`: app entry point
- `Kodama/App/`: app-wide state
- `Kodama/Models/`: SwiftData models
- `Kodama/Views/`: SwiftUI views
- `Kodama/ViewModels/`: view models and growth logic
- `Kodama/Scene/`: SceneKit rendering and tree generation

## Build And Test

```bash
# Build
xcodebuild -scheme Kodama -destination 'platform=iOS Simulator,name=iPhone 17' build

# Test
xcodebuild -scheme Kodama -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:KodamaTests test
```

## Test Policy

- During the current prototyping phase, run internal logic tests only by default.
- Use `KodamaTests` as the standard automated test target.
- Do not run `KodamaUITests` unless the user explicitly asks for UI testing.

## Commit Messages

- Use Conventional Commits style.
- Prefer prefixes such as `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, and `chore:`.
- Make the subject specific to the actual change.
- If the user provides or implies a preferred commit message style, follow that preference.

## Code Style And Architecture

- Use `@Observable` classes, not `ObservableObject`, unless an existing file already requires a different pattern.
- Follow the existing SwiftData model relationships and delete rules.
- Preserve the current MVVM structure. Do not move logic into views unless the surrounding code already does so.
- Keep SceneKit integration aligned with the existing `UIViewRepresentable` bridge approach.
- Logging: use `Logger` (OSLog) instead of `print` for error/diagnostic output.

## Project-Specific Notes

- Growth is calculated on app open, not in real time and not via background processing.
- Seasons are derived from real-world date and affect growth and colors.
- Shared `SCNGeometry` instances are used for performance; preserve that optimization when editing rendering code.
- The visual direction is quiet and local-first: no network, no accounts, no sound, no haptics.
