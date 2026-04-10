import Foundation

struct MusicalPosition {
    let bar: Int
    let beat: Int
    let subdivision: Int
    let tick: Int
    let ticksPerBeat: Int
    let beatsPerBar: Int
    let subdivisionsPerBeat: Int

    var barBeatText: String {
        "\(bar):\(beat)"
    }

    var displayText: String {
        "\(bar):\(beat):\(subdivision)"
    }

    var barBeatDivisionTickText: String {
        String(format: "%d.%d.%d.%03d", bar, beat, subdivision, tick)
    }
}

enum MusicalTransport {
    static func position(
        at playbackTime: TimeInterval,
        bpm: Double,
        songOffset: TimeInterval,
        beatsPerBar: Int = 4,
        subdivisionsPerBeat: Int = 4,
        ticksPerBeat: Int = 480
    ) -> MusicalPosition {
        let safeSubdivisionsPerBeat = max(subdivisionsPerBeat, 1)
        let safeTicksPerBeat = max(ticksPerBeat, 1)
        let adjustedTime = max(0, playbackTime - songOffset)
        let beatsElapsed = adjustedTime * (bpm / 60.0)
        let totalBeats = Int(floor(beatsElapsed))
        let beatFraction = max(0, beatsElapsed - floor(beatsElapsed))
        let totalSubdivisions = Int(floor(beatsElapsed * Double(safeSubdivisionsPerBeat)))
        let subdivision = (totalSubdivisions % safeSubdivisionsPerBeat) + 1

        let subdivisionsPerBar = beatsPerBar * safeSubdivisionsPerBeat
        let bar = (totalSubdivisions / subdivisionsPerBar) + 1
        let beat = (totalBeats % beatsPerBar) + 1

        let ticksPerSubdivision = max(safeTicksPerBeat / safeSubdivisionsPerBeat, 1)
        let subdivisionProgress = beatFraction * Double(safeSubdivisionsPerBeat)
        let tick = min(Int((subdivisionProgress.truncatingRemainder(dividingBy: 1) * Double(ticksPerSubdivision)).rounded(.down)), max(ticksPerSubdivision - 1, 0))

        return MusicalPosition(
            bar: bar,
            beat: beat,
            subdivision: subdivision,
            tick: tick,
            ticksPerBeat: safeTicksPerBeat,
            beatsPerBar: beatsPerBar,
            subdivisionsPerBeat: safeSubdivisionsPerBeat
        )
    }
}
