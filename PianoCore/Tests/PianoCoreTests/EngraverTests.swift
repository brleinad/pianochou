import Testing
@testable import PianoCore

struct EngraverTests {
    static let fixtures = ["c-major-scale", "waltz-3-4", "triplets", "two-voices", "clef-change", "key-change",
                           "pickup", "repeat-endings", "engraving-sampler"]

    func sampler(_ measures: Range<Int> = 0..<3) throws -> (Score, Engraving) {
        let score = try Fixture.score("engraving-sampler")
        return (score, Engraver.engrave(score, measures: measures))
    }

    // MARK: Staff positions

    @Test func staffStepsFollowTheClef() {
        #expect(StaffPosition.step(of: Pitch(step: .E, octave: 4), clef: .treble) == 0)
        #expect(StaffPosition.step(of: Pitch(step: .F, octave: 5), clef: .treble) == 8)
        #expect(StaffPosition.step(of: Pitch(step: .C, octave: 4), clef: .treble) == -2)
        #expect(StaffPosition.step(of: Pitch(step: .G, octave: 2), clef: .bass) == 0)
        #expect(StaffPosition.step(of: Pitch(step: .C, octave: 4), clef: .bass) == 10)
        #expect(StaffPosition.step(of: Pitch(step: .C, octave: 4), clef: Clef(sign: .c, line: 3)) == 4)
        #expect(StaffPosition.step(of: Pitch(step: .E, octave: 3), clef: Clef(sign: .g, line: 2, octaveChange: -1)) == 0)
    }

    @Test func keySignatureAccidentalsSitOnTheUsualLines() {
        #expect(StaffPosition.keySignature(fifths: 1, clef: .treble).map(\.step) == [8])
        #expect(StaffPosition.keySignature(fifths: 3, clef: .bass).map(\.step) == [6, 3, 7])
        #expect(StaffPosition.keySignature(fifths: -2, clef: .treble).map(\.step) == [4, 7])
        #expect(StaffPosition.keySignature(fifths: -2, clef: .treble).allSatisfy { $0.glyph == .accidentalFlat })
    }

    // MARK: Whole fixtures

    @Test(arguments: fixtures) func everyFixtureEngravesWithinItsBounds(name: String) throws {
        let score = try Fixture.score(name)
        let measures = score.parts[0].measures
        for start in stride(from: 0, to: measures.count, by: 2) {
            let range = start..<min(start + 2, measures.count)
            let engraving = Engraver.engrave(score, measures: range)
            let noteCount = range.reduce(0) { $0 + measures[$1].events.reduce(0) { $0 + $1.notes.count } }
            #expect(engraving.items.filter { $0.role == .notehead }.count == noteCount, "\(name) \(range)")
            #expect(engraving.width > 0 && engraving.height > 0)
            for item in engraving.items {
                let p = item.point
                #expect(p.x >= -0.01 && p.x <= engraving.width + 0.01, "\(name) \(item)")
                #expect(p.y >= -0.01 && p.y <= engraving.height + 0.01, "\(name) \(item)")
            }
        }
    }

    @Test func grandStaffLeavesRoomBetweenStaves() throws {
        let (_, engraving) = try sampler()
        #expect(engraving.staffTops.count == 2)
        #expect(engraving.staffTops[1] - engraving.staffTops[0] >= 4 + Tuning.staffGapMin)
        #expect(engraving.items.contains { $0.shape.glyph == .brace })
    }

    @Test func headerShowsClefsKeyAndTime() throws {
        let (_, engraving) = try sampler()
        let glyphs = engraving.items.compactMap(\.shape.glyph)
        #expect(glyphs.contains(.gClef) && glyphs.contains(.fClef))
        // One sharp per staff for G major.
        #expect(engraving.items.filter { $0.role == .keySignature }.count == 2)
        #expect(glyphs.filter { $0 == .timeSig4 }.count == 4)
    }

    // MARK: Notes

    @Test func stemsPointAwayFromTheFarSide() throws {
        let score = try Fixture.inline("""
        <measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
          <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><chord/><pitch><step>A</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <note><chord/><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
        </measure>
        """)
        let engraving = Engraver.engrave(score, measures: 0..<1)
        #expect(engraving.stemDirections() == [false, true, false, true]) // B4 down, A4 up, C4+A5 equally far → down, E4+E5 up
    }

    @Test func accidentalsFollowKeyAndMeasure() throws {
        let (_, engraving) = try sampler()
        let accidentals = engraving.items.filter { $0.role == .accidental }
        // F#5 in G major needs none; m2 has C#5 then C natural.
        #expect(accidentals.compactMap(\.shape.glyph) == [.accidentalSharp, .accidentalNatural])
        #expect(accidentals.allSatisfy { $0.ref?.measure == 1 })
    }

