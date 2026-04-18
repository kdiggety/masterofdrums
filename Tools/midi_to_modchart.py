#!/usr/bin/env python3
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

NOTE_LABELS = {
    35: "Kick",
    36: "Kick",
    37: "Side Stick",
    38: "Snare",
    39: "Hand Clap",
    40: "Snare",
    41: "Tom Low",
    42: "HiHat Closed",
    43: "Tom Low",
    44: "HiHat Pedal",
    45: "Tom Mid",
    46: "HiHat Open",
    47: "Tom Mid",
    48: "Tom High",
    49: "Crash",
    50: "Tom High",
    51: "Ride",
    52: "Crash",
    55: "Splash",
    57: "Crash",
    59: "Ride",
}

LANE_MAP = {
    35: 4, 36: 4,
    37: 0, 38: 0, 39: 0, 40: 0,
    41: 2, 43: 2, 45: 2, 47: 2, 48: 2, 50: 2,
    42: 1, 44: 1, 46: 1,
    49: 3, 51: 3, 52: 3, 55: 3, 57: 3, 59: 3,
}


def read_vlq(buf: bytes, pos: int) -> Tuple[int, int]:
    value = 0
    while True:
        b = buf[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not (b & 0x80):
            return value, pos


def friendly_title_from_filename(path: Path) -> str:
    base = path.stem.replace("_", " ").replace("-", " ").strip()
    compact = " ".join(base.split())
    if not compact:
        return "Imported MIDI Chart"
    return compact.title()


def parse_midi(path: Path):
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
    tempo = 500000
    time_sig = (4, 4)
    note_events: List[NoteEvent] = []
    title = friendly_title_from_filename(path)
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
                if meta == 0x03 and payload:
                    candidate = payload.decode("latin1", "replace").strip()
                    if candidate and candidate.lower() not in {"set de batterie", "drums", "drumset", "drum set"}:
                        title = candidate
                elif meta == 0x51 and length == 3:
                    tempo = int.from_bytes(payload, "big")
                elif meta == 0x58 and length >= 2:
                    time_sig = (payload[0], 2 ** payload[1])
                elif meta == 0x2F:
                    break
            elif status in (0xF0, 0xF7):
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
    return fmt, ticks_per_beat, tempo, time_sig, title, note_events


def tick_to_seconds(tick: int, ticks_per_beat: int, tempo: int) -> float:
    return (tick / ticks_per_beat) * (tempo / 1_000_000.0)


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: midi_to_modchart.py <input.mid> [output.modchart.json]", file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2]) if len(sys.argv) == 3 else src.with_suffix('.modchart.json')
    fmt, ticks_per_beat, tempo, time_sig, title, events = parse_midi(src)
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
            "unmappedMIDINotes": sorted(set(unmapped)),
        },
    }
    dst.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(dst),
        "title": title,
        "bpm": bpm,
        "ticksPerBeat": ticks_per_beat,
        "noteCount": len(notes),
        "unmappedMIDINotes": sorted(set(unmapped)),
    }, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
