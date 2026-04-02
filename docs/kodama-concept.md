# Kodama

**"Being with something alive"**

focuswave · Concept Document v1.0 · April 2026
iOS 26 | Swift | SceneKit | Freemium

---

## 1. Overview

Kodama is an iOS app where a voxel bonsai tree lives on your screen. The tree grows on its own — slowly, quietly, in its own time. You don't need to do anything. But if you choose to, you can touch it, give it color, or whisper a word. The tree responds, absorbs, and continues growing. Over weeks and months, it becomes something that could only be yours.

Kodama is not a mood tracker. It is not a game. It is not a tool. It is a companion — a small, quiet life that shares your time.

The name comes from 木霊 (kodama), the Japanese concept of spirits that inhabit trees. In Kodama, the spirit is the tree itself.

## 2. Core metaphor

A bonsai grows whether you tend to it or not. Sun rises, rain falls, seasons change. The tree responds to all of it. But when you sit beside it, touch its branches, choose where to guide its growth — your presence becomes part of its story. Years later, every curve of every branch holds a memory you may or may not recall. The tree remembers what you've forgotten.

Kodama is that bonsai.

## 3. Experience principles

Three principles guide every design decision.

### Principle 1: The tree is alive without you

The tree grows, changes, and breathes whether the app is open or not. When you return after a day, a week, a month — the tree has changed. New branches, shifted colors, fallen leaves. It did not wait for you. It lived. This removes all pressure to "use" the app. There are no streaks, no empty days, no guilt. The tree doesn't need you. But it's glad when you're here.

### Principle 2: Every touch matters, no touch is required

Opening the app is enough. The tree acknowledges your presence with a subtle shift — a leaf turns, light changes. If you touch the tree, something responds. If you choose a color, it absorbs. If you write a word, the tree remembers in its own way. But none of this is required. The deepest interaction and no interaction at all are equally valid.

### Principle 3: All weather is beautiful

Sunny days make the tree grow bright leaves. Rainy days make moss creep along the trunk. Storms bend the branches into dramatic curves. Snow covers everything in silence. None of these is better or worse. A tree that has known only sunshine is less interesting than one that has weathered all seasons. This is the bonsai philosophy: the beauty is in the character, and character comes from experience.

## 4. The tree's life

### Autonomous growth

The tree grows based on elapsed real-world time. Every hour, the growth engine evaluates whether to add new elements. Growth is slow — a few voxel blocks per day. The rate varies with season:

- Spring: faster growth, new branches, buds
- Summer: full foliage, dense leaves, occasional flowers
- Autumn: leaf color change (green → yellow → orange → red), gradual leaf drop
- Winter: bare branches, snow accumulation, slow/paused growth

Growth happens in the background (calculated on app open based on elapsed time, not via background processes). When you open the app after a week, you see a week's worth of growth appear gently.

### Time scale

The tree is a long-term companion, not a monthly project.

- Week 1: A small sapling — a few trunk blocks and tiny branches
- Month 1: A young tree — visible branch structure, first leaves
- Month 3: An adolescent tree — multiple branch layers, seasonal character
- Month 6: A mature tree — thick trunk, complex branching, rich history
- Year 1+: An old tree — deep character, moss on trunk, unique silhouette

The tree never "completes." It continues to evolve indefinitely.

## 5. User interaction

Interaction is layered. Each layer is optional. All layers can be combined.

### Layer 0: Just open

Open the app. See the tree. It reacts subtly to your presence — a gentle sway, a shift in light. Close the app whenever you want. This alone is a complete experience.

### Layer 1: Touch

Touch the tree anywhere on screen. The spot you touch glows softly. The tree responds — a leaf might grow near your touch, a branch might shift slightly. The longer you hold, the more the tree absorbs your presence. Touch is wordless, thoughtless. Pure presence.

### Layer 2: Color

While touching (or separately), a subtle color palette appears at the edge of the screen. Touch a color and it flows into the tree. The next blocks that grow will carry that color's influence — warm colors make warmer-toned leaves, cool colors deepen the green. Over time, the tree's palette becomes a record of the colors you've given it.

No labels on the colors. No "happy = yellow" mapping. The user chooses intuitively.

