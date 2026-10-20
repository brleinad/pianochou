import Foundation

/// Lays out a few bars of one part, as a grand staff or a single staff, for the playing screen.
///
/// Not a general engraver: one system, no line breaks, and only the collision handling a 1–2 bar
/// window of piano music needs (seconds in chords, stacked accidentals, two voices per staff).
public enum Engraver {
    public struct Options: Sendable {
        public var fingering: Bool
        public var counts: Bool
        /// Show the time signature at the start. Nil: only when the window starts at the first bar.
        public var timeSignature: Bool?

        public init(fingering: Bool = true, counts: Bool = true, timeSignature: Bool? = nil) {
            self.fingering = fingering
            self.counts = counts
            self.timeSignature = timeSignature
        }
    }

    public static func engrave(_ score: Score, part: Int = 0, measures: Range<Int>, options: Options = Options()) -> Engraving {
        Layout(part: score.parts[part], range: measures, options: options).run()
    }
}

// MARK: - Layout

private final class Layout {
    // Bravura engraving defaults, in staff spaces.
    static let staffLineThickness = 0.13
    static let stemThickness = 0.12
    static let ledgerThickness = 0.16
    static let ledgerExtension = 0.4
    static let thinBarline = 0.16
    static let thickBarline = 0.5
    static let stemAnchor = 0.168
    static let graceScale = 0.65
    static let accidentalColumn = 1.1
    static let middleLineY = 2.0

    struct Head {
        var noteIndex: Int
        var step: Int
        var displaced = false
        var accidental: Glyph?
        var accidentalColumn = 0
    }

    final class Info {
        let ref: Engraving.NoteRef
        let event: Event
        let time: Rational
        var heads: [Head] = []
        var hasStem = false
        var stemUp = true
        var beamGroup: Int?
        var voiceRank = 0
        var multiVoice = false
        var x = 0.0
        var stemEnd = 0.0
        var accidentalColumns = 0

        init(ref: Engraving.NoteRef, event: Event, time: Rational) {
            self.ref = ref
            self.event = event
            self.time = time
        }

        var scale: Double { event.isGrace ? Layout.graceScale : 1 }

        var headGlyph: Glyph {
            switch event.type {
            case .breve: .noteheadDoubleWhole
            case .whole: .noteheadWhole
            case .half: .noteheadHalf
            default: .noteheadBlack
            }
        }

        var headWidth: Double { headGlyph.width * scale }
        var hasLeftDisplaced: Bool { !stemUp && heads.contains(where: \.displaced) }
        var hasRightDisplaced: Bool { stemUp && heads.contains(where: \.displaced) }

        /// Flags or beams: 1 for eighths, 2 for sixteenths, …
        var beamLevels: Int {
            switch event.type {
            case .eighth: 1
            case .sixteenth: 2
            case .thirtySecond: 3
            case .sixtyFourth, .oneHundredTwentyEighth: 4
            default: 0
            }
        }

        var stemX: Double { stemUp ? x + headWidth - Layout.stemThickness / 2 : x + Layout.stemThickness / 2 }
        /// y of the notehead nearest the stem's free end, and of the one farthest from it.
        var nearY: Double { stemUp ? StaffPosition.y(heads.last!.step) : StaffPosition.y(heads.first!.step) }
        var farY: Double { stemUp ? StaffPosition.y(heads.first!.step) : StaffPosition.y(heads.last!.step) }

        func headX(_ head: Head) -> Double {
            head.displaced ? (stemUp ? x + headWidth : x - headWidth) : x
        }
    }

    struct Pending {
        var item: Engraving.Item
        /// Staff the item's y is relative to; nil once it is absolute.
        var staff: Int?
    }

    let part: Part
    let range: Range<Int>
    let options: Engraver.Options
    let staffCount: Int

    var infos: [[Info]] = []
    var beamGroups: [[Info]] = []
    var pending: [Pending] = []
    var timeline: [(time: Rational, x: Double, isOnset: Bool)] = []
    var barlineXs: [Double] = []
    var systemX = 0.0
    var contentStart = 0.0
    var endX = 0.0
    /// Clef in effect at each event, by measure and event index.
    var clefAt: [[Clef]] = []

    init(part: Part, range: Range<Int>, options: Engraver.Options) {
        self.part = part
        self.range = range.clamped(to: 0..<part.measures.count)
        self.options = options
        staffCount = max(1, part.staves, part.measures[self.range].flatMap(\.events).map(\.staff).max() ?? 1)
    }

    func run() -> Engraving {
        analyseNotes()
        layOutHorizontally()
        for group in beamGroups { placeBeam(group) }
        for measure in infos { for info in measure { emitEvent(info) } }
        emitTies()
        emitTuplets()
        let tops = stackStaves()
        emitStaffLinesAndBarlines(tops)
        let overlays = emitOverlays(tops)
        return finish(tops, overlays: overlays)
    }

    func add(_ shape: Engraving.Shape, _ role: Engraving.Role, staff: Int?, ref: Engraving.NoteRef? = nil, time: Rational? = nil) {
        pending.append(Pending(item: Engraving.Item(shape: shape, role: role, ref: ref, time: time), staff: staff))
    }

    // MARK: Pass 1 — pitches, accidentals, stems, beams

