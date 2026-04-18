#!/usr/bin/env python3
"""Tests for MIDI-to-modchart conversion, ensuring MIDI notes map to correct drum lanes."""

import unittest
from midi_to_modchart import NOTE_LABELS, LANE_MAP


class TestLaneMapping(unittest.TestCase):
    """Validate that MIDI note numbers map to correct drum lanes.

    Lane indices match the Swift Lane enum:
    - 0 = red (snare)
    - 1 = yellow (hi-hat, cymbals)
    - 2 = blue (high toms)
    - 3 = green (low/mid toms, crashes, rides)
    - 4 = kick
    """

    def test_kick_notes_map_to_kick_lane(self):
        """MIDI notes 35, 36 (kick) should map to lane 4."""
        self.assertEqual(LANE_MAP[35], 4, "Acoustic Bass Drum should be kick")
        self.assertEqual(LANE_MAP[36], 4, "Bass Drum should be kick")

    def test_snare_notes_map_to_red_lane(self):
        """MIDI notes 37-40 (snare/clap) should map to lane 0 (red)."""
        self.assertEqual(LANE_MAP[37], 0, "Side Stick should be red")
        self.assertEqual(LANE_MAP[38], 0, "Snare should be red")
        self.assertEqual(LANE_MAP[39], 0, "Hand Clap should be red")
        self.assertEqual(LANE_MAP[40], 0, "Snare should be red")

    def test_hihat_notes_map_to_yellow_lane(self):
        """MIDI notes 42, 44, 46 (hi-hat) should map to lane 1 (yellow)."""
        self.assertEqual(LANE_MAP[42], 1, "HiHat Closed should be yellow")
        self.assertEqual(LANE_MAP[44], 1, "HiHat Pedal should be yellow")
        self.assertEqual(LANE_MAP[46], 1, "HiHat Open should be yellow")

    def test_high_tom_notes_map_to_blue_lane(self):
        """MIDI notes 48, 50 (high tom) should map to lane 2 (blue)."""
        self.assertEqual(LANE_MAP[48], 2, "Tom High should be blue")
        self.assertEqual(LANE_MAP[50], 2, "Tom High should be blue")

    def test_low_and_mid_tom_notes_map_to_green_lane(self):
        """MIDI notes 41, 43, 45, 47 (low/mid tom) should map to lane 3 (green).

        This is where a common bug occurs: confusing which toms go to which lane.
        - Lane 2 (blue) = high toms only (48, 50)
        - Lane 3 (green) = low/mid toms (41, 43, 45, 47)
        """
        self.assertEqual(LANE_MAP[41], 3, "Tom Low should be green, not blue")
        self.assertEqual(LANE_MAP[43], 3, "Tom Low should be green, not blue")
        self.assertEqual(LANE_MAP[45], 3, "Tom Mid should be green, not blue")
        self.assertEqual(LANE_MAP[47], 3, "Tom Mid should be green, not blue")

    def test_crash_ride_notes_map_to_green_lane(self):
        """MIDI notes 49, 51-52, 55, 57, 59 (crash/ride) should map to lane 3 (green)."""
        self.assertEqual(LANE_MAP[49], 3, "Crash should be green")
        self.assertEqual(LANE_MAP[51], 3, "Ride should be green")
        self.assertEqual(LANE_MAP[52], 3, "Crash should be green")
        self.assertEqual(LANE_MAP[55], 3, "Splash should be green")
        self.assertEqual(LANE_MAP[57], 3, "Crash should be green")
        self.assertEqual(LANE_MAP[59], 3, "Ride should be green")

    def test_all_mapped_notes_have_labels(self):
        """Every MIDI note in LANE_MAP should have a label in NOTE_LABELS."""
        for midi_note in LANE_MAP.keys():
            self.assertIn(midi_note, NOTE_LABELS,
                         f"MIDI note {midi_note} has lane mapping but no label")

    def test_drum_kit_coverage(self):
        """Verify complete drum kit coverage with no unmapped notes."""
        expected_coverage = {
            4: [35, 36],                    # kick
            0: [37, 38, 39, 40],            # snare/clap (red)
            1: [42, 44, 46],                # hi-hat (yellow)
            2: [48, 50],                    # high tom (blue)
            3: [41, 43, 45, 47, 49, 51, 52, 55, 57, 59],  # low/mid tom, crash, ride (green)
        }

        # Build actual coverage from LANE_MAP
        actual_coverage = {}
        for midi_note, lane in LANE_MAP.items():
            if lane not in actual_coverage:
                actual_coverage[lane] = []
            actual_coverage[lane].append(midi_note)

        # Sort for comparison
        for lane in expected_coverage:
            expected_coverage[lane].sort()
        for lane in actual_coverage:
            actual_coverage[lane].sort()

        self.assertEqual(actual_coverage, expected_coverage,
                        "Drum kit coverage should match expected lane assignments")


if __name__ == "__main__":
    unittest.main()
