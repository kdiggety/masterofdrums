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
- BPM auto-fill from metadata, filename, or lightweight audio analysis

## Current controls

The prototype uses keyboard keys mapped to lanes:

- `D` → Red
- `F` → Yellow
- `J` → Blue
- `K` → Green
- `Space` → Kick

## Running on macOS

1. Open the package in Xcode on your Mac.
2. Let Xcode resolve the package.
3. Run the `MasterOfDrums` executable target.
4. Choose an audio file from the side panel.
5. Check the BPM source (`Metadata`, `Filename`, `Analysis`, or `Manual`).
6. Use the BPM and Offset controls to fine-tune alignment.

## Current prototype pass

This pass pushes the timing UI closer to actual playtesting needs.

Implemented in this pass:

1. More compact header to preserve lane height
2. Primary transport display now emphasizes `bar:beat`
3. Subdivision moved to a secondary display
4. BPM detection now falls back to lightweight audio analysis when tags and filename hints fail
5. Manual BPM and offset override remain available

## Next milestones

1. Verify BPM analysis quality across a few real tracks
2. MIDI/chart parsing into lane events and tempo metadata
3. Bind chart timing to imported song structure instead of the hardcoded prototype chart
4. Calibration UI and timing offsets persistence
5. Maschine MK3 device detection and input adapter