    func analyseNotes() {
        var openBeams: [String: [Info]] = [:]
        for m in range {
            let measure = part.measures[m]
            var clefs = measure.clefs
            var alters: [Int: [Int: Int]] = [:] // staff → diatonic → alter in effect
            var changes = measure.clefChanges.sorted { $0.offset < $1.offset }
            var measureInfos: [Info] = []
            var measureClefs: [Clef] = []

            // Which voices share each staff in this measure.
            var voices: [Int: [Int]] = [:]
            for event in measure.events where !voices[event.staff, default: []].contains(event.voice) {
                voices[event.staff, default: []].append(event.voice)
            }

            for (e, event) in measure.events.enumerated() {
                while let change = changes.first, change.offset <= event.onset {
                    clefs[change.staff] = change.clef
                    changes.removeFirst()
                }
                let clef = clefs[event.staff] ?? (event.staff == 1 ? .treble : .bass)
                measureClefs.append(clef)
                let info = Info(ref: .init(measure: m, event: e), event: event, time: measure.start + event.onset)
                let staffVoices = voices[event.staff, default: []].sorted()
                info.multiVoice = staffVoices.count > 1
                info.voiceRank = staffVoices.firstIndex(of: event.voice) ?? 0

                for (n, note) in event.notes.enumerated() {
                    let step = StaffPosition.step(of: note.pitch, clef: clef)
                    let diatonic = StaffPosition.diatonic(note.pitch.step, note.pitch.octave)
                    let current = alters[event.staff]?[diatonic] ?? Self.keyAlter(note.pitch.step, fifths: measure.key.fifths)
                    var accidental: Glyph?
                    if !note.tie.stop && (note.pitch.alter != current || note.accidental != nil) {
                        accidental = Self.accidentalGlyph(note.pitch.alter)
                    }
                    alters[event.staff, default: [:]][diatonic] = note.pitch.alter
                    info.heads.append(Head(noteIndex: n, step: step, accidental: accidental))
                }
                info.heads.sort { $0.step < $1.step }

                let stemless: Set<NoteType?> = [.whole, .breve, nil]
                info.hasStem = !event.isRest && !stemless.contains(event.type) && event.stem != Stem.none
                if let stem = event.stem, stem == .up || stem == .down || stem == .double {
                    info.stemUp = stem != .down
                } else if info.multiVoice {
                    info.stemUp = info.voiceRank == 0
                } else if !info.heads.isEmpty {
                    info.stemUp = Self.prefersStemUp(info.heads.map(\.step))
                }

                // Beam groups, per staff and voice.
                let key = "\(event.staff)/\(event.voice)"
                if let beam = event.beams.first(where: { $0.level == 1 }), info.hasStem {
                    switch beam.value {
                    case .begin:
                        openBeams[key] = [info]
                    case .continue:
                        openBeams[key, default: []].append(info)
                    case .end:
                        if var group = openBeams.removeValue(forKey: key) {
                            group.append(info)
                            closeBeamGroup(group)
                        }
                    case .forwardHook, .backwardHook:
                        break
                    }
                }
                measureInfos.append(info)
            }
            infos.append(measureInfos)
            clefAt.append(measureClefs)
        }

        for info in infos.joined() where !info.heads.isEmpty {
            displaceSeconds(info)
            stackAccidentals(info)
        }
    }

    func closeBeamGroup(_ group: [Info]) {
        guard group.count > 1 else { return }
        let index = beamGroups.count
        let up: Bool
        if let explicit = group.compactMap(\.event.stem).first(where: { $0 == .up || $0 == .down }) {
            up = explicit == .up
        } else if group[0].multiVoice {
            up = group[0].voiceRank == 0
        } else {
            up = Self.prefersStemUp(group.flatMap { $0.heads.map(\.step) })
        }
        for info in group {
            info.beamGroup = index
            info.stemUp = up
        }
        beamGroups.append(group)
    }

    /// Stem up when the notes lie mostly below the middle line; a tie goes down.
    static func prefersStemUp(_ steps: [Int]) -> Bool {
        guard let low = steps.min(), let high = steps.max() else { return true }
        return 4 - low > high - 4
    }

    /// In a chord with a second, one note of the pair moves to the other side of the stem.
    func displaceSeconds(_ info: Info) {
        let order = info.stemUp ? Array(info.heads.indices) : info.heads.indices.reversed()
        var previous: Int?
        for i in order {
            if let p = previous, abs(info.heads[i].step - info.heads[p].step) == 1, !info.heads[p].displaced {
                info.heads[i].displaced = true
            }
            previous = i
        }
    }

    /// Accidentals in a chord: top down, each in the first column where it clears the others by 3 spaces.
    func stackAccidentals(_ info: Info) {
        var columns: [[Int]] = []
        for i in info.heads.indices.reversed() where info.heads[i].accidental != nil {
            let step = info.heads[i].step
            let column = columns.firstIndex { $0.allSatisfy { abs($0 - step) >= 6 } } ?? columns.count
            if column == columns.count { columns.append([]) }
            columns[column].append(step)
            info.heads[i].accidentalColumn = column
        }
        info.accidentalColumns = columns.count
    }

