import XCTest
@testable import MasterOfDrums

final class DualAudioChartScrubTests: XCTestCase {

    var globalTime: GlobalMusicalTime!

    override func setUp() {
        super.setUp()
        globalTime = GlobalMusicalTime()
    }

    // MARK: - Both Audio and Chart Loaded

    func testScrubWithBothAudioAndChartLoaded() {
        // Simulate both audio and chart loaded
        globalTime.setDuration(120)  // Audio + chart total duration

        // Start scrubbing at 30 seconds
        globalTime.seek(to: 30, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 30, "Scrub should set time to 30")

        // Continue scrubbing to 60 seconds
        globalTime.seek(to: 60, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 60, "Scrub should update to 60")

        // Release scrub (simulate playback source)
        globalTime.seek(to: 60, from: .playback)
        XCTAssertEqual(globalTime.time, 60, "Time should remain at 60 after release")
    }

    func testScrubDoesNotResetToZero() {
        globalTime.setDuration(120)

        // Scrub to middle
        globalTime.seek(to: 50, from: .laneScrubbing)

        // Simulate sequence of events after release
        globalTime.seek(to: 50, from: .playback)
        globalTime.seek(to: 50, from: .playback)

        XCTAssertEqual(globalTime.time, 50, "Time should never snap back to 0")
    }

    func testMultipleScrubbingSessionsWithBothLoaded() {
        globalTime.setDuration(120)

        // First scrubbing session
        globalTime.seek(to: 20, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 20, "First scrub should set to 20")

        // Second scrubbing session
        globalTime.seek(to: 80, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 80, "Second scrub should set to 80")

        // Both should work without reset
        globalTime.seek(to: 40, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 40, "Third scrub should set to 40")
    }

    func testEventSourcesCorrectlyIdentified() {
        globalTime.setDuration(120)

        var lastSource: TimeChangeSource?
        let subscription = globalTime.didChange.sink { _, source in
            lastSource = source
        }

        globalTime.seek(to: 50, from: .laneScrubbing)
        XCTAssertEqual(lastSource, .laneScrubbing, "Source should be laneScrubbing")

        globalTime.seek(to: 60, from: .playback)
        XCTAssertEqual(lastSource, .playback, "Source should change to playback")

        subscription.cancel()
    }

    func testEventsFiredForEachScrubUpdate() {
        globalTime.setDuration(120)

        var eventCount = 0
        let subscription = globalTime.didChange.sink { _, _ in
            eventCount += 1
        }

        // Simulate user dragging through multiple positions
        globalTime.seek(to: 10, from: .laneScrubbing)
        globalTime.seek(to: 20, from: .laneScrubbing)
        globalTime.seek(to: 30, from: .laneScrubbing)
        globalTime.seek(to: 40, from: .laneScrubbing)

        XCTAssertEqual(eventCount, 4, "Each scrub position should fire an event")

        subscription.cancel()
    }

    func testTimeRemainsValidAcrossSourceChanges() {
        globalTime.setDuration(120)

        // Scrub to position
        globalTime.seek(to: 75, from: .laneScrubbing)

        // Playback takes over
        globalTime.seek(to: 75, from: .playback)
        XCTAssertEqual(globalTime.time, 75)

        // Scrub again
        globalTime.seek(to: 85, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 85)

        // Back to playback
        globalTime.seek(to: 85, from: .playback)
        XCTAssertEqual(globalTime.time, 85)

        // Scrub one more time
        globalTime.seek(to: 95, from: .laneScrubbing)
        XCTAssertEqual(globalTime.time, 95)
    }
}
