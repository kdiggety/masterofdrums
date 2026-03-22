import Foundation

struct MusicalPosition {
    let bar: Int
    let beat: Int
    let subdivision: Int
    let beatsPerBar: Int
    let subdivisionsPerBeat: Int

    var displayText: String {
        "\(bar):\(beat):\(subdivision)"
    }
}

enum MusicalTransport {
    static func position(
        at playbackTime: TimeInterval,
        bpm: Double,
        songOffset: TimeInterval,
        beatsPerBar: Int = 4,
        subdivisionsPerBeat: Int = 4
    ) -> MusicalPosition {
        let adjustedTime = max(0, playbackTime - songOffset)
        let beatsElapsed = adjustedTime * (bpm / 60.0)
        let totalSubdivisions = Int(floor(beatsElapsed * Double(subdivisionsPerBeat)))

        let subdivisionsPerBar = beatsPerBar * subdivisionsPerBeat
        let bar = (totalSubdivisions / subdivisionsPerBar) + 1
        let beat = ((totalSubdivisions / subdivisionsPerBeat) % beatsPerBar) + 1
        let subdivision = (totalSubdivisions % subdivisionsPerBeat) + 1

        return MusicalPosition(
            bar: bar,
            beat: beat,
            subdivision: subdivision,
            beatsPerBar: beatsPerBar,
            subdivisionsPerBeat: subdivisionsPerBeat
        )
    }
}
