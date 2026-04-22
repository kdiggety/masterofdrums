# Single Timer-Driven Global Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-source clock architecture with a single elapsed-wall-time timer that drives globalTime uniformly across all playback modes (audio-only, chart-only, audio+chart), fixing the issue where sounds don't trigger in chart-only mode.

**Architecture:** A 60Hz playback timer advances globalTime using elapsed wall time and playback rate: `globalTime.time = anchor + (elapsed × playbackRate)`. Audio engine and chart preview clock listen to globalTime changes and seek to stay in sync. Controls (play, stop, scrub, step) interact with globalTime directly. Lookahead scheduler reads from globalTime for consistent sound scheduling across all modes.

**Tech Stack:** Swift, SwiftUI, Combine (listener pattern), AVAudioEngine, Timers (Timer + DispatchSourceTimer)

---

## File Structure

**Modified:**
- `Sources/App/PrototypeGameController.swift` — Replace timer logic, track playback anchor/wall clock, replace activeTransportTime as driver

**No Changes Required:**
- `Sources/App/GlobalMusicalTime.swift` — Already has listener pattern via `didChange` PassthroughSubject
- `Sources/Audio/AudioPlaybackController.swift` — Already listens to globalTime changes
- `Sources/Audio/LaneSoundPlayer.swift` — Already reads from lookahead scheduler which reads globalTime

---

## Task 1: Add Playback Timer Properties

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Add timer properties and wall-clock anchors around line 200

**Context:**
Replace the old timer mechanism with properties that track:
- `playbackTimerCancellable`: The new 60Hz timer (replaces `chartPreviewTimerCancellable` in role)
- `playbackStartWallTime`: When playback started (in wall clock time)
- `playbackStartGlobalTime`: What globalTime was when playback started

- [ ] **Step 1: Locate the timer properties section**

Open `Sources/App/PrototypeGameController.swift` and find lines 199-201 where the current timers are defined:
```swift
private var chartPreviewTimerCancellable: AnyCancellable?
private var lookaheadSchedulerTimer: DispatchSourceTimer?
private var scheduledNoteIDs: Set<UUID> = []
```

- [ ] **Step 2: Replace chartPreviewTimerCancellable with new property**

Replace line 199 (`private var chartPreviewTimerCancellable: AnyCancellable?`) with:
```swift
private var playbackTimerCancellable: AnyCancellable?
private var playbackStartWallTime: Date?
private var playbackStartGlobalTime: Double = 0
```

The old `chartPreviewTimerCancellable` is no longer needed. The new `playbackTimerCancellable` will be the single timer for all modes.

Result: The file now has:
```swift
private var playbackTimerCancellable: AnyCancellable?
private var playbackStartWallTime: Date?
private var playbackStartGlobalTime: Double = 0
private var lookaheadSchedulerTimer: DispatchSourceTimer?
private var scheduledNoteIDs: Set<UUID> = []
```

- [ ] **Step 3: Commit the property changes**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "refactor: add playback timer properties for single-clock architecture

Replace chartPreviewTimerCancellable with playbackTimerCancellable and add
wall-clock anchors (playbackStartWallTime, playbackStartGlobalTime) to track
the playback position independently of audio/chart clock sources."
```

---

## Task 2: Implement Playback Timer Calculation Function

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Add helper function around line 2040 (after pauseTransport)

**Context:**
Create a function that calculates the current globalTime based on elapsed wall time and playback rate. This is the core of the new architecture.

- [ ] **Step 1: Locate where to add the function**

Find the `pauseTransport()` method in PrototypeGameController.swift (around line 1242). You'll add the new function after the `pauseTransport()` method ends.

- [ ] **Step 2: Add calculateCurrentPlaybackTime function**

After `pauseTransport()` method (which ends around line 1260), add this new function:

```swift
private func calculateCurrentPlaybackTime() -> Double {
    guard let startWallTime = playbackStartWallTime else { return 0 }
    let elapsedSeconds = Date().timeIntervalSince(startWallTime)
    let adjustedElapsed = elapsedSeconds * playbackRate
    return playbackStartGlobalTime + adjustedElapsed
}
```

This function:
- Takes the elapsed wall time since playback started
- Multiplies it by `playbackRate` (100%, 75%, 50%, etc.)
- Adds it to the anchor point (`playbackStartGlobalTime`)
- Returns the current playback position

- [ ] **Step 3: Verify the function is correct**

Skim the function. It should:
1. Return 0 if no playback anchor is set (not playing)
2. Calculate elapsed time from wall clock
3. Apply playback rate as a multiplier
4. Add to anchor time
5. Return the result as a Double

- [ ] **Step 4: Commit the new function**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "feat: add calculateCurrentPlaybackTime for wall-clock calculation

Calculates current playback position as: anchor + (elapsed × playbackRate).
This replaces reading from activeTransportTime (which came from inconsistent
sources). Returns adjusted elapsed wall time for use by the new timer."
```

