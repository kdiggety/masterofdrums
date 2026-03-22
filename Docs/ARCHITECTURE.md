# MasterOfDrums Architecture

## Stack

- SwiftUI for app shell and settings-oriented UI
- SpriteKit for gameplay rendering and the note highway
- Pure Swift game core for timing, note scheduling, and judgment
- Input routing layer for normalized lane-hit events
- Audio transport layer for playback clock ownership and file-backed song playback
- Musical transport layer for bar/beat/subdivision display and BPM/offset conversion
- Lightweight BPM detection from file metadata / filename hints
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

The app now treats playback time as shared state and derives both seconds and musical-position UI from it. It also attempts to prefill BPM from the loaded asset when possible.

### GameCore
Contains the lane model, chart model, note timing, hit windows, and scoring state.

### Input
Owns device-specific event capture and transforms it into normalized `InputEvent` values that the gameplay controller can consume.

Current prototype types:

- `InputDevice`
- `InputRouter`
- `LaneMapping`
- `KeyboardInputDevice`
- `DefaultKeyboardLaneMapper`

### Rendering
Contains the SpriteKit scene plus adapters to render notes and judgments from `GameCore` state.
The rendering layer consumes an injected playback clock via `timeProvider`.

## Prototype constraints

This prototype intentionally still avoids:

- Maschine-specific code
- real MIDI note parsing into lanes
- robust DSP-grade beat tracking as the authoritative source of timing
- calibration persistence
- chart editor tooling

The current path is: shared playback clock → musical transport UI → BPM prefill helpers → MIDI/chart import → hardware input.

## What changed in pass 6

- Moved transport and tempo controls into a side panel to restore lane height.
- Added BPM prefill from audio metadata when present.
- Added filename-based BPM fallback for common tagged files.
- Kept manual BPM/offset controls as the final override.
- Preserved the gameplay view as the main visual focus.

## Next gameplay integration step

Implement real chart import and timing binding:

- `MIDIChartLoader` parses note-on/note-off and tempo metadata
- lane mapping from MIDI pitches / tracks into `Lane`
- gameplay session consumes imported `Chart` instead of `.prototype`
- optional song+chart pairing metadata
- eventually add stronger beat estimation only as a helper when explicit tempo data is missing

Once that is stable, hardware input becomes another event source feeding the same timing system.
