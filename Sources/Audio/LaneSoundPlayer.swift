import Foundation
@preconcurrency import AVFoundation

final class LaneSoundPlayer {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double

    // Track playback session anchor to survive engine stop/start cycles
    private var playbackSessionStartSampleTime: Int64?
    private var playbackSessionStartGlobalTime: Double?

    init(engine: AVAudioEngine) {
        self.engine = engine
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        self.sampleRate = format.sampleRate

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func setPlaybackSessionAnchor(globalTime: Double) {
        guard let renderTime = engine.outputNode.lastRenderTime else {
            print("[LANEPLAY] Cannot set anchor: NO renderTime available! engine.isRunning=\(engine.isRunning)")
            return
        }
        playbackSessionStartSampleTime = renderTime.sampleTime
        playbackSessionStartGlobalTime = globalTime
        print("[LANEPLAY] Set session anchor: globalTime=\(String(format: "%.3f", globalTime)) sampleTime=\(renderTime.sampleTime)")
    }

    func clearPlaybackSessionAnchor() {
        playbackSessionStartSampleTime = nil
        playbackSessionStartGlobalTime = nil
        print("[LANEPLAY] Cleared session anchor")
    }

    func play(lane: Lane) {
        schedule(buffer: makeBuffer(for: lane), at: nil, interrupt: false)
    }

    func play(lane: Lane, at noteTime: Double, currentTime: Double) {
        if !engine.isRunning {
            do {
                try engine.start()
                print("[LANEPLAY] Restarted engine")
            } catch {
                print("[LANEPLAY] Failed to restart engine: \(error)")
            }
        }

        // Use session anchor to calculate sample-accurate time, independent of renderTime resets
        guard let sessionStartSampleTime = playbackSessionStartSampleTime,
              let sessionStartGlobalTime = playbackSessionStartGlobalTime else {
            print("[LANEPLAY] NO session anchor! engine.isRunning=\(engine.isRunning)")
            schedule(buffer: makeBuffer(for: lane), at: nil, interrupt: false)
            return
        }

        // Calculate elapsed time since session started
        let elapsedInSession = currentTime - sessionStartGlobalTime
        let elapsedSamples = Int64(round(elapsedInSession * sampleRate))
        let currentSessionSampleTime = sessionStartSampleTime + elapsedSamples

        // Calculate how far ahead the note is
        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(round(secondsAhead * sampleRate))
        let targetSampleTime = currentSessionSampleTime + samplesAhead

        let audioTime = AVAudioTime(sampleTime: targetSampleTime, atRate: sampleRate)
        print("[LANEPLAY] noteTime=\(String(format: "%.3f", noteTime)) current=\(String(format: "%.3f", currentTime)) target=\(targetSampleTime)")
        schedule(buffer: makeBuffer(for: lane), at: audioTime, interrupt: false)
    }

    func playMetronome(isDownbeat: Bool) {
        schedule(buffer: makeMetronomeBuffer(isDownbeat: isDownbeat), at: nil, interrupt: false)
    }

    func cancelScheduled() {
        player.stop()
        player.play()
    }

    private func schedule(buffer: AVAudioPCMBuffer, at time: AVAudioTime?, interrupt: Bool) {
        player.scheduleBuffer(buffer, at: time, options: interrupt ? .interrupts : [], completionHandler: nil)
        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
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
            duration = 0.06
            frequency = 520
            noiseMix = 0.96
            amplitude = 0.22
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
