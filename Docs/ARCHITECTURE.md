# MasterOfDrums Architecture

## Stack

- SwiftUI for app shell and settings-oriented UI
- SpriteKit for gameplay rendering and the note highway
- Pure Swift game core for timing, note scheduling, and judgment
- Input routing layer for normalized lane-hit events
- Later: CoreMIDI / HID for Maschine MK3 integration

## Layers

### App
Owns window structure, high-level screen state, and bridges SwiftUI to the gameplay scene.

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

## Prototype constraints

This prototype intentionally still avoids:

- Maschine-specific code
- audio playback
- chart import from MIDI
- calibration persistence

The goal is to validate that the Mac app structure and gameplay feel are viable before adding hardware-specific complexity.

## What changed in pass 2

- Keyboard input is no longer hard-coded directly into gameplay logic.
- The SpriteKit scene now emits normalized input events.
- The app controller owns routing and judgment handling.
- HUD state now exposes hits, misses, and active input source.
- Lane flashes make successful/failed interaction more legible while testing.

## Next hardware integration step

Add a Maschine-backed device implementation that conforms to the same input contracts:

- `MaschineInputDevice`
- `MaschinePadMapper`
- `InputRouter` device switching / discovery
- transport controls for calibration and clock sync

That will let the rest of the app consume normalized lane hit events regardless of source.
