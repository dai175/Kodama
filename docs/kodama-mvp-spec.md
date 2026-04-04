# Kodama — MVP Specification v1.0

## Project overview

Kodama is an iOS app where a voxel bonsai tree lives on your screen. The tree grows on its own over real-world time. Users can optionally interact — touching the tree, giving it color, or whispering a word. Each interaction subtly influences growth. Over months, the tree becomes unique to its owner. The app asks nothing and offers presence.

This document defines the MVP scope. For the full concept and design philosophy, see `kodama-concept.md`.

The Phase 1-2 prototype (`VoxelBonsaiPrototype/`) validated the core technology: procedural voxel tree generation, leaf rendering, and growth animation using SceneKit. The MVP builds on those learnings but is a new project with proper architecture.

## Tech stack

- **Platform:** iOS 26+, iPhone only
- **Language:** Swift 6.1+
- **UI framework:** SwiftUI (UI layer) + SceneKit (3D tree rendering)
- **Data:** SwiftData (local-first, no server)
- **Architecture:** MVVM
- **Build SDK:** Xcode 26 / iOS 26 SDK
- **Package manager:** Swift Package Manager
- **Minimum deployment target:** iOS 26.0

## MVP scope

### In scope (v1.0)

1. Voxel bonsai tree (procedural generation, SceneKit)
2. Autonomous growth (time-based, calculated on app open)
3. Seasonal changes (leaf color, growth rate, leaf fall, snow)
4. User interaction: touch
5. User interaction: color
6. User interaction: word
7. 3D camera control (rotate, zoom)
8. Data persistence (tree state saved locally)
9. Onboarding (minimal, 2-3 screens)
10. Settings (minimal)

### Out of scope (v2+)

- Moss terrarium mode
- The frog (silent garden resident)
- Multiple trees / tree collection
- Widgets
- Premium subscription / paywall (v1 is fully free)
- Sound / ambient audio
- AR mode
- Music / photo influence
- iCloud sync
- Apple Watch
- Localization (v1 is English only)
- Export / sharing features

For full v2+ details, see Section 14 of `kodama-concept.md`.

---

## Data model

### BonsaiTree

| Property | Type | Description |
|----------|------|-------------|
| id | UUID | Primary key |
| seed | Int | Base seed for deterministic generation |
| createdAt | Date | When the tree was first created |
| lastGrowthEval | Date | Last time growth engine ran |
| totalBlocks | Int | Current total block count (for quick reference) |

### VoxelBlock

| Property | Type | Description |
|----------|------|-------------|
| id | UUID | Primary key |
| treeID | UUID | Foreign key to BonsaiTree |
| x | Int | X coordinate in voxel grid |
| y | Int | Y coordinate in voxel grid |
| z | Int | Z coordinate in voxel grid |
| blockType | BlockType | trunk, branch, leaf, flower, moss, snow |
| colorHex | String | Hex color code |
| placedAt | Date | When this block was added |
| source | GrowthSource | autonomous, touch, color, word |
| parentBlockID | UUID? | Parent block in tree structure (for branch relationships) |

### Interaction

| Property | Type | Description |
|----------|------|-------------|
| id | UUID | Primary key |
| treeID | UUID | Foreign key to BonsaiTree |
| timestamp | Date | When interaction occurred |
| type | InteractionType | open, touch, color, word |
| value | String? | Color hex or word text |
| touchX | Int? | Touch position X in logical grid |
| touchY | Int? | Touch position Y in logical grid |
| touchZ | Int? | Touch position Z in logical grid |

### Enums

```swift
enum BlockType: String, Codable {
    case trunk
    case branch
    case leaf
    case flower
    case moss
    case snow
}

enum GrowthSource: String, Codable {
    case autonomous   // Time-based growth
    case touch        // User touched the tree
    case color        // User gave a color
    case word         // User gave a word
}

enum InteractionType: String, Codable {
    case open         // Just opened the app
    case touch        // Touched the tree
    case color        // Selected a color
    case word         // Entered a word
}

enum Season: String {
    case spring, summer, autumn, winter
    
    // Determined from real-world month
    // Spring: Mar-May, Summer: Jun-Aug, Autumn: Sep-Nov, Winter: Dec-Feb
}
```

---

## Screens

### 1. Tree view (home)

The main screen. The bonsai fills the screen.