---

## Task 3: Create New Playback Timer

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Replace startChartPreviewTimer function (around line 2042)

**Context:**
Replace the old 60Hz timer that read from `activeTransportTime` with a new timer that directly advances `globalTime` using the wall-clock calculation.

- [ ] **Step 1: Locate startChartPreviewTimer**

Find `startChartPreviewTimer()` around line 2042 in PrototypeGameController.swift. This function currently reads from `activeTransportTime` and calls `syncTransportState()`. We will replace its logic entirely.

- [ ] **Step 2: Replace startChartPreviewTimer with new implementation**

Replace the entire `startChartPreviewTimer()` function with:

```swift
private func startPlaybackTimer() {
    playbackTimerCancellable?.cancel()
    playbackTimerCancellable = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            guard let self else { return }
            let newTime = self.calculateCurrentPlaybackTime()
            self.globalTime.seek(to: newTime, from: .playback)
            self.syncTransportState()
        }
    startLookaheadScheduler()
}
```

This new timer:
1. Cancels any previous timer
2. Creates a 60Hz timer (every 1/60th second)
3. Each tick calls `calculateCurrentPlaybackTime()` to get the new position
4. Updates `globalTime` via `seek(to:from:)` with source `.playback`
5. Calls `syncTransportState()` to update UI
6. Starts the lookahead scheduler

- [ ] **Step 3: Verify the timer logic**

Skim the function:
- Does it cancel the old timer first? ✓
- Does it create a 60Hz timer? ✓
- Does it calculate time each tick? ✓
- Does it update globalTime? ✓
- Does it call syncTransportState? ✓
- Does it start the lookahead scheduler? ✓

- [ ] **Step 4: Commit the timer implementation**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "feat: replace startChartPreviewTimer with startPlaybackTimer

New 60Hz timer advances globalTime based on wall-clock elapsed time and
playback rate instead of reading from inconsistent sources. Each tick:
1. Calculates current position via calculateCurrentPlaybackTime()
2. Updates globalTime (triggers listener pattern for audio/chart sync)
3. Calls syncTransportState() for UI updates
4. Starts lookahead scheduler for sound scheduling"
```

---

## Task 4: Update startTransport to Use New Timer

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Modify startTransport function (around line 1997)

**Context:**
Update `startTransport()` to initialize the new playback timer and set the wall-clock anchors instead of relying on activeTransportTime.

- [ ] **Step 1: Locate startTransport**

Find `startTransport(at startTime: Double)` around line 1997 in PrototypeGameController.swift.

- [ ] **Step 2: Update startTransport to set anchors and call new timer**

Modify the `startTransport()` method. Find the section that currently calls `startChartPreviewTimer()` (around line 2033). Replace the entire method body with:

```swift
private func startTransport(at startTime: Double) {
    guard !isInitializing else { return }
    let hasAudio = audio.loadedTrackName != nil
    let hasChart = !session.chart.notes.isEmpty
    guard hasAudio || hasChart else {
        adminStatusText = "Load audio or chart first"
        refocusGameplay()
        return
    }

    adminScrubPreviewTime = nil
    adminScrubPreviewTargetTime = nil

    // Update globalTime and set playback anchors
    globalTime.setDuration(playbackDuration)
    globalTime.seek(to: startTime, from: .external)
    playbackStartGlobalTime = startTime
    playbackStartWallTime = Date()

    if hasAudio {
        stopChartOnlyPlaybackIfNeeded(resetTime: false)
        audio.play()
    } else {
        chartPreviewClock.stop()
        isChartOnlyPlaybackEnabled = true
        // Capture engine time for sample-accurate note scheduling in chart-only mode
        if let renderTime = audio.engine.outputNode.lastRenderTime {
            audio.anchorSampleTime = renderTime.sampleTime - Int64(startTime * 44100.0)
        }
        chartPreviewClock.play()
    }

    if hasChart && !isChartMuted {
        isChartAuditionActive = true
        lastChartPlaybackTriggeredNoteIDs.removeAll()
        scheduledNoteIDs.removeAll()
        chartPreviewLastAuditionTime = startTime - 0.02
        handleChartOnlyPlaybackTick(at: startTime)
        startPlaybackTimer()
    } else {
        isChartAuditionActive = false
    }

    syncTransportState()
    refocusGameplay()
}
```

Key changes:
- Sets `playbackStartGlobalTime = startTime` — anchor for the timer
- Sets `playbackStartWallTime = Date()` — captures wall clock time
- Calls `startPlaybackTimer()` instead of `startChartPreviewTimer()`

- [ ] **Step 3: Verify the changes**

Check that startTransport now:
1. Sets the two anchor properties before starting playback
2. Calls `startPlaybackTimer()` instead of `startChartPreviewTimer()` ✓
3. Preserves all other logic (audio.play(), chartPreviewClock.play(), etc.) ✓

- [ ] **Step 4: Commit the changes**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "feat: update startTransport to initialize wall-clock anchors

Sets playbackStartWallTime (Date()) and playbackStartGlobalTime (startTime)
when playback begins. Calls new startPlaybackTimer() to begin the
wall-clock-based timer instead of the old activeTransportTime reader."
```

