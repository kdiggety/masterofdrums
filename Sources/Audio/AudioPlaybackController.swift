import Foundation
import AppKit
@preconcurrency import AVFoundation
import Accelerate
import UniformTypeIdentifiers

struct BPMDetectionResult {
    let bpm: Double
    let source: String
}

struct BPMAnalysisDebug {
    let status: String
    let detail: String
}

struct BPMAnalysisEstimate {
    let bpm: Double
    let detail: String
}

enum BPMAnalysisFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

private final class AudioConverterFeeder: @unchecked Sendable {
    private let inputFile: AVAudioFile
    private let inputBuffer: AVAudioPCMBuffer
    private let inputCapacity: AVAudioFrameCount
    private var reachedEOF = false

    init(inputFile: AVAudioFile, inputBuffer: AVAudioPCMBuffer, inputCapacity: AVAudioFrameCount) {
        self.inputFile = inputFile
        self.inputBuffer = inputBuffer
        self.inputCapacity = inputCapacity
    }

    func feed(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if reachedEOF {
            outStatus.pointee = .endOfStream
            return nil
        }
        do {
            try inputFile.read(into: inputBuffer, frameCount: inputCapacity)
            if inputBuffer.frameLength == 0 {
                reachedEOF = true
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return inputBuffer
        } catch {
            reachedEOF = true
            outStatus.pointee = .noDataNow
            return nil
        }
    }
}

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, PlaybackClock {
    @Published private(set) var state: TransportState = .stopped
    @Published private(set) var loadedTrackName: String?
    @Published private(set) var statusText: String = "Preview clock"
    private(set) var currentFileURL: URL?
    @Published private(set) var detectedBPM: BPMDetectionResult?
    @Published private(set) var analysisDebug = BPMAnalysisDebug(status: "Idle", detail: "No file analyzed yet")
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var isMuted: Bool = false

    let engine = AVAudioEngine()
    private let filePlayer = AVAudioPlayerNode()
    private let previewClock = PreviewPlaybackClock()

    private var audioFile: AVAudioFile?
    var anchorSampleTime: Int64 = 0
    private var fileStartTime: TimeInterval = 0
    private var audioFileDuration: TimeInterval = 0
    private let sampleRate = 44100.0

    override init() {
        super.init()
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        engine.attach(filePlayer)
        engine.connect(filePlayer, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        try? engine.start()
    }

    var currentTime: TimeInterval {
        if audioFile != nil {
            guard let renderTime = engine.outputNode.lastRenderTime else { return 0 }
            let elapsedSamples = renderTime.sampleTime - anchorSampleTime
            return TimeInterval(elapsedSamples) / sampleRate
        }
        return previewClock.currentTime
    }

    var duration: TimeInterval {
        if audioFile != nil {
            return audioFileDuration
        }
        return 0
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose backing track"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadAudioFile(from: url)
    }

    func loadAudioFile(from url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            audioFileDuration = TimeInterval(file.length) / sampleRate
            currentFileURL = url
            loadedTrackName = url.lastPathComponent
            state = .stopped
            previewClock.stop()
            detectedBPM = nil
            analysisDebug = BPMAnalysisDebug(status: "Analyzing", detail: "Checking metadata, filename, and audio signal")
            statusText = "Loaded \(url.lastPathComponent) · analyzing BPM…"

            scheduleAudioFile()

            Task {
                let detectedBPM = await detectBPM(for: url)
                self.detectedBPM = detectedBPM
                if let detectedBPM {
                    self.statusText = "Loaded \(url.lastPathComponent) · BPM \(String(format: "%.1f", detectedBPM.bpm)) from \(detectedBPM.source)"
                } else {
                    self.statusText = "Loaded \(url.lastPathComponent) · BPM not detected"
                }
            }
        } catch {
            audioFile = nil
            currentFileURL = nil
            loadedTrackName = nil
            detectedBPM = nil
            state = .stopped
            analysisDebug = BPMAnalysisDebug(status: "Load failed", detail: error.localizedDescription)
            statusText = "Audio load failed: \(error.localizedDescription)"
        }
    }

    private func scheduleAudioFile() {
        guard let audioFile else { return }
        filePlayer.scheduleFile(audioFile, at: nil)
        fileStartTime = 0
    }

    func play() {
        if audioFile != nil {
            if let renderTime = engine.outputNode.lastRenderTime {
                anchorSampleTime = renderTime.sampleTime - Int64(fileStartTime * sampleRate)
            } else {
                anchorSampleTime = 0
            }
            if !filePlayer.isPlaying {
                try? engine.start()
                filePlayer.play()
            }
            state = .playing
            statusText = "Playing \(loadedTrackName ?? "track")"
        } else {
            previewClock.play()
            state = previewClock.state
            statusText = "Playing preview clock"
        }
    }

    func pause() {
        if audioFile != nil {
            filePlayer.pause()
            state = .paused
            statusText = "Paused \(loadedTrackName ?? "track")"
        } else {
            previewClock.pause()
            state = previewClock.state
            statusText = "Preview clock paused"
        }
    }

    func stop() {
        if audioFile != nil {
            filePlayer.stop()
            scheduleAudioFile()
            state = .stopped
            statusText = loadedTrackName == nil ? "Stopped" : "Stopped \(loadedTrackName!)"
        } else {
            previewClock.stop()
            state = previewClock.state
            statusText = "Preview clock reset"
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(1.0, rate))
        statusText = "Playback speed \(Int(playbackRate * 100))%"
    }

    func toggleMute() {
        isMuted.toggle()
        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
        statusText = isMuted ? "Audio muted" : "Audio unmuted"
    }

    func unloadAudio() {
        filePlayer.stop()
        audioFile = nil
        currentFileURL = nil
        loadedTrackName = nil
        detectedBPM = nil
        state = .stopped
        previewClock.stop()
        analysisDebug = BPMAnalysisDebug(status: "Idle", detail: "No file analyzed yet")
        statusText = "Audio unloaded"
    }

    func seek(to time: TimeInterval) {
        if audioFile != nil {
            let clamped = max(0, min(time, audioFileDuration))
            filePlayer.stop()

            let targetFrame = AVAudioFramePosition(clamped * sampleRate)
            let remainingFrames = AVAudioFrameCount(max(0, Int64(audioFile!.length) - targetFrame))
            filePlayer.scheduleSegment(audioFile!, startingFrame: targetFrame, frameCount: remainingFrames, at: nil)
            fileStartTime = clamped

            if state == .playing {
                if let renderTime = engine.outputNode.lastRenderTime {
                    anchorSampleTime = renderTime.sampleTime - Int64(clamped * sampleRate)
                }
                filePlayer.play()
            }
        }
    }

    private func detectBPM(for url: URL) async -> BPMDetectionResult? {
        if let metadataBPM = await detectBPMFromMetadata(for: url) {
            analysisDebug = BPMAnalysisDebug(status: "Detected", detail: "Found BPM in file metadata")
            return BPMDetectionResult(bpm: metadataBPM, source: "metadata")
        }
        if let filenameBPM = detectBPMFromFilename(url.lastPathComponent) {
            analysisDebug = BPMAnalysisDebug(status: "Detected", detail: "Found BPM in filename")
            return BPMDetectionResult(bpm: filenameBPM, source: "filename")
        }
        switch detectBPMFromAudioAnalysis(for: url) {
        case .success(let result):
            analysisDebug = BPMAnalysisDebug(status: "Detected", detail: result.detail)
            return BPMDetectionResult(bpm: result.bpm, source: "analysis")
        case .failure(let error):
            analysisDebug = BPMAnalysisDebug(status: "Analysis failed", detail: error.localizedDescription)
            return nil
        }
    }

    private func detectBPMFromMetadata(for url: URL) async -> Double? {
        let asset = AVAsset(url: url)
        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        let metadata = (try? await asset.load(.metadata)) ?? []
        let metadataItems = commonMetadata + metadata
        for item in metadataItems {
            let stringValue = try? await item.load(.stringValue)
            if let stringValue {
                let commonKey = item.commonKey?.rawValue.lowercased()
                if commonKey == "tempo" || stringValue.lowercased().contains("bpm") {
                    if let bpm = parseBPM(from: stringValue) { return bpm }
                }
            }
            if let key = item.key as? String, ["tbpm", "tempo", "bpm"].contains(key.lowercased()) {
                if let stringValue, let bpm = parseBPM(from: stringValue) { return bpm }
                if let numberValue = try? await item.load(.numberValue) {
                    return numberValue.doubleValue
                }
            }
        }
        return nil
    }

    private func detectBPMFromFilename(_ filename: String) -> Double? {
        parseBPM(from: filename)
    }

    private func detectBPMFromAudioAnalysis(for url: URL) -> Result<BPMAnalysisEstimate, BPMAnalysisFailure> {
        guard let samples = try? loadMonoSamples(from: url, maxFrames: 44100 * 180) else {
            return .failure(.message("Could not decode audio samples"))
        }
        guard samples.count > 44100 * 20 else {
            return .failure(.message("Too few decoded samples for multi-window analysis"))
        }

        let windowFrameCount = 44100 * 20
        let stepFrameCount = 44100 * 15
        var candidates: [(bpm: Double, ratio: Float)] = []
        var start = 0
        while start + windowFrameCount <= samples.count {
            let segment = Array(samples[start..<(start + windowFrameCount)])
            if let candidate = estimateBPMCandidate(from: segment) {
                candidates.append(candidate)
            }
            start += stepFrameCount
        }
        guard !candidates.isEmpty else {
            return .failure(.message("No stable tempo candidates found across windows"))
        }

        let grouped = Dictionary(grouping: candidates) { Int(($0.bpm * 2).rounded()) }
        let ranked = grouped.map { _, values in
            let bpm = values.map(\.bpm).reduce(0, +) / Double(values.count)
            let avgRatio = values.map(\.ratio).reduce(0, +) / Float(values.count)
            return (bpm: bpm, votes: values.count, ratio: avgRatio)
        }.sorted {
            if $0.votes == $1.votes { return $0.ratio > $1.ratio }
            return $0.votes > $1.votes
        }
        guard let winner = ranked.first else {
            return .failure(.message("No ranked tempo candidates available"))
        }

        let bpm = (winner.bpm * 10).rounded() / 10
        let detail = "Estimated from \(winner.votes) window(s) · avg ratio \(String(format: "%.3f", winner.ratio))"
        return .success(BPMAnalysisEstimate(bpm: bpm, detail: detail))
    }

    private func estimateBPMCandidate(from samples: [Float]) -> (bpm: Double, ratio: Float)? {
        let envelope = buildEnergyEnvelope(from: samples, windowSize: 512)
        guard envelope.count > 512 else { return nil }

        let sampleRate = 44100.0 / 512.0
        let minLag = Int(sampleRate * 60.0 / 190.0)
        let maxLag = Int(sampleRate * 60.0 / 70.0)
        guard maxLag < envelope.count else { return nil }

        var bestLag = 0
        var bestScore: Float = 0
        var secondBestScore: Float = 0
        for lag in minLag...maxLag {
            let score = autocorrelationScore(envelope: envelope, lag: lag)
            if score > bestScore {
                secondBestScore = bestScore
                bestScore = score
                bestLag = lag
            } else if score > secondBestScore {
                secondBestScore = score
            }
        }
        guard bestLag > 0, bestScore > 0 else { return nil }

        let ratio = bestScore / max(secondBestScore, 0.0001)
        guard ratio > 1.003 else { return nil }
        var bpm = 60.0 * sampleRate / Double(bestLag)
        while bpm < 80 { bpm *= 2 }
        while bpm > 180 { bpm /= 2 }
        return ((bpm * 10).rounded() / 10, ratio)
    }

    private func loadMonoSamples(from url: URL, maxFrames: AVAudioFrameCount) throws -> [Float] {
        let inputFile = try AVAudioFile(forReading: url)
        guard let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else {
            throw NSError(domain: "AudioPlaybackController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create processing format"])
        }
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: processingFormat) else {
            throw NSError(domain: "AudioPlaybackController", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }
        let inputCapacity: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inputCapacity) else {
            throw NSError(domain: "AudioPlaybackController", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }
        let outputCapacity = min(maxFrames, AVAudioFrameCount(Double(maxFrames) * processingFormat.sampleRate / inputFile.processingFormat.sampleRate) + 1024)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "AudioPlaybackController", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }

        let feeder = AudioConverterFeeder(inputFile: inputFile, inputBuffer: inputBuffer, inputCapacity: inputCapacity)
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            feeder.feed(outStatus)
        }
        if let error { throw error }
        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioPlaybackController", code: 5, userInfo: [NSLocalizedDescriptionKey: "No converted audio data available"])
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
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
        guard !envelope.isEmpty else { return [] }
        let mean = envelope.reduce(0, +) / Float(envelope.count)
        return envelope.map { max(0, $0 - mean) }
    }

    private func autocorrelationScore(envelope: [Float], lag: Int) -> Float {
        let count = envelope.count - lag
        guard count > 0 else { return 0 }
        let lhs = Array(envelope[0..<count])
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
                      value <= 240 else { continue }
                return value
            }
        }
        return nil
    }
}