**Layout:**
- Full-screen SceneKit view (`SCNView` via `UIViewRepresentable`)
- Dark gradient background (#0A1A12 to #0D2818)
- No visible UI by default — the tree is everything
- Subtle settings icon (top-right, semi-transparent, appears on tap)
- Interaction elements appear only when the user touches the screen

**3D camera:**
- User can rotate the tree with one-finger drag
- Pinch to zoom in/out
- Double-tap to reset camera to default position
- Default camera: slightly above and in front, looking at tree center
- Slow auto-rotation when idle (very slow, ~1 degree per 3 seconds, stops on touch)

**Behavior on app open:**
1. Load saved tree state from SwiftData
2. Calculate elapsed time since `lastGrowthEval`
3. Run growth engine to determine new blocks
4. Animate new blocks appearing (subtle scale-in, 0.15s per block)
5. Update `lastGrowthEval` to now
6. Log an `open` interaction

### 2. Interaction overlay

Not a separate screen — overlays on the tree view when the user interacts.

**Touch response:**
- User touches anywhere on the 3D scene
- Hit test to find the nearest tree block
- A soft glow appears at the touch point (SCNLight, warm color, fades over 2s)
- If touch is near a branch tip, queue a leaf/branch growth near that point
- The growth happens on next growth evaluation, not instantly

**Color palette:**
- After touching, or on a long press, a subtle arc of 7 color circles appears at the bottom
- Colors: warm red, orange, golden yellow, soft green, cool blue, gentle purple, neutral white
- No labels, no mood names — just colors
- Tap a color → it flows toward the tree (particle animation, 0.5s)
- The color is stored in the Interaction and influences next growth blocks
- Palette fades out after selection or after 5s of no interaction

**Word input:**
- After color selection (or independently via a small icon), a minimal text field appears
- Single-line, max 20 characters
- Placeholder text: none (empty field, blinking cursor)
- On submit: text dissolves into particles that flow toward the tree (0.8s)
- The word is stored in Interaction but never displayed on the tree
- Text field disappears after submission
- Keyboard style: dark, minimal

**Design rules for interaction:**
- No haptic feedback (keep it quiet)
- All animations use easeInEaseOut
- No bounce, no spring animations
- Everything fades in and out, nothing snaps
- Interaction elements are semi-transparent, never opaque

### 3. Onboarding

Shown only on first launch. 2-3 screens max.

- Screen 1: "This is your tree. It's alive." (small sapling in pot, dark background)
- Screen 2: "It grows on its own. Touch it, and it grows with you." (tree responds to touch animation)
- Screen 3: "There's nothing to do. Just be here." → Done

No notification permission request. No configuration. Just begin.

### 4. Settings

**Access:** Gear icon (top-right, semi-transparent) on tree view

**Options:**
- About (app version, focuswave link)
- Reset tree (with double confirmation — "This will remove your tree permanently")
- Season override for testing (debug only, hidden in release)

Minimal. Almost nothing here.

---

## Growth engine

### Core loop

The growth engine runs every time the app opens. It does NOT run in the background.

```
On app open:
  1. elapsedHours = hours since lastGrowthEval
  2. currentSeason = season from current real-world date
  3. for each growthTick in elapsedHours:
       a. Determine growth rate (season-dependent)
       b. Roll for autonomous growth (add 0-3 blocks per tick)
       c. Apply pending interactions (touch proximity, color influence)
       d. Apply seasonal effects (color shifts, leaf drop, snow)
  4. Add all new VoxelBlocks to the tree
  5. Animate new blocks appearing
  6. Save updated tree state
  7. Update lastGrowthEval = now
```

### Growth rate by season

| Season | Growth ticks per hour | New blocks per tick | Notes |
|--------|----------------------|--------------------:|-------|
| Spring | 1 | 1-3 | Fast growth, new branches and leaves |
| Summer | 1 | 1-2 | Steady growth, dense foliage |
| Autumn | 1 | 0-1 | Slow growth, color change active |
| Winter | 1 | 0 | No new growth, snow accumulation |

### Growth rules

**Trunk thickening:**
- Every 50 total blocks, evaluate if trunk should thicken
- Thicken by adding blocks around existing trunk blocks (1×1 → 2×2 → 3×3)
- New trunk blocks use slightly lighter brown (bark layer effect)

**Branch extension:**
- New branch blocks grow from existing branch tips
- Direction influenced by: seed randomness, season, and user touch positions
- Branches use the recursive builder logic from Phase 1-2 prototype
- Each new branch segment: 1-3 blocks long
- Branch probability of further splitting: 30-50% per growth tick

**Leaf generation:**
- Leaves appear on branch tips and along middle branches
- Leaf color determined by: season + user color history
- Spring: light green with occasional pink (buds)
- Summer: dense dark green
- Autumn: transition from green → yellow → orange → red (1 block per tick changes color)
- Winter: leaves fall (removed with subtle drop animation)

**User interaction influence:**
- Touch: next 2-3 growth blocks appear near the touched position
- Color: next 5-10 leaf blocks carry a tint of the chosen color
- Word: influences branch direction subtly (word length affects angle, first letter affects direction — deterministic but invisible to user)

### Seasonal effects

**Spring (March - May):**
- Growth rate: high
- New leaves: light green (#7AB648, #5A9E3A)
- Occasional flower blocks: pink (#E8A0BF) on branch tips, 10% chance per growth tick
- Flower blocks last 14 days then disappear

**Summer (June - August):**
- Growth rate: medium
- Leaves: dense, dark green (#2D5A1E, #3E7A2A)
- Existing leaves darken slightly over summer
- Moss blocks begin appearing on trunk base (1 per week)

**Autumn (September - November):**
- Growth rate: low
- Leaf color transition: each growth tick, 2-5 leaf blocks change color
- Transition order: green → yellow-green → yellow → orange → red → brown
- After turning brown, leaves have 30% chance per tick to "fall" (removed with drop animation)
- Fallen leaf blocks accumulate at pot base (y=0), removed after 7 days

**Winter (December - February):**
- Growth rate: zero (tree rests)
- Remaining leaves continue to fall
- Snow blocks (white, #E8E4DC) accumulate on top surfaces of branches (1-3 per day)
- Snow blocks removed gradually when spring begins
- Bare branch structure is visible — this is its own beauty

### Growth animation

When the app opens and new blocks are calculated:
- Blocks appear in natural order (lower Y first, trunk before branch before leaf)
- Each block scales from 0 to 1.0 over 0.15 seconds
- Interval between blocks: 0.05-0.1 seconds
- If many blocks accumulated (e.g., 1 week away), show growth in accelerated sequence (max 10 seconds total)
- Seasonal transitions (leaf color changes, snow) animate gradually over 2-3 seconds

---

## Performance

### Targets

- 60fps on iPhone 12 and later
- Support up to 5000 voxel blocks per tree
- Scene render within 300ms on app open
- Growth calculation within 100ms (even for 7 days elapsed)

### Optimization strategies

- Use shared `SCNGeometry` instances — one `SCNBox` geometry per unique color
- Use `SCNNode.flattenedClone()` for static parts of the tree
- Only animate blocks added in the current session
- Blocks older than 30 days: convert to static (no individual animation capability)
- Level of detail: blocks far from camera center can skip glow effects

---

## Design guidelines

### Color

- Background: dark gradient (#0A1A12 to #0D2818)
- Text: soft white (#E8E4DC, opacity 0.8)
- Accent: focuswave teal (#1D9E75)
- UI elements: semi-transparent, appear on interaction, fade when idle
- No pure white, no pure black

### Typography

- System font (SF Pro) for all UI text
- Lightweight/thin variants
- Minimal text anywhere — the tree speaks for itself

### Interaction design

- No haptic feedback
- Transitions: 0.3-1.5s, easeInEaseOut only
- No bounce, no spring animations
- Touch response: immediate glow, growth queued (not instant)
- Color palette: 7 circles, no labels, fade in/out
- Word input: minimal, dissolves into tree

### Lighting

- One directional light (above-left, soft white)
- One ambient light (very dim, provides base visibility)
- Touch interaction: temporary point light at touch position (warm, fades over 2s)
- Optional subtle glow on newest blocks (emissionIntensity on SCNMaterial)

### Sound

- No sound in MVP. Complete silence is intentional.

---

## File structure

```
Kodama/
├── App/
│   ├── KodamaApp.swift
│   └── AppState.swift
├── Models/
│   ├── BonsaiTree.swift
│   ├── VoxelBlock.swift
│   ├── Interaction.swift
│   ├── BlockType.swift
│   ├── GrowthSource.swift
│   └── Season.swift
├── Views/
│   ├── TreeView.swift              # Main screen (SwiftUI host for SceneKit)
│   ├── InteractionOverlay.swift    # Touch, color, word UI
│   ├── ColorPaletteView.swift      # 7 color circles
│   ├── WordInputView.swift         # Minimal text input
│   ├── OnboardingView.swift        # First launch
│   └── SettingsView.swift
├── ViewModels/
│   ├── TreeViewModel.swift         # Main VM — coordinates growth + interaction
│   └── GrowthEngine.swift          # Time-based growth calculation
├── Scene/
│   ├── BonsaiScene.swift           # SCNScene setup, lighting, camera
│   ├── BonsaiRenderer.swift        # VoxelBlock[] → SCNNode tree
│   ├── TreeBuilder.swift           # Recursive procedural tree generation
│   ├── SeasonalEngine.swift        # Season detection, color transitions
│   ├── InteractionHandler.swift    # Touch hit testing, glow effects
│   └── GrowthAnimator.swift        # Block appearance animations
├── Resources/
│   └── Assets.xcassets
└── Preview Content/
```

---

## Acceptance criteria

The MVP is complete when:

1. A voxel bonsai tree appears on screen on first launch (small sapling)
2. The tree can be rotated with one-finger drag and zoomed with pinch
3. Closing and reopening the app after 1+ hours shows new growth blocks appearing
4. Growth rate varies by real-world season (faster in spring, none in winter)
5. Leaf colors change with season (green → yellow → red → fall → snow)
6. Touching the tree produces a visible glow response
7. Touching near a branch tip causes growth in that area on next evaluation
8. Selecting a color from the palette visually flows into the tree
9. Selected colors influence subsequent leaf block colors
10. Entering a word dissolves it into the tree visually
11. Tree state persists across app launches (SwiftData)
12. Different seeds produce visually distinct trees
13. The tree looks good at every growth stage (sapling through mature)
14. Onboarding appears on first launch only
15. Settings allow tree reset with confirmation
16. No UI visible by default — only the tree on a dark background
17. Interaction elements (palette, text field) appear/disappear smoothly
18. 60fps on iPhone 12+
19. App works fully offline with no network dependency
20. Dark theme only
