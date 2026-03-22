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

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Architecture

- `Sources/App` — SwiftUI shell, HUD, gameplay controller, and transport controls
- `Sources/Audio` — playback clock, audio loading, and MIDI import scaffolding
- `Sources/GameCore` — models and timing/judgment logic
- `Sources/Input` — input abstractions, routing, and keyboard device support
- `Sources/Rendering` — SpriteKit gameplay scene and bridge view
- `Docs/ARCHITECTURE.md` — architecture notes and next steps

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.
4. Optionally choose an audio file from the transport bar to test song-backed timing.

This package is macOS-only because it uses SwiftUI, AppKit, SpriteKit, and AVFoundation.

## Current prototype pass

This pass starts moving the prototype from a pure preview timer toward real song-driven gameplay timing.

Implemented in this pass:

1. `AudioPlaybackController` with file picker + AVAudioPlayer-backed transport
2. `PreviewPlaybackClock` fallback so the prototype still works without a loaded song
3. Shared playback clock wiring from app controller into the gameplay scene
4. Transport UI for choosing audio, play, pause, and displaying current playback time
5. `MIDIChartLoader` scaffold for the upcoming chart-import pass

## Next milestones

1. MIDI/chart parsing into lane events
2. Bind chart timing to imported song structure instead of the hardcoded prototype chart
3. Calibration UI and timing offsets
4. Maschine MK3 device detection and input adapter
5. Expanded note rendering and lane-specific art
