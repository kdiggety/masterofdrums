import Foundation

struct MIDIChartLoader {
    struct LoadedChartSummary {
        let sourceName: String
        let bytes: Int
        let status: String
    }

    private struct MIDITrackData {
        let name: String
        let notes: [(tick: Int, note: Int, velocity: Int, channel: Int)]
    }

    func inspectFile(at url: URL) throws -> LoadedChartSummary {
        let data = try Data(contentsOf: url)
        let chart = try loadChart(from: url)
        return LoadedChartSummary(
            sourceName: url.lastPathComponent,
            bytes: data.count,
            status: "Imported \(chart.notes.count) notes from \(chart.title)"
        )
    }

    func loadChart(from url: URL) throws -> Chart {
        let data = try Data(contentsOf: url)
        var offset = 0

        guard readString(data, &offset, length: 4) == "MThd" else {
            throw NSError(domain: "MIDIChartLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing MIDI header"])
        }

        let headerLength = try readUInt32(data, &offset)
        _ = try readUInt16(data, &offset)
        let trackCount = try readUInt16(data, &offset)
        let division = Int(try readUInt16(data, &offset))

        if headerLength > 6 {
            offset += Int(headerLength - 6)
        }

        var tracks: [MIDITrackData] = []
        for _ in 0..<trackCount {
            guard readString(data, &offset, length: 4) == "MTrk" else {
                throw NSError(domain: "MIDIChartLoader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing track chunk"])
            }
            let length = Int(try readUInt32(data, &offset))
            let trackData = data.subdata(in: offset..<(offset + length))
            tracks.append(try parseTrack(trackData))
            offset += length
        }

        let ticksPerQuarter = max(division, 1)
        let secondsPerTick = (60.0 / 95.0) / Double(ticksPerQuarter)

        let mappedNotes = tracks.flatMap { track -> [NoteEvent] in
            let lane = lane(forTrackName: track.name)
            return track.notes.compactMap { note in
                guard let lane else { return nil }
                let time = Double(note.tick) * secondsPerTick
                return NoteEvent(lane: lane, time: time)
            }
        }
        .sorted { $0.time < $1.time }

        return Chart(notes: mappedNotes, title: url.deletingPathExtension().lastPathComponent)
    }

    private func lane(forTrackName name: String) -> Lane? {
        let lower = name.lowercased()
        if lower.contains("kick") { return .kick }
        if lower.contains("snare") { return .red }
        if lower.contains("closedhh") || lower.contains("closed hh") || lower.contains("hihat") || lower.contains("hi hat") { return .yellow }
        return nil
    }

    private func parseTrack(_ data: Data) throws -> MIDITrackData {
        var offset = 0
        var runningStatus: UInt8?
        var absoluteTick = 0
        var trackName = "Unnamed Track"
        var notes: [(tick: Int, note: Int, velocity: Int, channel: Int)] = []

        while offset < data.count {
            let delta = try readVariableLength(data, &offset)
            absoluteTick += delta
            guard offset < data.count else { break }

            var status = data[offset]
            if status < 0x80 {
                guard let runningStatus else {
                    throw NSError(domain: "MIDIChartLoader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Running status without previous status"])
                }
                status = runningStatus
            } else {
                offset += 1
                runningStatus = status
            }

            if status == 0xFF {
                let metaType = data[offset]
                offset += 1
                let length = try readVariableLength(data, &offset)
                let payload = data.subdata(in: offset..<(offset + length))
                offset += length

                if metaType == 0x03, let name = String(data: payload, encoding: .utf8) {
                    trackName = name
                } else if metaType == 0x2F {
                    break
                }
                continue
            }

            if status == 0xF0 || status == 0xF7 {
                let length = try readVariableLength(data, &offset)
                offset += length
                continue
            }

            let eventType = status >> 4
            let channel = Int(status & 0x0F)

            switch eventType {
            case 0x8, 0x9, 0xA, 0xB, 0xE:
                let note = Int(data[offset])
                let velocity = Int(data[offset + 1])
                offset += 2
                if eventType == 0x9, velocity > 0 {
                    notes.append((tick: absoluteTick, note: note, velocity: velocity, channel: channel))
                }
            case 0xC, 0xD:
                offset += 1
            default:
                break
            }
        }

        return MIDITrackData(name: trackName, notes: notes)
    }

    private func readString(_ data: Data, _ offset: inout Int, length: Int) -> String {
        let value = String(decoding: data[offset..<(offset + length)], as: UTF8.self)
        offset += length
        return value
    }

    private func readUInt16(_ data: Data, _ offset: inout Int) throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw NSError(domain: "MIDIChartLoader", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected end of MIDI data"])
        }
        let value = data[offset..<(offset + 2)].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        offset += 2
        return value
    }

    private func readUInt32(_ data: Data, _ offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw NSError(domain: "MIDIChartLoader", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected end of MIDI data"])
        }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        offset += 4
        return value
    }

    private func readVariableLength(_ data: Data, _ offset: inout Int) throws -> Int {
        var value = 0
        while true {
            guard offset < data.count else {
                throw NSError(domain: "MIDIChartLoader", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unexpected end of MIDI variable-length value"])
            }
            let byte = Int(data[offset])
            offset += 1
            value = (value << 7) | (byte & 0x7F)
            if (byte & 0x80) == 0 { break }
        }
        return value
    }
}
