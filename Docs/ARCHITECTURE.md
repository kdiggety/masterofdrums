# MasterOfDrums Architecture

## Stack

- SwiftUI for app shell and settings-oriented UI
- SpriteKit for gameplay rendering and the note highway
- Pure Swift game core for timing, note scheduling, and judgment
- Input routing layer for normalized lane-hit events
- Audio transport layer for playback clock ownership and file-backed song playback
- Musical transport layer for bar/beat/subdivision display and BPM/offset conversion
- Lightweight BPM detection from file metadata, filename hints, and audio analysis fallback
- Later: CoreMIDI / HID for Maschine MK3 integration

## Layers

### App
Owns window structure, screen state, transport controls, BPM/offset tuning, and bridges SwiftUI to the gameplay scene.

### Audio
Owns song playback and timing.

Current prototype types:

- `PlaybackClock`
- `PreviewPlaybackClock`
- `AudioPlaybackController`
- `MusicalTransport`
- `MIDIChartLoader` (scaffold)

The app now treats playback time as shared state and derives both seconds and musical-position UI from it. BPM prefill now tries metadata first, then filename hints, then lightweight signal analysis.

### Rendering
Contains the SpriteKit scene plus adapters to render notes and judgments from `GameCore` state.
The rendering layer consumes an injected playback clock via `timeProvider`.

## Prototype constraints

This prototype intentionally still avoids:

- Maschine-specific code
- real MIDI note parsing into lanes
- DSP-grade beat/downbeat tracking with confidence scoring
- calibration persistence
- chart editor tooling

The current path is: shared playback clock → musical transport UI → BPM helpers/analysis → MIDI/chart import → hardware input.

## What changed in pass 7

- Reduced header footprint further to preserve playfield height.
- Changed the transport emphasis to bar:beat first.
- Added audio-signal BPM estimation as a fallback when metadata is missing.
- Kept manual BPM/offset controls as the final authority.
- Preserved the side panel layout introduced in the prior pass.

## Next gameplay integration step

Implement real chart import and timing binding:

- `MIDIChartLoader` parses note-on/note-off and tempo metadata
- lane mapping from MIDI pitches / tracks into `Lane`
- gameplay session consumes imported `Chart` instead of `.prototype`
- optional song+chart pairing metadata
- later improve audio analysis to detect downbeats and confidence, but keep metadata/chart data authoritative when available
