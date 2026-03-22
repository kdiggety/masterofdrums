# MasterOfDrums Architecture

## Stack

- SwiftUI for app shell and settings-oriented UI
- SpriteKit for gameplay rendering and the note highway
- Pure Swift game core for timing, note scheduling, and judgment
- Input routing layer for normalized lane-hit events
- Audio transport layer for playback clock ownership and file-backed song playback
- Later: CoreMIDI / HID for Maschine MK3 integration

## Layers

### App
Owns window structure, screen state, transport controls, and bridges SwiftUI to the gameplay scene.

### Audio
Owns song playback and timing.

Current prototype types:

- `PlaybackClock`
- `PreviewPlaybackClock`
- `AudioPlaybackController`
- `MIDIChartLoader` (scaffold)

The app now treats playback time as shared state instead of letting the rendering layer invent its own clock.

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
The rendering layer now consumes an injected playback clock via `timeProvider`.

## Prototype constraints

This prototype intentionally still avoids:

- Maschine-specific code
- real MIDI note parsing into lanes
- calibration persistence
- chart editor tooling

The goal is now shifting from “prove the app shell works” to “prove playback-driven rhythm timing works before adding hardware-specific complexity.”

## What changed in pass 4

- Added a dedicated audio/transport layer.
- Added a file picker for loading a backing track on macOS.
- Added AVAudioPlayer-backed playback state and current-time reporting.
- Kept a preview fallback clock so the prototype remains usable without assets in-repo.
- Rewired gameplay timing to use a shared playback clock instead of a scene-owned timer.
- Added a MIDI import scaffold to make the next chart pass incremental instead of invasive.

## Next gameplay integration step

Implement real chart import and timing binding:

- `MIDIChartLoader` parses note-on/note-off and tempo metadata
- lane mapping from MIDI pitches / tracks into `Lane`
- gameplay session consumes imported `Chart` instead of `.prototype`
- optional song+chart pairing metadata

Once that is stable, hardware input becomes another event source feeding the same timing system.
