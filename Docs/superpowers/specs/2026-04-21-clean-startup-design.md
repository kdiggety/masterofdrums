# Clean App Startup Design

**Date:** 2026-04-21  
**Problem:** App auto-plays at startup, showing "Stop" button and advancing display when it should be idle  
**Goal:** App launches in clean state with no content, no playback, ready for user to load content

---

## Overview

The app currently auto-restores the previously opened chart/audio at startup via `restoreLastOpenedSessionIfPossible()`. This restoration process inadvertently triggers playback, causing the display to advance and the button to show "Stop" even though the user hasn't interacted with the app yet.

The solution is to disable auto-restoration and ensure the app always starts in a clean, stopped state.

---

## Design

### 1. Disable Auto-Restoration

**Current behavior:**
- `init()` calls `restoreLastOpenedSessionIfPossible()` at line 303
- This loads the last chart and audio from disk
- Triggers `applyChart()` → `loadChart()` → `applyChart()` → state updates

**New behavior:**
- **Remove** the call to `restoreLastOpenedSessionIfPossible()` entirely
- App launches with empty session (no chart, no audio)

**Why this is clean:**
- The auto-restoration was causing the bug in the first place
- Removes a source of complexity during initialization
- User can explicitly load content when ready (intentional, not surprising)

### 2. Explicit Clean State at Init End

Keep the explicit stops already added:
```swift
audio.stop()
chartPreviewClock.stop()
isChartOnlyPlaybackEnabled = false
```

This ensures any lingering state from initialization cleanup is neutralized.

### 3. Startup Guarantees

After init completes:
- `audio.state` = `.stopped`
- `chartPreviewClock.state` = `.stopped`
- `isChartOnlyPlaybackEnabled` = `false`
- `transportStateText` = "Stopped"
- Button displays "Play"
- Display shows `0.0.0.000` (no advancing)
- No timers running

### 4. User-Initiated Loading

User loads content by:
- Clicking "Open Chart" button → `chooseChartFile()` → loads and plays (optional)
- Clicking "Open Audio" button → `chooseAudioFile()` → loads and pauses
- Then clicking "Play" to start playback

---

## Implementation Plan

1. Delete the `restoreLastOpenedSessionIfPossible()` call from `init()` (line 303)
2. Verify app builds and all tests pass
3. Verify startup state: button says "Play", display is static, no advancing
4. Verify clicking Play starts playback correctly
5. Verify Play/Stop button works normally after that

---

## Risk & Mitigation

**Risk:** User loses convenience of auto-restoring previous session  
**Mitigation:** This is acceptable trade-off for correctness. The bug made the app unpredictable; a clean startup is more important than auto-restoration.

---

## Testing

Manual verification:
- [ ] App launches with "Play" button visible
- [ ] Display shows `0.0.0.000` and is NOT advancing
- [ ] Load a chart → chart appears in timeline
- [ ] Click Play → chart plays, display advances, button shows "Stop"
- [ ] Click Stop → display stops, button shows "Play"
- [ ] Click Play again → chart plays correctly
- [ ] Load audio + chart → same play/stop behavior works

---

## Files to Modify

- `Sources/App/PrototypeGameController.swift` — delete the `restoreLastOpenedSessionIfPossible()` call at line 304
