# Single Timer-Driven Global Clock Design

**Date:** 2026-04-21  
**Problem:** Sounds don't trigger at all in chart-only mode. Root cause: inconsistent clock sources per playback mode (audio.currentTime vs chartPreviewClock.currentTime) break timing synchronization.  
**Goal:** Single elapsed-wall-time timer drives globalTime in all modes (audio-only, chart-only, audio+chart). All components respond to globalTime via listener pattern.

---

## Overview

**Core principle:** Elapsed wall time is the single source of truth. One timer advances globalTime uniformly across all playback modes. Audio engine and chart preview clock respond to globalTime changes via listener pattern. Controls (play, stop, scrub, step) interact with globalTime directly.

---

## Architecture

### Single Playback Timer

**One timer advances globalTime during active playback:**
- Runs at 60Hz when playback is active
- Calculates: `globalTime.time = playbackStartAnchor + (elapsed × playbackRate)`
- Respects playback rate adjustments (100%, 75%, 50%)
- Cancels when stop is called (freezes time)

**Replaces:** Current `chartPreviewTimerCancellable` which reads from inconsistent sources

### Event Flow

**During playback:**
```
Timer fires every frame
  ↓
Calculates elapsed time × playbackRate
  ↓
Updates globalTime.time
  ↓
globalTime.didChange fires
  ↓
Audio engine listener seeks (if audio loaded)
Chart preview clock listener seeks (if chart-only)
  ↓
UI updates display (reads globalTime.time)
Lookahead scheduler schedules sounds (reads globalTime.time)
```

**When user controls interact (play, stop, scrub, step):**
- Controls call `globalTime.seek(to: newPosition, from: .source)`
- This triggers the listener, which seeks audio/chart
- Timer resumes from new position (or stays cancelled if stopped)
- Time can move forward or backward

### Sound Scheduling

**Lookahead scheduler:**
- Runs every 16ms reading `globalTime.time`
- Finds notes due in window: `[globalTime.time, globalTime.time + 0.2s]`
- Calls `laneSoundPlayer.play()` for each due note
- Multiple notes at the same time all schedule at identical audio engine sample time (play simultaneously, mixed)

**Why this now works:** globalTime advances uniformly in all modes, providing consistent input to the scheduler.

---

## Mode Behavior (Unified)

All three modes use identical timer logic. Only difference is which components are active:

### Audio + Chart Mode
- Timer drives globalTime
- Audio engine plays backing track (listens to globalTime, seeks to stay in sync)
- Chart preview clock seeks to match globalTime
- Sounds trigger from lookahead scheduler

### Chart-Only Mode
- Timer drives globalTime (same as audio+chart)
- Audio engine can be idle (no backing track)
- Chart preview clock seeks to match globalTime
- Sounds trigger from lookahead scheduler ← **Fixes the core issue**

### Audio-Only Mode
- Timer drives globalTime
- Audio engine plays backing track
- No chart involved
- No sound scheduling (no chart notes)

---

## Control Behavior (Preserved)

**Play button:**
- Starts the playback timer
- Records current time as anchor
- Timer advances globalTime from that point

**Stop button:**
- Cancels the playback timer
- Freezes globalTime at current position
- Time does not advance until play is clicked again

**Position slider / Lane scrubbing / Step navigation:**
- User action → `globalTime.seek(to: newPosition, from: .source)`
- Listener seeks audio/chart to match new position
- Timer continues from new position
- Time can move forward or backward

**Playback rate change:**
- User adjusts rate (100% → 75%)
- Timer continues running, but multiplies elapsed time by new rate
- globalTime advances at new speed going forward
- No seeking needed; just rate adjustment takes effect immediately

---

## Key Properties

**Single clock source:** Timer (elapsed wall time) — not audio.currentTime or chartPreviewClock.currentTime

**Playback rate:** Multiplies how fast elapsed time advances globalTime

**Time advancement:** Only during active playback (timer running). Frozen when stopped.

**Time direction:** Forward during normal playback. Can move backward via manual controls (scrub, step).

**Synchronization:** Audio engine and chart preview clock seek to stay in sync with globalTime via listener. Lookahead scheduler reads globalTime for consistent scheduling across all modes.

---

## What Changes

1. **Create new playback timer** that calculates `globalTime.time = anchor + (elapsed × playbackRate)` every frame
2. **Replace activeTransportTime as clock driver** — remove its role in driving globalTime
3. **Keep globalTime listener pattern** — already implemented, continues to work
4. **Keep control behavior unchanged** — they call globalTime.seek() as before
5. **Playback rate impacts timer speed** — already have playbackRate property, just use it in timer calculation
6. **Audio engine can be idle in chart-only** — no need for dummy audio

---

## Constraints & Guarantees

- **No breaking changes to scrubbing:** Controls continue to work via globalTime.seek()
- **Sounds trigger in all modes:** Consistent globalTime makes scheduler reliable
- **Time doesn't advance when stopped:** Timer is cancelled
- **Time freezes at manual seek position:** globalTime.seek() freezes time until timer resumes
- **Multiple simultaneous notes:** All scheduled at same audio engine sample time, play together
- **Playback rate affects everything:** Display speed, note travel speed, audio speed

---

## Testing

Manual verification:
- [ ] App plays audio + chart: sounds trigger in sync with display
- [ ] Chart-only playback: sounds trigger in sync with display
- [ ] Stop button: time freezes immediately
- [ ] Position slider: scrub forward/backward, sounds trigger correctly
- [ ] Lane scrubbing: move playhead backward, sounds trigger at correct times
- [ ] Playback rate 75%: display and sounds advance at 75% speed
- [ ] Multiple notes at same time: all play simultaneously

---

## Files to Modify

- `Sources/App/PrototypeGameController.swift` — Replace timer logic, remove activeTransportTime as driver
- `Sources/App/GlobalMusicalTime.swift` — No changes needed
- `Sources/Audio/AudioPlaybackController.swift` — No changes needed
- `Sources/Audio/LaneSoundPlayer.swift` — No changes needed
