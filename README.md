# MasterOfDrums

Initial macOS-native prototype scaffold for a rhythm drumming app designed around the Native Instruments Maschine MK3.

## Prototype goals

This first prototype focuses on:

- SwiftUI app shell for macOS
- SpriteKit-powered note highway scene
- Pure Swift gameplay core types for lanes, notes, charts, and judgments
- Keyboard fallback input so the prototype is testable before Maschine integration
- Basic scoring, combo, and hit feedback

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Architecture

- `Sources/App` — SwiftUI shell and root views
- `Sources/GameCore` — models and timing/judgment logic
- `Sources/Rendering` — SpriteKit gameplay scene and bridge view
- `Docs/ARCHITECTURE.md` — architecture notes and next steps

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.

This package is macOS-only because it uses SwiftUI and SpriteKit.

## Next milestones

1. Maschine MK3 device detection and input abstraction
2. Real song timing and playback clock
3. Calibration UI
4. Chart import format
5. Expanded note rendering and lane-specific art
