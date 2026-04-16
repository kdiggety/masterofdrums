#!/usr/bin/env python3
"""
Tests for the deterministic parts of Tools/chart_alignment_check.py.

Audio-dependent functions (load_audio, compute_onset_envelope, estimate_audio_bpm,
separate_percussive) are not tested here since they require real audio files and librosa.

The offset estimator, residual functions, mode-selection logic, and per-mode analysis
ARE tested with synthetic data because their math is fully deterministic.

Run from repo root:
    python3 Tools/test_chart_alignment_check.py
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import numpy as np
except ImportError:
    print("Missing: numpy. Install with: pip install numpy", file=sys.stderr)
    sys.exit(1)

sys.path.insert(0, str(Path(__file__).parent))

from chart_alignment_check import (
    ANCHOR_LANES, MATCH_WINDOW_S,
    THRESHOLD_NO_DRIFT_S, THRESHOLD_MINOR_DRIFT_S,
    PERC_ENERGY_MIN, PERC_MATCH_ADVANTAGE, FULL_PEAK_DOMINANCE,
    load_chart, extract_anchors, chart_bpm, chart_title, chart_duration,
    compute_residuals, checkpoint_stats, verdict_and_confidence,
    estimate_initial_offset, find_onset_peaks,
    select_analysis_mode, analyze_mode,
    format_report_text, format_report_json,
)

try:
    import scipy.signal as _scipy_signal
    _SCIPY_AVAILABLE = True
except ImportError:
    _SCIPY_AVAILABLE = False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_chart(notes: list, bpm: float = 120.0, duration: float = 10.0,
                title: str = "Test Chart") -> dict:
    return {
        "title": title,
        "bpm": bpm,
        "timing": {
            "bpm": bpm,
            "offsetSeconds": 0,
            "ticksPerBeat": 480,
            "timeSignature": {"numerator": 4, "denominator": 4},
            "source": "midi_import",
        },
        "timelineDuration": duration,
        "notes": notes,
        "sections": [],
    }


def _write_chart(chart: dict) -> Path:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".modchart.json",
                                     delete=False, encoding="utf-8") as f:
        json.dump(chart, f)
        return Path(f.name)


# ---------------------------------------------------------------------------
# Chart loading
# ---------------------------------------------------------------------------

class TestLoadChart(unittest.TestCase):

    def test_extract_anchors_kick_and_snare_only(self):
        chart = _make_chart([
            {"id": "1", "lane": 4, "time": 0.0,   "label": "Kick"},
            {"id": "2", "lane": 0, "time": 0.5,   "label": "Snare"},
            {"id": "3", "lane": 1, "time": 0.25,  "label": "HiHat"},   # not an anchor
            {"id": "4", "lane": 4, "time": 1.0,   "label": "Kick"},
        ])
        anchors = extract_anchors(chart)
        np.testing.assert_array_almost_equal(anchors, [0.0, 0.5, 1.0])

    def test_extract_anchors_sorted(self):
        chart = _make_chart([
            {"id": "1", "lane": 0, "time": 0.5,  "label": "Snare"},
            {"id": "2", "lane": 4, "time": 0.0,  "label": "Kick"},
            {"id": "3", "lane": 4, "time": 1.0,  "label": "Kick"},
        ])
        anchors = extract_anchors(chart)
        self.assertTrue(np.all(np.diff(anchors) >= 0), "Anchors must be sorted")

    def test_extract_anchors_empty_when_no_kick_or_snare(self):
        chart = _make_chart([
            {"id": "1", "lane": 1, "time": 0.0, "label": "HiHat"},
            {"id": "2", "lane": 2, "time": 0.5, "label": "Tom"},
        ])
        anchors = extract_anchors(chart)
        self.assertEqual(len(anchors), 0)

    def test_anchor_lanes_contains_kick_and_snare(self):
        self.assertIn(0, ANCHOR_LANES)   # snare / red
        self.assertIn(4, ANCHOR_LANES)   # kick

    def test_chart_bpm_from_timing(self):
        chart = _make_chart([], bpm=171.0)
        self.assertAlmostEqual(chart_bpm(chart), 171.0)

    def test_chart_bpm_falls_back_to_top_level(self):
        chart = {"bpm": 140.0, "notes": []}
        self.assertAlmostEqual(chart_bpm(chart), 140.0)

    def test_chart_bpm_none_when_missing(self):
        self.assertIsNone(chart_bpm({}))

    def test_chart_title(self):
        chart = _make_chart([], title="Blinding Lights The Weeknd")
        self.assertEqual(chart_title(chart), "Blinding Lights The Weeknd")

    def test_chart_duration(self):
        chart = _make_chart([], duration=175.86)
        self.assertAlmostEqual(chart_duration(chart), 175.86)

    def test_load_chart_from_file(self):
        chart = _make_chart([{"id": "1", "lane": 4, "time": 0.0, "label": "Kick"}])
        path = _write_chart(chart)
        try:
            loaded = load_chart(path)
            self.assertEqual(loaded["title"], "Test Chart")
        finally:
            path.unlink()

    def test_blinding_lights_example_anchors(self):
        """Verify the real example chart produces 555 kick+snare anchors."""
        example = Path(__file__).parent.parent / "Examples" / "blinding-lights-the-weeknd.modchart.json"
        if not example.exists():
            self.skipTest("Example chart not found")
        chart = load_chart(example)
        anchors = extract_anchors(chart)
        # 293 kicks + 262 snares = 555 total
        self.assertEqual(len(anchors), 555)
        self.assertAlmostEqual(anchors[0], 0.0, places=3)


# ---------------------------------------------------------------------------
# Offset estimation (synthetic — deterministic)
# ---------------------------------------------------------------------------

class TestOffsetEstimation(unittest.TestCase):
    """
    Tests use synthetic anchor + onset data where the expected offset is known.
    This validates that the scoring logic finds the correct alignment.
    """

    def _make_peaks(self, times):
        return np.array(sorted(times), dtype=float)

    def test_zero_offset_exact_match(self):
        """When chart anchors exactly match onset peaks, offset should be near 0."""
        anchors = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
        peaks = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
        # step=0.01 → resolution ±0.01s; weighted scoring ensures exact matches win
        offset, match_rate = estimate_initial_offset(anchors, peaks, search_range=1.0, step=0.01)
        self.assertAlmostEqual(offset, 0.0, delta=0.011)   # within one step + rounding
        self.assertGreater(match_rate, 0.9)

    def test_positive_offset_detected(self):
        """Audio peaks start 2.0 seconds after chart anchors."""
        anchors = np.array([0.0, 0.5, 1.0, 1.5, 2.0])
        peaks = np.array([2.0, 2.5, 3.0, 3.5, 4.0])  # shifted +2.0s
        offset, match_rate = estimate_initial_offset(anchors, peaks, search_range=3.0, step=0.01)
        self.assertAlmostEqual(offset, 2.0, delta=0.011)
        self.assertGreater(match_rate, 0.8)

    def test_negative_offset_detected(self):
        """Chart anchors start 1.5 seconds after onset peaks."""
        anchors = np.array([1.5, 2.0, 2.5, 3.0, 3.5])
        peaks = np.array([0.0, 0.5, 1.0, 1.5, 2.0])  # anchors are 1.5s ahead
        offset, match_rate = estimate_initial_offset(anchors, peaks, search_range=3.0, step=0.01)
        self.assertAlmostEqual(offset, -1.5, delta=0.011)
        self.assertGreater(match_rate, 0.8)

    def test_offset_with_noisy_extra_peaks(self):
        """Extra onset peaks (e.g. synths) shouldn't break offset detection."""
        anchors = np.array([0.0, 0.35, 0.70, 1.05, 1.40])  # 171 BPM pattern
        # True offset = +5.0; add many noise peaks
        true_peaks = anchors + 5.0
        noise = np.arange(0.0, 15.0, 0.1)  # a peak every 100ms everywhere
        peaks = np.sort(np.concatenate([true_peaks, noise]))
        peaks = np.unique(np.round(peaks, 3))
        offset, match_rate = estimate_initial_offset(anchors, peaks, search_range=6.0, step=0.01)
        # Weighted scoring gives exact matches (d=0 at offset 5.0) higher score than
        # noise matches at adjacent offsets. Tolerance = 2 steps.
        self.assertAlmostEqual(offset, 5.0, delta=0.021)

    def test_empty_anchors(self):
        offset, rate = estimate_initial_offset(np.array([]), np.array([1.0, 2.0]))
        self.assertEqual(offset, 0.0)
        self.assertEqual(rate, 0.0)

    def test_empty_peaks(self):
        offset, rate = estimate_initial_offset(np.array([1.0, 2.0]), np.array([]))
        self.assertEqual(offset, 0.0)
        self.assertEqual(rate, 0.0)


