import Foundation

final class InputRouter {
    private(set) var activeDevice: InputDevice
    var onInput: ((InputEvent) -> Void)?

    init(activeDevice: InputDevice) {
        self.activeDevice = activeDevice
    }

    func setActiveDevice(_ device: InputDevice) {
        activeDevice = device
    }

    func route(_ event: InputEvent) {
        onInput?(event)
    }
}
