import Foundation

enum TransportState: String {
    case stopped = "Stopped"
    case playing = "Playing"
    case paused = "Paused"
}

@MainActor
protocol PlaybackClock: AnyObject {
    var currentTime: TimeInterval { get }
    var state: TransportState { get }
    var loadedTrackName: String? { get }

    func play()
    func pause()
    func stop()
}

final class PreviewPlaybackClock: PlaybackClock {
    private var anchorDate: Date?
    private var accumulatedTime: TimeInterval = 0

    private(set) var state: TransportState = .stopped
    private(set) var loadedTrackName: String? = nil

    var currentTime: TimeInterval {
        switch state {
        case .playing:
            return accumulatedTime + (anchorDate.map { Date().timeIntervalSince($0) } ?? 0)
        case .paused, .stopped:
            return accumulatedTime
        }
    }

    func play() {
        guard state != .playing else { return }
        anchorDate = Date()
        state = .playing
    }

    func pause() {
        guard state == .playing else { return }
        accumulatedTime = currentTime
        anchorDate = nil
        state = .paused
    }

    func stop() {
        accumulatedTime = 0
        anchorDate = nil
        state = .stopped
    }
}
