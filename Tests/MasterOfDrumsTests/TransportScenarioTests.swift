import XCTest
@testable import MasterOfDrums

@MainActor
final class TransportScenarioTests: XCTestCase {

    // MARK: - Playback Duration Tests

    func testPlaybackDurationAudioOnly() {
        // Given: audio loaded, no chart
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(0)

        // When: getting playback duration
        let duration = game.playbackDuration

        // Then: should return audio duration
        XCTAssertEqual(duration, 60.0, "Audio-only duration should be audio duration")
    }

    func testPlaybackDurationChartOnly() {
        // Given: chart loaded, no audio
        let game = MockGameController()
        game.setAudioDuration(0)
        game.setChartEndTime(120.0)

        // When: getting playback duration
        let duration = game.playbackDuration

        // Then: should return chart end time
        XCTAssertEqual(duration, 120.0, "Chart-only duration should be chart end time")
    }

    func testPlaybackDurationAudioLonger() {
        // Given: audio 120s, chart 60s
        let game = MockGameController()
        game.setAudioDuration(120.0)
        game.setChartEndTime(60.0)

        // When: getting playback duration
        let duration = game.playbackDuration

        // Then: should return max (audio duration)
        XCTAssertEqual(duration, 120.0, "Should return audio duration when audio is longer")
    }

    func testPlaybackDurationChartLonger() {
        // Given: audio 60s, chart 120s
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(120.0)

        // When: getting playback duration
        let duration = game.playbackDuration

        // Then: should return max (chart end time)
        XCTAssertEqual(duration, 120.0, "Should return chart end time when chart is longer")
    }

    // MARK: - Scrubbing Past Audio Duration Tests

    func testScrubChartOnlyPastDuration() {
        // Given: chart-only with 120s duration
        let game = MockGameController()
        game.setAudioDuration(0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)

        // When: seeking to 90s (well within duration)
        game.seekTransport(to: 90.0)

        // Then: position should update
        XCTAssertEqual(game.currentPlaybackTime, 90.0, accuracy: 1.0, "Chart-only seek should work")
    }

    func testScrubAudioChartPastAudioEnd() {
        // Given: audio 60s, chart 120s (chart is longer)
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)

        // When: seeking to 90s (past audio end, within chart)
        game.seekTransport(to: 90.0)

        // Then: should be able to seek past audio duration
        let time = game.currentPlaybackTime
        XCTAssertGreaterThan(time, 60.0, "Should be able to scrub past audio duration")
        XCTAssertLessThanOrEqual(time, 120.0, "Should stay within chart duration")
    }

    func testScrubAudioChartFullDuration() {
        // Given: audio 60s, chart 120s
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)

        // When: seeking to end of chart
        game.seekTransport(to: 120.0)

        // Then: should reach the end
        let time = game.currentPlaybackTime
        XCTAssertGreaterThanOrEqual(time, 110.0, "Should be able to seek to near chart end")
    }

    // MARK: - Position Slider Tests

    func testSliderValueProgressCalc() {
        // Given: duration is 120s
        let game = MockGameController()
        game.setAudioDuration(120.0)

        // When: at 60s (halfway through)
        game.mockSetCurrentTime(60.0)
        let progress = game.playbackProgress

        // Then: should be 0.5
        XCTAssertEqual(progress, 0.5, accuracy: 0.01, "Progress at halfway should be 0.5")
    }

    func testSliderValueProgressChartLonger() {
        // Given: audio 60s, chart 120s
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)

        // When: at 60s position
        game.mockSetChartTime(60.0)
        let progress = game.playbackProgress

        // Then: should be 0.5 of 120s duration
        XCTAssertEqual(progress, 0.5, accuracy: 0.01, "Progress should be normalized to max duration")
    }

    // MARK: - Active Transport Time Tests

    func testActiveTransportTimeAudioOnly() {
        // Given: audio-only at 30s
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.mockSetCurrentTime(30.0)

        // When: getting active transport time
        let time = game.currentPlaybackTime

        // Then: should return audio time
        XCTAssertEqual(time, 30.0, accuracy: 1.0, "Should return audio current time")
    }

    func testActiveTransportTimeChartOnly() {
        // Given: chart-only at 30s
        let game = MockGameController()
        game.setAudioDuration(0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)
        game.mockSetChartTime(30.0)

        // When: getting active transport time
        let time = game.currentPlaybackTime

        // Then: should return chart time
        XCTAssertEqual(time, 30.0, accuracy: 1.0, "Should return chart current time")
    }

    func testActiveTransportTimeAudioChartAudio() {
        // Given: audio+chart, position within audio
        let game = MockGameController()
        game.setAudioDuration(60.0)
        game.setChartEndTime(120.0)
        game.setAdminChartActive(true)
        game.mockSetCurrentTime(30.0)

        // When: getting active transport time
        let time = game.currentPlaybackTime

        // Then: should return audio time (audio is primary when available)
        XCTAssertEqual(time, 30.0, accuracy: 1.0, "Should return audio time when both loaded")
    }
}

// MARK: - Mock Game Controller

@MainActor
class MockGameController {
    private var mockAudioDuration: Double = 0
    private var mockChartEndTime: Double = 0
    private var mockCurrentAudioTime: Double = 0
    private var mockCurrentChartTime: Double = 0
    private var mockAdminChartActive: Bool = false

    var playbackDuration: Double {
        max(mockAudioDuration, mockChartEndTime, 0)
    }

    var currentPlaybackTime: Double {
        // Match the real activeTransportTime logic:
        // When both audio and chart are present, use chart time if it's ahead (seeked past audio),
        // otherwise use audio time (audio is primary when synchronized)
        if mockAudioDuration > 0 && mockAdminChartActive {
            return mockCurrentChartTime > mockCurrentAudioTime ? mockCurrentChartTime : mockCurrentAudioTime
        } else if mockAudioDuration > 0 {
            return mockCurrentAudioTime
        } else if mockAdminChartActive {
            return mockCurrentChartTime
        } else {
            return 0
        }
    }

    var playbackProgress: Double {
        let duration = max(playbackDuration, 0.1)
        return min(max(currentPlaybackTime / duration, 0), 1)
    }

    func setAudioDuration(_ duration: Double) {
        mockAudioDuration = duration
    }

    func setChartEndTime(_ endTime: Double) {
        mockChartEndTime = endTime
    }

    func setAdminChartActive(_ active: Bool) {
        mockAdminChartActive = active
    }

    func mockSetCurrentTime(_ time: Double) {
        mockCurrentAudioTime = time
    }

    func mockSetChartTime(_ time: Double) {
        mockCurrentChartTime = time
    }

    func seekTransport(to time: Double) {
        // Mock: seek both
        let clampedTime = max(0, min(playbackDuration, time))
        mockCurrentAudioTime = min(clampedTime, mockAudioDuration)
        mockCurrentChartTime = clampedTime
    }
}