# ---------------------------------------------------------------------------
# Residual computation (deterministic)
# ---------------------------------------------------------------------------

class TestComputeResiduals(unittest.TestCase):

    def test_perfect_alignment_zero_residuals(self):
        anchors = np.array([0.0, 0.5, 1.0])
        peaks = np.array([0.0, 0.5, 1.0])
        matched, residuals, unmatched = compute_residuals(anchors, peaks, offset=0.0)
        self.assertEqual(len(matched), 3)
        np.testing.assert_array_almost_equal(residuals, [0.0, 0.0, 0.0])
        self.assertEqual(unmatched, 0)

    def test_residual_sign_audio_later(self):
        # Anchor at 0.0 + offset=0.0; nearest peak at +0.03 → residual = +0.03
        anchors = np.array([0.0])
        peaks = np.array([0.030])
        _, residuals, _ = compute_residuals(anchors, peaks, offset=0.0)
        self.assertAlmostEqual(residuals[0], 0.030, places=4)

    def test_residual_sign_audio_earlier(self):
        # Anchor at 1.0 + offset=0.0; nearest peak at 0.97 → residual = -0.03
        anchors = np.array([1.0])
        peaks = np.array([0.970])
        _, residuals, _ = compute_residuals(anchors, peaks, offset=0.0)
        self.assertAlmostEqual(residuals[0], -0.030, places=4)

    def test_offset_applied_before_matching(self):
        # Anchor at 0.0, offset = 2.0 → target = 2.0; peak at 2.02 → residual = 0.02
        anchors = np.array([0.0])
        peaks = np.array([2.020])
        _, residuals, _ = compute_residuals(anchors, peaks, offset=2.0)
        self.assertAlmostEqual(residuals[0], 0.020, places=4)

    def test_unmatched_when_outside_window(self):
        anchors = np.array([0.0])
        peaks = np.array([0.5])  # 500ms away — outside MATCH_WINDOW_S (100ms)
        matched, residuals, unmatched = compute_residuals(anchors, peaks, offset=0.0)
        self.assertEqual(len(matched), 0)
        self.assertEqual(unmatched, 1)

    def test_nearest_peak_chosen(self):
        # Two peaks: 0.08s and 0.06s away; should pick the closer one (0.06)
        anchors = np.array([1.0])
        peaks = np.array([0.920, 1.060])  # 0.08s before and 0.06s after
        _, residuals, _ = compute_residuals(anchors, peaks, offset=0.0)
        self.assertAlmostEqual(residuals[0], 0.060, places=4)


