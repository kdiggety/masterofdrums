# MasterOfDrums

Initial macOS-native prototype scaffold for a rhythm drumming app designed around the Native Instruments Maschine MK3.

## Prototype goals

This prototype currently covers:

- SwiftUI app shell for macOS
- SpriteKit-powered note highway scene
- Pure Swift gameplay core types for lanes, notes, charts, and judgments
- Routed input layer with a keyboard fallback device
- Basic scoring, combo, miss tracking, and hit feedback
- Audio transport scaffolding with a shared playback clock
- Musical transport display with manual BPM and song-offset controls

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Architecture

- `Sources/App` — SwiftUI shell, HUD, gameplay controller, transport controls, and BPM/offset tuning
- `Sources/Audio` — playback clock, audio loading, musical transport math, and MIDI import scaffolding
- `Sources/GameCore` — models and timing/judgment logic
- `Sources/Input` — input abstractions, routing, and keyboard device support
- `Sources/Rendering` — SpriteKit gameplay scene and bridge view
- `Docs/ARCHITECTURE.md` — architecture notes and next steps

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.
4. Optionally choose an audio file from the transport bar to test song-backed timing.
5. Use the BPM and Offset controls to align the musical transport with the song.

This package is macOS-only because it uses SwiftUI, AppKit, SpriteKit, and AVFoundation.

## Current prototype pass

This pass makes the transport legible in musical units instead of seconds only.

Implemented in this pass:

1. Musical transport math for `bar:beat:subdivision` display
2. Manual BPM control in the UI
3. Manual song offset control in the UI
4. Live musical-position readout alongside seconds-based transport time
5. Architecture groundwork for real MIDI tempo/map import next

## Next milestones

1. MIDI/chart parsing into lane events and tempo metadata
2. Bind chart timing to imported song structure instead of the hardcoded prototype chart
3. Calibration UI and timing offsets persistence
4. Maschine MK3 device detection and input adapter
5. Expanded note rendering and lane-specific art
