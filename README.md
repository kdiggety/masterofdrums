# MasterOfDrums

Initial macOS-native prototype scaffold for a rhythm drumming app designed around the Native Instruments Maschine MK3.

## Prototype goals

This prototype currently covers:

- SwiftUI app shell for macOS
- SpriteKit-powered note highway scene
- Pure Swift gameplay core types for lanes, notes, charts, and judgments
- Routed input layer with a keyboard fallback device
- Basic scoring, combo, miss tracking, and hit feedback

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Architecture

- `Sources/App` — SwiftUI shell, HUD, and gameplay controller
- `Sources/GameCore` — models and timing/judgment logic
- `Sources/Input` — input abstractions, routing, and keyboard device support
- `Sources/Rendering` — SpriteKit gameplay scene and bridge view
- `Docs/ARCHITECTURE.md` — architecture notes and next steps

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.

This package is macOS-only because it uses SwiftUI, AppKit, and SpriteKit.

## Current prototype pass

This pass moves input handling out of the gameplay scene and into a dedicated input layer so the app can accept normalized lane-hit events from multiple device types later.

Implemented in this pass:

1. `InputSource`, `InputEvent`, and `InputDevice` building blocks
2. `InputRouter` for normalized event delivery
3. `KeyboardInputDevice` + key-to-lane mapper
4. HUD updates for hits, misses, and active input source
5. Lane flash feedback on hits

## Next milestones

1. Maschine MK3 device detection and input adapter
2. Real song timing and playback clock
3. Calibration UI
4. Chart import format
5. Expanded note rendering and lane-specific art