# ---------------------------------------------------------------------------
# Checkpoint stats (deterministic)
# ---------------------------------------------------------------------------

class TestCheckpointStats(unittest.TestCase):

    def test_three_segments_returned(self):
        anchors = np.array([1.0, 2.0, 3.0])
        residuals = np.array([0.01, 0.02, 0.03])
        result = checkpoint_stats(anchors, residuals, song_duration=6.0)
        self.assertEqual(len(result), 3)

    def test_segment_labels(self):
        result = checkpoint_stats(np.array([]), np.array([]), song_duration=10.0)
        labels = [cp["label"] for cp in result]
        self.assertEqual(labels, ["early (0–33%)", "mid (33–66%)", "late (66–100%)"])

    def test_empty_segment_has_none_values(self):
        # All anchors in early third; mid and late are empty.
        anchors = np.array([0.5, 1.0, 1.5])  # all < 3.33 (song_duration=10)
        residuals = np.array([0.01, 0.01, 0.01])
        result = checkpoint_stats(anchors, residuals, song_duration=10.0)
        self.assertEqual(result[1]["anchors_checked"], 0)
        self.assertIsNone(result[1]["mean_abs_delta_ms"])
        self.assertEqual(result[2]["anchors_checked"], 0)

    def test_mean_abs_delta_ms_correct(self):
        # Put two anchors in the early third (song=6, early=0-2)
        # residuals = [+0.010, -0.030] → abs = [10ms, 30ms] → mean = 20ms
        anchors = np.array([0.5, 1.5])
        residuals = np.array([0.010, -0.030])
        result = checkpoint_stats(anchors, residuals, song_duration=6.0)
        self.assertAlmostEqual(result[0]["mean_abs_delta_ms"], 20.0)

    def test_max_abs_delta_ms_correct(self):
        anchors = np.array([0.5, 1.5])
        residuals = np.array([0.010, -0.030])
        result = checkpoint_stats(anchors, residuals, song_duration=6.0)
        self.assertAlmostEqual(result[0]["max_abs_delta_ms"], 30.0)

    def test_anchor_count_per_segment(self):
        anchors = np.array([0.5, 1.5,   3.5, 4.5,   6.5, 7.5])  # 2 in each third of 9s
        residuals = np.array([0.01] * 6)
        result = checkpoint_stats(anchors, residuals, song_duration=9.0)
        for cp in result:
            self.assertEqual(cp["anchors_checked"], 2)


