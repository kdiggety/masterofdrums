#!/usr/bin/env python3
"""Analyze lane coverage for MIDI files in ~/Downloads/MOD-MIDI."""

from pathlib import Path
from midi_to_modchart import parse_midi, LANE_MAP, NOTE_LABELS

midi_dir = Path("/Users/klewisjr/Downloads/MOD-MIDI")

# Find all MIDI files
midi_files = []
for pattern in ["*.mid", "**/*.mid"]:
    midi_files.extend(midi_dir.glob(pattern))

midi_files = sorted(set(midi_files))

# Swift Lane mapping
lane_names = {
    0: "red (snare)",
    1: "yellow (hihat)",
    2: "blue (tom_high)",
    3: "green (crash/ride/tom)",
    4: "kick",
}

print("Lane Coverage Analysis for Downloaded MIDI Files")
print("=" * 90)

for midi_file in midi_files:
    try:
        fmt, ticks_per_beat, tempo, time_sig, title, events = parse_midi(midi_file)

        # Collect unique lanes from events
        lanes = set()
        note_counts = {}

        for event in events:
            if event.note in LANE_MAP:
                lane = LANE_MAP[event.note]
                lanes.add(lane)
                label = NOTE_LABELS.get(event.note, f"Note {event.note}")
                note_counts[label] = note_counts.get(label, 0) + 1

        lanes_sorted = sorted(lanes)
        lane_desc = ", ".join(f"Lane {l} ({lane_names[l]})" for l in lanes_sorted)

        # Calculate duration
        duration = max((e.tick / ticks_per_beat) * (tempo / 1_000_000.0) for e in events) if events else 0
        bpm = 60_000_000 / tempo

        print(f"\n{midi_file.relative_to(midi_dir.parent)}")
        print(f"  Title: {title}")
        print(f"  BPM: {bpm:.1f} | Duration: {duration:.1f}s | Notes: {len(events)}")
        print(f"  Lanes: {len(lanes)} — {lane_desc}")

        # Top instruments
        top_notes = sorted(note_counts.items(), key=lambda x: -x[1])[:5]
        notes_str = ", ".join(f"{label}({count})" for label, count in top_notes)
        print(f"  Top instruments: {notes_str}")

    except Exception as e:
        print(f"\n{midi_file.name}")
        print(f"  ERROR: {e}")

print("\n" + "=" * 90)