    static func keyAlter(_ step: Step, fifths: Int) -> Int {
        let sharps: [Step] = [.F, .C, .G, .D, .A, .E, .B]
        if fifths > 0 { return sharps.prefix(fifths).contains(step) ? 1 : 0 }
        if fifths < 0 { return sharps.reversed().prefix(-fifths).contains(step) ? -1 : 0 }
        return 0
    }

    static func accidentalGlyph(_ alter: Int) -> Glyph {
        switch alter {
        case ...(-2): .accidentalDoubleFlat
        case -1: .accidentalFlat
        case 0: .accidentalNatural
        case 1: .accidentalSharp
        default: .accidentalDoubleSharp
        }
    }

    // MARK: Pass 2 — horizontal positions

    func layOutHorizontally() {
        let first = part.measures[range.lowerBound]
        systemX = staffCount > 1 ? 1.4 : 0
        var x = systemX + 0.6

        // Header: clefs, key signature, time signature.
        for staff in 1...staffCount {
            emitClef(first.clefs[staff] ?? (staff == 1 ? .treble : .bass), change: false, x: x, staff: staff)
        }
        x += 2.8 + 0.7
        let keyWidth = emitKeySignature(fifths: first.key.fifths, cancelling: 0, measure: range.lowerBound, x: x)
        x += keyWidth > 0 ? keyWidth + 0.7 : 0
        if options.timeSignature ?? (range.lowerBound == 0) {
            x += emitTimeSignature(first.time, x: x) + 1.0
        }
        contentStart = x
        timeline.append((first.start, x, false))
        x += 0.4

        for (k, m) in range.enumerated() {
            let measure = part.measures[m]
            if k > 0 {
                let previous = part.measures[m - 1]
                x += 1.0
                var clefChanged = false
                for staff in 1...staffCount {
                    if let clef = measure.clefs[staff], let before = endClef(previous, staff: staff), clef != before {
                        emitClef(clef, change: true, x: x, staff: staff)
                        clefChanged = true
                    }
                }
                if clefChanged { x += 2.4 }
                if measure.key != previous.key {
                    let width = emitKeySignature(fifths: measure.key.fifths, cancelling: previous.key.fifths, measure: m, x: x)
                    x += width + 0.8
                }
                if measure.time != previous.time {
                    x += emitTimeSignature(measure.time, x: x) + 1.0
                }
            }
            if measure.startRepeat {
                emitRepeat(start: true, x: x)
                x += 1.6
            }
            x = layOutMeasure(k, from: x)
            barlineXs.append(x)
            timeline.append((measure.start + measure.duration, x, false))
        }
        endX = x
    }

    func endClef(_ measure: Measure, staff: Int) -> Clef? {
        measure.clefChanges.last { $0.staff == staff }?.clef ?? measure.clefs[staff]
    }

    /// Places one measure's events from `start`; returns the x of its closing barline.
    func layOutMeasure(_ k: Int, from start: Double) -> Double {
        let measure = part.measures[range.lowerBound + k]
        let events = infos[k]
        let onsets = Array(Set(events.filter { !$0.event.isGrace }.map(\.event.onset))).sorted()
        var x = start
        guard !onsets.isEmpty else { return x + 4 }

        for (j, onset) in onsets.enumerated() {
            let here = events.filter { $0.event.onset == onset }
            let main = here.filter { !$0.event.isGrace }
            let graces = here.filter(\.event.isGrace)

            var pre = 0.0
            for info in main {
                var left = info.hasLeftDisplaced ? info.headWidth : 0
                if info.accidentalColumns > 0 { left += 0.25 + Double(info.accidentalColumns) * Self.accidentalColumn }
                pre = max(pre, left)
            }
            var graceWidth = 0.0
            for staff in 1...staffCount {
                graceWidth = max(graceWidth, Double(graces.filter { $0.event.staff == staff }.count) * 1.6)
            }
            let clefChangeHere = measure.clefChanges.contains { $0.offset == onset && onset > 0 }
            let clefWidth = clefChangeHere ? 2.4 : 0
            x += pre + graceWidth + clefWidth

            if clefChangeHere {
                for change in measure.clefChanges where change.offset == onset {
                    emitClef(change.clef, change: true, x: x - pre - graceWidth - clefWidth, staff: change.staff)
                }
            }
            for staff in 1...staffCount {
                let staffGraces = graces.filter { $0.event.staff == staff }
                for (g, grace) in staffGraces.enumerated() {
                    grace.x = x - pre - Double(staffGraces.count - g) * 1.6 + 0.2
                }
            }

            var right = Glyph.noteheadBlack.width
            for info in main {
                info.x = x
                var width = info.headWidth + (info.hasRightDisplaced ? info.headWidth : 0)
                if info.event.dots > 0 { width += 0.35 + Double(info.event.dots) * 0.5 }
                if info.hasStem && info.stemUp && info.beamGroup == nil && info.beamLevels > 0 { width += 0.9 }
                right = max(right, width)
            }
            let headWidth = main.first { !$0.event.isRest }?.headWidth ?? Glyph.noteheadBlack.width
            timeline.append((measure.start + onset, x + headWidth / 2, true))

            let next = j + 1 < onsets.count ? onsets[j + 1] : measure.duration
            let duration = max((next - onset).doubleValue, 1.0 / 16)
            let space = max(Tuning.quarterNoteSpace * pow(duration, Tuning.noteSpaceExponent), Tuning.minimumNoteSpace)
            x += max(space, right + 0.6)
        }
        if measure.clefChanges.contains(where: { $0.offset >= measure.duration }) {
            for change in measure.clefChanges where change.offset >= measure.duration {
                emitClef(change.clef, change: true, x: x, staff: change.staff)
            }
            x += 2.4
        }
        return x
    }