# ---------------------------------------------------------------------------
# Verdict (deterministic)
# ---------------------------------------------------------------------------

class TestVerdictAndConfidence(unittest.TestCase):

    def _cp(self, mean_ms: float, anchors: int = 50) -> dict:
        return {
            "label": "test",
            "anchors_checked": anchors,
            "mean_abs_delta_ms": mean_ms,
            "max_abs_delta_ms": mean_ms * 1.5,
            "std_delta_ms": mean_ms * 0.3,
        }

    def test_no_drift_below_threshold(self):
        cp = [self._cp(10.0), self._cp(12.0), self._cp(8.0)]
        verdict, _, _ = verdict_and_confidence(cp, match_rate=0.80, bpm_chart=120.0, bpm_audio=120.0)
        self.assertEqual(verdict, "no_drift")

    def test_minor_drift_between_thresholds(self):
        cp = [self._cp(20.0), self._cp(35.0), self._cp(50.0)]
        verdict, _, _ = verdict_and_confidence(cp, match_rate=0.70, bpm_chart=120.0, bpm_audio=120.0)
        self.assertEqual(verdict, "minor_drift")

    def test_material_drift_above_threshold(self):
        cp = [self._cp(30.0), self._cp(60.0), self._cp(90.0)]
        verdict, _, _ = verdict_and_confidence(cp, match_rate=0.65, bpm_chart=120.0, bpm_audio=120.0)
        self.assertEqual(verdict, "material_drift")

    def test_unknown_when_no_valid_checkpoints(self):
        empty_cp = [
            {"label": "x", "anchors_checked": 0, "mean_abs_delta_ms": None,
             "max_abs_delta_ms": None, "std_delta_ms": None}
        ] * 3
        verdict, confidence, warnings = verdict_and_confidence(
            empty_cp, match_rate=0.0, bpm_chart=120.0, bpm_audio=None)
        self.assertEqual(verdict, "unknown")
        self.assertEqual(confidence, "low")

    def test_confidence_high_when_match_rate_high(self):
        cp = [self._cp(15.0)] * 3
        _, confidence, _ = verdict_and_confidence(cp, match_rate=0.75, bpm_chart=120.0, bpm_audio=121.0)
        self.assertEqual(confidence, "high")

    def test_confidence_medium_when_match_rate_medium(self):
        cp = [self._cp(15.0)] * 3
        _, confidence, _ = verdict_and_confidence(cp, match_rate=0.45, bpm_chart=120.0, bpm_audio=121.0)
        self.assertEqual(confidence, "medium")

    def test_confidence_low_when_match_rate_low(self):
        cp = [self._cp(15.0)] * 3
        _, confidence, warnings = verdict_and_confidence(cp, match_rate=0.20, bpm_chart=120.0, bpm_audio=121.0)
        self.assertEqual(confidence, "low")
        self.assertTrue(any("20%" in w or "anchors" in w.lower() for w in warnings))

    def test_confidence_low_and_warning_on_bpm_mismatch(self):
        cp = [self._cp(15.0)] * 3
        _, confidence, warnings = verdict_and_confidence(cp, match_rate=0.80, bpm_chart=120.0, bpm_audio=130.0)
        self.assertEqual(confidence, "low")
        self.assertTrue(any("BPM" in w for w in warnings))

    def test_bpm_none_does_not_crash(self):
        cp = [self._cp(15.0)] * 3
        # Should not raise even when one or both BPM values are None
        verdict_and_confidence(cp, match_rate=0.70, bpm_chart=None, bpm_audio=None)
        verdict_and_confidence(cp, match_rate=0.70, bpm_chart=120.0, bpm_audio=None)

    def test_worst_checkpoint_determines_verdict(self):
        # Early and mid are fine; late is bad → should be material_drift
        cp = [self._cp(10.0), self._cp(20.0), self._cp(95.0)]
        verdict, _, _ = verdict_and_confidence(cp, match_rate=0.70, bpm_chart=120.0, bpm_audio=120.0)
        self.assertEqual(verdict, "material_drift")


# ---------------------------------------------------------------------------
# Find onset peaks (deterministic — operates on synthetic numpy arrays)
# ---------------------------------------------------------------------------

