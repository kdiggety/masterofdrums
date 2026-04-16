#!/usr/bin/env python3
"""
chart_alignment_check.py — Bounded alignment check between a .modchart.json chart
and a reference audio file.

DECISION QUESTION
    Does this MIDI-derived chart stay in sync with its reference audio well enough
    to justify using (and buying more of) this MIDI source?

USAGE
    python3 Tools/chart_alignment_check.py <audio_file> <chart.modchart.json> [options]

OPTIONS
    --json              Output JSON (default: plain text)
    --search-range S    Offset search range in seconds (default: 12.0)
    --threshold T       Onset peak threshold 0–1 (default: 0.30)

EXAMPLE
    python3 Tools/chart_alignment_check.py \\
        ~/Music/blinding-lights-the-weeknd.m4a \\
        Examples/blinding-lights-the-weeknd.modchart.json

DEPENDENCIES
    pip install librosa numpy scipy soundfile

HOW PERCUSSION ISOLATION WORKS
    HPSS (harmonic/percussive source separation) median-filters the audio spectrogram
    in two directions:
      Horizontal (time)      → sustained tones   → harmonic component
      Vertical (frequency)   → short transients  → percussive component
    The percussive component is then used for onset detection instead of the full signal.
    This suppresses synth arpeggios, sustained pads, and bass lines — all of which create
    onset peaks in full-spectrum analysis that compete with drum transients.

WHERE PERCUSSION ISOLATION HELPS
    Songs where synth/harmonic transients would otherwise pollute onset detection.
    When the HPSS percussive component has a clearly higher anchor-match rate than the
    full-spectrum path, synth contamination was the likely culprit.

WHERE PERCUSSION ISOLATION CAN STILL FAIL
    - Processed 808 basses that decay like pitched tones (HPSS classifies them as harmonic).
    - Distorted or clipped drums that have spread-out harmonic content.
    - Very sparse or quiet drums buried below synth transients — HPSS separation may
      still be noisy.
    - In any case, HPSS does not distinguish kick from snare; both land in the same
      percussive onset envelope.

VERDICT THRESHOLDS
    no_drift:       worst-checkpoint mean delta < 25ms (within typical "Perfect" window)
    minor_drift:    worst-checkpoint mean delta < 75ms (within "Good" window; correctable)
    material_drift: worst-checkpoint mean delta >= 75ms (likely to feel wrong in gameplay)
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional, Tuple

try:
    import numpy as np
    _NUMPY_OK = True
except ImportError:
    _NUMPY_OK = False
    np = None  # type: ignore

try:
    import librosa
    import scipy.signal
    _LIBROSA_OK = True
except ImportError:
    _LIBROSA_OK = False
    librosa = None  # type: ignore
    scipy = None    # type: ignore


def _require_audio_deps() -> None:
    """Call at the start of any function that needs librosa. Exits with a clear message."""
    if not _NUMPY_OK:
        print("Missing: numpy. Install with: pip install librosa numpy scipy soundfile", file=sys.stderr)
        sys.exit(1)
    if not _LIBROSA_OK:
        print("Missing audio deps. Install with: pip install librosa numpy scipy soundfile", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Thresholds (module-level so tests can import and check boundary conditions)
# ---------------------------------------------------------------------------

MATCH_WINDOW_S = 0.10           # onset must be within ±100ms of anchor to match
THRESHOLD_NO_DRIFT_S = 0.025    # 25ms mean residual → no_drift
THRESHOLD_MINOR_DRIFT_S = 0.075 # 75ms mean residual → minor_drift; else material_drift

CONFIDENCE_HIGH_MATCH = 0.60    # >= 60% anchors matched → eligible for "high" confidence
CONFIDENCE_LOW_MATCH = 0.30     # < 30% anchors matched → "low" regardless of residuals

# Mode-selection thresholds
PERC_ENERGY_MIN = 0.08          # percussive RMS / full RMS must exceed this to trust HPSS
PERC_MATCH_ADVANTAGE = 0.05     # percussive preferred unless full beats it by >5pp
FULL_PEAK_DOMINANCE = 2.5       # full has >2.5× more peaks than perc → synth contamination signal

ANCHOR_LANES = frozenset({0, 4})  # snare (0/red) and kick (4)

# ---------------------------------------------------------------------------
# Chart helpers (deterministic; testable without audio)
# ---------------------------------------------------------------------------

def load_chart(chart_path: Path) -> dict:
    with open(chart_path, encoding="utf-8") as f:
        return json.load(f)


def extract_anchors(chart: dict) -> "np.ndarray":
    """
    Return sorted array of anchor event times (seconds) from kick and snare notes.
    Only uses lane 0 (snare/red) and lane 4 (kick) — the two events most likely to
    produce clear transients detectable in audio onset analysis.
    """
    notes = chart.get("notes", [])
    times = [n["time"] for n in notes if n.get("lane") in ANCHOR_LANES]
    return np.array(sorted(times), dtype=float)


def chart_bpm(chart: dict) -> Optional[float]:
    timing = chart.get("timing") or {}
    return timing.get("bpm") or chart.get("bpm") or None


def chart_title(chart: dict) -> str:
    return chart.get("title") or "Unknown"


def chart_duration(chart: dict) -> float:
    return float(chart.get("timelineDuration") or 0.0)


# ---------------------------------------------------------------------------
# Audio analysis (requires librosa)
# ---------------------------------------------------------------------------

def load_audio(audio_path: Path, sr: int = 22050) -> Tuple["np.ndarray", int]:
    _require_audio_deps()
    y, loaded_sr = librosa.load(str(audio_path), sr=sr, mono=True)
    return y, loaded_sr


def separate_percussive(y: "np.ndarray", sr: int) -> Tuple["np.ndarray", float]:
    """
    Apply HPSS to isolate the percussive component.

    Returns (y_percussive, perc_energy_ratio) where perc_energy_ratio is the ratio of
    percussive RMS to full-signal RMS.  Values < PERC_ENERGY_MIN suggest HPSS found
    little percussion and the result may not be reliable.
    """
    _require_audio_deps()
    _, y_perc = librosa.effects.hpss(y)
    full_rms = float(np.sqrt(np.mean(y ** 2)))
    perc_rms = float(np.sqrt(np.mean(y_perc ** 2)))
    ratio = perc_rms / full_rms if full_rms > 0 else 0.0
    return y_perc, ratio


def compute_onset_envelope(
    y: "np.ndarray", sr: int, hop_length: int = 512
) -> Tuple["np.ndarray", "np.ndarray"]:
    """
    Return (onset_times_s, onset_strength_normalized).
    hop_length=512 at sr=22050 → ~23ms per frame.
    Works on the full signal or any pre-filtered component (e.g. percussive).
    """
    _require_audio_deps()
    env = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop_length)
    times = librosa.frames_to_time(np.arange(len(env)), sr=sr, hop_length=hop_length)
    peak = env.max()
    if peak > 0:
        env = env / peak
    return times, env


def find_onset_peaks(
    onset_times: "np.ndarray", onset_env: "np.ndarray", threshold: float = 0.30
) -> "np.ndarray":
    """
    Return times of onset envelope peaks above threshold.
    distance=4 frames (~92ms at 22050/512) prevents double-counting.
    """
    peaks, _ = scipy.signal.find_peaks(onset_env, height=threshold, distance=4)
    return onset_times[peaks]


def estimate_audio_bpm(y: "np.ndarray", sr: int) -> Optional[float]:
    """Estimate BPM from audio. Returns None on failure or implausible value."""
    _require_audio_deps()
    try:
        tempo = librosa.beat.tempo(y=y, sr=sr)
        val = float(np.atleast_1d(tempo)[0])
        if 40 <= val <= 300:
            return val
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Mode selection (pure / deterministic — testable without audio)
# ---------------------------------------------------------------------------

def select_analysis_mode(
    full_match_rate: float,
    perc_match_rate: float,
    perc_energy_ratio: float,
    full_peak_count: int,
    perc_peak_count: int,
) -> Tuple[str, str, bool]:
    """
    Choose between full-spectrum and percussive onset modes for the final verdict.

    Returns (mode_name, reason, synth_contamination_suspected).

    mode_name: "full_spectrum" | "percussive"
    reason:    human-readable explanation for the choice
    synth_contamination_suspected: True when evidence suggests full-spectrum was polluted
        by synth/harmonic transients (i.e. HPSS helped meaningfully)

    Logic:
      1. If HPSS produced a weak percussive component (< PERC_ENERGY_MIN), fall back
         to full-spectrum — HPSS separation is unreliable.
      2. If full-spectrum has a significantly higher match rate (> 15pp advantage),
         use full-spectrum — HPSS may have removed real drum content.
      3. Otherwise prefer percussive.  Flag synth contamination when percussive has a
         meaningful match-rate advantage OR when full-spectrum has far more peaks
         (indicating non-drum transients flooding the full path).
    """
    # Guard: weak percussive component
    if perc_energy_ratio < PERC_ENERGY_MIN:
        return (
            "full_spectrum",
            f"Percussive component is too weak (energy ratio {perc_energy_ratio:.2f} "
            f"< {PERC_ENERGY_MIN}). HPSS separation unreliable for this audio.",
            False,
        )

    # Guard: full-spectrum has a large advantage — HPSS may have hurt drum detection
    if full_match_rate - perc_match_rate > 0.15:
        return (
            "full_spectrum",
            f"Full-spectrum had significantly higher match rate "
            f"({full_match_rate:.0%} vs {perc_match_rate:.0%}). "
            "Drum transients may not survive HPSS cleanly for this recording.",
            False,
        )

    # Detect synth contamination signals
    match_rate_advantage = perc_match_rate > full_match_rate + PERC_MATCH_ADVANTAGE
    peak_count_ratio = (
        full_peak_count / perc_peak_count if perc_peak_count > 0 else 0.0
    )
    peak_dominance = peak_count_ratio > FULL_PEAK_DOMINANCE
    synth_contamination = match_rate_advantage or peak_dominance

    if synth_contamination:
        if match_rate_advantage:
            reason = (
                f"Percussive mode has higher match rate ({perc_match_rate:.0%} vs "
                f"{full_match_rate:.0%}) — synth/harmonic transients likely contaminating "
                "full-spectrum onset detection."
            )
        else:
            reason = (
                f"Full-spectrum has {peak_count_ratio:.1f}× more onset peaks than percussive "
                f"({full_peak_count} vs {perc_peak_count}) — synth transient activity "
                "suspected. Percussive mode selected for cleaner drum focus."
            )
    else:
        reason = (
            f"Percussive mode is comparable to full-spectrum "
            f"({perc_match_rate:.0%} vs {full_match_rate:.0%}); "
            "percussion isolation selected for better drum focus."
        )

    return "percussive", reason, synth_contamination


# ---------------------------------------------------------------------------
# Offset estimation (vectorised)
# ---------------------------------------------------------------------------

def estimate_initial_offset(
    chart_anchors: "np.ndarray",
    onset_peak_times: "np.ndarray",
    search_range: float = 12.0,
    step: float = 0.010,
) -> Tuple[float, float]:
    """
    Find the global time offset (seconds) that best aligns chart_anchors to audio onsets.

    Positive offset → drums appear later in audio than in chart (audio has intro before drums).
    Negative offset → audio starts after chart time 0.

    Uses weighted scoring: each anchor contributes (MATCH_WINDOW_S − distance) when matched,
    0 otherwise.  This means exact matches score higher than boundary matches, preventing
    ties when the same number of anchors match at multiple candidate offsets.

    Returns (best_offset_s, binary_match_rate).
    """
    if len(chart_anchors) == 0 or len(onset_peak_times) == 0:
        return 0.0, 0.0

    offsets = np.arange(-search_range, search_range + step / 2.0, step)
    scores = np.zeros(len(offsets), dtype=np.float64)

    for i, offset in enumerate(offsets):
        shifted = chart_anchors + offset
        idx = np.searchsorted(onset_peak_times, shifted)
        left_i = np.clip(idx - 1, 0, len(onset_peak_times) - 1)
        right_i = np.clip(idx,     0, len(onset_peak_times) - 1)
        left_d  = np.abs(onset_peak_times[left_i]  - shifted)
        right_d = np.abs(onset_peak_times[right_i] - shifted)
        min_d = np.minimum(left_d, right_d)
        scores[i] = float(
            np.where(min_d < MATCH_WINDOW_S, MATCH_WINDOW_S - min_d, 0.0).sum()
        )

    best_i = int(np.argmax(scores))
    best_offset = float(offsets[best_i])

    # Binary match rate for human-readable output
    shifted_best = chart_anchors + best_offset
    idx_b = np.searchsorted(onset_peak_times, shifted_best)
    l_i = np.clip(idx_b - 1, 0, len(onset_peak_times) - 1)
    r_i = np.clip(idx_b,     0, len(onset_peak_times) - 1)
    min_d_best = np.minimum(
        np.abs(onset_peak_times[l_i] - shifted_best),
        np.abs(onset_peak_times[r_i] - shifted_best),
    )
    match_rate = float((min_d_best < MATCH_WINDOW_S).sum()) / len(chart_anchors)
    return best_offset, match_rate


# ---------------------------------------------------------------------------
# Residual / drift analysis (deterministic given anchors + peaks)
# ---------------------------------------------------------------------------

def compute_residuals(
    chart_anchors: "np.ndarray",
    onset_peak_times: "np.ndarray",
    offset: float,
) -> Tuple["np.ndarray", "np.ndarray", int]:
    """
    For each chart anchor, find the nearest onset peak within MATCH_WINDOW_S after
    applying the global offset.

    residual = onset_peak_time − (anchor_time + offset)
    Positive: audio event is later than chart (chart leads audio).
    Negative: audio event is earlier.

    Returns (matched_anchor_times, residuals, unmatched_count).
    """
    if len(chart_anchors) == 0 or len(onset_peak_times) == 0:
        return np.array([]), np.array([]), len(chart_anchors)

    matched_times: List[float] = []
    residuals_list: List[float] = []
    unmatched = 0

    for t in chart_anchors:
        target = t + offset
        idx = np.searchsorted(onset_peak_times, target)
        best_d: Optional[float] = None
        for j in (idx - 1, idx):
            if 0 <= j < len(onset_peak_times):
                d = float(onset_peak_times[j] - target)
                if abs(d) <= MATCH_WINDOW_S and (best_d is None or abs(d) < abs(best_d)):
                    best_d = d
        if best_d is not None:
            matched_times.append(t)
            residuals_list.append(best_d)
        else:
            unmatched += 1

    return np.array(matched_times), np.array(residuals_list), unmatched


def checkpoint_stats(
    matched_times: "np.ndarray",
    residuals: "np.ndarray",
    song_duration: float,
) -> List[dict]:
    """
    Split matched events into three equal time segments and compute per-segment stats.

    Returns list of three dicts:
        label, anchors_checked, mean_abs_delta_ms, max_abs_delta_ms, std_delta_ms
    *_ms values are None for empty segments.
    """
    if song_duration <= 0:
        song_duration = float(matched_times.max()) if len(matched_times) > 0 else 1.0

    thirds = song_duration / 3.0
    boundaries = [
        (0.0,        thirds,           "early (0–33%)"),
        (thirds,     2 * thirds,       "mid (33–66%)"),
        (2 * thirds, song_duration + 1.0, "late (66–100%)"),
    ]

    result = []
    for lo, hi, label in boundaries:
        mask = (matched_times >= lo) & (matched_times < hi)
        seg = residuals[mask]
        if len(seg) == 0:
            result.append({
                "label": label,
                "anchors_checked": 0,
                "mean_abs_delta_ms": None,
                "max_abs_delta_ms": None,
                "std_delta_ms": None,
            })
        else:
            abs_seg = np.abs(seg)
            result.append({
                "label": label,
                "anchors_checked": int(len(seg)),
                "mean_abs_delta_ms": round(float(abs_seg.mean()) * 1000, 1),
                "max_abs_delta_ms": round(float(abs_seg.max()) * 1000, 1),
                "std_delta_ms": round(float(seg.std()) * 1000, 1),
            })
    return result


# ---------------------------------------------------------------------------
# Per-mode analysis helper
# ---------------------------------------------------------------------------

def analyze_mode(
    anchors: "np.ndarray",
    onset_peaks: "np.ndarray",
    effective_duration: float,
    bpm_chart: Optional[float],
    bpm_audio: Optional[float],
    search_range: float,
) -> dict:
    """
    Run offset estimation, residuals, checkpoints, and verdict for one onset mode.
    Returns a dict with all per-mode fields.  Does NOT require librosa directly —
    all inputs are numpy arrays, so this is testable with synthetic data.
    """
    if len(onset_peaks) == 0:
        return {
            "onset_peak_count": 0,
            "match_rate": 0.0,
            "initial_offset_s": 0.0,
            "unmatched_anchor_count": int(len(anchors)),
            "checkpoints": checkpoint_stats(np.array([]), np.array([]), effective_duration),
            "verdict": "unknown",
            "confidence": "low",
            "warnings": ["No onset peaks found for this mode."],
        }

    offset, match_rate = estimate_initial_offset(anchors, onset_peaks, search_range=search_range)
    matched_times, residuals, unmatched = compute_residuals(anchors, onset_peaks, offset)
    checkpoints = checkpoint_stats(matched_times, residuals, effective_duration)
    verdict, confidence, warnings = verdict_and_confidence(checkpoints, match_rate, bpm_chart, bpm_audio)

    return {
        "onset_peak_count": int(len(onset_peaks)),
        "match_rate": round(match_rate, 3),
        "initial_offset_s": round(offset, 3),
        "unmatched_anchor_count": int(unmatched),
        "checkpoints": checkpoints,
        "verdict": verdict,
        "confidence": confidence,
        "warnings": warnings,
    }


# ---------------------------------------------------------------------------
# Verdict (deterministic)
# ---------------------------------------------------------------------------

def verdict_and_confidence(
    checkpoints: List[dict],
    match_rate: float,
    bpm_chart: Optional[float],
    bpm_audio: Optional[float],
) -> Tuple[str, str, List[str]]:
    """
    Return (verdict, confidence, warnings).

    verdict:    "no_drift" | "minor_drift" | "material_drift" | "unknown"
    confidence: "high" | "medium" | "low"
    """
    warnings: List[str] = []

    valid_means = [
        cp["mean_abs_delta_ms"] / 1000.0
        for cp in checkpoints
        if cp["mean_abs_delta_ms"] is not None
    ]

    if not valid_means:
        return "unknown", "low", ["No anchors matched onset peaks — cannot assess drift."]

    worst_mean = max(valid_means)

    if worst_mean < THRESHOLD_NO_DRIFT_S:
        verdict = "no_drift"
    elif worst_mean < THRESHOLD_MINOR_DRIFT_S:
        verdict = "minor_drift"
    else:
        verdict = "material_drift"

    bpm_delta_pct: Optional[float] = None
    if bpm_chart and bpm_audio:
        bpm_delta_pct = abs(bpm_chart - bpm_audio) / bpm_chart * 100.0

    if bpm_delta_pct is not None and bpm_delta_pct > 3.0:
        warnings.append(
            f"BPM mismatch: chart {bpm_chart:.2f} vs audio ~{bpm_audio:.1f} "
            f"({bpm_delta_pct:.1f}% off). Timing residuals may be unreliable."
        )
        confidence = "low"
    elif match_rate >= CONFIDENCE_HIGH_MATCH:
        confidence = "high"
    elif match_rate >= CONFIDENCE_LOW_MATCH:
        confidence = "medium"
    else:
        confidence = "low"
        warnings.append(
            f"Only {match_rate:.0%} of chart anchors matched audio onsets. "
            "Possible causes: long audio intro, onset threshold too high, "
            "or drums are weak relative to other instruments."
        )

    return verdict, confidence, warnings


# ---------------------------------------------------------------------------
# Report formatting
# ---------------------------------------------------------------------------

_VERDICT_LABEL = {
    "no_drift":       "NO DRIFT",
    "minor_drift":    "MINOR DRIFT  (correctable with a timing offset)",
    "material_drift": "MATERIAL DRIFT  (would feel wrong in gameplay)",
    "unknown":        "UNKNOWN  (insufficient data)",
}

_VERDICT_PURCHASE_GUIDANCE = {
    "no_drift":       "Chart alignment looks solid. Evidence supports buying more from this MIDI source.",
    "minor_drift":    "Drift is within correctable range. Fine to proceed if you can apply an offset trim.",
    "material_drift": "Significant drift detected. Inspect manually before purchasing more from this source.",
    "unknown":        "Cannot determine alignment. Try a different audio file or reduce --threshold.",
}

_MODE_LABEL = {
    "full_spectrum": "Full-spectrum",
    "percussive":    "Percussive (HPSS)",
}


def format_report_text(result: dict) -> str:
    lines = []
    sep = "=" * 60

    lines.append(sep)
    lines.append("  CHART ALIGNMENT REPORT")
    lines.append(sep)
    lines.append(f"  Chart:         {result['chart_title']}")
    lines.append(f"  Audio:         {result['audio_file']}")
    lines.append(f"  Anchors:       {result.get('anchor_definition', 'kick + snare')}")
    if result.get("bpm_chart"):
        lines.append(f"  Chart BPM:     {result['bpm_chart']:.3f}")
    else:
        lines.append("  Chart BPM:     unknown")
    if result.get("bpm_audio") is not None:
        delta = (
            abs(result["bpm_chart"] - result["bpm_audio"]) / result["bpm_chart"] * 100
            if result.get("bpm_chart") else 0
        )
        lines.append(f"  Audio BPM:     ~{result['bpm_audio']:.1f}  (delta {delta:.1f}%)")
    else:
        lines.append("  Audio BPM:     (detection failed)")
    lines.append(f"  Total anchors: {result['total_anchors']}")
    lines.append("")

    # --- Mode comparison ---
    lines.append("  AUDIO ANALYSIS MODES")
    modes = result.get("modes", {})
    selected = result.get("audio_analysis_mode", "")
    for key in ("full_spectrum", "percussive"):
        m = modes.get(key, {})
        if not m:
            continue
        marker = " *" if key == selected else "  "
        label = _MODE_LABEL.get(key, key)
        lines.append(
            f"  {marker} {label:<22}  "
            f"{m.get('onset_peak_count', '?'):>5} peaks  "
            f"match {m.get('match_rate', 0):.0%}  "
            f"verdict: {m.get('verdict', '?')}"
        )
    perc_ratio = result.get("percussive_energy_ratio")
    if perc_ratio is not None:
        pct = f"{perc_ratio:.0%}"
        flag = (
            "  (weak — HPSS may be unreliable)"
            if perc_ratio < PERC_ENERGY_MIN
            else ""
        )
        lines.append(f"    Percussive energy ratio: {pct}{flag}")
    if result.get("synth_contamination_suspected"):
        lines.append("    ! Synth/harmonic transient contamination suspected in full-spectrum path")
    mode_reason = result.get("audio_analysis_mode_reason", "")
    lines.append(f"    Mode used: {_MODE_LABEL.get(selected, selected)}")
    if mode_reason:
        # Wrap long reason to 70 chars
        words = mode_reason.split()
        line_buf = "    Reason: "
        for word in words:
            if len(line_buf) + len(word) + 1 > 74:
                lines.append(line_buf)
                line_buf = "      " + word
            else:
                line_buf += (" " if line_buf.rstrip() else "") + word
        if line_buf.strip():
            lines.append(line_buf)
    lines.append("")

    # --- Offset ---
    lines.append("  INITIAL OFFSET")
    offset = result["initial_offset_s"]
    sign = "+" if offset >= 0 else ""
    lines.append(f"    Estimated offset:  {sign}{offset:.3f} s")
    if offset >= 0:
        lines.append(f"    Chart time 0.0 aligns to audio ~{offset:.2f} s")
    else:
        lines.append(f"    Audio starts ~{abs(offset):.2f} s after chart time 0.0")
    lines.append(f"    Anchors matched at offset:  {result['match_rate']:.0%}")
    lines.append("")

    # --- Checkpoints ---
    lines.append("  DRIFT CHECKPOINTS  (residuals after offset correction)")
    for cp in result["checkpoints"]:
        if cp["mean_abs_delta_ms"] is None:
            lines.append(f"    {cp['label']:<18}  — no data —")
        else:
            lines.append(
                f"    {cp['label']:<18}  "
                f"mean {cp['mean_abs_delta_ms']:>5.1f}ms  "
                f"max {cp['max_abs_delta_ms']:>5.1f}ms  "
                f"[{cp['anchors_checked']} anchors]"
            )
    lines.append("")

    verdict = result["verdict"]
    confidence = result["confidence"]
    lines.append(f"  VERDICT:     {_VERDICT_LABEL.get(verdict, verdict)}")
    lines.append(f"  CONFIDENCE:  {confidence.upper()}")
    lines.append("")
    lines.append("  PURCHASE GUIDANCE")
    lines.append(f"    {_VERDICT_PURCHASE_GUIDANCE.get(verdict, '')}")

    if result.get("warnings"):
        lines.append("")
        lines.append("  WARNINGS")
        for w in result["warnings"]:
            lines.append(f"    ! {w}")

    lines.append("")
    lines.append("  LIMITATIONS")
    for lim in result.get("limitations", []):
        lines.append(f"    - {lim}")

    lines.append(sep)
    return "\n".join(lines)


def format_report_json(result: dict) -> str:
    return json.dumps(result, indent=2)


# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

LIMITATIONS = [
    "Constant-tempo assumption: variable-tempo MIDI produces meaningless drift numbers.",
    "HPSS may mis-classify processed 808 basses or distorted kicks as harmonic content.",
    "HPSS does not distinguish kick from snare; both contribute to the percussive envelope.",
    "Match window is ±100ms; sub-beat timing precision is not measured.",
    "Audio BPM estimate is from beat tracking and may be off by 1-2% on complex rhythms.",
    "Only kick (lane 4) and snare (lane 0) used as anchors — hi-hat / tom lanes ignored.",
]


def run(
    audio_path: Path,
    chart_path: Path,
    search_range: float = 12.0,
    onset_threshold: float = 0.30,
) -> dict:
    """
    Full alignment check using both full-spectrum and percussive onset modes.
    Selects the more reliable mode for the final verdict.
    Returns a result dict suitable for text or JSON output.
    Raises ValueError with a user-friendly message on unrecoverable errors.
    """
    # --- Chart ---
    chart = load_chart(chart_path)
    anchors = extract_anchors(chart)
    bpm_c = chart_bpm(chart)
    duration = chart_duration(chart)
    title = chart_title(chart)

    if len(anchors) == 0:
        raise ValueError("Chart has no kick or snare notes (lanes 0/4). Cannot check alignment.")

    # --- Audio ---
    print("Loading audio...", file=sys.stderr)
    y, sr = load_audio(audio_path)
    audio_duration = len(y) / sr
    effective_duration = max(duration, audio_duration)

    print("Estimating audio BPM...", file=sys.stderr)
    bpm_a = estimate_audio_bpm(y, sr)

    # --- Full-spectrum onset ---
    print("Computing full-spectrum onset...", file=sys.stderr)
    times_full, env_full = compute_onset_envelope(y, sr)
    peaks_full = find_onset_peaks(times_full, env_full, threshold=onset_threshold)

    # --- Percussive isolation + onset ---
    print("Separating percussive component (HPSS)...", file=sys.stderr)
    y_perc, perc_energy_ratio = separate_percussive(y, sr)
    times_perc, env_perc = compute_onset_envelope(y_perc, sr)
    peaks_perc = find_onset_peaks(times_perc, env_perc, threshold=onset_threshold)

    if len(peaks_full) == 0 and len(peaks_perc) == 0:
        raise ValueError(
            f"No onset peaks found above threshold {onset_threshold} in either mode. "
            "Try lowering --threshold."
        )

    print(f"Searching offsets [{-search_range:.0f}, +{search_range:.0f}] s ...", file=sys.stderr)

    # --- Analyze both modes ---
    mode_full = analyze_mode(anchors, peaks_full, effective_duration, bpm_c, bpm_a, search_range)
    mode_perc = analyze_mode(anchors, peaks_perc, effective_duration, bpm_c, bpm_a, search_range)

    # --- Mode selection ---
    selected_mode, mode_reason, synth_contamination = select_analysis_mode(
        full_match_rate=mode_full["match_rate"],
        perc_match_rate=mode_perc["match_rate"],
        perc_energy_ratio=perc_energy_ratio,
        full_peak_count=mode_full["onset_peak_count"],
        perc_peak_count=mode_perc["onset_peak_count"],
    )

    primary = mode_perc if selected_mode == "percussive" else mode_full

    # Combine warnings from the selected mode plus any isolation notes
    warnings: List[str] = list(primary["warnings"])
    if synth_contamination:
        warnings.insert(0,
            "Synth/harmonic contamination suspected in full-spectrum onset detection. "
            "Percussive mode preferred."
        )
    if perc_energy_ratio < PERC_ENERGY_MIN * 2 and selected_mode == "percussive":
        warnings.append(
            f"Percussive energy ratio is low ({perc_energy_ratio:.2f}). "
            "HPSS separation may be imperfect for this recording."
        )

    return {
        "chart_title": title,
        "chart_file": str(chart_path),
        "audio_file": str(audio_path.name),
        "anchor_definition": "kick (lane 4) + snare (lane 0)",
        "bpm_chart": bpm_c,
        "bpm_audio": bpm_a,
        "total_anchors": int(len(anchors)),
        # Mode metadata
        "audio_analysis_mode": selected_mode,
        "audio_analysis_mode_reason": mode_reason,
        "percussive_energy_ratio": round(perc_energy_ratio, 3),
        "synth_contamination_suspected": synth_contamination,
        # Primary mode results (flat, for backward compat)
        "onset_peak_count": primary["onset_peak_count"],
        "initial_offset_s": primary["initial_offset_s"],
        "match_rate": primary["match_rate"],
        "unmatched_anchor_count": primary["unmatched_anchor_count"],
        "checkpoints": primary["checkpoints"],
        "verdict": primary["verdict"],
        "confidence": primary["confidence"],
        "warnings": warnings,
        # Both modes for comparison
        "modes": {
            "full_spectrum": mode_full,
            "percussive": mode_perc,
        },
        "limitations": LIMITATIONS,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check alignment between a .modchart.json chart and a reference audio file."
    )
    parser.add_argument("audio", type=Path, help="Reference audio file (.mp3, .m4a, .wav, etc.)")
    parser.add_argument("chart", type=Path, help=".modchart.json file")
    parser.add_argument("--json", action="store_true", help="Output JSON instead of plain text")
    parser.add_argument("--search-range", type=float, default=12.0,
                        help="Offset search range in seconds (default: 12.0)")
    parser.add_argument("--threshold", type=float, default=0.30,
                        help="Onset peak detection threshold 0–1 (default: 0.30)")
    args = parser.parse_args()

    if not args.audio.exists():
        print(f"Error: audio file not found: {args.audio}", file=sys.stderr)
        return 1
    if not args.chart.exists():
        print(f"Error: chart file not found: {args.chart}", file=sys.stderr)
        return 1

    try:
        result = run(
            args.audio,
            args.chart,
            search_range=args.search_range,
            onset_threshold=args.threshold,
        )
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    if args.json:
        print(format_report_json(result))
    else:
        print(format_report_text(result))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