    // MARK: Pass 3 — items (y relative to each staff's top line)

    func emitClef(_ clef: Clef, change: Bool, x: Double, staff: Int) {
        let glyph: Glyph = switch (clef.sign, clef.octaveChange, change) {
        case (.f, _, true): .fClefChange
        case (.c, _, true): .cClefChange
        case (_, _, true): .gClefChange
        case (.f, -1, _): .fClef8vb
        case (.f, _, _): .fClef
        case (.c, _, _): .cClef
        case (_, -1, _): .gClef8vb
        case (_, 1, _): .gClef8va
        default: .gClef
        }
        add(.glyph(glyph, at: .init(x: x, y: Double(5 - clef.line)), scale: 1), .clef, staff: staff)
    }

    /// Draws the key signature on every staff (with naturals for accidentals the new key drops); returns its width.
    func emitKeySignature(fifths: Int, cancelling old: Int, measure: Int, x: Double) -> Double {
        var width = 0.0
        for staff in 1...staffCount {
            let resolved = part.measures[measure].clefs[staff] ?? (staff == 1 ? .treble : .bass)
            var keep = abs(fifths)
            if (old > 0) != (fifths > 0) || fifths == 0 { keep = 0 }
            let cancelled = StaffPosition.keySignature(fifths: old, clef: resolved).dropFirst(min(keep, abs(old)))
            var cx = x
            for accidental in cancelled {
                add(.glyph(.accidentalNatural, at: .init(x: cx, y: StaffPosition.y(accidental.step)), scale: 1), .keySignature, staff: staff)
                cx += 0.9
            }
            for accidental in StaffPosition.keySignature(fifths: fifths, clef: resolved) {
                add(.glyph(accidental.glyph, at: .init(x: cx, y: StaffPosition.y(accidental.step)), scale: 1), .keySignature, staff: staff)
                cx += 1.05
            }
            width = max(width, cx - x)
        }
        return width
    }

    /// Draws the time signature on every staff; returns its width.
    func emitTimeSignature(_ time: TimeSignature, x: Double) -> Double {
        func digits(_ n: Int) -> [Glyph] { String(n).compactMap(\.wholeNumberValue).map(Glyph.timeSigDigit) }
        let top = digits(time.beats), bottom = digits(time.beatType)
        let topWidth = top.reduce(0) { $0 + $1.width }, bottomWidth = bottom.reduce(0) { $0 + $1.width }
        let width = max(topWidth, bottomWidth)
        for staff in 1...staffCount {
            for (row, y, rowWidth) in [(top, 1.0, topWidth), (bottom, 3.0, bottomWidth)] {
                var cx = x + (width - rowWidth) / 2
                for glyph in row {
                    add(.glyph(glyph, at: .init(x: cx, y: y), scale: 1), .timeSignature, staff: staff)
                    cx += glyph.width
                }
            }
        }
        return width
    }

    /// `tops` given: the staves are already stacked, so the dots are placed absolutely.
    func emitRepeat(start: Bool, x: Double, tops: [Double]? = nil) {
        // Thick, thin, dots for a start repeat; mirrored for an end repeat. Lines are drawn across staves later.
        let thick = start ? x + Self.thickBarline / 2 : x - Self.thickBarline / 2
        let thin = start ? x + Self.thickBarline + 0.4 : x - Self.thickBarline - 0.4
        let dots = start ? thin + 0.4 : thin - 0.4 - Glyph.repeatDot.width
        repeats.append((thick, Self.thickBarline))
        repeats.append((thin, Self.thinBarline))
        for staff in 1...staffCount {
            for y in [1.5, 2.5] {
                let top = tops?[staff - 1] ?? 0
                add(.glyph(.repeatDot, at: .init(x: dots, y: top + y), scale: 1), .barline, staff: tops == nil ? staff : nil)
            }
        }
    }

    var repeats: [(x: Double, thickness: Double)] = []