### Layer 3: Word

A minimal text input appears. Write one word or a short phrase. The word dissolves into the tree — visually absorbed. It influences growth direction or branch character subtly. The word itself is not displayed on the tree or stored visibly. It becomes part of the tree's invisible history.

### Combining layers

Touch the tree, slide to a color, type a word — all in one fluid gesture. Or just open and close. The app adapts to whatever the user offers.

## 6. Visual style

### Voxel aesthetic

All elements are constructed from voxel blocks (3D cubes). The style is reminiscent of Minecraft but more refined — warm lighting, subtle glow, organic arrangements. The voxel style is a deliberate choice: it allows code-generated visuals to be inherently beautiful, eliminating the gap between "concept art" and "actual app" that plagued Mood Garden.

### Scene composition

- Background: dark gradient (#0A1A12 to #0D2818)
- The bonsai tree occupies the center of the screen
- A voxel pot sits at the bottom
- Soft directional lighting from above-left
- Subtle ambient glow on select blocks
- The user can rotate the tree with gestures and zoom in/out
- No UI elements visible by default — they appear on interaction

### Color palette

Tree colors shift with season and user input:

| Element | Default colors |
|---------|---------------|
| Trunk | #4A3728, #5A4433, #6B5540 (dark to light brown) |
| Branches | #6B4E37, #8B6F4E, #A68B6B |
| Leaves (spring) | #5A9E3A, #7AB648, #3E7A2A + pink buds |
| Leaves (summer) | #2D5A1E, #3E7A2A, #5A9E3A (dense green) |
| Leaves (autumn) | #C4882F, #D4632A, #8B2E1A (amber to red) |
| Leaves (winter) | sparse, #8B7355 (dried), white snow blocks |
| User colors | Influence leaf/flower tint — not override |
| Moss | #2A4A1E (appears on mature trunks) |
| Flowers | seasonal — cherry blossom pink in spring, subtle |

## 7. Technical architecture

### Platform

- iOS 26+, iPhone
- Swift 6.1, SwiftUI + SceneKit
- SwiftData for persistence
- Local-first, no server dependency

### Tree data model

```
BonsaiTree:
  - id: UUID
  - seed: Int (deterministic generation base)
  - createdAt: Date
  - blocks: [VoxelBlock]
  - interactionHistory: [Interaction]

VoxelBlock:
  - position: (x, y, z)
  - type: BlockType (trunk, branch, leaf, flower, moss, snow)
  - color: Color
  - placedAt: Date
  - source: GrowthSource (autonomous, touch, color, word)

Interaction:
  - timestamp: Date
  - type: InteractionType (open, touch, color, word)
  - value: String? (color hex or word)
  - touchPosition: (x, y, z)?
```

### Growth engine

The growth engine runs on app open. It calculates elapsed time since last open and determines what growth occurred:

1. Calculate elapsed hours since last growth evaluation
2. For each "growth tick" (roughly 1 per hour):
   - Determine current season from real-world date
   - Evaluate autonomous growth rules (branch extension, leaf addition, seasonal changes)
   - Apply any pending user interactions
3. Add new VoxelBlocks to the tree
4. Animate the additions subtly

Tree generation uses the recursive tree builder validated in Phase 1-2 prototypes, with parameters controlled by seed + time + user interaction history.

### Rendering

- SceneKit with SCNBox nodes for each voxel
- Shared geometries per color for performance
- Target: 60fps with up to 2000 voxel blocks
- Directional light + ambient light + optional point lights for glow

## 8. Retention design

Kodama does not chase the user. Instead, it creates reasons to return.

### The tree changed

Every time you open the app, the tree is different. Maybe a new branch appeared. Maybe leaves changed color. Maybe snow melted. The change is always subtle, never dramatic — but always there. "What happened while I was away?" is the pull.

### Seasonal anticipation

Real-world seasons create natural anticipation. "What will my tree look like in autumn?" "Will it snow this year?" The first cherry blossom of spring is a reward that requires no action — just time.

### Your history is visible

Over months, the tree carries visible history. Colored blocks from past interactions. Branch directions influenced by words. Moss from a period of quiet neglect (not punishment — beauty). The tree is a living journal you never have to write in.

### No punishment, ever

Periods of not opening the app result in autonomous growth — possibly the most interesting kind. A tree left alone for a month develops "wild" growth that looks different from a carefully tended tree. Both are beautiful. The user who opens daily and the user who opens monthly have equally valid trees.

## 9. Competitive position

| App | What it does | How Kodama differs |
|-----|-------------|-------------------|
| Finch | Virtual pet + self-care tasks | Kodama has no tasks, no gamification, no pet personality |
| Forest | Focus timer grows a tree | Kodama's tree grows without productivity goals |
| Avocation | Habit tracker + plant growth | Kodama has no habits to track |
| Voidpet Garden | Emotion creatures + CBT journal | Kodama has no therapy framework, no quests |
| Calm / Headspace | Meditation content library | Kodama has zero content — just a tree |

Kodama's unique position: **an app that asks nothing and offers presence**. No tasks, no content, no tracking, no goals. Just a living thing that shares your time.

No existing app combines voxel art + bonsai + autonomous growth + optional emotional interaction.

## 10. Monetization

Freemium model. The free experience is complete — one bonsai tree, full interaction, unlimited time.

### Free tier

- One bonsai tree
- All interaction layers (touch, color, word)
- Full seasonal cycle
- Autonomous growth
- Rotate and zoom

### Premium tier (estimated ¥480/month or ¥3,800/year)

- Additional tree species (different branching patterns, leaf shapes)
- Moss terrarium mode (future — v2)
- Tree gallery (save snapshots, view growth timeline)
- Custom pot styles
- Export tree as 3D rotating image / video for sharing
- Multiple trees (tend a small collection)

### Paywall design

Premium tree species are shown as locked previews — the user can see the silhouette and style but not grow one. The beauty of the preview itself drives conversion.

## 11. Widget strategy

Widgets show a static snapshot of the current tree, rendered from the latest saved state.

| Size | Display | Interaction |
|------|---------|-------------|
| Small | Tree silhouette, current season colors | Tap opens app |
| Medium | Tree with more detail, season + day count | Tap opens app |
| Large | Full tree view + subtle color palette for quick interaction | Tap color → absorbed into tree |

The widget serves as a quiet reminder that the tree exists — a small life on your home screen.

## 12. Marketing synergy

Kodama amplifies the focuswave brand:

- **Instagram**: Tree screenshots are inherently shareable — beautiful voxel art on dark backgrounds. "My tree at 6 months" posts. No captions needed.
- **X (@focuswaveapp)**: Development journey in Japanese. Voxel bonsai creation process. Technical insights.
- **Portfolio**: Smart Photo Diary (visual memory) + Flowease (physical wellbeing) + Kodama (quiet presence) = "apps for being, not doing"

## 13. Brand alignment

Kodama is the most focuswave app imaginable. The concentric ripple becomes the rings inside a tree trunk. The dark, minimal aesthetic becomes a moonlit bonsai. The philosophy of "asking nothing" becomes a tree that grows whether you're there or not.

The voxel style adds something new to the brand: warmth. focuswave has been sleek and dark. Kodama introduces craft, texture, and a living thing. The brand evolves from "zen minimalism" to "zen life."

## 14. Future vision (v2+)

### Moss terrarium mode

A glass jar containing a miniature world — voxel moss, tiny mushrooms, small ferns, a water pool. Same interaction principles, different aesthetic. The jar as a "closed world" vs. the bonsai as an "open world."

### The frog

A small voxel frog that lives near the bonsai. No name, no reactions, no gamification. Sometimes visible, sometimes hidden. Part of the scene, like moss or wind. The Claude Code crab philosophy.

### Sound

Optional ambient sound that responds to the tree's state. Wind through branches, rain on leaves, snow silence. Not music — environmental sound. Off by default.

### AR mode

Place your bonsai on your real desk using ARKit. See your tree in the real world.

### Music / photo influence

As explored in Mood Garden concept: listening history or photo colors subtly influence the tree's growth palette. Invisible to the user — they discover the influence themselves.

---

*Confidential — focuswave 2026*
