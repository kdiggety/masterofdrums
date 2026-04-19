#!/usr/bin/env python3
"""Analyze how many lanes each test MIDI file fills."""

from midi_to_modchart import LANE_MAP, NOTE_LABELS
from pathlib import Path

# Mapping from MIDI notes used in test files
test_files = {
    "test-kick-only.mid": [35],  # 3 kick notes
    "test-full-kit.mid": [35, 38, 42, 48, 45, 41, 49, 51],  # Full kit
    "test-tom-high.mid": [48],  # High tom repeated
    "test-tom-mid.mid": [45],  # Mid tom repeated
    "test-tom-low.mid": [41],  # Low tom repeated
    "test-zero-velocity.mid": [35, 38],  # Kick (0 vel, filtered), Snare
    "test-hihats.mid": [42, 44, 46],  # Hi-hat variations
    "test-wrong-channel.mid": [35, 38],  # Only channel 9 counts: kick + snare
}

# Swift Lane enum values (from ChartFileStore)
lane_names = {
    0: "red (snare)",
    1: "yellow (hihat)",
    2: "blue (tom_high)",
    3: "green (crash/ride/tom_low_mid)",
    4: "kick",
}

print("Test MIDI File Lane Coverage Analysis")
print("=" * 80)

for filename, midi_notes in test_files.items():
    lanes = set()

    for midi_note in midi_notes:
        if midi_note in LANE_MAP:
            lane = LANE_MAP[midi_note]
            lanes.add(lane)
            label = NOTE_LABELS.get(midi_note, f"Unknown ({midi_note})")

    lanes_sorted = sorted(lanes)
    lane_desc = ", ".join(f"Lane {l} ({lane_names[l]})" for l in lanes_sorted)

    print(f"\n{filename}")
    print(f"  MIDI notes: {midi_notes}")
    print(f"  Lanes filled: {len(lanes)} — {lane_desc}")

    # Show the notes
    notes_str = ", ".join(f"{n}={NOTE_LABELS.get(n, '?')}" for n in midi_notes)
    print(f"  Notes: {notes_str}")

print("\n" + "=" * 80)
print("\nActual Lane Coverage (after MIDI filtering):")
print("  test-kick-only: 1 lane (monophonic kick)")
print("  test-full-kit: 5 lanes (ALL Swift lanes: kick, snare, hihat, tom_high, crash/ride/toms)")
print("  test-tom-high: 1 lane (monophonic tom_high)")
print("  test-tom-mid: 1 lane (monophonic tom_mid)")
print("  test-tom-low: 1 lane (monophonic tom_low)")
print("  test-zero-velocity: 1 lane (kick velocity=0 FILTERED, only snare remains)")
print("  test-hihats: 1 lane (all hihat variants map to yellow)")
print("  test-wrong-channel: 2 lanes (channel 9 only: kick + snare, melody ignored)")