    func emitEvent(_ info: Info) {
        let staff = info.event.staff
        let ref = info.ref, time = info.time
        if info.event.isRest {
            emitRest(info)
            return
        }
        let width = info.headWidth
        let scale = info.scale
        let left = info.x - (info.hasLeftDisplaced ? width : 0)

        for head in info.heads {
            let y = StaffPosition.y(head.step)
            let hx = info.headX(head)
            let noteRef = Engraving.NoteRef(measure: ref.measure, event: ref.event, note: head.noteIndex)
            add(.glyph(info.headGlyph, at: .init(x: hx, y: y), scale: scale), .notehead, staff: staff, ref: noteRef, time: time)
            if let accidental = head.accidental {
                let columnRight = left - 0.2 - Double(head.accidentalColumn) * Self.accidentalColumn
                add(.glyph(accidental, at: .init(x: columnRight - accidental.width * scale, y: y), scale: scale),
                    .accidental, staff: staff, ref: noteRef, time: time)
            }
        }

        // Ledger lines: one per line between the staff and the note, as wide as the noteheads needing it.
        var ledgers: [Int: (Double, Double)] = [:]
        for head in info.heads where head.step <= -2 || head.step >= 10 {
            let hx = info.headX(head)
            let lines = head.step < 0 ? Array(stride(from: -2, through: head.step, by: -2)) : Array(stride(from: 10, through: head.step, by: 2))
            for line in lines {
                let span = ledgers[line] ?? (hx, hx + width)
                ledgers[line] = (min(span.0, hx), max(span.1, hx + width))
            }
        }
        for (line, span) in ledgers.sorted(by: { $0.key < $1.key }) {
            let y = StaffPosition.y(line)
            add(.line(from: .init(x: span.0 - Self.ledgerExtension * scale, y: y), to: .init(x: span.1 + Self.ledgerExtension * scale, y: y),
                      thickness: Self.ledgerThickness), .ledger, staff: staff, ref: ref, time: time)
        }

        // Dots sit in spaces: a note on a line moves its dot up (down for a lower voice).
        if info.event.dots > 0 {
            let dotX = info.x + width + (info.hasRightDisplaced ? width : 0) + 0.35 * scale
            var steps: [Int] = []
            for head in info.heads {
                let step = head.step % 2 == 0 ? head.step + (info.multiVoice && !info.stemUp ? -1 : 1) : head.step
                if !steps.contains(step) { steps.append(step) }
            }
            for step in steps {
                for d in 0..<info.event.dots {
                    add(.glyph(.augmentationDot, at: .init(x: dotX + Double(d) * 0.5, y: StaffPosition.y(step)), scale: scale),
                        .dot, staff: staff, ref: ref, time: time)
                }
            }
        }

        guard info.hasStem else { return }
        if info.beamGroup == nil {
            var length = Tuning.stemLength + Double(max(0, info.beamLevels - 2)) * 0.5
            if info.event.isGrace { length *= 0.75 }
            if info.stemUp {
                info.stemEnd = info.nearY - length * scale
                if !info.event.isGrace { info.stemEnd = min(info.stemEnd, Self.middleLineY) }
            } else {
                info.stemEnd = info.nearY + length * scale
                if !info.event.isGrace { info.stemEnd = max(info.stemEnd, Self.middleLineY) }
            }
        }
        let stemStart = info.farY + (info.stemUp ? -Self.stemAnchor : Self.stemAnchor) * scale
        add(.line(from: .init(x: info.stemX, y: stemStart), to: .init(x: info.stemX, y: info.stemEnd), thickness: Self.stemThickness * scale),
            .stem, staff: staff, ref: ref, time: time)

        if info.beamGroup == nil && info.beamLevels > 0 {
            let flags: [Glyph] = info.stemUp ? [.flag8thUp, .flag16thUp, .flag32ndUp, .flag64thUp] : [.flag8thDown, .flag16thDown, .flag32ndDown, .flag64thDown]
            let flag = flags[min(info.beamLevels, 4) - 1]
            add(.glyph(flag, at: .init(x: info.stemX - Self.stemThickness * scale / 2, y: info.stemEnd + flag.stemAnchorY * scale), scale: scale),
                .flag, staff: staff, ref: ref, time: time)
        }
    }

    func emitRest(_ info: Info) {
        let event = info.event
        let glyph: Glyph = switch event.type {
        case .breve: .restDoubleWhole
        case .half: .restHalf
        case .quarter: .restQuarter
        case .eighth: .rest8th
        case .sixteenth: .rest16th
        case .thirtySecond: .rest32nd
        case .sixtyFourth, .oneHundredTwentyEighth: .rest64th
        default: .restWhole
        }
        let isWhole = glyph == .restWhole
        var y = isWhole ? 1.0 : Self.middleLineY
        if info.multiVoice { y += info.voiceRank == 0 ? (isWhole ? -1 : -2) : 2 }
        var x = info.x + (Glyph.noteheadBlack.width - glyph.width) / 2
        if event.isMeasureRest || event.type == nil {
            // Centred in the bar.
            let k = info.ref.measure - range.lowerBound
            let barStart = k == 0 ? contentStart : barlineXs[k - 1]
            x = (barStart + barlineXs[k]) / 2 - glyph.width / 2
        }
        add(.glyph(glyph, at: .init(x: x, y: y), scale: 1), .rest, staff: event.staff, ref: info.ref, time: info.time)
        for d in 0..<event.dots {
            add(.glyph(.augmentationDot, at: .init(x: x + glyph.width + 0.3 + Double(d) * 0.5, y: y - 0.5), scale: 1),
                .dot, staff: event.staff, ref: info.ref, time: info.time)
        }
    }