@unittest.skipUnless(_SCIPY_AVAILABLE, "scipy not installed")
class TestFindOnsetPeaks(unittest.TestCase):

    def test_finds_peaks_above_threshold(self):
        times = np.array([0.0, 0.1, 0.2, 0.3, 0.4])
        env = np.array([0.1, 0.8, 0.1, 0.9, 0.1])
        peaks = find_onset_peaks(times, env, threshold=0.5)
        self.assertIn(0.1, peaks)
        self.assertIn(0.3, peaks)

    def test_no_peaks_below_threshold(self):
        times = np.array([0.0, 0.1, 0.2])
        env = np.array([0.1, 0.2, 0.1])
        peaks = find_onset_peaks(times, env, threshold=0.5)
        self.assertEqual(len(peaks), 0)

    def test_peaks_sorted(self):
        times = np.linspace(0, 1, 100)
        env = np.random.default_rng(42).random(100)
        peaks = find_onset_peaks(times, env, threshold=0.4)
        if len(peaks) > 1:
            self.assertTrue(np.all(np.diff(peaks) > 0))


# ---------------------------------------------------------------------------
# select_analysis_mode (fully deterministic — no audio deps)
# ---------------------------------------------------------------------------

class TestSelectAnalysisMode(unittest.TestCase):
    """
    select_analysis_mode() is pure/deterministic.  All branches can be exercised
    with synthetic scalar inputs — no audio loading required.
    """

    def test_percussive_preferred_when_comparable(self):
        """Normal case: both modes have similar match rates, percussive preferred."""
        mode, reason, contamination = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.63,
            perc_energy_ratio=0.25,
            full_peak_count=800,
            perc_peak_count=400,
        )
        self.assertEqual(mode, "percussive")
        self.assertFalse(contamination)
        self.assertGreater(len(reason), 0)

    def test_full_selected_when_percussive_energy_too_low(self):
        """HPSS found almost no percussion — fall back to full-spectrum."""
        mode, reason, contamination = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.60,
            perc_energy_ratio=PERC_ENERGY_MIN - 0.01,  # just below threshold
            full_peak_count=800,
            perc_peak_count=200,
        )
        self.assertEqual(mode, "full_spectrum")
        self.assertFalse(contamination)
        self.assertIn(str(PERC_ENERGY_MIN), reason)

    def test_full_selected_at_exact_energy_threshold(self):
        """Energy exactly at PERC_ENERGY_MIN passes the guard (code uses <, not <=)."""
        mode, _, _ = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.60,
            perc_energy_ratio=PERC_ENERGY_MIN,
            full_peak_count=800,
            perc_peak_count=400,
        )
        # Guard is `perc_energy_ratio < PERC_ENERGY_MIN` — equal value is NOT less-than,
        # so it passes the guard and percussive is still a candidate.
        self.assertEqual(mode, "percussive")

    def test_full_selected_when_full_has_large_advantage(self):
        """Full beats percussive by more than 15pp → full is more reliable here."""
        mode, reason, contamination = select_analysis_mode(
            full_match_rate=0.80,
            perc_match_rate=0.60,  # 20pp gap > 15pp threshold
            perc_energy_ratio=0.30,
            full_peak_count=800,
            perc_peak_count=600,
        )
        self.assertEqual(mode, "full_spectrum")
        self.assertFalse(contamination)
        self.assertGreater(len(reason), 0)

    def test_contamination_flagged_when_perc_match_rate_much_higher(self):
        """Percussive has >5pp advantage → synth contamination suspected in full path."""
        mode, reason, contamination = select_analysis_mode(
            full_match_rate=0.55,
            perc_match_rate=0.65,  # 10pp advantage > PERC_MATCH_ADVANTAGE (5pp)
            perc_energy_ratio=0.30,
            full_peak_count=800,
            perc_peak_count=400,
        )
        self.assertEqual(mode, "percussive")
        self.assertTrue(contamination)
        self.assertGreater(len(reason), 0)

    def test_contamination_flagged_by_peak_dominance(self):
        """Full has >2.5× more peaks than percussive → synth transient contamination."""
        mode, reason, contamination = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.63,
            perc_energy_ratio=0.25,
            full_peak_count=1200,
            perc_peak_count=400,   # ratio = 3.0 > FULL_PEAK_DOMINANCE (2.5)
        )
        self.assertEqual(mode, "percussive")
        self.assertTrue(contamination)

    def test_no_contamination_when_peak_ratio_below_threshold(self):
        """Peak ratio at 2.5 (not above) + small match-rate difference → no contamination."""
        mode, _, contamination = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.63,
            perc_energy_ratio=0.25,
            full_peak_count=1000,
            perc_peak_count=400,   # ratio = 2.5, equal to threshold (not >, so no flag)
        )
        self.assertEqual(mode, "percussive")
        self.assertFalse(contamination)

    def test_reason_is_never_empty(self):
        """All code paths must produce a non-empty reason string."""
        cases = [
            # energy too low
            (0.65, 0.60, PERC_ENERGY_MIN - 0.01, 800, 400),
            # full has large advantage
            (0.85, 0.60, 0.30, 800, 600),
            # normal perc preferred, no contamination
            (0.65, 0.63, 0.25, 800, 400),
            # contamination by match rate
            (0.55, 0.65, 0.30, 800, 400),
            # contamination by peak dominance
            (0.65, 0.63, 0.25, 1200, 400),
        ]
        for args in cases:
            _, reason, _ = select_analysis_mode(*args)
            self.assertGreater(len(reason.strip()), 0, f"Empty reason for args {args}")

    def test_perc_peak_count_zero_does_not_crash(self):
        """Edge case: HPSS found zero peaks — should not raise ZeroDivisionError."""
        mode, reason, _ = select_analysis_mode(
            full_match_rate=0.65,
            perc_match_rate=0.0,
            perc_energy_ratio=0.25,
            full_peak_count=800,
            perc_peak_count=0,
        )
        # With 0 perc peaks the full advantage is large → full_spectrum selected
        self.assertIn(mode, ("full_spectrum", "percussive"))
        self.assertGreater(len(reason), 0)

    def test_just_below_15pp_boundary_uses_percussive(self):
        """Full advantage of 14pp (< 15pp threshold) leaves percussive as the choice."""
        mode, _, _ = select_analysis_mode(
            full_match_rate=0.74,
            perc_match_rate=0.60,   # difference is 0.14, clearly < 0.15
            perc_energy_ratio=0.25,
            full_peak_count=800,
            perc_peak_count=600,
        )
        self.assertEqual(mode, "percussive")

    def test_just_above_15pp_boundary_uses_full(self):
        """Full advantage of 16pp (> 15pp threshold) selects full_spectrum."""
        mode, _, _ = select_analysis_mode(
            full_match_rate=0.76,
            perc_match_rate=0.60,   # difference is 0.16, clearly > 0.15
            perc_energy_ratio=0.25,
            full_peak_count=800,
            perc_peak_count=600,
        )
        self.assertEqual(mode, "full_spectrum")


