import Foundation
import AppKit
import AVFoundation
import Accelerate
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
            previewClock.stop()
            detectedBPM = detectBPM(for: url)

            if let detectedBPM {
                statusText = "Loaded \(url.lastPathComponent) · BPM \(String(format: "%.1f", detectedBPM.bpm)) from \(detectedBPM.source)"
            } else {
                statusText = "Loaded \(url.lastPathComponent)"
            }
        } catch {
            audioPlayer = nil
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

        if let analyzedBPM = detectBPMFromAudioAnalysis(for: url) {
            return BPMDetectionResult(bpm: analyzedBPM, source: "analysis")
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
        }

        return nil
    }

    private func detectBPMFromFilename(_ filename: String) -> Double? {
        parseBPM(from: filename)
    }

    private func detectBPMFromAudioAnalysis(for url: URL) -> Double? {
        guard let samples = try? loadMonoSamples(from: url, maxFrames: 44100 * 90), samples.count > 8192 else {
            return nil
        }

        let envelope = buildEnergyEnvelope(from: samples, windowSize: 1024)
        guard envelope.count > 256 else { return nil }

        let sampleRate = 44100.0 / 1024.0
        let minBPM = 70.0
        let maxBPM = 190.0
        let minLag = Int(sampleRate * 60.0 / maxBPM)
        let maxLag = Int(sampleRate * 60.0 / minBPM)
        guard maxLag < envelope.count else { return nil }

        var bestLag = 0
        var bestScore: Float = 0

        for lag in minLag...maxLag {
            let score = autocorrelationScore(envelope: envelope, lag: lag)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return nil }
        var bpm = 60.0 * sampleRate / Double(bestLag)

        while bpm < 80 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }

        return (bpm * 10).rounded() / 10
    }

    private func loadMonoSamples(from url: URL, maxFrames: AVAudioFrameCount) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let frameCount = min(maxFrames, AVAudioFrameCount(file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }

        try file.read(into: buffer, frameCount: frameCount)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func buildEnergyEnvelope(from samples: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 0 else { return [] }
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / windowSize)

        var index = 0
        while index + windowSize <= samples.count {
            let window = Array(samples[index..<(index + windowSize)])
            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
            envelope.append(rms)
            index += windowSize
        }

        guard let mean = envelope.isEmpty ? nil : envelope.reduce(0, +) / Float(envelope.count) else {
            return envelope
        }

        return envelope.map { max(0, $0 - mean) }
    }

    private func autocorrelationScore(envelope: [Float], lag: Int) -> Float {
        let count = envelope.count - lag
        guard count > 0 else { return 0 }

        var lhs = Array(envelope[0..<count])
        let rhs = Array(envelope[lag..<(lag + count)])
        var result: Float = 0
        vDSP_dotpr(lhs, 1, rhs, 1, &result, vDSP_Length(count))
        return result
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