    @Test func anAccidentalLastsUntilTheBarline() throws {
        let score = try Fixture.inline("""
        <measure number="1"><attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
          <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><type>half</type></note>
          <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><type>half</type></note>
        </measure>
        <measure number="2">
          <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
        </measure>
        """)
        let engraving = Engraver.engrave(score, measures: 0..<2)
        let accidentals = engraving.items.filter { $0.role == .accidental }
        #expect(accidentals.map { $0.ref?.measure } == [0, 1])
    }

    @Test func ledgerLinesAboveAndBelow() throws {
        let (_, engraving) = try sampler(1..<2)
        func ledgers(_ event: Int) -> Int {
            engraving.items.filter { $0.role == .ledger && $0.ref?.event == event }.count
        }
        let m2 = try Fixture.score("engraving-sampler").parts[0].measures[1].events
        let a5 = m2.firstIndex { $0.notes.first?.pitch.name == "A5" }!
        let c6 = m2.firstIndex { $0.notes.first?.pitch.name == "C6" }!
        let e2 = m2.firstIndex { $0.notes.first?.pitch.name == "E2" }!
        #expect(ledgers(a5) == 1)
        #expect(ledgers(c6) == 2)
        #expect(ledgers(e2) == 1)
    }

    @Test func aSecondInAChordSitsOnTheOtherSideOfTheStem() throws {
        let (score, engraving) = try sampler(1..<2)
        let chord = score.parts[0].measures[1].events.firstIndex { $0.notes.count == 2 }!
        let heads = engraving.items.filter { $0.role == .notehead && $0.ref?.event == chord }
            .sorted { ($0.ref?.note ?? 0) < ($1.ref?.note ?? 0) }
        #expect(heads.count == 2)
        // G4 A4, stem up: A4 moves right by one notehead width.
        #expect(abs(heads[1].point.x - heads[0].point.x - Glyph.noteheadBlack.width) < 0.01)
    }

    @Test func dotSitsInASpace() throws {
        let (score, engraving) = try sampler(0..<1)
        let fSharp = score.parts[0].measures[0].events.firstIndex { $0.notes.first?.pitch.name == "F#5" }!
        let head = engraving.items.first { $0.role == .notehead && $0.ref?.event == fSharp }!
        let dot = engraving.items.first { $0.role == .dot && $0.ref?.event == fSharp }!
        // F5 is on the top line, so the dot moves up half a space.
        #expect(abs(dot.point.y - (head.point.y - 0.5)) < 0.01)
        #expect(dot.point.x > head.point.x + Glyph.noteheadBlack.width)
    }

    @Test func restsUseTheirGlyphs() throws {
        let (_, engraving) = try sampler()
        let rests = engraving.items.filter { $0.role == .rest }.compactMap(\.shape.glyph)
        #expect(rests == [.restQuarter, .restQuarter, .rest8th, .restQuarter])
    }

    // MARK: Beams, flags, ties, tuplets

    @Test func beamedNotesShareABeamAndStemsReachIt() throws {
        let (score, engraving) = try sampler(0..<1)
        let events = score.parts[0].measures[0].events
        let d5 = events.firstIndex { $0.notes.first?.pitch.name == "D5" }!
        let beams = engraving.items.filter { $0.role == .beam }
        #expect(beams.count == 2) // RH eighth pair, LH four eighths
        let beam = beams.first { $0.ref?.event == d5 }!
        guard case let .beam(from, to, _) = beam.shape else { Issue.record("not a beam"); return }
        let stem = engraving.items.first { $0.role == .stem && $0.ref?.event == d5 }!
        guard case let .line(a, b, _) = stem.shape else { Issue.record("not a line"); return }
        let stemEnd = abs(a.y - from.y) < abs(b.y - from.y) ? a : b
        let beamY = from.y + (to.y - from.y) * (stemEnd.x - from.x) / (to.x - from.x)
        // Down stems end on the beam's bottom edge, up stems on its top edge.
        #expect(abs(stemEnd.y - beamY) < 0.01 || abs(stemEnd.y - (beamY + Tuning.beamThickness)) < 0.01)
        #expect(!engraving.items.contains { $0.role == .flag && $0.ref?.event == d5 })
    }

    @Test func sixteenthsGetASecondBeam() throws {
        let (_, engraving) = try sampler(1..<2)
        #expect(engraving.items.filter { $0.role == .beam }.count == 2)
    }

