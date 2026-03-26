import AppKit
import Foundation

struct KeyboardInputDevice: InputDevice {
    let source: InputSource = .keyboard
    private let laneMapper: LaneMapping

    init(laneMapper: LaneMapping = DefaultKeyboardLaneMapper()) {
        self.laneMapper = laneMapper
    }

    func makeInputEvent(from event: NSEvent, songTime: TimeInterval) -> InputEvent? {
        guard let lane = laneMapper.lane(for: event.keyCode) else {
            return nil
        }

        return InputEvent(lane: lane, timestamp: songTime, source: source)
    }
}