---

## Task 5: Update pauseTransport to Stop New Timer

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Modify pauseTransport function (around line 1242)

**Context:**
Update `pauseTransport()` to cancel the new playback timer and clear anchors.

- [ ] **Step 1: Locate pauseTransport**

Find `pauseTransport()` around line 1242 in PrototypeGameController.swift.

- [ ] **Step 2: Update pauseTransport to use new timer**

Replace the method body. Currently it cancels `chartPreviewTimerCancellable`. Update it to:

```swift
func pauseTransport() {
    isChartAuditionActive = false
    playbackTimerCancellable?.cancel()
    playbackTimerCancellable = nil
    playbackStartWallTime = nil
    lookaheadSchedulerTimer?.cancel()
    lookaheadSchedulerTimer = nil
    laneSoundPlayer.cancelScheduled()
    scheduledNoteIDs.removeAll()
    if isChartOnlyPlaybackEnabled {
        stopChartOnlyPlaybackIfNeeded(resetTime: false)
        adminStatusText = "Chart-only playback off"
    } else {
        audio.pause()
    }
    syncTransportState()
    refocusGameplay()
}
```

Key changes:
- Cancels `playbackTimerCancellable` instead of `chartPreviewTimerCancellable`
- Clears `playbackStartWallTime = nil` to signal timer not running
- Preserves all other cleanup logic

- [ ] **Step 3: Verify the changes**

Check that pauseTransport now:
1. Cancels the new `playbackTimerCancellable` ✓
2. Clears the `playbackStartWallTime` anchor ✓
3. Cancels lookahead scheduler and clears scheduled notes ✓
4. Calls syncTransportState() to update UI ✓

- [ ] **Step 4: Commit the changes**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "feat: update pauseTransport to stop new playback timer

