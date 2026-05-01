# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build
swift build

# Run app
swift run

# Run all tests
swift test

# Run specific test file
swift test --filter TestClassName

# Clean build
swift package clean && swift build
```

## Architecture Overview

The app is layered around a **shared playback clock** that synchronizes audio playback with gameplay timing.

### Layer Structure

**App** (`Sources/App/`) — Window state, transport controls, BPM/offset tuning, scene integration via `PrototypeGameController`

**Audio** (`Sources/Audio/`) — Playback and note scheduling. **Critical: timing-sensitive layer.**
- `AudioPlaybackController` — Song file playback, duration tracking
- `LaneSoundPlayer` — Drum sample synthesis/playback with per-lane AVAudioPlayerNode instances
- `MusicalTransport` — Bar/beat/subdivision calculation from playback time
- `PlaybackClock` / `PreviewPlaybackClock` — Time source for entire app

**GameCore** (`Sources/GameCore/`) — Pure Swift game logic (lanes, notes, judgments, scoring)

**Rendering** (`Sources/Rendering/`) — SpriteKit scene, note highway, visual feedback

**Input** (`Sources/Input/`) — Keyboard (and later Maschine MK3) input routing

**Charts** (`Sources/Charts/`) — MIDI chart loading and parsing

## Audio System Details

### Per-Lane Architecture
Each `Lane` (purple/kick, red/snare, yellow/closed-hat, blue/tom, green/crash) has its own dedicated `LaneSoundPlayer` instance with its own `AVAudioPlayerNode`. **All players share one `AVAudioEngine`.**

Benefits:
- No buffer queue contention between lanes
- Repeated notes on one lane don't block another lane
- Green lane (crash) can interrupt itself independently

### Scheduling & Interrupt Logic

Notes are scheduled via the 60Hz main timer (`startPlaybackTimer`), integrated directly into the playback timer tick (not a separate background scheduler):

```swift
// In startPlaybackTimer:
if timerFireCount % 6 == 0 {
    self.syncTransportState()  // UI updates
}
self.scheduleDueNotes()  // Always: schedule notes in 200ms lookahead window
```

**Interrupt behavior (per-lane):**
- **Green lane (crash/open hi-hat)**: `interrupt: true` — cuts off previous notes
- **All other lanes**: `interrupt: false` — queueing natural, no interruption

### Sample Loading

Drum sounds can be either:
1. **Loaded from WAV files** — `Sources/Audio/Samples/*.wav`
2. **Procedurally synthesized** — fallback if no sample found (see `makeBuffer`)

Sample loading with format conversion:
- Loads WAV as `AVAudioFile`
- Converts stereo→mono if needed (mix channels to mono)
- Creates buffer copies per note (not reusing buffer instances)
- Applies per-lane volume scaling (e.g., green lane at 50% volume)

**Key file:** `LaneSoundPlayer.swift` — `loadSampleBuffer()`, `getBuffer()`, `scaleVolume()`

### Buffer Synthesis Parameters

Synthesized drums use sine + noise with exponential decay. Parameters per lane in `makeBuffer()`:

```swift
case .yellow:      // Closed hi-hat
    duration=0.04s, frequency=1400Hz, noiseMix=0.75, amplitude=0.12
case .green:       // Crash (fallback if no sample)
    duration=0.12s, frequency=150Hz,  noiseMix=0.30, amplitude=0.50
```

## Audio Timing Context

**Critical constraint:** Audio playback must stay in sync with visual note timing and UI rendering. Recent work fixed:

1. **Main thread dispatch delays** — Eliminated by integrating lookahead into 60Hz timer (was causing 15-20ms variance)
2. **Synthesis CPU load** — Moved buffer synthesis to background thread (maintains main thread responsiveness)
3. **Buffer queue contention** — Per-lane players allow independent scheduling without cross-lane blocking

**When modifying audio scheduling:**
- Do NOT move scheduling off main thread again (causes sync loss with UI)
- Do NOT revert to single shared player (causes repeated-note queueing issues)
- Test on charts with repeated note clusters (Kill Bill, Blinding Lights bars 5-7)

## Key Testing Notes

Test suite covers:
- Chart loading and MIDI parsing
- Musical timing (bar/beat/subdivision calculations)
- Lane normalization and note assignment
- Gameplay scene rendering and note positioning
- Audio scheduling (see `LaneSoundPlayerSchedulingTests.swift`)

Run tests frequently during audio changes — regressions are easy on timing-critical code.

## Common Workflows

**Adding a new drum sample:**
1. Copy `.wav` to `Sources/Audio/Samples/`
2. Map lane in `LaneSoundPlayer.loadSampleBuffer()` sampleFilenames dict
3. Add volume scaling if needed in `scaleVolume()` switch
4. Test interrupt behavior (does it need to cut off itself? set lane in `schedule()` check)

**Tuning audio timing:**
- Modify `scheduleDueNotes()` lookahead window or scheduling logic
- Modify per-lane interrupt behavior in `schedule()`
- **Always test on repeated-note clusters first**

**Debugging sync issues:**
- `PrototypeGameController.globalTime` is the authoritative playback position
- `AudioPlaybackController.currentTime` computed from engine's render time
- Mismatch = timing drift (check anchor updates and seek behavior)

## Performance Notes

- 60Hz main timer is the scheduling heartbeat — no lower-latency thread needed
- Background synthesis thread is `.userInitiated` QoS (high priority)
- Per-lane players are lightweight (one AVAudioPlayerNode each)
- Metronome uses same audio engine (doesn't interrupt, queues naturally)

## 🧠 Autonomous Self-Improvement & Learning

At the end of each session, learnings are reviewed and patterns that should become persistent guidance are identified. This section documents those learnings so that future Claude sessions can apply them immediately.

### Session Learnings (updated 2026-04-25)

**Audio Timing:**
- Lookahead scheduling on 60Hz main thread (not background threads) keeps audio in sync with UI
- Per-lane AVAudioPlayerNode instances prevent cross-lane blocking
- Sample-accurate scheduling with AVAudioTime causes lag — use nil scheduling + synthesize on background instead
- Green lane (crash) interrupts to handle repeated notes; other lanes queue naturally
- Volume adjustments: Apply AFTER synthesis to buffer copies, not during synthesis

**Testing & Iteration:**
- Test on specific patterns: repeated note clusters (Blinding Lights bar 5-7), double kicks, rapid samples
- Mute/solo button consistency requires matching lane IDs across UI, button handlers, and filtering logic — use `Lane.displayName.lowercased()` everywhere
- When timing regresses, revert immediately and try different approach — don't iterate on broken paths

