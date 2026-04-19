import Foundation

enum InputSource: String {
    case keyboard = "Keyboard"
    case maschineMK3 = "Maschine MK3"
}

struct InputEvent {
    let lane: Lane
    let timestamp: TimeInterval
    let source: InputSource
}

protocol InputDevice {
    var source: InputSource { get }
}

protocol LaneMapping {
    func lane(for keyCode: UInt16) -> Lane?
}

struct DefaultKeyboardLaneMapper: LaneMapping {
    func lane(for keyCode: UInt16) -> Lane? {
        switch keyCode {
        case 2: return .red      // D
        case 3: return .yellow   // F
        case 38: return .blue    // J
        case 40: return .green   // K
        case 49: return .purple    // Space
        default: return nil
        }
    }
}