Cancels playbackTimerCancellable and clears playbackStartWallTime anchor
to signal that playback is stopped. The timer will return 0 when reading
playbackStartWallTime == nil in calculateCurrentPlaybackTime()."
```

---

## Task 6: Update Cleanup in stopChartOnlyPlaybackIfNeeded and deinit

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Update cleanup functions

**Context:**
Ensure all cleanup paths cancel the new timer instead of the old one.

- [ ] **Step 1: Locate stopChartOnlyPlaybackIfNeeded**

Find `stopChartOnlyPlaybackIfNeeded(resetTime:)` around line 1947 in PrototypeGameController.swift.

- [ ] **Step 2: Update stopChartOnlyPlaybackIfNeeded**

Find the section that cancels `chartPreviewTimerCancellable` (around line 1958). Replace it with:

```swift
private func stopChartOnlyPlaybackIfNeeded(resetTime: Bool) {
    adminScrubPreviewTime = nil
    adminScrubPreviewTargetTime = nil
    isChartOnlyPlaybackEnabled = false
    isChartAuditionActive = false
    playbackTimerCancellable?.cancel()
    playbackTimerCancellable = nil
    playbackStartWallTime = nil
    lastChartPlaybackTriggeredNoteIDs.removeAll()
    chartPreviewLastAuditionTime = nil
    lastMetronomeSubdivisionIndex = nil
    if resetTime {
        globalTime.reset(from: .external)
    }
}
```

- [ ] **Step 3: Locate handleChartOnlyPlaybackTick**

Find `handleChartOnlyPlaybackTick(at:)` around line 1972 in PrototypeGameController.swift. Find the cleanup section near line 1987-1993 that checks if playback has ended.

- [ ] **Step 4: Update handleChartOnlyPlaybackTick cleanup**

In the else clause (around line 1988), replace `chartPreviewTimerCancellable` references with `playbackTimerCancellable`:

```swift
} else if !isChartOnlyPlaybackEnabled && activeTransportState != .playing {
    isChartAuditionActive = false
    playbackTimerCancellable?.cancel()
    playbackTimerCancellable = nil
    lookaheadSchedulerTimer?.cancel()
    lookaheadSchedulerTimer = nil
}
```

- [ ] **Step 5: Locate deinit or init cleanup**

Find the deinit or initialization cleanup around line 293 where timers are cancelled. Replace `chartPreviewTimerCancellable?.cancel()` with `playbackTimerCancellable?.cancel()`.

- [ ] **Step 6: Verify all cleanup paths**

Search the file for any remaining `chartPreviewTimerCancellable` references. They should all be replaced with `playbackTimerCancellable`.

Run:
```bash
grep -n "chartPreviewTimerCancellable" Sources/App/PrototypeGameController.swift
```

Expected: No matches (all replaced)

- [ ] **Step 7: Commit cleanup updates**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "refactor: update all timer cleanup paths to use new playback timer

Replace all chartPreviewTimerCancellable cancellations with 
playbackTimerCancellable and clear playbackStartWallTime in:
- stopChartOnlyPlaybackIfNeeded()
- handleChartOnlyPlaybackTick() 
- init() deinit cleanup"
```

---

## Task 7: Update toggleChartMute to Use New Timer

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Modify toggleChartMute function (around line 1306)

**Context:**
When chart mute is toggled and playback resumes, use the new timer.

- [ ] **Step 1: Locate toggleChartMute**

Find `toggleChartMute()` around line 1306 in PrototypeGameController.swift.

- [ ] **Step 2: Update toggleChartMute**

Find the section that calls `startChartPreviewTimer()` (around line 1315) and replace it with `startPlaybackTimer()`:

```swift
func toggleChartMute() {
    isChartMuted.toggle()
    if isChartMuted {
        isChartAuditionActive = false
        playbackTimerCancellable?.cancel()
        playbackTimerCancellable = nil
    } else if activeTransportState == .playing && !session.chart.notes.isEmpty {
        isChartAuditionActive = true
        chartPreviewLastAuditionTime = max(0, activeTransportTime - 0.02)
        startPlaybackTimer()
    }
    adminStatusText = isChartMuted ? "Chart muted" : chartLaneFilterStatusText(base: "Chart unmuted")
    refocusGameplay()
}
```

Changes:
- Cancels `playbackTimerCancellable` instead of `chartPreviewTimerCancellable` when muting
- Calls `startPlaybackTimer()` instead of `startChartPreviewTimer()` when unmuting

- [ ] **Step 3: Verify the changes**

Check that toggleChartMute:
1. Cancels the new timer when muting ✓
2. Calls the new startPlaybackTimer when unmuting ✓

- [ ] **Step 4: Commit the changes**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "refactor: update toggleChartMute to use new playback timer

Use playbackTimerCancellable instead of chartPreviewTimerCancellable and
call startPlaybackTimer() instead of startChartPreviewTimer() when
resuming chart playback after unmuting."
```

---

## Task 8: Remove activeTransportTime Dependency from syncTransportState

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Update syncTransportState function (around line 1690)

**Context:**
Now that globalTime is driven by the playback timer directly, verify that syncTransportState reads from globalTime.time instead of activeTransportTime.

- [ ] **Step 1: Locate syncTransportState**

Find `syncTransportState(requestedSource:)` around line 1690 in PrototypeGameController.swift.

- [ ] **Step 2: Review syncTransportState**

Read the current implementation. It should already read from `globalTime.time` if the previous changes are in place. Verify the key line:

```swift
private func syncTransportState(requestedSource: TimeChangeSource? = nil) {
    guard !isInitializing else { return }
    let hasContent = audio.duration > 0 || isAdminChartActive
    let nextTime = hasContent ? (adminScrubPreviewTime ?? globalTime.time) : 0
    // ... rest of function
}
```

If `syncTransportState` is already reading from `globalTime.time`, no changes are needed. If it's still reading from `activeTransportTime`, update it.

- [ ] **Step 3: Verify globalTime is used**

The line above shows it reads from `adminScrubPreviewTime ?? globalTime.time`. This is correct—it prefers admin scrub preview if set, otherwise uses globalTime. No changes needed if this is already in place.

If changes were made:

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "refactor: verify syncTransportState reads from globalTime

Confirmed that syncTransportState() reads from globalTime.time instead of
activeTransportTime. The timer now feeds globalTime, which feeds UI updates
via syncTransportState()."
```

