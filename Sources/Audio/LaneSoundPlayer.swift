import Foundation
@preconcurrency import AVFoundation

final class LaneSoundPlayer {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double
    private var sampleCache: [Lane: AVAudioPCMBuffer] = [:]

    // Track playback session anchor to survive engine stop/start cycles
    private var playbackSessionStartSampleTime: Int64?
    private var playbackSessionStartGlobalTime: Double?

    init(engine: AVAudioEngine) {
        self.engine = engine
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        self.sampleRate = format.sampleRate

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Initialize player node state by stopping it - ensures clean state before first play
        player.stop()
    }

    func setPlaybackSessionAnchor(globalTime: Double) {
        guard let renderTime = engine.outputNode.lastRenderTime else {
            return
        }
        playbackSessionStartSampleTime = renderTime.sampleTime
        playbackSessionStartGlobalTime = globalTime
    }

    func clearPlaybackSessionAnchor() {
        playbackSessionStartSampleTime = nil
        playbackSessionStartGlobalTime = nil
        // When stopping, reset the player node so it will play() again when engine restarts
        player.stop()
    }

    func play(lane: Lane) {
        // Load sample or synthesize on background thread, schedule on main
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = self?.getBuffer(for: lane)
            DispatchQueue.main.async {
                guard let buffer else { return }
                self?.schedule(buffer: buffer, lane: lane, at: nil, interrupt: false)
            }
        }
    }

    func play(lane: Lane, at noteTime: Double, currentTime: Double) {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // Engine restart failed, but schedule anyway
            }
        }

        // Load sample or synthesize on background thread, schedule on main
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = self?.getBuffer(for: lane)
            DispatchQueue.main.async {
                guard let buffer else { return }
                self?.schedule(buffer: buffer, lane: lane, at: nil, interrupt: false)
            }
        }
    }

    func playMetronome(isDownbeat: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = self?.makeMetronomeBuffer(isDownbeat: isDownbeat)
            DispatchQueue.main.async {
                guard let buffer else { return }
                // Metronome doesn't interrupt
                self?.schedule(buffer: buffer, lane: nil, at: nil, interrupt: false)
            }
        }
    }

    func cancelScheduled() {
        player.stop()
        player.play()
    }

    private func schedule(buffer: AVAudioPCMBuffer, lane: Lane?, at time: AVAudioTime?, interrupt: Bool) {
        // Determine if we should interrupt based on lane type
        let shouldInterrupt: Bool
        if let lane = lane {
            // Green lane (crash/open hi-hat) always interrupts
            // Others (kicks, snares, toms) don't interrupt
            shouldInterrupt = (lane == .green)
        } else {
            shouldInterrupt = interrupt
        }

        player.scheduleBuffer(buffer, at: time, options: shouldInterrupt ? .interrupts : [], completionHandler: nil)
        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    private func getBuffer(for lane: Lane) -> AVAudioPCMBuffer? {
        // Check cache first
        if let cached = sampleCache[lane] {
            // Create a copy of the cached buffer to allow simultaneous playback
            let copy = AVAudioPCMBuffer(pcmFormat: cached.format, frameCapacity: cached.frameLength)!
            copy.frameLength = cached.frameLength
            memcpy(copy.floatChannelData![0], cached.floatChannelData![0], Int(cached.frameLength) * MemoryLayout<Float>.size)
            // Scale volume for specific lanes
            scaleVolume(buffer: copy, for: lane)
            return copy
        }

        // Try to load sample file
        if let sampleBuffer = loadSampleBuffer(for: lane) {
            sampleCache[lane] = sampleBuffer
            // Return a copy for this playback
            let copy = AVAudioPCMBuffer(pcmFormat: sampleBuffer.format, frameCapacity: sampleBuffer.frameLength)!
            copy.frameLength = sampleBuffer.frameLength
            memcpy(copy.floatChannelData![0], sampleBuffer.floatChannelData![0], Int(sampleBuffer.frameLength) * MemoryLayout<Float>.size)
            // Scale volume for specific lanes
            scaleVolume(buffer: copy, for: lane)
            return copy
        }

        // Fallback to synthesis
        return makeBuffer(for: lane)
    }

    private func scaleVolume(buffer: AVAudioPCMBuffer, for lane: Lane) {
        let scale: Float
        switch lane {
        case .green:
            scale = 0.7  // 30% reduction = 70% of original
        default:
            scale = 1.0  // No change
        }

        guard scale != 1.0 else { return }

        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) {
            channel[i] *= scale
        }
    }

    private func loadSampleBuffer(for lane: Lane) -> AVAudioPCMBuffer? {
        let sampleFilenames: [Lane: String] = [
            .yellow: "Sources/Audio/Samples/Closed-Hi-Hat-1.wav",
            .green: "Sources/Audio/Samples/Yamaha-TG100-Open-Hi-Hat.wav"
        ]

        guard let relativePath = sampleFilenames[lane] else {
            return nil
        }

        let url = URL(fileURLWithPath: relativePath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Sample file not found at: \(url.path)")
            return nil
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            print("✅ Loaded \(lane) sample: \(audioFile.length) frames @ \(audioFile.processingFormat.sampleRate)Hz, channels: \(audioFile.processingFormat.channelCount)")

            // Read into original format first
            let originalBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length))!
            try audioFile.read(into: originalBuffer)

            // Convert to player format if needed
            if audioFile.processingFormat.channelCount != format.channelCount {
                print("⚠️ Converting from \(audioFile.processingFormat.channelCount) channels to \(format.channelCount) channels")
                let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: originalBuffer.frameLength)!

                // Simple mono conversion: if stereo, mix channels; if mono, use as-is
                if audioFile.processingFormat.channelCount == 2 && format.channelCount == 1 {
                    // Mix stereo to mono
                    let sourceL = originalBuffer.floatChannelData![0]
                    let sourceR = originalBuffer.floatChannelData![1]
                    let dest = convertedBuffer.floatChannelData![0]
                    for i in 0..<Int(originalBuffer.frameLength) {
                        dest[i] = (sourceL[i] + sourceR[i]) * 0.5
                    }
                }
                convertedBuffer.frameLength = originalBuffer.frameLength
                print("✅ Converted to \(format.channelCount) channels, \(convertedBuffer.frameLength) frames")
                return convertedBuffer
            }

            print("✅ Buffered \(originalBuffer.frameLength) frames for \(lane)")
            return originalBuffer
        } catch {
            print("❌ Error loading \(lane) sample: \(error)")
            return nil
        }
    }

    private func makeBuffer(for lane: Lane) -> AVAudioPCMBuffer {
        let duration: Double
        let frequency: Double
        let noiseMix: Double
        let amplitude: Double

        switch lane {
        case .purple:
            duration = 0.18
            frequency = 62
            noiseMix = 0.02
            amplitude = 0.85
        case .red:
            duration = 0.14
            frequency = 215
            noiseMix = 0.72
            amplitude = 0.72
        case .yellow:
            duration = 0.04
            frequency = 1400
            noiseMix = 0.75
            amplitude = 0.12
        case .blue:
            duration = 0.10
            frequency = 240
            noiseMix = 0.40
            amplitude = 0.45
        case .green:
            duration = 0.12
            frequency = 150
            noiseMix = 0.30
            amplitude = 0.50
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        var phase: Double = 0
        let phaseStep = (2.0 * Double.pi * frequency) / sampleRate

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let decay = exp(-7.5 * t / duration)
            let sine = sin(phase)
            let noise = Double.random(in: -1...1)
            let sample = ((1.0 - noiseMix) * sine + noiseMix * noise) * amplitude * decay
            channel[i] = Float(max(-1, min(1, sample)))
            phase += phaseStep
        }

        return buffer
    }

    private func makeMetronomeBuffer(isDownbeat: Bool) -> AVAudioPCMBuffer {
        let duration: Double = isDownbeat ? 0.07 : 0.05
        let frequency: Double = isDownbeat ? 1760 : 1320
        let amplitude: Double = isDownbeat ? 0.5 : 0.35
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        var phase: Double = 0
        let phaseStep = (2.0 * Double.pi * frequency) / sampleRate
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let decay = exp(-14.0 * t / duration)
            let sample = sin(phase) * amplitude * decay
            channel[i] = Float(max(-1, min(1, sample)))
            phase += phaseStep
        }

        return buffer
    }
}
