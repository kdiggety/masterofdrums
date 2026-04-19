#!/usr/bin/env python3
"""Validate MIDI BPM against audio BPM and check sync alignment."""

from pathlib import Path
from midi_to_modchart import parse_midi
import json

try:
    import librosa
    import numpy as np
    HAS_LIBROSA = True
except ImportError:
    HAS_LIBROSA = False
    print("Warning: librosa not installed. Install with: pip install librosa")


def extract_midi_bpm(midi_path: Path) -> float:
    """Extract BPM from MIDI file."""
    try:
        fmt, ticks_per_beat, tempo, time_sig, title, events = parse_midi(midi_path)
        bpm = 60_000_000 / tempo
        return bpm
    except Exception as e:
        return None


def extract_audio_bpm(audio_path: Path) -> dict:
    """Extract BPM from audio file using librosa."""
    if not HAS_LIBROSA:
        return {"bpm": None, "error": "librosa not installed"}

    try:
        y, sr = librosa.load(str(audio_path))

        # Estimate tempo using librosa's built-in beat tracking
        tempo, beats = librosa.beat.beat_track(y=y, sr=sr)

        return {
            "bpm": float(tempo),
            "detected_beats": len(beats),
            "duration_seconds": librosa.get_duration(y=y, sr=sr),
        }
    except Exception as e:
        return {"bpm": None, "error": str(e)}


def main():
    midi_dir = Path("/Users/klewisjr/Development/MacOS/masterofdrums-pipeline/Tests/PipelineRuntimeTests/Fixtures/midi")
    audio_dir = Path("/Users/klewisjr/Downloads/MOD-AUDIO")

    print("=" * 90)
    print("MIDI BPM Extraction")
    print("=" * 90)

    midi_files = list(midi_dir.glob("*.mid"))
    midi_bpms = {}

    for midi_file in sorted(midi_files):
        bpm = extract_midi_bpm(midi_file)
        name = midi_file.stem
        midi_bpms[name] = bpm
        if bpm:
            print(f"{name[:50]:50s} → {bpm:6.1f} BPM")
        else:
            print(f"{name[:50]:50s} → ERROR")

    print("\n" + "=" * 90)
    print("Audio BPM Detection (using librosa beat tracking)")
    print("=" * 90)

    audio_files = list(audio_dir.glob("*.wav")) + list(audio_dir.glob("*.mp3"))
    audio_bpms = {}

    for audio_file in sorted(audio_files):
        result = extract_audio_bpm(audio_file)
        name = audio_file.stem
        audio_bpms[name] = result
        if result["bpm"]:
            print(f"{name[:50]:50s} → {result['bpm']:6.1f} BPM ({result['duration_seconds']:.1f}s, {result['detected_beats']} beats)")
        else:
            print(f"{name[:50]:50s} → ERROR: {result.get('error', 'unknown')}")

    print("\n" + "=" * 90)
    print("BPM Comparison (MIDI vs Audio)")
    print("=" * 90)

    # Try to match MIDI files to audio files by BPM proximity
    if HAS_LIBROSA:
        matched = set()
        for midi_name, midi_bpm in midi_bpms.items():
            if midi_bpm is None:
                continue

            best_match = None
            best_diff = float('inf')

            for audio_name, audio_data in audio_bpms.items():
                if audio_name in matched:
                    continue
                if audio_data["bpm"] is None:
                    continue

                bpm_diff = abs(midi_bpm - audio_data["bpm"])
                if bpm_diff < best_diff:
                    best_diff = bpm_diff
                    best_match = (audio_name, audio_data["bpm"])

            if best_match and best_diff < 10:  # Within 10 BPM
                matched.add(best_match[0])
                match_quality = "✓ EXCELLENT" if best_diff < 1 else "≈ CLOSE" if best_diff < 5 else "⚠ LOOSE"
                print(f"\n{midi_name[:45]:45s}")
                print(f"  MIDI BPM:  {midi_bpm:6.1f}")
                print(f"  Audio BPM: {best_match[1]:6.1f} ({best_match[0]})")
                print(f"  Diff:      {best_diff:6.1f} BPM {match_quality}")
            else:
                print(f"\n{midi_name[:45]:45s}")
                print(f"  MIDI BPM:  {midi_bpm:6.1f}")
                print(f"  No matching audio found (within 10 BPM threshold)")

    print("\n" + "=" * 90)
    print("Summary")
    print("=" * 90)
    print(f"MIDI files analyzed: {len([b for b in midi_bpms.values() if b])}")
    print(f"Audio files analyzed: {len([d for d in audio_bpms.values() if d['bpm']])}")
    print("\nNote: Drum loops may have different BPM from the full track.")
    print("Full song audio files needed for accurate validation.")


if __name__ == "__main__":
    main()