# ---------------------------------------------------------------------------
# analyze_mode (numpy-only — no librosa required)
# ---------------------------------------------------------------------------

class TestAnalyzeMode(unittest.TestCase):
    """
    analyze_mode() accepts numpy arrays and calls only deterministic helpers.
    Tests use synthetic data; no audio file is needed.
    """

    _REQUIRED_KEYS = {
        "onset_peak_count", "match_rate", "initial_offset_s",
        "unmatched_anchor_count", "checkpoints", "verdict", "confidence", "warnings",
    }

    def _anchors(self):
        return np.array([0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0])

    def test_empty_peaks_returns_unknown_verdict(self):
        result = analyze_mode(
            anchors=self._anchors(),
            onset_peaks=np.array([]),
            effective_duration=10.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=2.0,
        )
        self.assertEqual(result["verdict"], "unknown")
        self.assertEqual(result["confidence"], "low")
        self.assertEqual(result["onset_peak_count"], 0)
        self.assertEqual(result["match_rate"], 0.0)

    def test_empty_peaks_returns_all_required_keys(self):
        result = analyze_mode(
            anchors=self._anchors(),
            onset_peaks=np.array([]),
            effective_duration=10.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=2.0,
        )
        for key in self._REQUIRED_KEYS:
            self.assertIn(key, result, f"Missing key: {key}")

    def test_perfect_match_returns_all_required_keys(self):
        anchors = self._anchors()
        peaks = anchors.copy()  # exact match, offset=0
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=4.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=1.0,
        )
        for key in self._REQUIRED_KEYS:
            self.assertIn(key, result, f"Missing key: {key}")

    def test_perfect_match_high_match_rate(self):
        anchors = self._anchors()
        peaks = anchors.copy()
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=4.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=1.0,
        )
        self.assertGreater(result["match_rate"], 0.9)

    def test_perfect_match_near_zero_offset(self):
        anchors = self._anchors()
        peaks = anchors.copy()
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=4.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=1.0,
        )
        self.assertAlmostEqual(result["initial_offset_s"], 0.0, delta=0.015)

    def test_shifted_peaks_correct_offset(self):
        anchors = self._anchors()
        peaks = anchors + 2.0  # audio starts 2s later
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=6.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=3.0,
        )
        self.assertAlmostEqual(result["initial_offset_s"], 2.0, delta=0.015)

    def test_checkpoints_is_list_of_three(self):
        anchors = self._anchors()
        peaks = anchors.copy()
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=4.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=1.0,
        )
        self.assertEqual(len(result["checkpoints"]), 3)

    def test_unmatched_count_is_nonnegative_int(self):
        anchors = self._anchors()
        peaks = anchors.copy()
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=4.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=1.0,
        )
        self.assertIsInstance(result["unmatched_anchor_count"], int)
        self.assertGreaterEqual(result["unmatched_anchor_count"], 0)

    def test_warnings_is_list(self):
        result = analyze_mode(
            anchors=self._anchors(),
            onset_peaks=np.array([]),
            effective_duration=10.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=2.0,
        )
        self.assertIsInstance(result["warnings"], list)

    def test_onset_peak_count_matches_input_length(self):
        anchors = self._anchors()
        peaks = np.array([0.0, 0.5, 1.0, 5.0, 6.0, 7.0])  # 6 peaks, some unmatched
        result = analyze_mode(
            anchors=anchors,
            onset_peaks=peaks,
            effective_duration=10.0,
            bpm_chart=120.0,
            bpm_audio=120.0,
            search_range=2.0,
        )
        self.assertEqual(result["onset_peak_count"], len(peaks))


