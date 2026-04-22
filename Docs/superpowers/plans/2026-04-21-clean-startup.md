# Clean App Startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove auto-restoration of previous chart/audio at startup so the app launches in a clean, stopped state with no content loaded.

**Architecture:** Delete the single line that calls `restoreLastOpenedSessionIfPossible()` in `init()`. The app will initialize with empty session, no timers running, button showing "Play", display at 0.0.0.000. The explicit `stop()` calls already in place at the end of init will ensure clean state.

**Tech Stack:** Swift, SwiftUI, AVFoundation

---

## File Structure

**Modified:**
- `Sources/App/PrototypeGameController.swift` — Remove one line (304) from `init()`

**Tests:**
- No new tests needed. Existing 166 tests should still pass.
- Manual verification: startup state, play/stop button behavior

---

## Task 1: Remove Auto-Restoration Call

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift:304`

- [ ] **Step 1: Locate the line to remove**

Open `Sources/App/PrototypeGameController.swift` and find the `init()` function. Look for the line:
```swift
restoreLastOpenedSessionIfPossible()
```

It should be around line 304 in the init function, after the `updateAdminHistoryAvailability()` call and before the `audio.stop()` call.

- [ ] **Step 2: Delete the line**

Remove the entire line:
```swift
restoreLastOpenedSessionIfPossible()
```

Leave the surrounding lines intact:
```swift
updateAdminHistoryAvailability()
// restoreLastOpenedSessionIfPossible() <- DELETE THIS LINE
audio.stop()
```

- [ ] **Step 3: Verify the change**

The `init()` function should now have this sequence near the end:
```swift
syncState()
updateStepCursorDisplay()
updatePlaybackRateText()
updateLoopStatusText()
scene.selectedAdminNoteID = adminSelectedNoteID
updateAdminHistoryAvailability()
audio.stop()
chartPreviewClock.stop()
isChartOnlyPlaybackEnabled = false
isInitializing = false
syncTransportState()
```

- [ ] **Step 4: Build the app**

Run:
```bash
swift build
```

Expected: Build succeeds with no errors.

- [ ] **Step 5: Run all tests**

Run:
```bash
swift test
```

Expected: All 166 tests pass.

- [ ] **Step 6: Commit the change**

Run:
```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "fix: disable auto-restoration at startup for clean initialization

Removes the restoreLastOpenedSessionIfPossible() call from init() so the app
launches in a clean state with no chart or audio loaded. Button shows 'Play',
display shows 0.0.0.000, and nothing is advancing.

Fixes the auto-play issue where the app appeared to be playing immediately
upon launch."
```

---

## Task 2: Manual Verification of Startup Behavior

- [ ] **Step 1: Launch the app**

Run the app in the simulator or on your machine:
```bash
swift run MasterOfDrums
```

Wait for the app to fully launch.

- [ ] **Step 2: Verify button state**

Check the transport control button. It should say **"Play"** (not "Stop").

Expected result: Button displays "Play"

- [ ] **Step 3: Verify display state**

Check the position display (the time readout showing Bar.Beat.Division.Tick format). It should show **`0.0.0.000`** (or similar starting position).

Expected result: Display shows `0.0.0.000`

- [ ] **Step 4: Verify no advancing**

Watch the position display for 2-3 seconds without touching anything. The numbers should **NOT change**.

Expected result: Display is static, no advancing time

- [ ] **Step 5: Verify clean state indicators**

Look at the app status/debug area (if visible). It should indicate:
- No chart loaded
- No audio loaded
- Transport state is "Stopped"

Expected result: App shows idle state with no content

---

## Task 3: Verify Play/Stop Functionality After Fix

- [ ] **Step 1: Click the Play button**

With the app idle (from Task 2), click the "Play" button.

Expected result: Button changes to say "Stop"

- [ ] **Step 2: Verify nothing happens**

Since there's no chart or audio loaded, nothing audible should happen, but the button state changed. That's correct.

Expected result: Button says "Stop" but no sound/visuals advance (no content to play)

- [ ] **Step 3: Click Stop button**

Click the "Stop" button to return to idle state.

Expected result: Button changes back to "Play", display returns to static

- [ ] **Step 4: Load a chart manually**

Using the UI, load a chart file:
- Click on the admin/chart load button
- Select a chart file that has notes

Expected result: Chart loads and appears in the timeline

- [ ] **Step 5: Click Play**

Click the "Play" button to start playback of the loaded chart.

Expected result:
- Button shows "Stop"
- Display time advances
- If audio is working correctly, drum sounds play at scheduled times

- [ ] **Step 6: Click Stop**

Click the "Stop" button to pause playback.

Expected result:
- Button shows "Play"
- Display time stops advancing
- Any audio stops immediately

- [ ] **Step 7: Click Play again**

Click "Play" to resume playback.

Expected result: Playback resumes correctly from where it was stopped

---
