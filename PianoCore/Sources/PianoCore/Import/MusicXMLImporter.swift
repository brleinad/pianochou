import Foundation

public enum MusicXMLError: Error, Equatable {
    case notXML(line: Int, message: String)
    case notMusicXML
    case unsupportedFormat(String)
    case malformed(String)
}

/// Reads uncompressed partwise MusicXML (`.musicxml` / `.xml`).
public enum MusicXMLImporter {

    public static func parse(url: URL) throws -> Score {
        try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> Score {
        let root: XNode
        do {
            root = try XMLTree.parse(data)
        } catch let error as XMLTree.ParseError {
            throw MusicXMLError.notXML(line: error.line, message: error.message)
        }

        switch root.name {
        case "score-partwise": break
        case "score-timewise": throw MusicXMLError.unsupportedFormat("score-timewise")
        default: throw MusicXMLError.notMusicXML
        }

        var partNames: [String: String] = [:]
        for scorePart in root.child("part-list")?.children("score-part") ?? [] {
            if let id = scorePart.attributes["id"] { partNames[id] = scorePart.string("part-name") }
        }

        let parts = try root.children("part").map { node in
            let id = node.attributes["id"] ?? ""
            return try parsePart(node, id: id, name: partNames[id])
        }
        guard !parts.isEmpty else { throw MusicXMLError.malformed("no parts") }

        let title = root.child("work")?.string("work-title") ?? root.string("movement-title")
        let composer = root.child("identification")?.children("creator")
            .first { $0.attributes["type"] == "composer" }?.value
        return Score(title: title, composer: composer, parts: parts)
    }

    // MARK: - Parts and measures

    /// Attributes that carry from one measure to the next.
    private struct PartState {
        var divisions = 1
        var key = KeySignature(fifths: 0)
        var time = TimeSignature(beats: 4, beatType: 4)
        var clefs: [Int: Clef] = [1: .treble]
        var staves = 1
        var openEnding: [Int]?
    }

    private static func parsePart(_ node: XNode, id: String, name: String?) throws -> Part {
        var state = PartState()
        var measures: [Measure] = []
        var start = Rational.zero
        for (index, measureNode) in node.children("measure").enumerated() {
            let measure = try parseMeasure(measureNode, index: index, start: start, state: &state)
            measures.append(measure)
            start = start + measure.duration
        }
        applyDynamicsAndPedal(to: &measures)
        return Part(id: id, name: name, staves: state.staves, measures: measures)
    }

    private static func parseMeasure(_ node: XNode, index: Int, start: Rational, state: inout PartState) throws -> Measure {
        var cursor = Rational.zero
        var lastOnset = Rational.zero
        var length = Rational.zero
        var sawNote = false

        var events: [Event] = []
        var directions: [Direction] = []
        var clefChanges: [ClefChange] = []
        var startClefs = state.clefs
        var key = state.key
        var time = state.time

        var startRepeat = false
        var endRepeatTimes: Int?
        var endingNumbers = state.openEnding

        func quarters(_ divisions: Int?) -> Rational {
            Rational(divisions ?? 0, state.divisions)
        }

        for child in node.children {
            switch child.name {
            case "attributes":
                if let divisions = child.int("divisions"), divisions > 0 { state.divisions = divisions }
                if let keyNode = child.child("key") {
                    state.key = KeySignature(fifths: keyNode.int("fifths") ?? 0, mode: keyNode.string("mode"))
                }
                if let timeNode = child.child("time"), let parsed = parseTime(timeNode) {
                    state.time = parsed
                }
                if let staves = child.int("staves") { state.staves = staves }
                // Key and time take effect for the whole measure (mid-measure changes are rare in piano music).
                if !sawNote {
                    key = state.key
                    time = state.time
                }
                for clefNode in child.children("clef") {
                    let staff = clefNode.attributes["number"].flatMap { Int($0) } ?? 1
                    let clef = parseClef(clefNode)
                    state.clefs[staff] = clef
                    if !sawNote && cursor == .zero {
                        startClefs[staff] = clef
                    } else {
                        clefChanges.append(ClefChange(offset: cursor, staff: staff, clef: clef))
                    }
                }

            case "note":
                let isGrace = child.child("grace") != nil
                let isChordNote = child.child("chord") != nil
                let duration = isGrace ? .zero : quarters(child.int("duration"))
                let note = try parseNote(child)

                if isChordNote, let last = events.indices.last, events[last].isGrace == isGrace, let note {
                    events[last].notes.append(note)
                    continue
                }

                let onset = isChordNote ? lastOnset : cursor
                events.append(Event(
                    onset: onset,
                    duration: duration,
                    type: child.string("type").flatMap(NoteType.init(rawValue:)),
                    dots: child.children("dot").count,
                    tuplet: parseTuplet(child),
                    staff: child.int("staff") ?? 1,
                    voice: child.int("voice") ?? 1,
                    isGrace: isGrace,
                    isMeasureRest: child.child("rest")?.attributes["measure"] == "yes",
                    notes: note.map { [$0] } ?? [],
                    beams: child.children("beam").compactMap(parseBeam),
                    stem: child.string("stem").flatMap(Stem.init(rawValue:)),
                    dynamic: nil,
                    pedalDown: false
                ))
                sawNote = true
                if !isGrace && !isChordNote {
                    lastOnset = cursor
                    cursor = cursor + duration
                }

            case "backup":
                cursor = max(.zero, cursor - quarters(child.int("duration")))

            case "forward":
                cursor = cursor + quarters(child.int("duration"))

            case "direction":
                let offset = cursor + quarters(child.int("offset"))
                let staff = child.int("staff")
                for kind in parseDirectionKinds(child) {
                    directions.append(Direction(offset: offset, staff: staff, kind: kind))
                }

            case "sound":
                if let tempo = child.attributes["tempo"].flatMap(Double.init) {
                    directions.append(Direction(offset: cursor, staff: nil, kind: .tempo(tempo)))
                }

            case "barline":
                if let repeatNode = child.child("repeat") {
                    if repeatNode.attributes["direction"] == "forward" {
                        startRepeat = true
                    } else {
                        endRepeatTimes = repeatNode.attributes["times"].flatMap { Int($0) } ?? 2
                    }
                }
                if let ending = child.child("ending") {
                    let numbers = parseEndingNumbers(ending.attributes["number"] ?? "")
                    if ending.attributes["type"] == "start" {
                        endingNumbers = numbers
                        state.openEnding = numbers
                    } else {
                        endingNumbers = endingNumbers ?? numbers
                        state.openEnding = nil
                    }
                }

            default:
                break
            }
            length = max(length, cursor)
        }

        let order = events.indices.sorted { a, b in
            let x = events[a], y = events[b]
            if x.onset != y.onset { return x.onset < y.onset }
            if x.staff != y.staff { return x.staff < y.staff }
            if x.voice != y.voice { return x.voice < y.voice }
            return a < b
        }

        let isImplicit = node.attributes["implicit"] == "yes"
        let isPickup = index == 0 && length > .zero && (isImplicit || length < time.measureLength)

        return Measure(
            index: index,
            number: node.attributes["number"] ?? "\(index + 1)",
            isPickup: isPickup,
            key: key,
            time: time,
            clefs: startClefs,
            clefChanges: clefChanges,
            start: start,
            duration: length,
            events: order.map { events[$0] },
            directions: directions.sorted { $0.offset < $1.offset },
            startRepeat: startRepeat,
            endRepeatTimes: endRepeatTimes,
            endingNumbers: endingNumbers
        )
    }

    // MARK: - Elements

    private static func parseNote(_ node: XNode) throws -> Note? {
        guard let pitchNode = node.child("pitch") else { return nil } // rest or unpitched
        guard let stepText = pitchNode.string("step"), let step = Step(rawValue: stepText),
              let octave = pitchNode.int("octave") else {
            throw MusicXMLError.malformed("note without a valid step/octave")
        }
        let alter = Int((pitchNode.double("alter") ?? 0).rounded())
        let ties = node.children("tie").compactMap { $0.attributes["type"] }
        let fingering = node.child("notations")?.child("technical")?.int("fingering")
        return Note(
            pitch: Pitch(step: step, alter: alter, octave: octave),
            tie: Tie(start: ties.contains("start"), stop: ties.contains("stop")),
            fingering: fingering,
            accidental: node.string("accidental")
        )
    }

    private static func parseTuplet(_ node: XNode) -> Tuplet? {
        guard let modification = node.child("time-modification"),
              let actual = modification.int("actual-notes"),
              let normal = modification.int("normal-notes") else { return nil }
        let brackets = node.child("notations")?.children("tuplet").compactMap { $0.attributes["type"] } ?? []
        return Tuplet(actual: actual, normal: normal,
                      bracketStart: brackets.contains("start"), bracketStop: brackets.contains("stop"))
    }

    private static func parseBeam(_ node: XNode) -> Beam? {
        guard let value = Beam.Value(rawValue: node.value) else { return nil }
        return Beam(level: node.attributes["number"].flatMap { Int($0) } ?? 1, value: value)
    }

    /// Handles "3", "3+2" (summed) and compound signatures like 6/8.
    private static func parseTime(_ node: XNode) -> TimeSignature? {
        guard let beatsText = node.string("beats"), let beatType = node.int("beat-type") else { return nil }
        let beats = beatsText.split(separator: "+").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
        return beats > 0 && beatType > 0 ? TimeSignature(beats: beats, beatType: beatType) : nil
    }

    private static func parseClef(_ node: XNode) -> Clef {
        let sign = node.string("sign").flatMap(Clef.Sign.init(rawValue:)) ?? .g
        let defaultLine = sign == .f ? 4 : (sign == .c ? 3 : 2)
        return Clef(sign: sign, line: node.int("line") ?? defaultLine, octaveChange: node.int("clef-octave-change") ?? 0)
    }

    private static func parseDirectionKinds(_ node: XNode) -> [Direction.Kind] {
        var kinds: [Direction.Kind] = []
        for directionType in node.children("direction-type") {
            for item in directionType.children {
                switch item.name {
                case "dynamics":
                    for mark in item.children {
                        kinds.append(.dynamic(mark.name == "other-dynamics" ? mark.value : mark.name))
                    }
                case "pedal":
                    if let action = item.attributes["type"].flatMap(Direction.PedalAction.init(rawValue:)) {
                        kinds.append(.pedal(action))
                    }
                case "words":
                    if !item.value.isEmpty { kinds.append(.words(item.value)) }
                default:
                    break
                }
            }
        }
        if let tempo = node.child("sound")?.attributes["tempo"].flatMap(Double.init) {
            kinds.append(.tempo(tempo))
        }
        return kinds
    }

    /// "1", "1, 2", "1 2" → [1, 2].
    private static func parseEndingNumbers(_ text: String) -> [Int] {
        text.split { $0 == "," || $0 == " " }.compactMap { Int($0) }
    }

    // MARK: - Carried state

    /// Marks each event with the dynamic in effect and whether the pedal is down,
    /// walking the part in written order. Dynamics are tracked per part, not per staff.
    private static func applyDynamicsAndPedal(to measures: inout [Measure]) {
        var dynamic: String?
        var pedalDown = false

        func apply(_ direction: Direction) {
            switch direction.kind {
            case .dynamic(let mark): dynamic = mark
            case .pedal(.start), .pedal(.change): pedalDown = true
            case .pedal(.stop): pedalDown = false
            default: break
            }
        }

        for m in measures.indices {
            let directions = measures[m].directions
            var next = 0
            for e in measures[m].events.indices {
                let onset = measures[m].events[e].onset
                while next < directions.count && directions[next].offset <= onset {
                    apply(directions[next])
                    next += 1
                }
                measures[m].events[e].dynamic = dynamic
                measures[m].events[e].pedalDown = pedalDown
            }
            directions[next...].forEach(apply)
        }
    }
}