    /// Beam line through the group's stems, then stems shortened or lengthened to meet it.
    func placeBeam(_ group: [Info]) {
        let up = group[0].stemUp
        let levels = max(1, group.map(\.beamLevels).max() ?? 1)
        let first = group.first!, last = group.last!
        let ideal = { (info: Info) in up ? info.nearY - Tuning.stemLength : info.nearY + Tuning.stemLength }
        let x1 = first.stemX, x2 = last.stemX
        let rise = min(max(ideal(last) - ideal(first), -Tuning.maximumBeamRise), Tuning.maximumBeamRise)
        let slope = x2 > x1 ? rise / (x2 - x1) : 0
        var y1 = ideal(first)
        let minimum = Tuning.minimumBeamedStem + Double(levels - 1) * (Tuning.beamThickness + Tuning.beamGap)

        // Outer edge of the beam at each stem; push the whole line out until every stem is long enough.
        func line(_ x: Double) -> Double { y1 + slope * (x - x1) }
        var shift = 0.0
        for info in group {
            let y = line(info.stemX)
            if up {
                shift = max(shift, y - (info.nearY - minimum), y - Self.middleLineY)
            } else {
                shift = max(shift, (info.nearY + minimum) - y, Self.middleLineY - y)
            }
        }
        y1 += up ? -shift : shift
        for info in group { info.stemEnd = line(info.stemX) }

        let staff = first.event.staff
        let half = Self.stemThickness / 2
        func top(_ x: Double, level: Int) -> Double {
            let inset = Double(level - 1) * (Tuning.beamThickness + Tuning.beamGap)
            return up ? line(x) + inset : line(x) - Tuning.beamThickness - inset
        }
        func emit(_ from: Double, _ to: Double, level: Int) {
            add(.beam(from: .init(x: from, y: top(from, level: level)), to: .init(x: to, y: top(to, level: level)),
                      thickness: Tuning.beamThickness), .beam, staff: staff, ref: first.ref, time: first.time)
        }
        emit(x1 - half, x2 + half, level: 1)

        for level in 2...max(2, levels) where levels >= 2 {
            var open: Int?
            for (i, info) in group.enumerated() {
                guard let beam = info.event.beams.first(where: { $0.level == level }) else {
                    open = nil
                    continue
                }
                switch beam.value {
                case .begin: open = i
                case .continue: if open == nil { open = i }
                case .end:
                    if let start = open { emit(group[start].stemX - half, info.stemX + half, level: level) }
                    open = nil
                case .forwardHook: emit(info.stemX - half, info.stemX + 1.1, level: level)
                case .backwardHook: emit(info.stemX - 1.1, info.stemX + half, level: level)
                }
            }
        }
    }

    func emitTies() {
        let all = Array(infos.joined())
        var arrived: Set<Engraving.NoteRef> = []
        for (i, info) in all.enumerated() where !info.event.isRest {
            for (h, head) in info.heads.enumerated() {
                let note = info.event.notes[head.noteIndex]
                guard note.tie.start else { continue }
                let above = tieAbove(info, headIndex: h)
                let y = StaffPosition.y(head.step) + (above ? -0.5 : 0.5)
                let from = Engraving.Point(x: info.headX(head) + info.headWidth + 0.1, y: y)
                var to = Engraving.Point(x: endX - 0.3, y: y)
                let candidates = all[(i + 1)...].filter { $0.event.staff == info.event.staff && !$0.event.isRest && !$0.event.isGrace }
                let ordered = candidates.filter { $0.event.voice == info.event.voice } + candidates.filter { $0.event.voice != info.event.voice }
                for target in ordered {
                    if let match = target.heads.first(where: { target.event.notes[$0.noteIndex].pitch.midi == note.pitch.midi && target.event.notes[$0.noteIndex].tie.stop }) {
                        to = .init(x: target.headX(match) - 0.1, y: y)
                        arrived.insert(.init(measure: target.ref.measure, event: target.ref.event, note: match.noteIndex))
                        break
                    }
                }
                add(.tie(from: from, to: to, above: above), .tie, staff: info.event.staff,
                    ref: .init(measure: info.ref.measure, event: info.ref.event, note: head.noteIndex), time: info.time)
            }
        }
        // Ties arriving from before the window.
        for info in all where !info.event.isRest {
            for (h, head) in info.heads.enumerated() {
                let ref = Engraving.NoteRef(measure: info.ref.measure, event: info.ref.event, note: head.noteIndex)
                guard info.event.notes[head.noteIndex].tie.stop, !arrived.contains(ref) else { continue }
                let above = tieAbove(info, headIndex: h)
                let y = StaffPosition.y(head.step) + (above ? -0.5 : 0.5)
                let x = info.headX(head) - 0.1
                add(.tie(from: .init(x: max(contentStart - 0.4, x - 3), y: y), to: .init(x: x, y: y), above: above),
                    .tie, staff: info.event.staff, ref: ref, time: info.time)
            }
        }
    }

    /// Single notes tie away from the stem; in a chord, the upper half ties above and the lower half below.
    func tieAbove(_ info: Info, headIndex: Int) -> Bool {
        let count = info.heads.count
        if count > 1 {
            if count % 2 == 1 && headIndex == count / 2 { return !info.stemUp }
            return headIndex >= count / 2
        }
        if !info.hasStem { return info.heads[headIndex].step >= 4 }
        return !info.stemUp
    }