---

## Task 9: Remove or Deprecate activeTransportTime Property (Optional)

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Keep activeTransportTime but mark as deprecated

**Context:**
The `activeTransportTime` property is no longer the clock driver, but it may still be used in other parts of the code (e.g., displaying current position, scrubbing UI). Keep it for now but verify it's not driving the timer.

- [ ] **Step 1: Locate activeTransportTime property**

Find the `activeTransportTime` property around line 1891 in PrototypeGameController.swift.

- [ ] **Step 2: Check for remaining uses**

Search for all uses of `activeTransportTime`:

```bash
grep -n "activeTransportTime" Sources/App/PrototypeGameController.swift
```

Expected: Should only appear in UI display contexts (syncStepCursorToPlayback, playTransport, etc.), not in timer logic.

- [ ] **Step 3: Verify it's not used as a clock driver**

Skim the search results. Confirm that:
- No timer reads from activeTransportTime ✓
- No globalTime is calculated from activeTransportTime ✓
- Remaining uses are for display or manual control (acceptable) ✓

If all checks pass, the migration is complete. No commit needed for this task.

---

## Task 10: Verify Timer Anchor Updates on Manual Seek

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Verify seeker-related functions (around line 1500+)

**Context:**
When the user scrubs the position slider or uses lane scrubbing, the controls call `globalTime.seek()`. The playback timer should continue from the new position. This requires updating the anchors when seeking while playing.

- [ ] **Step 1: Locate seek-related functions**

Search for functions that call `globalTime.seek()`:

```bash
grep -n "globalTime.seek" Sources/App/PrototypeGameController.swift
```

Look for: `moveStepCursor`, `seekTransport`, or scrubbing handlers.

- [ ] **Step 2: Understand current seek behavior**

Read one of these functions to understand how seeking works. Seeking should:
1. Call `globalTime.seek(to: newPosition, from: .source)` 
2. The listener pattern updates audio/chart to match
3. If playback is active, the timer continues from the new position

- [ ] **Step 3: Verify timer anchor updates (if playing)**

In the seek handler, if playback is currently active (`playbackStartWallTime != nil`), the anchors should update so the timer continues from the new position:

Add this logic after seeking if playback is active:

```swift
// If playback is active, update timer anchor to continue from new position
if playbackStartWallTime != nil {
    playbackStartGlobalTime = globalTime.time
    playbackStartWallTime = Date()
}
```

This ensures the timer continues from the new seek position without a discontinuity.

**Find all seek calls and add anchor update (if not already there).**

Example locations to check:
- `moveStepCursor(to:seekPlayback:)` around line 900
- `seekTransport(to:)` (if it exists)
- Lane scrubbing handlers

- [ ] **Step 4: Verify seek during playback works**

Manually test (recorded in Task 11). For now, just ensure the code has the logic to update anchors on seek.

- [ ] **Step 5: Commit anchor update logic (if changes made)**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "fix: update playback timer anchors when seeking during playback

