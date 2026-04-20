import Foundation
import Combine

enum TimeChangeSource {
    case positionSlider
    case laneScrubbing
    case stepNavigation
    case barJump
    case songSectionDrag
    case playback
    case external
}

class GlobalMusicalTime {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0

    let didChange = PassthroughSubject<(time: Double, source: TimeChangeSource), Never>()

    func seek(to newTime: Double, from source: TimeChangeSource) {
        let clamped = clamp(newTime, min: 0, max: duration)
        if time != clamped {
            time = clamped
            didChange.send((time, source))
        }
    }

    func reset(from source: TimeChangeSource) {
        seek(to: 0, from: source)
    }

    func setDuration(_ newDuration: Double) {
        duration = max(0, newDuration)
        // Clamp current time if it exceeds new duration
        if time > duration {
            time = duration
            didChange.send((time, .external))
        }
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
