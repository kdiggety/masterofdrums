#!/usr/bin/env python3
"""
midi_to_modchart.py — Convert a MIDI drum track to MasterOfDrums .modchart.json format.

Usage:
    python3 Tools/midi_to_modchart.py <input.mid> [output.modchart.json]

Reads channel-10 (index 9) note-on events and maps standard GM drum notes to the
five app lanes (Red/Snare=0, Yellow/Cymbal=1, Blue/TomHigh=2, Green/TomMid-Low=3, Kick=4).
Unmapped GM notes are recorded in metadata.unmappedMIDINotes and skipped.

Known limitations:
- Timing is computed from the first tempo event only. Songs with mid-song tempo changes
  will have drifting timestamps after the first change. tempoChanges in metadata indicates
  whether this applies.
- Only channel-10 note-on events are collected. Drum notes on other channels are ignored.
"""
import json
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

@dataclass
class NoteEvent:
    tick: int
    note: int
    velocity: int

# Human-readable labels for GM drum notes that are mapped to app lanes.
# Keys must match LANE_MAP exactly.
NOTE_LABELS = {
    # Kick
    35: "Bass Drum 2",
    36: "Kick",
    # Snare / rim / clap
    37: "Side Stick",
    38: "Snare",
    39: "Hand Clap",
    40: "Snare",
    # Tom low / floor tom
    41: "Tom Low",
    43: "Tom Low",
    # Hi-hat
    42: "HiHat Closed",
    44: "HiHat Pedal",
    46: "HiHat Open",
    # Tom mid
    45: "Tom Mid",
    47: "Tom Mid",
    # Tom high
    48: "Tom High",
    50: "Tom High",
    # Cymbals
    49: "Crash",
    51: "Ride",
    52: "Chinese Cymbal",
    53: "Ride Bell",
    54: "Tambourine",
    55: "Splash",
    56: "Cowbell",
    57: "Crash 2",
    59: "Ride 2",
}

# GM note → app lane index.
# 0 = Red / Snare    (D key)
# 1 = Yellow / Cymbal (F key)
# 2 = Blue / Tom High (J key)
# 3 = Green / Tom Mid-Low (K key)
# 4 = Kick           (Space)
LANE_MAP = {
    # Kick
    35: 4, 36: 4,
    # Snare / rim / clap
    37: 0, 38: 0, 39: 0, 40: 0,
    # Hi-hat and all cymbals → yellow
    42: 1, 44: 1, 46: 1,
    49: 1, 51: 1, 52: 1, 53: 1, 54: 1, 55: 1, 56: 1, 57: 1, 59: 1,
    # Tom high → blue
    48: 2, 50: 2,
    # Tom mid / floor tom → green
    41: 3, 43: 3, 45: 3, 47: 3,
}

# Track-name and text-event strings that carry no useful song information.
_GENERIC_TRACK_NAMES = frozenset({
    "set de batterie", "drums", "drumset", "drum set", "drum kit", "drumkit",
    "acoustic drums", "drum track", "percussion", "perc", "battery", "batterie",
    "standard kit", "midi drums", "gm drums",
})


