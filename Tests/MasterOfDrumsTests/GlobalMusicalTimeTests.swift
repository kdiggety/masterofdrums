import XCTest
@testable import MasterOfDrums

final class GlobalMusicalTimeTests: XCTestCase {

    var globalTime: GlobalMusicalTime!

    override func setUp() {
        super.setUp()
        globalTime = GlobalMusicalTime()
    }

    // MARK: - Basic Time Updates

    func testInitialTimeIsZero() {
        XCTAssertEqual(globalTime.time, 0, "Initial time should be 0")
    }

    func testInitialDurationIsZero() {
        XCTAssertEqual(globalTime.duration, 0, "Initial duration should be 0")
    }

    func testSeekUpdatesTime() {
        globalTime.setDuration(120)
        globalTime.seek(to: 30, from: .external)
        XCTAssertEqual(globalTime.time, 30, "Seek should update time")
    }

    func testResetToZero() {
        globalTime.setDuration(120)
        globalTime.seek(to: 60, from: .external)
        globalTime.reset(from: .external)
        XCTAssertEqual(globalTime.time, 0, "Reset should set time to 0")
    }

    // MARK: - Clamping

    func testSeekClampedToMinimumZero() {
        globalTime.setDuration(120)
        globalTime.seek(to: -10, from: .external)
        XCTAssertEqual(globalTime.time, 0, "Seek should clamp to 0")
    }

    func testSeekClampedToMaximumDuration() {
        globalTime.setDuration(120)
        globalTime.seek(to: 150, from: .external)
        XCTAssertEqual(globalTime.time, 120, "Seek should clamp to duration")
    }

    func testSetDurationClampsCurrentTime() {
        globalTime.setDuration(120)
        globalTime.seek(to: 100, from: .external)
        globalTime.setDuration(50)
        XCTAssertEqual(globalTime.time, 50, "Setting duration should clamp current time")
    }

    // MARK: - Event Emissions

    func testDidChangeEventSentOnSeek() {
        globalTime.setDuration(120)
        var receivedTime: Double?
        var receivedSource: TimeChangeSource?

        let subscription = globalTime.didChange.sink { time, source in
            receivedTime = time
            receivedSource = source
        }

        globalTime.seek(to: 45, from: .positionSlider)

        XCTAssertEqual(receivedTime, 45, "Event should contain updated time")
        XCTAssertEqual(receivedSource, .positionSlider, "Event should contain source")
        subscription.cancel()
    }

    func testDidChangeEventSentOnReset() {
        globalTime.setDuration(120)
        globalTime.seek(to: 60, from: .external)

        var receivedTime: Double?
        var receivedSource: TimeChangeSource?

        let subscription = globalTime.didChange.sink { time, source in
            receivedTime = time
            receivedSource = source
        }

        globalTime.reset(from: .laneScrubbing)

        XCTAssertEqual(receivedTime, 0, "Reset event should have time 0")
        XCTAssertEqual(receivedSource, .laneScrubbing, "Reset event should contain source")
        subscription.cancel()
    }

    func testNoEventWhenTimeUnchanged() {
        globalTime.setDuration(120)
        globalTime.seek(to: 50, from: .external)

        var eventCount = 0
        let subscription = globalTime.didChange.sink { _, _ in
            eventCount += 1
        }

        globalTime.seek(to: 50, from: .external)

        XCTAssertEqual(eventCount, 0, "No event should fire if time doesn't change")
        subscription.cancel()
    }

    // MARK: - Multiple Subscribers

    func testMultipleSubscribersReceiveEvents() {
        globalTime.setDuration(120)

        var subscriber1Received = false
        var subscriber2Received = false

        let sub1 = globalTime.didChange.sink { _, _ in subscriber1Received = true }
        let sub2 = globalTime.didChange.sink { _, _ in subscriber2Received = true }

        globalTime.seek(to: 30, from: .external)

        XCTAssertTrue(subscriber1Received, "First subscriber should receive event")
        XCTAssertTrue(subscriber2Received, "Second subscriber should receive event")

        sub1.cancel()
        sub2.cancel()
    }

    // MARK: - Source Tracking

    func testAllSourcesProperlyTracked() {
        globalTime.setDuration(120)

        let sources: [TimeChangeSource] = [
            .positionSlider, .laneScrubbing, .stepNavigation, .barJump,
            .songSectionDrag, .playback, .external
        ]

        for (index, source) in sources.enumerated() {
            var receivedSource: TimeChangeSource?
            let subscription = globalTime.didChange.sink { _, src in
                receivedSource = src
            }

            let seekTime = Double((index + 1) * 10)
            globalTime.seek(to: seekTime, from: source)

            XCTAssertEqual(receivedSource, source, "Source \(source) should be properly tracked")
            subscription.cancel()
        }
    }

    // MARK: - Published Properties

    func testTimePublishedPropertyUpdates() {
        globalTime.setDuration(120)

        var publishedTime: Double?
        let subscription = globalTime.$time.sink { time in
            publishedTime = time
        }

        globalTime.seek(to: 75, from: .external)

        XCTAssertEqual(publishedTime, 75, "@Published time should update")
        subscription.cancel()
    }

    func testDurationPublishedPropertyUpdates() {
        var publishedDuration: Double?
        let subscription = globalTime.$duration.sink { duration in
            publishedDuration = duration
        }

        globalTime.setDuration(240)

        XCTAssertEqual(publishedDuration, 240, "@Published duration should update")
        subscription.cancel()
    }

    // MARK: - Edge Cases

    func testSetDurationToZeroResetsTime() {
        globalTime.setDuration(120)
        globalTime.seek(to: 60, from: .external)
        globalTime.setDuration(0)

        XCTAssertEqual(globalTime.time, 0, "Setting duration to 0 should reset time")
    }

    func testNegativeDurationTreatedAsZero() {
        globalTime.setDuration(-50)
        XCTAssertEqual(globalTime.duration, 0, "Negative duration should be treated as 0")
    }

    func testSeekWithZeroDuration() {
        globalTime.setDuration(0)
        globalTime.seek(to: 100, from: .external)
        XCTAssertEqual(globalTime.time, 0, "Cannot seek beyond 0 when duration is 0")
    }

    // MARK: - Bidirectional Control Pattern

    func testControlCanIgnoreOwnEvents() {
        globalTime.setDuration(120)

        var updateCount = 0
        let subscription = globalTime.didChange.sink { _, source in
            // Control ignores its own events
            if source == .positionSlider { return }
            updateCount += 1
        }

        // Event from position slider - ignored
        globalTime.seek(to: 30, from: .positionSlider)
        XCTAssertEqual(updateCount, 0, "Control should ignore own events")

        // Event from playback - processed
        globalTime.seek(to: 40, from: .playback)
        XCTAssertEqual(updateCount, 1, "Control should process other sources")

        subscription.cancel()
    }

    // MARK: - Rapid Sequential Updates

    func testRapidUpdatesAllEmitEvents() {
        globalTime.setDuration(120)

        var eventCount = 0
        let subscription = globalTime.didChange.sink { _, _ in
            eventCount += 1
        }

        globalTime.seek(to: 10, from: .playback)
        globalTime.seek(to: 20, from: .playback)
        globalTime.seek(to: 30, from: .playback)

        XCTAssertEqual(eventCount, 3, "All sequential updates should emit events")
        subscription.cancel()
    }
}