    @Test func unbeamedEighthsGetAFlag() throws {
        let (_, engraving) = try sampler()
        let flags = engraving.items.filter { $0.role == .flag }.compactMap(\.shape.glyph)
        #expect(flags == [.flag8thDown, .flag8thDown]) // G5 in m1, D5 in m3
    }

    @Test func tieCrossesTheBarline() throws {
        let (_, both) = try sampler(1..<3)
        let ties = both.items.filter { $0.role == .tie }
        #expect(ties.count == 1)
        guard case let .tie(from, to, above) = ties[0].shape else { Issue.record("not a tie"); return }
        #expect(to.x > from.x + 1.5)
        #expect(above) // the upper note of a chord ties above
        // Cut off at the end of the window: the tie still shows, running to the edge.
        let (_, first) = try sampler(1..<2)
        #expect(first.items.filter { $0.role == .tie }.count == 1)
        let (_, second) = try sampler(2..<3)
        #expect(second.items.filter { $0.role == .tie }.count == 1)
    }

    @Test func tripletGetsItsNumber() throws {
        let score = try Fixture.score("triplets")
        let engraving = Engraver.engrave(score, measures: 0..<score.parts[0].measures.count)
        #expect(engraving.items.contains { $0.role == .tuplet && $0.shape.glyph == .tuplet3 })
    }

    // MARK: Changes inside the window

    @Test func clefChangeIsDrawn() throws {
        let score = try Fixture.score("clef-change")
        let engraving = Engraver.engrave(score, measures: 0..<score.parts[0].measures.count)
        #expect(engraving.items.contains { $0.role == .clef && [.fClefChange, .gClefChange].contains($0.shape.glyph) })
    }

    @Test func keyChangeIsDrawnAtItsMeasure() throws {
        let score = try Fixture.score("key-change")
        let engraving = Engraver.engrave(score, measures: 0..<score.parts[0].measures.count)
        let flats = engraving.items.filter { $0.role == .keySignature && $0.shape.glyph == .accidentalFlat }
        #expect(flats.count == 2)
    }

    // MARK: Overlays

    @Test func fingersSitAboveTheRightHandAndBelowTheLeftHand() throws {
        let (_, engraving) = try sampler()
        let fingers = engraving.items.filter { $0.role == .finger }
        let topStaff = engraving.staffTops[0], bottomStaff = engraving.staffTops[1] + 4
        let rh = fingers.filter { $0.point.y < topStaff }
        let lh = fingers.filter { $0.point.y > bottomStaff }
        #expect(rh.count + lh.count == fingers.count)
        #expect(rh.count == 8)
        #expect(lh.count == 10)
    }

    @Test func beatCountsFollowTheMeter() throws {
        let waltz = try Fixture.score("waltz-3-4")
        let counts = Engraver.engrave(waltz, measures: 0..<1).items.filter { $0.role == .count }
        #expect(counts.compactMap(\.shape.text) == ["1", "2", "3"])
        let (_, sampler) = try sampler(0..<1)
        let eighths = sampler.items.filter { $0.role == .count }.compactMap(\.shape.text)
        #expect(eighths == ["1", "&", "2", "&", "3", "&", "4", "&"])
    }

    @Test func pickupCountsFromTheRightBeat() throws {
        let score = try Fixture.score("pickup")
        let first = score.parts[0].measures[0]
        #expect(first.isPickup)
        let counts = Engraver.engrave(score, measures: 0..<1).items.filter { $0.role == .count }.compactMap(\.shape.text)
        #expect(counts.last == "\(first.time.beats)")
    }

    @Test func timeMapsToTheNoteheadAndInterpolatesBetween() throws {
        let (score, engraving) = try sampler(0..<2)
        let m1 = score.parts[0].measures[0]
        let fSharp = m1.events.firstIndex { $0.notes.first?.pitch.name == "F#5" }!
        let head = engraving.items.first { $0.role == .notehead && $0.ref?.event == fSharp }!
        let x = try #require(engraving.x(at: m1.start + m1.events[fSharp].onset))
        #expect(abs(x - (head.point.x + Glyph.noteheadBlack.width / 2)) < 0.01)
        var last = -Double.infinity
        for sixteenth in 0..<32 {
            let x = try #require(engraving.x(at: Rational(sixteenth, 4)))
            #expect(x > last)
            last = x
        }
    }
}

private extension Engraving {
    /// Stem direction per stemmed event, in order: true = up.
    func stemDirections() -> [Bool] {
        items.filter { $0.role == .stem }.compactMap { item in
            guard case let .line(from, to, _) = item.shape else { return nil }
            let head = items.first { $0.role == .notehead && $0.ref?.event == item.ref?.event }!
            return from.x > head.point.x + Glyph.noteheadBlack.width / 2 && to.y < from.y
        }
    }
}