def read_vlq(buf: bytes, pos: int) -> Tuple[int, int]:
    value = 0
    while True:
        b = buf[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not (b & 0x80):
            return value, pos


def _normalize_midi_title(raw: str) -> str:
    """Strip whitespace; apply title-case when the string is entirely upper-case."""
    stripped = raw.strip()
    if not stripped:
        return ""
    if stripped == stripped.upper() and any(c.isalpha() for c in stripped):
        return stripped.title()
    return stripped


def friendly_title_from_filename(path: Path) -> str:
    base = path.stem.replace("_", " ").replace("-", " ").strip()
    compact = " ".join(base.split())
    if not compact:
        return "Imported MIDI Chart"
    return compact.title()


def parse_midi(path: Path):
    """
    Parse a MIDI file and return:
        (fmt, ticks_per_beat, tempo, time_sig, title, note_events, track_count, tempo_change_count)

    tempo is taken from the *first* tempo meta event encountered; subsequent tempo
    events increment tempo_change_count but do not affect timing calculations.
    """
    data = path.read_bytes()
    if data[:4] != b"MThd":
        raise ValueError("Not a MIDI file")
    header_len = int.from_bytes(data[4:8], "big")
    fmt = int.from_bytes(data[8:10], "big")
    track_count = int.from_bytes(data[10:12], "big")
    ticks_per_beat = int.from_bytes(data[12:14], "big")
    pos = 8 + header_len
    tracks = []
    for _ in range(track_count):
        if data[pos:pos+4] != b"MTrk":
            raise ValueError("Missing track header")
        length = int.from_bytes(data[pos+4:pos+8], "big")
        tracks.append(data[pos+8:pos+8+length])
        pos += 8 + length

    tempo = 500000          # default: 120 BPM
    tempo_locked = False    # True after the first tempo event is seen
    tempo_change_count = 0  # total number of tempo meta events across all tracks
    time_sig = (4, 4)
    note_events: List[NoteEvent] = []

    # Title candidates, lowest-priority first; the best available wins.
    title_from_filename = friendly_title_from_filename(path)
    title_from_text_event: Optional[str] = None   # meta 0x01
    title_from_track_name: Optional[str] = None   # meta 0x03

    for track in tracks:
        tpos = 0
        abs_tick = 0
        running = None
        while tpos < len(track):
            delta, tpos = read_vlq(track, tpos)
            abs_tick += delta
            status = track[tpos]
            if status < 0x80:
                if running is None:
                    raise ValueError("Invalid running status")
                status = running
            else:
                tpos += 1
                if status < 0xF0:
                    running = status
            if status == 0xFF:
                meta = track[tpos]
                tpos += 1
                length, tpos = read_vlq(track, tpos)
                payload = track[tpos:tpos+length]
                tpos += length
                if meta == 0x01 and payload and title_from_text_event is None:
                    candidate = _normalize_midi_title(payload.decode("latin1", "replace"))
                    if candidate and candidate.lower() not in _GENERIC_TRACK_NAMES:
                        title_from_text_event = candidate
                elif meta == 0x03 and payload and title_from_track_name is None:
                    candidate = _normalize_midi_title(payload.decode("latin1", "replace"))
                    if candidate and candidate.lower() not in _GENERIC_TRACK_NAMES:
                        title_from_track_name = candidate
                elif meta == 0x51 and length == 3:
                    tempo_change_count += 1
                    if not tempo_locked:
                        tempo = int.from_bytes(payload, "big")
                        tempo_locked = True
                elif meta == 0x58 and length >= 2:
                    time_sig = (payload[0], 2 ** payload[1])
                elif meta == 0x2F:
                    break
            elif status in (0xF0, 0xF7):
                running = None  # SysEx cancels running status per MIDI spec
                length, tpos = read_vlq(track, tpos)
                tpos += length
            else:
                event_type = status >> 4
                channel = status & 0x0F
                if event_type in (0x8, 0x9, 0xA, 0xB, 0xE):
                    a = track[tpos]
                    b = track[tpos + 1]
                    tpos += 2
                    if event_type == 0x9 and b > 0 and channel == 9:
                        note_events.append(NoteEvent(abs_tick, a, b))
                elif event_type in (0xC, 0xD):
                    tpos += 1

    # Track-name beats text-event; both beat the filename fallback.
    title = title_from_track_name or title_from_text_event or title_from_filename

    return fmt, ticks_per_beat, tempo, time_sig, title, note_events, track_count, tempo_change_count


def tick_to_seconds(tick: int, ticks_per_beat: int, tempo: int) -> float:
    return (tick / ticks_per_beat) * (tempo / 1_000_000.0)


def convert(src: Path, dst: Path) -> dict:
    """
    Convert src MIDI to dst modchart.json.
    Returns the summary dict that is also printed to stdout.
    """
    fmt, ticks_per_beat, tempo, time_sig, title, events, track_count, tempo_change_count = parse_midi(src)
    bpm = 60_000_000 / tempo
    notes = []
    unmapped = []
    for ev in events:
        lane = LANE_MAP.get(ev.note)
        if lane is None:
            unmapped.append(ev.note)
            continue
        notes.append({
            "id": str(uuid.uuid4()),
            "lane": lane,
            "time": round(tick_to_seconds(ev.tick, ticks_per_beat, tempo), 6),
            "label": NOTE_LABELS.get(ev.note),
        })
    document = {
        "title": title,
        "bpm": round(bpm, 6),
        "timingContractVersion": "0.1.0",
        "timing": {
            "bpm": round(bpm, 6),
            "offsetSeconds": 0,
            "ticksPerBeat": ticks_per_beat,
            "timeSignature": {"numerator": time_sig[0], "denominator": time_sig[1]},
            "source": "midi_import",
        },
        "timelineDuration": round(max((n["time"] for n in notes), default=0) + 2.0, 6),
        "notes": notes,
        "sections": [],
        "metadata": {
            "sourceMIDI": src.name,
            "format": fmt,
            "trackCount": track_count,
            "tempoChanges": tempo_change_count,
            "unmappedMIDINotes": sorted(set(unmapped)),
        },
    }
    dst.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary = {
        "output": str(dst),
        "title": title,
        "bpm": bpm,
        "ticksPerBeat": ticks_per_beat,
        "noteCount": len(notes),
        "unmappedMIDINotes": sorted(set(unmapped)),
    }
    print(json.dumps(summary, indent=2))
    return summary


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: midi_to_modchart.py <input.mid> [output.modchart.json]", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) == 3 else src.with_suffix('.modchart.json')
    convert(src, dst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
