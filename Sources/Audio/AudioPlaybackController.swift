import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct BPMDetectionResult {
    let bpm: Double
    let source: String
}

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, PlaybackClock, AVAudioPlayerDelegate {
    @Published private(set) var state: TransportState = .stopped
    @Published private(set) var loadedTrackName: String?
    @Published private(set) var statusText: String = "Preview clock"
    @Published private(set) var detectedBPM: BPMDetectionResult?

    private let previewClock = PreviewPlaybackClock()
    private var audioPlayer: AVAudioPlayer?
    private var loadedURL: URL?

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
            loadedURL = url
            loadedTrackName = url.lastPathComponent
            state = .stopped
            previewClock.stop()
            detectedBPM = detectBPM(for: url)

            if let detectedBPM {
                statusText = "Loaded \(url.lastPathComponent) · BPM \(String(format: "%.1f", detectedBPM.bpm)) from \(detectedBPM.source)"
            } else {
                statusText = "Loaded \(url.lastPathComponent)"
            }
        } catch {
            audioPlayer = nil
            loadedURL = nil
            loadedTrackName = nil
            detectedBPM = nil
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

    private func detectBPM(for url: URL) -> BPMDetectionResult? {
        if let metadataBPM = detectBPMFromMetadata(for: url) {
            return BPMDetectionResult(bpm: metadataBPM, source: "metadata")
        }

        if let filenameBPM = detectBPMFromFilename(url.lastPathComponent) {
            return BPMDetectionResult(bpm: filenameBPM, source: "filename")
        }

        return nil
    }

    private func detectBPMFromMetadata(for url: URL) -> Double? {
        let asset = AVAsset(url: url)
        let metadataItems = asset.commonMetadata + asset.metadata

        for item in metadataItems {
            if let stringValue = item.stringValue {
                let commonKey = item.commonKey?.rawValue.lowercased()
                if commonKey == "tempo" || stringValue.lowercased().contains("bpm") {
                    if let bpm = parseBPM(from: stringValue) {
                        return bpm
                    }
                }
            }

            if let key = item.key as? String,
               ["tbpm", "tempo", "bpm"].contains(key.lowercased()) {
                if let stringValue = item.stringValue, let bpm = parseBPM(from: stringValue) {
                    return bpm
                }
                if let numberValue = item.numberValue?.doubleValue {
                    return numberValue
                }
            }

            if let keySpace = item.keySpace?.rawValue.lowercased(),
               keySpace.contains("id3"),
               let key = item.key as? String,
               key.lowercased().contains("tbpm") {
                if let stringValue = item.stringValue, let bpm = parseBPM(from: stringValue) {
                    return bpm
                }
            }
        }

        return nil
    }

    private func detectBPMFromFilename(_ filename: String) -> Double? {
        parseBPM(from: filename)
    }

    private func parseBPM(from text: String) -> Double? {
        let pattern = #"(?i)(\d{2,3}(?:\.\d+)?)\s*bpm|\b(\d{2,3}(?:\.\d+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            for index in 1..<match.numberOfRanges {
                let matchRange = match.range(at: index)
                guard matchRange.location != NSNotFound,
                      let range = Range(matchRange, in: text),
                      let value = Double(text[range]),
                      value >= 40,
                      value <= 240 else {
                    continue
                }
                return value
            }
        }

        return nil
    }
}