    func emitTuplets() {
        var open: [String: [Info]] = [:]
        for info in infos.joined() where !info.event.isGrace {
            guard let tuplet = info.event.tuplet else { continue }
            let key = "\(info.event.staff)/\(info.event.voice)"
            if tuplet.bracketStart { open[key] = [] }
            open[key, default: []].append(info)
            guard tuplet.bracketStop, let group = open.removeValue(forKey: key) else { continue }

            let notes = group.filter { !$0.event.isRest }
            let up = notes.first?.stemUp ?? true
            let beamed = notes.count == group.count && Set(group.map(\.beamGroup)).count == 1 && group[0].beamGroup != nil
            var edge = up ? 0.0 : 4.0
            for info in notes {
                let ys = [StaffPosition.y(info.heads.first!.step), StaffPosition.y(info.heads.last!.step)] + (info.hasStem ? [info.stemEnd] : [])
                edge = up ? min(edge, ys.min()!) : max(edge, ys.max()!)
            }
            let scale = 0.8
            let digit = Glyph.tupletDigit(min(tuplet.actual, 9))
            let left = group.first!.x - 0.2, right = group.last!.x + group.last!.headWidth + 0.2
            let centre = (left + right) / 2
            let lineY = up ? edge - 0.8 : edge + 0.8
            let baseline = lineY + digit.bounds.ne.y * scale / 2 // number centred on the bracket line
            add(.glyph(digit, at: .init(x: centre - digit.width * scale / 2, y: baseline), scale: scale),
                .tuplet, staff: info.event.staff, ref: group[0].ref, time: group[0].time)
            if !beamed {
                let gap = digit.width * scale / 2 + 0.3
                let hook = up ? 0.6 : -0.6
                for (a, b) in [(left, centre - gap), (centre + gap, right)] {
                    add(.line(from: .init(x: a, y: lineY), to: .init(x: b, y: lineY), thickness: 0.16), .tuplet, staff: info.event.staff, ref: group[0].ref)
                }
                add(.line(from: .init(x: left, y: lineY), to: .init(x: left, y: lineY + hook), thickness: 0.16), .tuplet, staff: info.event.staff, ref: group[0].ref)
                add(.line(from: .init(x: right, y: lineY), to: .init(x: right, y: lineY + hook), thickness: 0.16), .tuplet, staff: info.event.staff, ref: group[0].ref)
            }
        }
    }

    // MARK: Pass 4 — staves stacked, then overlays

    /// Vertical extent of an item, relative to its staff.
    func extent(_ item: Engraving.Item) -> (Double, Double) {
        switch item.shape {
        case let .glyph(glyph, at, scale):
            let b = glyph.bounds
            if glyph == .brace { return (at.y, at.y) }
            return (at.y - b.ne.y * scale, at.y - b.sw.y * scale)
        case let .line(from, to, _): return (min(from.y, to.y), max(from.y, to.y))
        case let .beam(from, to, thickness): return (min(from.y, to.y), max(from.y, to.y) + thickness)
        case let .tie(from, to, above): return above ? (min(from.y, to.y) - 0.8, max(from.y, to.y)) : (min(from.y, to.y), max(from.y, to.y) + 0.8)
        case let .text(_, at, size): return (at.y - size / 2, at.y + size / 2)
        }
    }

    func staffExtent(_ staff: Int) -> (Double, Double) {
        var low = 0.0, high = 4.0
        for p in pending where p.staff == staff {
            let (a, b) = extent(p.item)
            low = min(low, a)
            high = max(high, b)
        }
        return (low, high)
    }

    func stackStaves() -> [Double] {
        var tops = [0.0]
        for staff in stride(from: 2, through: staffCount, by: 1) {
            let above = staffExtent(staff - 1), below = staffExtent(staff)
            let needed = (above.1 - 4) + (-below.0) + 2
            tops.append(tops.last! + 4 + max(Tuning.staffGapMin, needed))
        }
        for i in pending.indices {
            guard let staff = pending[i].staff else { continue }
            pending[i].item.shape = Self.offset(pending[i].item.shape, dy: tops[staff - 1])
            pending[i].staff = nil
        }
        return tops
    }

    static func offset(_ shape: Engraving.Shape, dx: Double = 0, dy: Double) -> Engraving.Shape {
        func o(_ p: Engraving.Point) -> Engraving.Point { .init(x: p.x + dx, y: p.y + dy) }
        return switch shape {
        case let .glyph(g, at, s): .glyph(g, at: o(at), scale: s)
        case let .line(a, b, t): .line(from: o(a), to: o(b), thickness: t)
        case let .beam(a, b, t): .beam(from: o(a), to: o(b), thickness: t)
        case let .tie(a, b, above): .tie(from: o(a), to: o(b), above: above)
        case let .text(s, at, size): .text(s, at: o(at), size: size)
        }
    }

