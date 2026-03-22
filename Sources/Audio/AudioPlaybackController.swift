import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, PlaybackClock, AVAudioPlayerDelegate {
    @Published private(set) var state: TransportState = .stopped
    @Published private(set) var loadedTrackName: String?
    @Published private(set) var statusText: String = "Preview clock"

    private let previewClock = PreviewPlaybackClock()
    private var audioPlayer: AVAudioPlayer?

    var currentTime: TimeInterval {
        if let audioPlayer {
            return audioPlayer.currentTime
        }
        return previewClock.currentTime
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose backing track"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadAudioFile(from: url)
    }

    func loadAudioFile(from url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.delegate = self
            audioPlayer = player
            loadedTrackName = url.lastPathComponent
            state = .stopped
            statusText = "Loaded \(url.lastPathComponent)"
            previewClock.stop()
        } catch {
            audioPlayer = nil
            loadedTrackName = nil
            state = .stopped
            statusText = "Audio load failed: \(error.localizedDescription)"
        }
    }

    func play() {
        if let audioPlayer {
            audioPlayer.play()
            state = .playing
            statusText = "Playing \(loadedTrackName ?? "track")"
        } else {
            previewClock.play()
            state = previewClock.state
            statusText = "Playing preview clock"
        }
    }

    func pause() {
        if let audioPlayer {
            audioPlayer.pause()
            state = .paused
            statusText = "Paused \(loadedTrackName ?? "track")"
        } else {
            previewClock.pause()
            state = previewClock.state
            statusText = "Preview clock paused"
        }
    }

    func stop() {
        if let audioPlayer {
            audioPlayer.stop()
            audioPlayer.currentTime = 0
            state = .stopped
            statusText = loadedTrackName == nil ? "Stopped" : "Stopped \(loadedTrackName!)"
        } else {
            previewClock.stop()
            state = previewClock.state
            statusText = "Preview clock reset"
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        state = .stopped
        statusText = flag ? "Finished \(loadedTrackName ?? "track")" : "Playback stopped"
    }
}
