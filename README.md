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
- Side-panel transport UI to preserve playfield height
- BPM auto-fill from metadata or filename when available

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Architecture

- `Sources/App` — SwiftUI shell, HUD, gameplay controller, transport controls, and BPM/offset tuning
- `Sources/Audio` — playback clock, audio loading, musical transport math, BPM detection, and MIDI import scaffolding
- `Sources/GameCore` — models and timing/judgment logic
- `Sources/Input` — input abstractions, routing, and keyboard device support
- `Sources/Rendering` — SpriteKit gameplay scene and bridge view
- `Docs/ARCHITECTURE.md` — architecture notes and next steps

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.
4. Choose an audio file from the side panel.
5. Check whether BPM was auto-filled from metadata/filename; adjust manually if needed.
6. Use the BPM and Offset controls to align the musical transport with the song.

This package is macOS-only because it uses SwiftUI, AppKit, SpriteKit, and AVFoundation.

## Current prototype pass

This pass improves the usability of the transport/timing workflow while keeping the playfield large enough for testing.

Implemented in this pass:

1. Side-panel transport and tempo controls
2. Restored gameplay lane height by moving controls out of the top stack
3. BPM auto-detection from metadata when present
4. Filename-based BPM fallback for common tagged files like `songname-128bpm.mp3`
5. Manual BPM and offset override remain available

## Next milestones

1. Real BPM/beat analysis fallback beyond metadata and filename hints
2. MIDI/chart parsing into lane events and tempo metadata
3. Bind chart timing to imported song structure instead of the hardcoded prototype chart
4. Calibration UI and timing offsets persistence
5. Maschine MK3 device detection and input adapter