    func emitStaffLinesAndBarlines(_ tops: [Double]) {
        let top = tops.first!, bottom = tops.last! + 4
        for staffTop in tops {
            for line in 0..<5 {
                let y = staffTop + Double(line)
                add(.line(from: .init(x: systemX, y: y), to: .init(x: endX, y: y), thickness: Self.staffLineThickness), .staffLine, staff: nil)
            }
        }
        if staffCount > 1 {
            add(.line(from: .init(x: systemX, y: top), to: .init(x: systemX, y: bottom), thickness: Self.thinBarline), .barline, staff: nil)
            let scale = (bottom - top) / 4
            add(.glyph(.brace, at: .init(x: systemX - 0.25 - Glyph.brace.width * scale, y: bottom), scale: scale), .brace, staff: nil)
        }
        for (k, x) in barlineXs.enumerated() {
            let measure = part.measures[range.lowerBound + k]
            let isLast = measure.index == part.measures.count - 1
            if measure.endRepeatTimes != nil {
                emitRepeat(start: false, x: x, tops: tops)
            } else if isLast {
                repeats.append((x - Self.thickBarline / 2, Self.thickBarline))
                repeats.append((x - Self.thickBarline - 0.4, Self.thinBarline))
            } else {
                add(.line(from: .init(x: x, y: top), to: .init(x: x, y: bottom), thickness: Self.thinBarline), .barline, staff: nil)
            }
        }
        for line in repeats {
            add(.line(from: .init(x: line.x, y: top), to: .init(x: line.x, y: bottom), thickness: line.thickness), .barline, staff: nil)
        }
    }

    struct Overlays {
        var fingers: [Engraving.Item] = []
        var counts: [Engraving.Item] = []
    }

    func emitOverlays(_ tops: [Double]) -> Overlays {
        var overlays = Overlays()
        var low = Double.infinity, high = -Double.infinity
        for p in pending {
            let (a, b) = extent(p.item)
            low = min(low, a)
            high = max(high, b)
        }
        let lastBottom = tops.last! + 4
        let aboveRow = min(tops[0] - 1.6, low - 1.0)
        var belowRow = max(lastBottom + 1.6, high + 1.0)
        let lineHeight = Tuning.fingerTextSize * 0.9
        var deepestBelow = belowRow - lineHeight

        if options.fingering {
            for info in infos.joined() where !info.event.isRest {
                let above = info.event.staff == 1 || staffCount == 1
                let fingered = info.heads.filter { info.event.notes[$0.noteIndex].fingering != nil }
                let ordered = above ? fingered : fingered.reversed()
                for (i, head) in ordered.enumerated() {
                    let finger = info.event.notes[head.noteIndex].fingering!
                    let x = info.headX(head) + info.headWidth / 2
                    let y = above ? aboveRow - Double(i) * lineHeight : belowRow + Double(i) * lineHeight
                    if !above { deepestBelow = max(deepestBelow, y) }
                    overlays.fingers.append(Engraving.Item(shape: .text("\(finger)", at: .init(x: x, y: y), size: Tuning.fingerTextSize * info.scale),
                                                           role: .finger, ref: .init(measure: info.ref.measure, event: info.ref.event, note: head.noteIndex),
                                                           time: info.time))
                }
            }
        }

        if options.counts {
            belowRow = deepestBelow + lineHeight + 0.4
            let partial = Engraving(width: endX, height: 0, staffTops: tops, items: [], start: part.measures[range.lowerBound].start,
                                    end: part.measures[range.upperBound - 1].start + part.measures[range.upperBound - 1].duration,
                                    contentStart: contentStart, timeline: timeline)
            for (k, m) in range.enumerated() {
                let measure = part.measures[m]
                let beat = Rational(4, measure.time.beatType)
                // "&" only when a note falls on a half beat (not for triplets).
                let offBeats = infos[k].contains { !$0.event.isGrace && ($0.event.onset / beat).denominator == 2 }
                let step = offBeats && measure.time.beatType <= 4 ? beat / 2 : beat
                // A pickup is the end of a full bar: count from where that bar would start.
                let lead = measure.isPickup ? measure.time.measureLength - measure.duration : .zero
                var position = Rational.zero
                while position < measure.time.measureLength {
                    let offset = position - lead
                    if offset >= .zero && offset < measure.duration, let x = partial.x(at: measure.start + offset) {
                        let beats = position / beat
                        let label = beats.denominator == 1 ? "\(beats.numerator + 1)" : "&"
                        overlays.counts.append(Engraving.Item(shape: .text(label, at: .init(x: x, y: belowRow), size: Tuning.countTextSize),
                                                              role: .count, ref: nil, time: measure.start + offset))
                    }
                    position = position + step
                }
            }
        }
        return overlays
    }

    func finish(_ tops: [Double], overlays: Overlays) -> Engraving {
        var items = pending.map(\.item) + overlays.fingers + overlays.counts
        var low = Double.infinity, high = -Double.infinity, left = 0.0
        for item in items {
            let (a, b) = extent(item)
            low = min(low, a)
            high = max(high, b)
            left = min(left, item.point.x)
        }
        let dy = 0.6 - low, dx = -left
        items = items.map { item in
            var moved = item
            moved.shape = Self.offset(item.shape, dx: dx, dy: dy)
            return moved
        }
        let first = part.measures[range.lowerBound], last = part.measures[range.upperBound - 1]
        return Engraving(width: endX + dx + 0.3, height: high - low + 1.2, staffTops: tops.map { $0 + dy }, items: items,
                         start: first.start, end: last.start + last.duration, contentStart: contentStart + dx,
                         timeline: timeline.map { ($0.time, $0.x + dx, $0.isOnset) })
    }
}