When user scrubs/steps during playback, update playbackStartWallTime and
playbackStartGlobalTime so the timer continues from the new position without
causing time to jump or skip."
```

---

## Task 11: Build and Run Tests

**Files:**
- No files created/modified
- Test: Verify app builds and existing tests pass

- [ ] **Step 1: Clean build**

Run:
```bash
swift build --configuration debug 2>&1 | head -50
```

Expected: Build succeeds with no errors (or expected warnings only)

- [ ] **Step 2: Run all tests**

Run:
```bash
swift test 2>&1 | tail -20
```

Expected: All existing tests pass (166 tests or similar count)

If tests fail, read the failure message and create a fix commit.

- [ ] **Step 3: Commit test verification (if no failures)**

If all tests passed without changes:

```bash
git log --oneline -1
```

Just document the result. No commit needed if nothing broke.

---

## Task 12: Manual Verification — Audio + Chart Playback

**Files:**
- No code changes
- Test: Play audio + chart, verify sounds trigger in sync

- [ ] **Step 1: Launch the app**

Run the app in your environment or simulator:
```bash
swift run MasterOfDrums
```

Wait for app to fully launch.

- [ ] **Step 2: Load audio and chart**

1. Click "Open Audio" and select an audio file with a backing track
2. Click "Open Chart" and select a chart file with drum notes
3. Verify both are loaded (audio waveform visible, chart notes visible)

- [ ] **Step 3: Play and verify sounds trigger**

1. Click the "Play" button
2. Verify:
   - Button changes to "Stop"
   - Display time advances in Bar.Beat.Division.Tick format
   - Drum sounds play at note times
   - Sounds appear synchronized with the visual chart

Expected: Sounds trigger in sync with visual playhead

- [ ] **Step 4: Verify stop freezes time**

1. Click "Stop" button during playback
2. Verify:
   - Button changes back to "Play"
   - Display time stops advancing immediately
   - Sounds stop playing

Expected: Time frozen, button shows Play

- [ ] **Step 5: Verify play resumes correctly**

1. Click "Play" again
2. Verify playback resumes from the stopped position
3. Sounds trigger correctly from that point onward

Expected: Playback resumes without issues

---

## Task 13: Manual Verification — Chart-Only Playback (Critical Test)

**Files:**
- No code changes
- Test: Play chart-only, verify sounds trigger (this was the original bug)

- [ ] **Step 1: Launch the app**

Run the app:
```bash
swift run MasterOfDrums
```

- [ ] **Step 2: Load chart only (no audio)**

1. Click "Open Chart" and select a chart file with drum notes
2. Do NOT load audio
3. Verify chart is loaded and ready to play

- [ ] **Step 3: Play and verify sounds trigger**

1. Click "Play" button
2. Verify:
   - Button changes to "Stop"
   - Display time advances
   - **Drum sounds play at note times** ← This was broken before!
   - Sounds appear synchronized with the visual chart

Expected: Sounds trigger consistently in chart-only mode (fixes the core bug)

- [ ] **Step 4: Verify playback rate affects sound speed**

1. If there's a playback rate control, change it to 75%
2. Verify:
   - Display advances at 75% speed
   - Sounds trigger at adjusted times (slower)

Expected: Sounds trigger at rate-adjusted times

- [ ] **Step 5: Stop and verify**

1. Click "Stop"
2. Verify time freezes and button shows "Play"

Expected: Clean stop

---

## Task 14: Manual Verification — Scrubbing and Manual Controls

**Files:**
- No code changes
- Test: Verify scrubbing, stepping, and manual controls work with new timer

- [ ] **Step 1: Load content**

Load audio + chart as in Task 12.

- [ ] **Step 2: Scrub during playback**

1. Click "Play" to start playback
2. Click and drag the position slider backward (or forward)
3. Verify:
   - Display jumps to new position
   - Playback resumes from new position
   - Sounds trigger correctly from new position

Expected: Scrubbing works smoothly without time jumps

- [ ] **Step 3: Step cursor navigation (if available)**

1. If there's a step/lane scrubbing feature, use it to move the playhead
2. Verify:
   - Playhead moves to stepped position
   - Playback resumes correctly
   - Sounds trigger at correct times

Expected: Stepping works correctly

- [ ] **Step 4: Verify no time jumps on seek**

During and after seeking, ensure:
- Time advances smoothly after seek (no backward jumps)
- No duplicate sounds triggered
- No skipped sounds

Expected: Seek is seamless, no artifacts

---

## Task 15: Manual Verification — Playback Rate Changes

**Files:**
- No code changes
- Test: Verify playback rate affects timing uniformly

- [ ] **Step 1: Load content**

Load audio + chart.

- [ ] **Step 2: Play at 100% rate**

1. Start playback
2. Note the display speed and sound timing
3. Stop

Expected: Normal playback

- [ ] **Step 3: Change rate to 75%**

1. Change playback rate to 75% (if UI has this control)
2. Click "Play"
3. Verify:
   - Display advances at 75% speed
   - Sounds trigger at slowed times
   - Audio (if playing) is pitched down or otherwise indicates slower playback

Expected: Everything advances at 75% speed

- [ ] **Step 4: Resume at original rate**

1. Change rate back to 100%
2. Verify playback speed returns to normal

Expected: Rate changes apply immediately

---

## Task 16: Verify Audio Engine Listener Pattern Works

**Files:**
- No code changes
- Test: Verify audio engine listens to globalTime changes

**Context:**
The audio engine should already have a listener attached to `globalTime.didChange`. Verify this works by checking that audio seeks to match globalTime when globalTime changes.

- [ ] **Step 1: Verify listener is attached**

Search for where `globalTime.didChange` is subscribed:

```bash
grep -n "globalTime.didChange" Sources/Audio/AudioPlaybackController.swift
```

Expected: A subscription that calls `seek()` on the audio engine

If not found, verify in PrototypeGameController:

```bash
grep -n "globalTime.didChange" Sources/App/PrototypeGameController.swift
```

- [ ] **Step 2: Manual test**

During audio + chart playback:
1. Play the audio + chart
2. Scrub the position slider
3. Verify audio seeks to the new position (sound jumps to that point)

Expected: Audio syncs with globalTime changes

If audio doesn't sync, the listener isn't working. Check the implementation.

- [ ] **Step 3: No changes needed if working**

If the listener is already working, no commit needed for this verification.

---

## Task 17: Final Code Review and Cleanup

**Files:**
- Modify: `Sources/App/PrototypeGameController.swift` — Final cleanup pass

**Context:**
Review the modified file for any dead code, commented-out lines, or inconsistencies.

- [ ] **Step 1: Review for dead code**

Search for any commented-out code related to the old timer:

```bash
grep -n "// chartPreviewTimerCancellable\|// activeTransportTime.*timer" Sources/App/PrototypeGameController.swift
```

Remove any leftover comments or dead code.

- [ ] **Step 2: Review for consistency**

Verify:
- All timer references use `playbackTimerCancellable` (not `chartPreviewTimerCancellable`)
- All timer starts call `startPlaybackTimer()` (not `startChartPreviewTimer()`)
- All `playbackStartWallTime` updates happen together with `playbackStartGlobalTime` updates

Run:
```bash
grep -n "playbackTimer\|chartPreviewTimer" Sources/App/PrototypeGameController.swift | grep -v "playbackStartGlobalTime\|playbackStartWallTime"
```

Review results for any anomalies.

- [ ] **Step 3: Final build and test**

```bash
swift build 2>&1 | grep -i error
swift test 2>&1 | tail -5
```

Expected: No errors, all tests pass

- [ ] **Step 4: Final commit (if changes made)**

```bash
git add Sources/App/PrototypeGameController.swift
git commit -m "refactor: final cleanup and consistency pass

