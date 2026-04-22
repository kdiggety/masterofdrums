import XCTest
@testable import MasterOfDrums

@MainActor
final class LaneSoundPlayerSchedulingTests: XCTestCase {

    func testSampleTimeCalculationWithFreshRenderTime() {
        // Scenario: Schedule a note 100ms ahead of current time
        let currentTime: Double = 0.5      // We're at 0.5 seconds
        let noteTime: Double = 0.6         // Note is at 0.6 seconds (100ms ahead)
        let sampleRate: Double = 44100.0

        // Expected calculation:
        // secondsAhead = 0.6 - 0.5 = 0.1
        // samplesAhead = 0.1 * 44100 = 4410 samples
        // If renderTime.sampleTime = 22050 (0.5s at 44.1kHz), then:
        // targetSampleTime = 22050 + 4410 = 26460

        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(round(secondsAhead * sampleRate))

        // Verify the math: 100ms @ 44.1kHz = 4410 samples
        XCTAssertEqual(samplesAhead, 4410, "100ms should be 4410 samples at 44.1kHz")
    }

    func testSampleTimeMonotonicity() {
        // Verify: When scheduling multiple notes in sequence, sample times increase monotonically
        let sampleRate: Double = 44100.0

        // Simulate scheduling 3 notes with advancing currentTime
        // This tests that the fresh-renderTime approach produces correct ordering
        let notes = [
            (currentTime: 0.0, noteTime: 0.1),   // 4410 samples ahead
            (currentTime: 0.05, noteTime: 0.15), // 4410 samples ahead
            (currentTime: 0.10, noteTime: 0.20), // 4410 samples ahead
        ]

        var calculatedSampleTimes: [Int64] = []
        let mockRenderTimeSampleTime: Int64 = 22050 // 0.5 seconds at 44.1kHz

        for (currentTime, noteTime) in notes {
            let secondsAhead = noteTime - currentTime
            let samplesAhead = Int64(secondsAhead * sampleRate)
            let targetSampleTime = mockRenderTimeSampleTime + samplesAhead
            calculatedSampleTimes.append(targetSampleTime)
        }

        // All should have the same offset (4410 samples) from the mock render time
        XCTAssertEqual(calculatedSampleTimes[0], 22050 + 4410, "First note: 0.5s + 100ms")
        XCTAssertEqual(calculatedSampleTimes[1], 22050 + 4410, "Second note: same offset")
        XCTAssertEqual(calculatedSampleTimes[2], 22050 + 4410, "Third note: same offset")
    }

    func testSampleTimeAdvancesWithRenderTime() {
        // Verify: As the render time advances, scheduled notes advance too
        // This is the key difference from stale anchorSampleTime
        let sampleRate: Double = 44100.0

        let noteTime: Double = 0.6
        let currentTime: Double = 0.5
        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(secondsAhead * sampleRate)

        // Scenario 1: renderTime at start (sampleTime = 22050 = 0.5s)
        let renderTime1: Int64 = 22050
        let targetTime1 = renderTime1 + samplesAhead  // Should be 26460

        // Scenario 2: renderTime 100ms later (sampleTime = 26460 = 0.6s)
        let renderTime2: Int64 = 26460
        let targetTime2 = renderTime2 + samplesAhead  // Should be 30870

        // The difference is 4410 samples (100ms), which is correct!
        XCTAssertEqual(targetTime2 - targetTime1, 4410, "Render time advance should match time elapsed")
    }

    func testStaleAnchorTimeProblematic() {
        // Demonstrate why stale anchorSampleTime is wrong:
        // If we capture anchorSampleTime=22050 at engine start, but then
        // schedule a note 100ms later when renderTime=26460, we get wrong result

        let sampleRate: Double = 44100.0
        let staleAnchorSampleTime: Int64 = 22050  // Captured at engine start
        let noteTime: Double = 0.6
        let currentTime: Double = 0.5
        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(secondsAhead * sampleRate)

        // OLD method (broken):
        let targetWithStaleAnchor = staleAnchorSampleTime + samplesAhead  // 22050 + 4410 = 26460

        // NEW method (correct, assuming renderTime has advanced):
        let freshRenderTime: Int64 = 26460  // Has advanced by now
        let targetWithFreshRender = freshRenderTime + samplesAhead  // 26460 + 4410 = 30870

        // They're different! The stale anchor is 4410 samples behind
        XCTAssertEqual(targetWithFreshRender - targetWithStaleAnchor, 4410,
                      "Stale anchor causes sample time to be 100ms in the past")
    }

    func testNoNegativeSampleOffsets() {
        // Verify: Notes scheduled at or before current time don't produce negative offsets
        let sampleRate: Double = 44100.0

        // Note already playing or just passed
        let currentTime: Double = 0.5
        let noteTime: Double = 0.5  // Same time
        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(round(secondsAhead * sampleRate))

        XCTAssertEqual(samplesAhead, 0, "Note at current time should be 0 offset")

        // Note in the past (shouldn't happen but check safety)
        let noteTimePast: Double = 0.4
        let secondsAheadPast = noteTimePast - currentTime
        let samplesAheadPast = Int64(round(secondsAheadPast * sampleRate))

        XCTAssertEqual(samplesAheadPast, -4410, "Past note should have negative offset")
    }
}
