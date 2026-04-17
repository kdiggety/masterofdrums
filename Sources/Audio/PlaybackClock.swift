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
        print("[scrub] PreviewPlaybackClock.play called: accumulatedTime=\(accumulatedTime), state before=\(state)")
        anchorDate = Date()
        state = .playing
        print("[scrub] PreviewPlaybackClock.play done: state after=\(state)")
    }

    func pause() {
        guard state == .playing else { return }
        print("[scrub] PreviewPlaybackClock.pause called: accumulatedTime before=\(accumulatedTime), state before=\(state)")
        accumulatedTime = currentTime
        anchorDate = nil
        state = .paused
        print("[scrub] PreviewPlaybackClock.pause done: accumulatedTime after=\(accumulatedTime), state after=\(state)")
    }

    func stop() {
        print("[scrub] PreviewPlaybackClock.stop called: accumulatedTime before=\(accumulatedTime), state before=\(state)")
        accumulatedTime = 0
        anchorDate = nil
        state = .stopped
        print("[scrub] PreviewPlaybackClock.stop done: accumulatedTime after=\(accumulatedTime), state after=\(state)")
    }

    func seek(to time: TimeInterval) {
        print("[scrub] PreviewPlaybackClock.seek called: time=\(time), state=\(state), accumulatedTime before=\(accumulatedTime)")
        accumulatedTime = max(0, time)
        if state == .playing {
            anchorDate = Date()
        }
        print("[scrub] PreviewPlaybackClock.seek done: accumulatedTime after=\(accumulatedTime), currentTime=\(currentTime)")
    }
}
