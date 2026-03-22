# MasterOfDrums Architecture

## Stack

- SwiftUI for app shell and settings-oriented UI
- SpriteKit for gameplay rendering and the note highway
- Pure Swift game core for timing, note scheduling, and judgment
- Later: CoreMIDI / HID for Maschine MK3 integration

## Layers

### App
Owns window structure, high-level screen state, and bridges SwiftUI to the gameplay scene.

### GameCore
Contains the lane model, chart model, note timing, hit windows, and scoring state.

### Rendering
Contains the SpriteKit scene plus adapters to render notes and judgments from `GameCore` state.

## Prototype constraints

This initial prototype intentionally avoids:

- Maschine-specific code
- audio playback
- chart import from MIDI
- calibration persistence

The goal is to validate that the Mac app structure and gameplay feel are viable before adding hardware-specific complexity.

## Next hardware integration step

Add an `Input` layer with:

- `InputDevice`
- `InputRouter`
- `LaneMapper`
- `MaschineMIDIInputDevice`
- `KeyboardInputDevice`

That will let the rest of the app consume normalized lane hit events regardless of source.