# ---------------------------------------------------------------------------
# Report formatting (smoke tests)
# ---------------------------------------------------------------------------

class TestFormatReport(unittest.TestCase):

    def _sample_result(self, verdict="no_drift", confidence="high",
                       mode="percussive", contamination=False):
        """Build a minimal but complete result dict matching the current run() output."""
        _mode_data = {
            "onset_peak_count": 800,
            "match_rate": 0.72,
            "initial_offset_s": 4.0,
            "unmatched_anchor_count": 84,
            "checkpoints": [
                {"label": "early (0–33%)", "anchors_checked": 90,
                 "mean_abs_delta_ms": 12.0, "max_abs_delta_ms": 35.0, "std_delta_ms": 8.0},
                {"label": "mid (33–66%)", "anchors_checked": 95,
                 "mean_abs_delta_ms": 14.0, "max_abs_delta_ms": 40.0, "std_delta_ms": 9.0},
                {"label": "late (66–100%)", "anchors_checked": 85,
                 "mean_abs_delta_ms": 18.0, "max_abs_delta_ms": 50.0, "std_delta_ms": 11.0},
            ],
            "verdict": verdict,
            "confidence": confidence,
            "warnings": [],
        }
        _full_mode_data = {
            "onset_peak_count": 1500,
            "match_rate": 0.65,
            "initial_offset_s": 4.0,
            "unmatched_anchor_count": 105,
            "checkpoints": _mode_data["checkpoints"],
            "verdict": verdict,
            "confidence": confidence,
            "warnings": [],
        }
        return {
            "chart_title": "Test Song",
            "chart_file": "/tmp/test.modchart.json",
            "audio_file": "test.mp3",
            "anchor_definition": "kick (lane 4) + snare (lane 0)",
            "bpm_chart": 120.0,
            "bpm_audio": 120.5,
            "total_anchors": 300,
            "audio_analysis_mode": mode,
            "audio_analysis_mode_reason": "Percussive mode preferred for drum focus.",
            "percussive_energy_ratio": 0.22,
            "synth_contamination_suspected": contamination,
            # Primary mode (flat)
            "onset_peak_count": _mode_data["onset_peak_count"],
            "initial_offset_s": 4.0,
            "match_rate": _mode_data["match_rate"],
            "unmatched_anchor_count": _mode_data["unmatched_anchor_count"],
            "checkpoints": _mode_data["checkpoints"],
            "verdict": verdict,
            "confidence": confidence,
            "warnings": [],
            "limitations": ["Test limitation"],
            # Both modes
            "modes": {
                "percussive": _mode_data,
                "full_spectrum": _full_mode_data,
            },
        }

    # --- Existing tests (preserved) ---

    def test_text_report_contains_verdict(self):
        result = self._sample_result(verdict="no_drift")
        text = format_report_text(result)
        self.assertIn("NO DRIFT", text)

    def test_text_report_contains_chart_title(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("Test Song", text)

    def test_text_report_contains_offset(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("4.000", text)

    def test_text_report_contains_checkpoints(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("early", text)
        self.assertIn("mid", text)
        self.assertIn("late", text)

    def test_json_report_is_valid_json(self):
        result = self._sample_result()
        output = format_report_json(result)
        parsed = json.loads(output)
        self.assertEqual(parsed["verdict"], "no_drift")

    def test_json_report_contains_all_required_fields(self):
        result = self._sample_result()
        parsed = json.loads(format_report_json(result))
        for field in ("chart_title", "audio_file", "bpm_chart", "initial_offset_s",
                      "match_rate", "checkpoints", "verdict", "confidence", "limitations"):
            self.assertIn(field, parsed, f'Missing field: "{field}"')

    def test_minor_drift_purchase_guidance_present(self):
        result = self._sample_result(verdict="minor_drift")
        text = format_report_text(result)
        self.assertIn("PURCHASE GUIDANCE", text)

    def test_warning_appears_in_text(self):
        result = self._sample_result()
        result["warnings"] = ["BPM mismatch detected."]
        text = format_report_text(result)
        self.assertIn("BPM mismatch", text)

    # --- New tests for HPSS / mode fields ---

    def test_text_report_contains_modes_section(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("AUDIO ANALYSIS MODES", text)

    def test_text_report_shows_both_modes(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("Full-spectrum", text)
        self.assertIn("Percussive", text)

    def test_text_report_marks_selected_mode(self):
        """The selected mode line should start with ' *' as a selection marker."""
        result = self._sample_result(mode="percussive")
        text = format_report_text(result)
        # The marker ' *' should appear before 'Percussive'
        self.assertRegex(text, r"\*.*Percussive")

    def test_text_report_shows_percussive_energy_ratio(self):
        result = self._sample_result()
        text = format_report_text(result)
        # Energy ratio 0.22 → formatted as "22%"
        self.assertIn("22%", text)

    def test_text_report_weak_energy_flag(self):
        """When percussive_energy_ratio < PERC_ENERGY_MIN, a weak-energy note appears."""
        result = self._sample_result()
        result["percussive_energy_ratio"] = PERC_ENERGY_MIN - 0.01
        text = format_report_text(result)
        self.assertIn("weak", text.lower())

    def test_text_report_contamination_warning(self):
        """When synth_contamination_suspected=True, a contamination notice appears."""
        result = self._sample_result(contamination=True)
        text = format_report_text(result)
        self.assertIn("contamination", text.lower())

    def test_text_report_no_contamination_when_false(self):
        result = self._sample_result(contamination=False)
        text = format_report_text(result)
        self.assertNotIn("contamination", text.lower())

    def test_text_report_shows_mode_reason(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("Percussive mode preferred for drum focus", text)

    def test_text_report_shows_anchor_definition(self):
        result = self._sample_result()
        text = format_report_text(result)
        self.assertIn("kick", text.lower())
        self.assertIn("snare", text.lower())

    def test_json_report_contains_modes_dict(self):
        result = self._sample_result()
        parsed = json.loads(format_report_json(result))
        self.assertIn("modes", parsed)
        self.assertIn("full_spectrum", parsed["modes"])
        self.assertIn("percussive", parsed["modes"])

    def test_json_report_contains_mode_metadata(self):
        result = self._sample_result()
        parsed = json.loads(format_report_json(result))
        for field in ("audio_analysis_mode", "audio_analysis_mode_reason",
                      "percussive_energy_ratio", "synth_contamination_suspected",
                      "anchor_definition"):
            self.assertIn(field, parsed, f'Missing JSON field: "{field}"')

    def test_json_report_mode_match_rates_present(self):
        result = self._sample_result()
        parsed = json.loads(format_report_json(result))
        self.assertIn("match_rate", parsed["modes"]["percussive"])
        self.assertIn("match_rate", parsed["modes"]["full_spectrum"])

    def test_json_report_contamination_flag_serializes(self):
        result = self._sample_result(contamination=True)
        parsed = json.loads(format_report_json(result))
        self.assertTrue(parsed["synth_contamination_suspected"])

    def test_json_report_false_contamination_flag_serializes(self):
        result = self._sample_result(contamination=False)
        parsed = json.loads(format_report_json(result))
        self.assertFalse(parsed["synth_contamination_suspected"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
