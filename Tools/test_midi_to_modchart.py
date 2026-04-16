#!/usr/bin/env python3
"""
Tests for Tools/midi_to_modchart.py.

Run from the repo root:
    python3 Tools/test_midi_to_modchart.py

Or via unittest discovery:
    python3 -m unittest Tools.test_midi_to_modchart
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Allow running from any working directory.
sys.path.insert(0, str(Path(__file__).parent))

from midi_to_modchart import (
    NOTE_LABELS, LANE_MAP, _GENERIC_TRACK_NAMES,
    _normalize_midi_title, friendly_title_from_filename,
    convert, parse_midi, tick_to_seconds,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _vlq(n: int) -> bytes:
    """Encode an integer as a MIDI variable-length quantity."""
    if n == 0:
        return b'\x00'
    result = []
    result.append(n & 0x7F)
    n >>= 7
    while n:
        result.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(result))


def _make_midi(
    ticks_per_beat: int = 480,
    tempo: int = 500000,
    time_sig: tuple = (4, 4),
    notes: list = None,
    track_name: str = "",
    text_event: str = "",
    extra_tempos: list = None,
) -> bytes:
    """
    Build a minimal format-0 MIDI with one track.

    notes: list of (abs_tick, gm_note, velocity) tuples on channel 10 (index 9).
    extra_tempos: list of additional tempo values appended after the first tempo event.
    """
    notes = notes or []
    extra_tempos = extra_tempos or []

    body = b""

    if track_name:
        name_bytes = track_name.encode("latin1")
        body += b'\x00\xff\x03' + _vlq(len(name_bytes)) + name_bytes

    if text_event:
        text_bytes = text_event.encode("latin1")
        body += b'\x00\xff\x01' + _vlq(len(text_bytes)) + text_bytes

    # First tempo
    body += b'\x00\xff\x51\x03' + tempo.to_bytes(3, "big")

    # Optional extra tempo events (all at delta 0)
    for t in extra_tempos:
        body += b'\x00\xff\x51\x03' + t.to_bytes(3, "big")

    # Time signature
    denom_exp = {1: 0, 2: 1, 4: 2, 8: 3, 16: 4, 32: 5}.get(time_sig[1], 2)
    body += b'\x00\xff\x58\x04' + bytes([time_sig[0], denom_exp, 24, 8])

    # Note-on events on channel 10 (status byte 0x99)
    prev_tick = 0
    for tick, note, vel in notes:
        delta = tick - prev_tick
        prev_tick = tick
        body += _vlq(delta) + bytes([0x99, note, vel])

    # End of track
    body += b'\x00\xff\x2f\x00'

    track = b'MTrk' + len(body).to_bytes(4, "big") + body
    header_body = (0).to_bytes(2, "big") + (1).to_bytes(2, "big") + ticks_per_beat.to_bytes(2, "big")
    header = b'MThd' + (6).to_bytes(4, "big") + header_body
    return header + track


def _write_temp_midi(midi_bytes: bytes) -> Path:
    with tempfile.NamedTemporaryFile(suffix=".mid", delete=False) as f:
        f.write(midi_bytes)
        return Path(f.name)


# ---------------------------------------------------------------------------
# Note mapping tests
# ---------------------------------------------------------------------------

class TestNoteMapping(unittest.TestCase):

    def test_lane_map_and_note_labels_have_identical_keys(self):
        self.assertEqual(set(LANE_MAP.keys()), set(NOTE_LABELS.keys()),
                         "LANE_MAP and NOTE_LABELS must cover exactly the same GM note numbers")

    def test_lane_map_values_are_valid_lanes(self):
        valid_lanes = {0, 1, 2, 3, 4}
        for note, lane in LANE_MAP.items():
            self.assertIn(lane, valid_lanes, f"Note {note} maps to invalid lane {lane}")

    def test_kick_notes(self):
        self.assertEqual(LANE_MAP[35], 4, "Bass Drum 2 (35) → kick")
        self.assertEqual(LANE_MAP[36], 4, "Kick (36) → kick")

    def test_snare_notes(self):
        for note in (37, 38, 39, 40):
            self.assertEqual(LANE_MAP[note], 0, f"Note {note} → snare (lane 0)")

    def test_hihat_and_cymbal_notes(self):
        for note in (42, 44, 46, 49, 51, 52, 53, 54, 55, 56, 57, 59):
            self.assertEqual(LANE_MAP[note], 1, f"Note {note} → cymbal/hihat (lane 1)")

    def test_tom_high_notes(self):
        for note in (48, 50):
            self.assertEqual(LANE_MAP[note], 2, f"Note {note} → tom high (lane 2)")

    def test_tom_low_mid_notes(self):
        for note in (41, 43, 45, 47):
            self.assertEqual(LANE_MAP[note], 3, f"Note {note} → tom mid/low (lane 3)")

    # Specifically verify the newly added notes.
    def test_hand_clap_maps_to_snare(self):
        self.assertEqual(LANE_MAP[39], 0)
        self.assertEqual(NOTE_LABELS[39], "Hand Clap")

    def test_ride_bell_maps_to_cymbal(self):
        self.assertEqual(LANE_MAP[53], 1)
        self.assertEqual(NOTE_LABELS[53], "Ride Bell")

    def test_tambourine_maps_to_cymbal(self):
        self.assertEqual(LANE_MAP[54], 1)
        self.assertEqual(NOTE_LABELS[54], "Tambourine")

    def test_cowbell_maps_to_cymbal(self):
        self.assertEqual(LANE_MAP[56], 1)
        self.assertEqual(NOTE_LABELS[56], "Cowbell")


# ---------------------------------------------------------------------------
# Title derivation tests
# ---------------------------------------------------------------------------

class TestTitleDerivation(unittest.TestCase):

    def test_friendly_title_from_simple_filename(self):
        self.assertEqual(friendly_title_from_filename(Path("/tmp/my_cool_song.mid")), "My Cool Song")

    def test_friendly_title_from_hyphenated_filename(self):
        self.assertEqual(
            friendly_title_from_filename(Path("/tmp/blinding-lights-the-weeknd.mid")),
            "Blinding Lights The Weeknd",
        )

    def test_friendly_title_empty_stem_returns_default(self):
        # A stem of "_" becomes an empty string after replacing underscores with spaces and stripping.
        self.assertEqual(friendly_title_from_filename(Path("/tmp/_.mid")), "Imported MIDI Chart")

    def test_normalize_midi_title_strips_whitespace(self):
        self.assertEqual(_normalize_midi_title("  My Song  "), "My Song")

    def test_normalize_midi_title_applies_title_case_to_allcaps(self):
        self.assertEqual(_normalize_midi_title("MY SONG"), "My Song")

    def test_normalize_midi_title_preserves_mixed_case(self):
        self.assertEqual(_normalize_midi_title("Blinding Lights"), "Blinding Lights")

    def test_normalize_midi_title_empty(self):
        self.assertEqual(_normalize_midi_title("   "), "")

    def test_generic_names_are_filtered(self):
        for name in ("Drums", "DrumSet", "Drum Set", "Percussion", "Battery", "Batterie"):
            self.assertIn(name.lower(), _GENERIC_TRACK_NAMES, f'"{name}" should be generic')


# ---------------------------------------------------------------------------
# MIDI parsing tests
# ---------------------------------------------------------------------------

class TestParseMidi(unittest.TestCase):

    def test_parse_basic_kick_and_snare(self):
        midi = _make_midi(
            ticks_per_beat=480,
            tempo=500000,
            notes=[(0, 36, 100), (480, 38, 90)],
        )
        path = _write_temp_midi(midi)
        try:
            fmt, tpb, tempo, time_sig, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertEqual(fmt, 0)
            self.assertEqual(tpb, 480)
            self.assertEqual(tempo, 500000)
            self.assertEqual(time_sig, (4, 4))
            self.assertEqual(len(events), 2)
            self.assertEqual(events[0].note, 36)
            self.assertEqual(events[0].tick, 0)
            self.assertEqual(events[1].note, 38)
            self.assertEqual(events[1].tick, 480)
            self.assertEqual(track_count, 1)
            self.assertEqual(tempo_changes, 1)
        finally:
            path.unlink()

    def test_parse_uses_first_tempo_not_last(self):
        midi = _make_midi(tempo=500000, extra_tempos=[300000])  # 120 BPM then 200 BPM
        path = _write_temp_midi(midi)
        try:
            _, _, tempo, _, _, _, _, tempo_changes = parse_midi(path)
            self.assertEqual(tempo, 500000, "Should keep first tempo event, not overwrite with later ones")
            self.assertEqual(tempo_changes, 2)
        finally:
            path.unlink()

    def test_tempo_change_count_is_tracked(self):
        midi = _make_midi(tempo=500000, extra_tempos=[400000, 600000])
        path = _write_temp_midi(midi)
        try:
            *_, tempo_changes = parse_midi(path)
            self.assertEqual(tempo_changes, 3)
        finally:
            path.unlink()

    def test_title_from_track_name_meta(self):
        midi = _make_midi(track_name="Awesome Song")
        path = _write_temp_midi(midi)
        try:
            *rest, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertEqual(title, "Awesome Song")
        finally:
            path.unlink()

    def test_title_from_text_event_when_no_track_name(self):
        midi = _make_midi(text_event="Text Song Name")
        path = _write_temp_midi(midi)
        try:
            *rest, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertEqual(title, "Text Song Name")
        finally:
            path.unlink()

    def test_track_name_beats_text_event(self):
        midi = _make_midi(track_name="Track Name", text_event="Text Event Name")
        path = _write_temp_midi(midi)
        try:
            *rest, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertEqual(title, "Track Name")
        finally:
            path.unlink()

    def test_generic_track_name_falls_back_to_filename(self):
        midi = _make_midi(track_name="Drums")
        path = _write_temp_midi(midi)
        try:
            *rest, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertNotEqual(title.lower(), "drums",
                                "Generic track name should be filtered; title should come from filename")
        finally:
            path.unlink()

    def test_note_velocity_zero_is_ignored(self):
        # Note-on with velocity 0 is a note-off event and must be skipped.
        midi = _make_midi(notes=[(0, 36, 0), (480, 36, 100)])
        path = _write_temp_midi(midi)
        try:
            *rest, events, _, _ = parse_midi(path)
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0].velocity, 100)
        finally:
            path.unlink()

    def test_time_signature_parsed(self):
        midi = _make_midi(time_sig=(3, 4))
        path = _write_temp_midi(midi)
        try:
            *rest, title, events, track_count, tempo_changes = parse_midi(path)
            # Unpack from front: fmt, tpb, tempo, time_sig
            fmt, tpb, tempo, time_sig, title, events, track_count, tempo_changes = parse_midi(path)
            self.assertEqual(time_sig, (3, 4))
        finally:
            path.unlink()

    def test_all_five_lanes_produced(self):
        # One representative note per lane.
        midi = _make_midi(notes=[
            (0,    36, 100),  # kick → 4
            (480,  38, 90),   # snare → 0
            (960,  42, 80),   # hihat closed → 1
            (1440, 48, 70),   # tom high → 2
            (1920, 41, 60),   # tom low → 3
        ])
        path = _write_temp_midi(midi)
        try:
            *rest, events, _, _ = parse_midi(path)
            from midi_to_modchart import LANE_MAP
            lanes = {LANE_MAP[ev.note] for ev in events if ev.note in LANE_MAP}
            self.assertEqual(lanes, {0, 1, 2, 3, 4})
        finally:
            path.unlink()


# ---------------------------------------------------------------------------
# Tick-to-seconds tests
# ---------------------------------------------------------------------------

class TestTickToSeconds(unittest.TestCase):

    def test_one_beat_at_120bpm(self):
        # 120 BPM → 500 000 µs/beat; 480 ticks = 1 beat = 0.5 s
        self.assertAlmostEqual(tick_to_seconds(480, 480, 500000), 0.5)

    def test_zero_tick(self):
        self.assertEqual(tick_to_seconds(0, 480, 500000), 0.0)

    def test_quarter_beat(self):
        # 120 ticks at 480 tpb = 0.25 beats at 120 BPM = 0.125 s
        self.assertAlmostEqual(tick_to_seconds(120, 480, 500000), 0.125)

    def test_96_tpb_one_beat(self):
        # 60 BPM = 1 000 000 µs/beat; 96 ticks = 1 beat = 1.0 s
        self.assertAlmostEqual(tick_to_seconds(96, 96, 1000000), 1.0)


# ---------------------------------------------------------------------------
# Full conversion / JSON contract tests
# ---------------------------------------------------------------------------

class TestConvert(unittest.TestCase):

    def setUp(self):
        self._temps = []

    def tearDown(self):
        for p in self._temps:
            try:
                p.unlink()
            except FileNotFoundError:
                pass

    def _tmp(self, suffix: str) -> Path:
        fd, name = tempfile.mkstemp(suffix=suffix)
        os.close(fd)
        p = Path(name)
        self._temps.append(p)
        return p

    def _run_convert(self, notes, track_name="", ticks_per_beat=480, tempo=500000):
        midi_path = self._tmp(".mid")
        out_path = self._tmp(".modchart.json")
        midi_path.write_bytes(_make_midi(
            ticks_per_beat=ticks_per_beat,
            tempo=tempo,
            notes=notes,
            track_name=track_name,
        ))
        summary = convert(midi_path, out_path)
        doc = json.loads(out_path.read_text())
        return doc, summary, midi_path

    def test_output_has_required_top_level_fields(self):
        doc, _, _ = self._run_convert([(0, 36, 100)])
        for field in ("title", "bpm", "timingContractVersion", "timing", "timelineDuration", "notes", "sections"):
            self.assertIn(field, doc, f'Missing required field "{field}"')

    def test_output_timing_fields(self):
        doc, _, _ = self._run_convert([], ticks_per_beat=480, tempo=500000)
        t = doc["timing"]
        self.assertAlmostEqual(t["bpm"], 120.0, places=2)
        self.assertEqual(t["ticksPerBeat"], 480)
        self.assertEqual(t["offsetSeconds"], 0)
        self.assertEqual(t["source"], "midi_import")
        self.assertEqual(t["timeSignature"], {"numerator": 4, "denominator": 4})

    def test_note_fields(self):
        doc, _, _ = self._run_convert([(0, 36, 100)])
        note = doc["notes"][0]
        self.assertIn("id", note)
        self.assertIn("lane", note)
        self.assertIn("time", note)
        # id must be a valid UUID string
        import uuid
        uuid.UUID(note["id"])

    def test_kick_note_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 36, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 4)
        self.assertEqual(note["label"], "Kick")

    def test_snare_note_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 38, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 0)
        self.assertEqual(note["label"], "Snare")

    def test_hand_clap_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 39, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 0)
        self.assertEqual(note["label"], "Hand Clap")

    def test_cowbell_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 56, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 1)
        self.assertEqual(note["label"], "Cowbell")

    def test_ride_bell_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 53, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 1)
        self.assertEqual(note["label"], "Ride Bell")

    def test_tambourine_lane_and_label(self):
        doc, _, _ = self._run_convert([(0, 54, 100)])
        note = doc["notes"][0]
        self.assertEqual(note["lane"], 1)
        self.assertEqual(note["label"], "Tambourine")

    def test_unmapped_note_in_metadata_not_in_notes(self):
        doc, summary, _ = self._run_convert([(0, 36, 100), (480, 99, 80)])
        self.assertEqual(len(doc["notes"]), 1, "Unmapped note 99 should not appear in notes array")
        self.assertIn(99, doc["metadata"]["unmappedMIDINotes"])
        self.assertIn(99, summary["unmappedMIDINotes"])

    def test_note_timing_at_120bpm(self):
        # At 120 BPM (500000 µs/beat), 480 ticks = 0.5 s
        doc, _, _ = self._run_convert([(480, 36, 100)])
        self.assertAlmostEqual(doc["notes"][0]["time"], 0.5, places=4)

    def test_notes_sorted_by_time(self):
        # Even if MIDI events are in order, verify the output is too.
        doc, _, _ = self._run_convert([(0, 36, 100), (480, 38, 90), (960, 42, 80)])
        times = [n["time"] for n in doc["notes"]]
        self.assertEqual(times, sorted(times))

    def test_timeline_duration_extends_past_last_note(self):
        doc, _, _ = self._run_convert([(960, 36, 100)])   # last note at 1.0 s (120 BPM)
        self.assertGreater(doc["timelineDuration"], 1.0)

    def test_title_from_track_name_in_output(self):
        doc, _, _ = self._run_convert([], track_name="My Test Song")
        self.assertEqual(doc["title"], "My Test Song")

    def test_metadata_source_midi_field(self):
        doc, _, midi_path = self._run_convert([])
        self.assertEqual(doc["metadata"]["sourceMIDI"], midi_path.name)

    def test_metadata_track_count_and_tempo_changes(self):
        doc, _, _ = self._run_convert([])
        self.assertEqual(doc["metadata"]["trackCount"], 1)
        self.assertEqual(doc["metadata"]["tempoChanges"], 1)

    def test_summary_note_count_matches_mapped_notes(self):
        _, summary, _ = self._run_convert([
            (0, 36, 100),   # kick   → mapped
            (480, 38, 90),  # snare  → mapped
            (960, 99, 80),  # note 99 → unmapped
        ])
        self.assertEqual(summary["noteCount"], 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
