import Foundation
@preconcurrency import AVFoundation

final class LaneSoundPlayer {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double

    init(engine: AVAudioEngine) {
        self.engine = engine
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        self.sampleRate = format.sampleRate

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(lane: Lane) {
        schedule(buffer: makeBuffer(for: lane), at: nil, interrupt: false)
    }

    func play(lane: Lane, at noteTime: Double, currentTime: Double) {
        if !engine.isRunning {
            try? engine.start()
        }
        guard let renderTime = engine.outputNode.lastRenderTime else {
            print("[LANEPLAY] NO renderTime! engine.isRunning=\(engine.isRunning)")
            schedule(buffer: makeBuffer(for: lane), at: nil, interrupt: false)
            return
        }
        let secondsAhead = noteTime - currentTime
        let samplesAhead = Int64(round(secondsAhead * sampleRate))
        let targetSampleTime = renderTime.sampleTime + samplesAhead
        let audioTime = AVAudioTime(sampleTime: targetSampleTime, atRate: sampleRate)
        print("[LANEPLAY] noteTime=\(String(format: "%.3f", noteTime)) current=\(String(format: "%.3f", currentTime)) secondsAhead=\(String(format: "%.3f", secondsAhead)) renderTime.sampleTime=\(renderTime.sampleTime) targetSampleTime=\(targetSampleTime)")
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