Removed dead code, verified all timer references use new names,
ensured anchor updates are consistent throughout. Ready for testing."
```

---

## Summary of Changes

**Before:**
- Multiple clock sources: `audio.currentTime`, `chartPreviewClock.currentTime`, `activeTransportTime`
- `startChartPreviewTimer()` read from `activeTransportTime` (inconsistent in different modes)
- Sounds didn't trigger in chart-only mode because the timer relied on `activeTransportTime`
- No unified time source across all modes

**After:**
- Single clock: Elapsed wall time drives `globalTime.time` directly
- 60Hz playback timer calculates: `globalTime.time = anchor + (elapsed × playbackRate)`
- `globalTime.didChange` listener triggers audio/chart sync (already implemented)
- Lookahead scheduler reads from `globalTime.time` (already did this)
- Sounds trigger consistently in all three modes (audio-only, chart-only, audio+chart)
- Scrubbing, stepping, playback rate changes work through `globalTime.seek()` (existing mechanism)

**Key Properties Added:**
- `playbackTimerCancellable: AnyCancellable?` — The single playback timer
- `playbackStartWallTime: Date?` — Wall-clock anchor
- `playbackStartGlobalTime: Double` — Music-time anchor

**Key Functions Added:**
- `calculateCurrentPlaybackTime()` — Returns `anchor + (elapsed × rate)`
- `startPlaybackTimer()` — Replaces `startChartPreviewTimer()`

**No Changes to:**
- `GlobalMusicalTime.swift` — Already has listener pattern
- `AudioPlaybackController.swift` — Already listens to globalTime
- `LaneSoundPlayer.swift` — Already reads from lookahead scheduler
